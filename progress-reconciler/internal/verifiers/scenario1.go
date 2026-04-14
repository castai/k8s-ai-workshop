package verifiers

import (
	"context"
	"log"
	"strings"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/remotecommand"
)

// Riddle1Verifier implements verification for riddle-1 (Cluster Debugging)
type Riddle1Verifier struct {
	clientset *kubernetes.Clientset
	config    *rest.Config
	namespace string
}

// NewRiddle1Verifier creates a new Riddle 1 verifier
func NewRiddle1Verifier(clientset *kubernetes.Clientset, config *rest.Config, namespace string) *Riddle1Verifier {
	return &Riddle1Verifier{
		clientset: clientset,
		config:    config,
		namespace: namespace,
	}
}

// Verify runs all 10 checks for Riddle 1
func (v *Riddle1Verifier) Verify(ctx context.Context) VerifyResult {
	type namedCheck struct {
		name string
		fn   func(context.Context) bool
	}

	checks := []namedCheck{
		{"All deployments ready", v.checkAllDeploymentsReady},
		{"No pods pending", v.checkNoPodsInPending},
		{"No pods in error states", v.checkNoPodsInErrorStates},
		{"All init containers completed", v.checkAllInitContainersCompleted},
		{"All pods fully ready", v.checkAllPodsFullyReady},
		{"All services have endpoints", v.checkAllServicesHaveEndpoints},
		{"Entry point accessible", v.checkEntryPointAccessible},
		{"Core services reachable", v.checkCoreServicesReachable},
		{"Analytics service operational", v.checkAnalyticsServiceOperational},
		{"Dashboard reports nominal", v.checkDashboardReportsNominal},
	}

	results := make([]CheckResult, 0, len(checks))
	passed := 0

	for i, check := range checks {
		ok := check.fn(ctx)
		if ok {
			passed++
		} else {
			log.Printf("  Riddle1 Check %d/%d FAIL: %s", i+1, len(checks), check.name)
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

// Check 1: All deployments have desired replicas running
func (v *Riddle1Verifier) checkAllDeploymentsReady(ctx context.Context) bool {
	deployments, err := v.clientset.AppsV1().Deployments(v.namespace).List(ctx, metav1.ListOptions{})
	if err != nil || len(deployments.Items) == 0 {
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
func (v *Riddle1Verifier) checkNoPodsInPending(ctx context.Context) bool {
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		FieldSelector: "status.phase=Pending",
	})
	if err != nil {
		return false
	}

	return len(pods.Items) == 0
}

// Check 3: No pods in error states
func (v *Riddle1Verifier) checkNoPodsInErrorStates(ctx context.Context) bool {
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return false
	}

	errorStates := []string{"CrashLoopBackOff", "ImagePullBackOff", "Error", "ErrImagePull", "CreateContainerConfigError"}

	for _, pod := range pods.Items {
		// Check container statuses
		for _, cs := range pod.Status.ContainerStatuses {
			if cs.State.Waiting != nil {
				for _, errorState := range errorStates {
					if cs.State.Waiting.Reason == errorState {
						return false
					}
				}
			}
		}
		// Also check pod phase
		if pod.Status.Phase == corev1.PodFailed {
			return false
		}
	}

	return true
}

// Check 4: All init containers completed
func (v *Riddle1Verifier) checkAllInitContainersCompleted(ctx context.Context) bool {
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return false
	}

	hasInitContainers := false
	initPending := 0

	for _, pod := range pods.Items {
		if len(pod.Spec.InitContainers) > 0 {
			hasInitContainers = true
		}

		// Check if pod status shows "Init:" which means init containers are still running
		for _, condition := range pod.Status.Conditions {
			if condition.Type == corev1.PodInitialized && condition.Status != corev1.ConditionTrue {
				initPending++
			}
		}

		// Also check container statuses for init containers that haven't completed
		for _, initStatus := range pod.Status.InitContainerStatuses {
			if initStatus.State.Terminated == nil || initStatus.State.Terminated.ExitCode != 0 {
				if initStatus.State.Running != nil || initStatus.State.Waiting != nil {
					initPending++
				}
			}
		}
	}

	// Pass if: no init containers are pending AND at least one pod has init containers
	return initPending == 0 && hasInitContainers
}

// Check 5: All pods fully Ready (N/N)
func (v *Riddle1Verifier) checkAllPodsFullyReady(ctx context.Context) bool {
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{})
	if err != nil || len(pods.Items) == 0 {
		return false
	}

	for _, pod := range pods.Items {
		if !isPodReady(pod) {
			return false
		}
	}

	return true
}

