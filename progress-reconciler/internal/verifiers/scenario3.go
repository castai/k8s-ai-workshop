package verifiers

import (
	"context"
	"fmt"

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
		{"Memory limit >= 150Mi (headroom)", v.checkMemoryLimitSufficient},
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
		Metadata:     v.collectMetadata(ctx),
	}
}

// collectMetadata gathers display-only information for the CLI output.
func (v *Riddle3Verifier) collectMetadata(ctx context.Context) map[string]string {
	meta := map[string]string{}

	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=stress-app",
	})
	if err != nil {
		return meta
	}

	total := len(pods.Items)
	running := 0
	for _, pod := range pods.Items {
		if pod.Status.Phase == corev1.PodRunning {
			running++
		}
	}
	meta["total_pods"] = fmt.Sprintf("%d", total)
	meta["running_pods"] = fmt.Sprintf("%d", running)

	// Memory request from first running pod
	for _, pod := range pods.Items {
		if pod.Status.Phase == corev1.PodRunning && len(pod.Spec.Containers) > 0 {
			memReq := pod.Spec.Containers[0].Resources.Requests.Memory()
			if memReq != nil {
				meta["memory_request"] = memReq.String()
			}
			break
		}
	}

	// Fall back to deployment spec if no running pods (e.g. all OOMKilling)
	if _, ok := meta["memory_request"]; !ok {
		deploy, err := v.clientset.AppsV1().Deployments(v.namespace).Get(ctx, "stress-app", metav1.GetOptions{})
		if err == nil && len(deploy.Spec.Template.Spec.Containers) > 0 {
			memReq := deploy.Spec.Template.Spec.Containers[0].Resources.Requests.Memory()
			if memReq != nil {
				meta["memory_request"] = memReq.String()
			}
		}
	}

	return meta
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
	// Get running pods (VPA may modify pod spec directly, not deployment)
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

// Check 5: Memory limit >= 150Mi (rewards setting limit with proper headroom)
func (v *Riddle3Verifier) checkMemoryLimitSufficient(ctx context.Context) bool {
	// Check running pods first (VPA may modify pod spec directly)
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=stress-app",
		FieldSelector: "status.phase=Running",
	})
	if err == nil && len(pods.Items) > 0 {
		pod := pods.Items[0]
		if len(pod.Spec.Containers) > 0 {
			memLimit := pod.Spec.Containers[0].Resources.Limits.Memory()
			if memLimit != nil {
				minLimit := resource.MustParse("150Mi")
				return memLimit.Cmp(minLimit) >= 0
			}
		}
	}

	// Fall back to deployment spec
	deploy, err := v.clientset.AppsV1().Deployments(v.namespace).Get(ctx, "stress-app", metav1.GetOptions{})
	if err == nil && len(deploy.Spec.Template.Spec.Containers) > 0 {
		memLimit := deploy.Spec.Template.Spec.Containers[0].Resources.Limits.Memory()
		if memLimit != nil {
			minLimit := resource.MustParse("150Mi")
			return memLimit.Cmp(minLimit) >= 0
		}
	}

	return false
}
