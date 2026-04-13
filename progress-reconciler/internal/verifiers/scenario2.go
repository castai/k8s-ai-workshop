package verifiers

import (
	"context"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// Riddle2Verifier implements verification for riddle-2 (Scaling Under Pressure)
type Riddle2Verifier struct {
	clientset *kubernetes.Clientset
	namespace string
}

// NewRiddle2Verifier creates a new Riddle 2 verifier
func NewRiddle2Verifier(clientset *kubernetes.Clientset, namespace string) *Riddle2Verifier {
	return &Riddle2Verifier{
		clientset: clientset,
		namespace: namespace,
	}
}

// Verify runs all 5 checks for Riddle 2 (Scaling Under Pressure)
func (v *Riddle2Verifier) Verify(ctx context.Context) VerifyResult {
	type namedCheck struct {
		name string
		fn   func(context.Context) bool
	}

	checks := []namedCheck{
		{"HPA active for web-frontend", v.checkHPAWebFrontend},
		{"HPA active for order-service", v.checkHPAOrderService},
		{"All deployments ready", v.checkAllDeploymentsReady},
		{"PodDisruptionBudgets exist", v.checkPDBsExist},
		{"web-frontend replicas on different nodes", v.checkTopologySpread},
	}

	results := make([]CheckResult, 0, len(checks))
	passed := 0

	for _, check := range checks {
		ok := check.fn(ctx)
		if ok {
			passed++
		}
		results = append(results, CheckResult{Name: check.name, Passed: ok})
	}

	return VerifyResult{
		ChecksPassed: passed,
		TotalChecks:  len(checks),
		Status:       DetermineStatus(passed, len(checks)),
		Checks:       results,
	}
}

// Check 1: HPA exists for web-frontend and has scaled to >= 2 replicas
func (v *Riddle2Verifier) checkHPAWebFrontend(ctx context.Context) bool {
	return v.checkHPAActive(ctx, "web-frontend", 2)
}

// Check 2: HPA exists for order-service and has scaled to >= 2 replicas
func (v *Riddle2Verifier) checkHPAOrderService(ctx context.Context) bool {
	return v.checkHPAActive(ctx, "order-service", 2)
}

// checkHPAActive checks if an HPA targeting the given deployment exists and has scaled
func (v *Riddle2Verifier) checkHPAActive(ctx context.Context, deploymentName string, minReplicas int32) bool {
	hpas, err := v.clientset.AutoscalingV2().HorizontalPodAutoscalers(v.namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return false
	}

	for _, hpa := range hpas.Items {
		if hpa.Spec.ScaleTargetRef.Name == deploymentName {
			return hpa.Status.CurrentReplicas >= minReplicas
		}
	}

	return false
}

// Check 3: All deployments have desired replicas ready
func (v *Riddle2Verifier) checkAllDeploymentsReady(ctx context.Context) bool {
	deployments, err := v.clientset.AppsV1().Deployments(v.namespace).List(ctx, metav1.ListOptions{})
	if err != nil || len(deployments.Items) == 0 {
		return false
	}

	for _, deploy := range deployments.Items {
		// Skip the load generator — it doesn't need to be "ready" in the same sense
		if deploy.Name == "load-generator" {
			continue
		}
		desired := int32(0)
		if deploy.Spec.Replicas != nil {
			desired = *deploy.Spec.Replicas
		}
		if deploy.Status.ReadyReplicas < desired {
			return false
		}
	}

	return true
}

// Check 4: At least 2 PodDisruptionBudgets exist in the namespace
func (v *Riddle2Verifier) checkPDBsExist(ctx context.Context) bool {
	pdbs, err := v.clientset.PolicyV1().PodDisruptionBudgets(v.namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return false
	}

	return len(pdbs.Items) >= 2
}

// Check 5: web-frontend pods are scheduled on at least 2 distinct nodes
func (v *Riddle2Verifier) checkTopologySpread(ctx context.Context) bool {
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=web-frontend",
	})
	if err != nil || len(pods.Items) < 2 {
		return false
	}

	nodes := make(map[string]bool)
	for _, pod := range pods.Items {
		if pod.Spec.NodeName != "" {
			nodes[pod.Spec.NodeName] = true
		}
	}

	return len(nodes) >= 2
}