// Check 6: All services have endpoints (skip services with annotation status=pending-deployment)
func (v *Riddle1Verifier) checkAllServicesHaveEndpoints(ctx context.Context) bool {
	services, err := v.clientset.CoreV1().Services(v.namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return false
	}

	for _, svc := range services.Items {
		// Skip services with annotation status=pending-deployment
		if svc.Annotations != nil && svc.Annotations["status"] == "pending-deployment" {
			continue
		}

		endpoints, err := v.clientset.CoreV1().Endpoints(v.namespace).Get(ctx, svc.Name, metav1.GetOptions{})
		if err != nil {
			return false
		}

		hasAddresses := false
		for _, subset := range endpoints.Subsets {
			if len(subset.Addresses) > 0 {
				hasAddresses = true
				break
			}
		}

		if !hasAddresses {
			return false
		}
	}

	return len(services.Items) > 0
}

// Check 7: Entry point accessible (via exec into a pod, works both in-cluster and from CLI)
func (v *Riddle1Verifier) checkEntryPointAccessible(ctx context.Context) bool {
	// Find config-service pod to use as tester (same as checks 8/9)
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=config-service",
	})
	if err != nil || len(pods.Items) == 0 {
		log.Printf("    Check 7: no config-service pod found to test from")
		return false
	}

	testerPod := pods.Items[0].Name
	url := "http://api-gateway:80"
	output, err := v.execInPod(ctx, testerPod, []string{"wget", "-q", "-O-", "-T", "5", "--server-response", url})
	if err != nil {
		log.Printf("    Check 7 error accessing %s via exec in %s: %v", url, testerPod, err)
		return false
	}

	// wget succeeded (exit 0) means HTTP 2xx/3xx
	_ = output
	return true
}

// Check 8: Core services reachable from within cluster
func (v *Riddle1Verifier) checkCoreServicesReachable(ctx context.Context) bool {
	// Find config-service pod to use as tester
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=config-service",
	})
	if err != nil || len(pods.Items) == 0 {
		return false
	}

	testerPod := pods.Items[0].Name
	coreServices := []string{
		"order-service",
		"inventory-service",
		"notification-service",
		"payment-processor-svc",
		"search-service",
		"recommendation-service",
	}

	for _, svc := range coreServices {
		url := "http://" + svc + ":8080/health"
		output, err := v.execInPod(ctx, testerPod, []string{"wget", "-q", "-O-", "-T", "3", url})
		if err != nil || !strings.Contains(output, "healthy") {
			return false
		}
	}

	return true
}

// Check 9: Analytics service operational
func (v *Riddle1Verifier) checkAnalyticsServiceOperational(ctx context.Context) bool {
	// Find config-service pod to use as tester
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=config-service",
	})
	if err != nil || len(pods.Items) == 0 {
		return false
	}

	testerPod := pods.Items[0].Name
	url := "http://analytics-service:8080/health"
	output, err := v.execInPod(ctx, testerPod, []string{"wget", "-q", "-O-", "-T", "3", url})
	if err != nil || !strings.Contains(output, "healthy") {
		return false
	}

	return true
}

// Check 10: Dashboard reports "All systems nominal" (via exec into a pod)
func (v *Riddle1Verifier) checkDashboardReportsNominal(ctx context.Context) bool {
	// Find config-service pod to use as tester (same as checks 7/8/9)
	pods, err := v.clientset.CoreV1().Pods(v.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "app=config-service",
	})
	if err != nil || len(pods.Items) == 0 {
		log.Printf("    Check 10: no config-service pod found to test from")
		return false
	}

	testerPod := pods.Items[0].Name
	url := "http://api-gateway:80"
	output, err := v.execInPod(ctx, testerPod, []string{"wget", "-q", "-O-", "-T", "5", url})
	if err != nil {
		log.Printf("    Check 10 error accessing %s via exec in %s: %v", url, testerPod, err)
		return false
	}

	contains := strings.Contains(output, "All systems nominal")
	if !contains {
		log.Printf("    Check 10: 'All systems nominal' not found in response")
	}
	return contains
}

// Helper: Execute command in pod
func (v *Riddle1Verifier) execInPod(ctx context.Context, podName string, command []string) (string, error) {
	req := v.clientset.CoreV1().RESTClient().Post().
		Resource("pods").
		Name(podName).
		Namespace(v.namespace).
		SubResource("exec").
		VersionedParams(&corev1.PodExecOptions{
			Command: command,
			Stdout:  true,
			Stderr:  true,
		}, scheme.ParameterCodec)

	exec, err := remotecommand.NewSPDYExecutor(v.config, "POST", req.URL())
	if err != nil {
		return "", err
	}

	var stdout, stderr strings.Builder
	err = exec.StreamWithContext(ctx, remotecommand.StreamOptions{
		Stdout: &stdout,
		Stderr: &stderr,
	})

	return stdout.String(), err
}

// Helper: Check if pod is ready
func isPodReady(pod corev1.Pod) bool {
	for _, condition := range pod.Status.Conditions {
		if condition.Type == corev1.PodReady {
			return condition.Status == corev1.ConditionTrue
		}
	}
	return false
}
