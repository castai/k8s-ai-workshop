package reconciler

import (
	"context"
	"log"
	"sync"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"

	"progress-reconciler/internal/config"
	"progress-reconciler/internal/reporter"
	"progress-reconciler/internal/verifiers"
)

// Reconciler manages riddle verification and reporting
type Reconciler struct {
	clientset   *kubernetes.Clientset
	restConfig  *rest.Config
	config      *config.Config
	reporter    *reporter.SupabaseReporter
	rateLimiter *reporter.RateLimiter
	states      map[string]*RiddleState
	stateMutex  sync.RWMutex
	verifiers   map[string]verifiers.Verifier
}

// NewReconciler creates a new reconciler
func NewReconciler(
	clientset *kubernetes.Clientset,
	restCfg *rest.Config,
	cfg *config.Config,
	rep *reporter.SupabaseReporter,
) *Reconciler {
	r := &Reconciler{
		clientset:   clientset,
		restConfig:  restCfg,
		config:      cfg,
		reporter:    rep,
		rateLimiter: reporter.NewRateLimiter(cfg.ReportMinInterval),
		states:      make(map[string]*RiddleState),
		verifiers:   make(map[string]verifiers.Verifier),
	}

	r.initializeVerifiers()
	return r
}

// initializeVerifiers creates verifiers for enabled riddles
func (r *Reconciler) initializeVerifiers() {
	for _, riddleConfig := range r.config.Riddles {
		if !riddleConfig.Enabled {
			continue
		}

		var verifier verifiers.Verifier
		switch riddleConfig.RiddleID {
		case "2eecc00a-79a6-4d8e-92a3-06440b5d08c2": // Riddle 1
			verifier = verifiers.NewRiddle1Verifier(r.clientset, r.restConfig, riddleConfig.Namespace)
		case "24e96064-68d7-4bf9-b222-af29fe2306be": // Riddle 2
			verifier = verifiers.NewRiddle2Verifier(r.clientset, riddleConfig.Namespace)
		case "7d7c5ea7-9b3d-4890-ac40-c79b8f30c778": // Riddle 3
			verifier = verifiers.NewRiddle3Verifier(r.clientset, riddleConfig.Namespace)
		default:
			log.Printf("⚠️  Unknown riddle_id: %s", riddleConfig.RiddleID)
			continue
		}

		r.verifiers[riddleConfig.RiddleID] = verifier
	}
}

// Run starts the reconciliation loop
func (r *Reconciler) Run(ctx context.Context) {
	ticker := time.NewTicker(r.config.ReconciliationInterval)
	defer ticker.Stop()

	log.Printf("🔄 Reconciliation loop started (interval: %s)", r.config.ReconciliationInterval)

	// Run immediately on startup
	r.reconcile(ctx)

	for {
		select {
		case <-ticker.C:
			r.reconcile(ctx)
		case <-ctx.Done():
			log.Println("🛑 Reconciliation loop stopped")
			return
		}
	}
}

// reconcile checks all enabled riddles
func (r *Reconciler) reconcile(ctx context.Context) {
	for _, riddleConfig := range r.config.Riddles {
		if !riddleConfig.Enabled {
			continue
		}

		r.reconcileRiddle(ctx, riddleConfig)
	}
}

// reconcileRiddle checks a single riddle
func (r *Reconciler) reconcileRiddle(ctx context.Context, riddleConfig config.RiddleConfig) {
	// Check if namespace exists
	_, err := r.clientset.CoreV1().Namespaces().Get(ctx, riddleConfig.Namespace, metav1.GetOptions{})
	if err != nil {
		// Namespace doesn't exist - riddle not started
		r.stateMutex.Lock()
		delete(r.states, riddleConfig.RiddleID) // Clear state if previously existed
		r.stateMutex.Unlock()
		return
	}

	// Get or create state
	r.stateMutex.Lock()
	state, exists := r.states[riddleConfig.RiddleID]
	if !exists {
		state = &RiddleState{
			RiddleID:      riddleConfig.RiddleID,
			Namespace:     riddleConfig.Namespace,
			LastStatus:    "not_started",
			FirstSeenTime: time.Now(),
		}
		r.states[riddleConfig.RiddleID] = state
		log.Printf("🔍 Detected new riddle: %s (%s)", riddleConfig.Namespace, riddleConfig.RiddleID)
	}
	r.stateMutex.Unlock()

	// Skip if within grace period
	if time.Since(state.FirstSeenTime) < r.config.StartupGracePeriod {
		return
	}

	// Run verification
	verifier, ok := r.verifiers[riddleConfig.RiddleID]
	if !ok {
		log.Printf("⚠️  No verifier found for %s", riddleConfig.RiddleID)
		return
	}

	result := verifier.Verify(ctx)

	// Check if state changed
	r.stateMutex.Lock()
	stateChanged := state.LastStatus != result.Status || state.ChecksPassed != result.ChecksPassed
	oldStatus := state.LastStatus
	oldChecks := state.ChecksPassed
	r.stateMutex.Unlock()

	// Report if state changed and rate limit allows
	if stateChanged && r.rateLimiter.ShouldReport(riddleConfig.RiddleID) {
		log.Printf("📊 State changed for %s: status %s→%s, checks %d/%d→%d/%d",
			riddleConfig.RiddleID, oldStatus, result.Status, oldChecks, result.TotalChecks, result.ChecksPassed, result.TotalChecks)

		r.reporter.QueueReport(reporter.ReportMessage{
			RiddleID:     riddleConfig.RiddleID,
			Status:       result.Status,
			ChecksPassed: result.ChecksPassed,
			TotalChecks:  result.TotalChecks,
		})

		// Only update in-memory state after the report is queued,
		// so rate-limited changes will be retried on the next cycle.
		r.stateMutex.Lock()
		state.LastStatus = result.Status
		state.ChecksPassed = result.ChecksPassed
		state.TotalChecks = result.TotalChecks
		state.LastReportTime = time.Now()
		r.stateMutex.Unlock()
	}
}

// GetStates returns current riddle states (for status endpoint)
func (r *Reconciler) GetStates() map[string]*RiddleState {
	r.stateMutex.RLock()
	defer r.stateMutex.RUnlock()

	// Create copy to avoid data races
	states := make(map[string]*RiddleState)
	for k, v := range r.states {
		stateCopy := *v
		states[k] = &stateCopy
	}

	return states
}
