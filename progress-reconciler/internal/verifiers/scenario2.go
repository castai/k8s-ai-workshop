package verifiers

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// Riddle2Verifier implements verification for riddle-2 (Autoscaler & Rebalancing)
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

// Verify runs all 5 checks for Riddle 2 (Autoscaler & Rebalancing)
func (v *Riddle2Verifier) Verify(ctx context.Context) (checksPassed, totalChecks int, status string) {
	checks := []func(context.Context) bool{
		v.checkAllDeploymentsReady,
		v.checkNoPendingPods,
		v.checkNoErrorPods,
		v.checkAllPodsFullyReady,
		v.checkCASTAIRebalancingCompleted,
	}

	totalChecks = len(checks)
	checksPassed = 0

	for _, check := range checks {
		if check(ctx) {
			checksPassed++
		}
	}

	// Determine status
	if checksPassed == 0 {
		status = "not_started"
	} else if checksPassed < totalChecks {
		status = "in_progress"
	} else {
		status = "completed"
	}

	return checksPassed, totalChecks, status
}

// Check 1: All deployments have desired replicas ready
func (v *Riddle2Verifier) checkAllDeploymentsReady(ctx context.Context) bool {
	deployments, err := v.clientset.AppsV1().Deployments(v.namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return false
	}

	for _, deploy := range deployments.Items {
		desired := int32(0)
		if deploy.Spec.Replicas != nil {
			desired = *deploy.Spec.Replicas
		}
		ready := deploy.Status.ReadyReplicas

		if ready != desired {
			return false
		}
	}

	return true
}

// Check 2: No pods in Pending state
func (v *Riddle2Verifier) checkNoPendingPods(ctx context.Context) bool {
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		FieldSelector: "status.phase=Pending",
	})
	if err != nil {
		return false
	}

	return len(pods.Items) == 0
}

// Check 3: No pods in error states (exclude completed Job pods)
func (v *Riddle2Verifier) checkNoErrorPods(ctx context.Context) bool {
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return false
	}

	errorStates := []string{
		"CrashLoopBackOff",
		"ImagePullBackOff",
		"Error",
		"ErrImagePull",
		"CreateContainerConfigError",
	}

	for _, pod := range pods.Items {
		// Skip completed job pods
		if pod.Status.Phase == corev1.PodSucceeded {
			continue
		}

		// Check container statuses for error states
		for _, containerStatus := range pod.Status.ContainerStatuses {
			if containerStatus.State.Waiting != nil {
				reason := containerStatus.State.Waiting.Reason
				for _, errorState := range errorStates {
					if strings.Contains(reason, errorState) {
						return false
					}
				}
			}
		}
	}

	return true
}

// Check 4: All deployment pods fully Ready (exclude completed Job pods)
func (v *Riddle2Verifier) checkAllPodsFullyReady(ctx context.Context) bool {
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return false
	}

	runningPods := 0
	for _, pod := range pods.Items {
		// Skip completed job pods
		if pod.Status.Phase == corev1.PodSucceeded {
			continue
		}

		runningPods++

		// Check if all containers are ready
		for _, containerStatus := range pod.Status.ContainerStatuses {
			if !containerStatus.Ready {
				return false
			}
		}
	}

	// Must have at least one pod running
	return runningPods > 0
}

// Check 5: CAST AI rebalancing completed successfully
func (v *Riddle2Verifier) checkCASTAIRebalancingCompleted(ctx context.Context) bool {
	// Get API key from environment
	apiKey := os.Getenv("CASTAI_API_KEY")
	if apiKey == "" {
		// API key not configured - skip this check (return false)
		return false
	}

	// Get cluster ID from CAST AI API
	clusterID, err := v.getCASTAIClusterID(ctx, apiKey)
	if err != nil || clusterID == "" {
		return false
	}

	// Query rebalancing plans for the cluster
	completedCount, err := v.getCompletedRebalancingPlans(ctx, apiKey, clusterID)
	if err != nil {
		return false
	}

	// Check if at least one rebalancing plan completed
	return completedCount > 0
}

// getCASTAIClusterID retrieves the cluster ID from CAST AI API
func (v *Riddle2Verifier) getCASTAIClusterID(ctx context.Context, apiKey string) (string, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequestWithContext(ctx, "GET", "https://api.cast.ai/v1/kubernetes/external-clusters", nil)
	if err != nil {
		return "", err
	}

	req.Header.Set("X-API-Key", apiKey)

	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("API returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	var result struct {
		Items []struct {
			ID string `json:"id"`
		} `json:"items"`
	}

	if err := json.Unmarshal(body, &result); err != nil {
		return "", err
	}

	if len(result.Items) == 0 {
		return "", fmt.Errorf("no clusters found")
	}

	return result.Items[0].ID, nil
}

// getCompletedRebalancingPlans retrieves the count of completed rebalancing plans
func (v *Riddle2Verifier) getCompletedRebalancingPlans(ctx context.Context, apiKey, clusterID string) (int, error) {
	client := &http.Client{Timeout: 10 * time.Second}
	url := fmt.Sprintf("https://api.cast.ai/v1/kubernetes/clusters/%s/rebalancing-plans", clusterID)
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return 0, err
	}

	req.Header.Set("X-API-Key", apiKey)

	resp, err := client.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("API returned status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return 0, err
	}

	var result struct {
		Items []struct {
			Status string `json:"status"`
		} `json:"items"`
	}

	if err := json.Unmarshal(body, &result); err != nil {
		return 0, err
	}

	// Count completed plans
	completedCount := 0
	for _, plan := range result.Items {
		if plan.Status == "finished" {
			completedCount++
		}
	}

	return completedCount, nil
}
