package verifiers

import (
	"context"
	"strings"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// Riddle3Verifier implements verification for riddle-3 (Autoscaling/Optimization)
type Riddle3Verifier struct {
	clientset *kubernetes.Clientset
	namespace string
}

// NewRiddle3Verifier creates a new Riddle 3 verifier
func NewRiddle3Verifier(clientset *kubernetes.Clientset, namespace string) *Riddle3Verifier {
	return &Riddle3Verifier{
		clientset: clientset,
		namespace: namespace,
	}
}

// Verify runs all 5 checks for Riddle 3 (Resource Right-Sizing)
func (v *Riddle3Verifier) Verify(ctx context.Context) VerifyResult {
	type namedCheck struct {
		name string
		fn   func(context.Context) bool
	}

	checks := []namedCheck{
		{"No OOMKilled pods", v.checkNoOOMKilledPods},
		{"All pods running and ready", v.checkAllPodsRunningAndReady},
		{"No recent OOMKill terminations", v.checkNoRecentOOMKills},
		{"Memory request >= 120Mi", v.checkMemoryRequestSufficient},
		{"WOOP applied recommendations", v.checkWOOPApplied},
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

// Check 1: No pods in OOMKilled state
func (v *Riddle3Verifier) checkNoOOMKilledPods(ctx context.Context) bool {
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=stress-app",
	})
	if err != nil {
		return false
	}

	for _, pod := range pods.Items {
		if pod.Status.Phase == corev1.PodFailed && pod.Status.Reason == "OOMKilled" {
			return false
		}
		// Check container statuses
		for _, containerStatus := range pod.Status.ContainerStatuses {
			if containerStatus.State.Waiting != nil && containerStatus.State.Waiting.Reason == "OOMKilled" {
				return false
			}
		}
	}

	return true
}

// Check 2: All pods Running and Ready
func (v *Riddle3Verifier) checkAllPodsRunningAndReady(ctx context.Context) bool {
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=stress-app",
	})
	if err != nil || len(pods.Items) == 0 {
		return false
	}

	runningCount := 0
	for _, pod := range pods.Items {
		if pod.Status.Phase == corev1.PodRunning {
			// Check if all containers are ready
			allReady := true
			for _, containerStatus := range pod.Status.ContainerStatuses {
				if !containerStatus.Ready {
					allReady = false
					break
				}
			}
			if allReady {
				runningCount++
			}
		}
	}

	// All pods should be running and ready
	return runningCount == len(pods.Items) && runningCount > 0
}

// Check 3: No recent OOMKill terminations
func (v *Riddle3Verifier) checkNoRecentOOMKills(ctx context.Context) bool {
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=stress-app",
	})
	if err != nil {
		return false
	}

	for _, pod := range pods.Items {
		for _, containerStatus := range pod.Status.ContainerStatuses {
			if containerStatus.LastTerminationState.Terminated != nil {
				if containerStatus.LastTerminationState.Terminated.Reason == "OOMKilled" {
					return false
				}
			}
		}
	}

	return true
}

// Check 4: Memory request >= 120Mi (checking actual pod spec, not deployment)
func (v *Riddle3Verifier) checkMemoryRequestSufficient(ctx context.Context) bool {
	// Get running pods (WOOP modifies pod spec directly, not deployment)
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=stress-app",
		FieldSelector: "status.phase=Running",
	})
	if err != nil || len(pods.Items) == 0 {
		return false
	}

	// Check first running pod's actual memory request
	pod := pods.Items[0]
	if len(pod.Spec.Containers) == 0 {
		return false
	}

	memRequest := pod.Spec.Containers[0].Resources.Requests.Memory()
	if memRequest == nil {
		return false
	}

	minMemory := resource.MustParse("120Mi")
	return memRequest.Cmp(minMemory) >= 0
}

// Check 5: WOOP applied recommendations
func (v *Riddle3Verifier) checkWOOPApplied(ctx context.Context) bool {
	// Method 1: Check pod annotations for CAST AI / WOOP markers
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=stress-app",
		FieldSelector: "status.phase=Running",
	})
	if err == nil {
		for _, pod := range pods.Items {
			if hasCastAnnotations(pod.Annotations) {
				return true
			}
		}
	}

	// Method 2: Check deployment + pod template annotations
	deploy, err := v.clientset.AppsV1().Deployments(v.namespace).Get(ctx, "stress-app", metav1.GetOptions{})
	if err == nil {
		if hasCastAnnotations(deploy.Annotations) ||
			hasCastAnnotations(deploy.Spec.Template.Annotations) {
			return true
		}
	}

	return false
}

func hasCastAnnotations(annotations map[string]string) bool {
	for key := range annotations {
		keyLower := strings.ToLower(key)
		if strings.Contains(keyLower, "cast") ||
			strings.Contains(keyLower, "woop") ||
			strings.Contains(keyLower, "autoscaling.cast.ai") {
			return true
		}
	}
	return false
}
