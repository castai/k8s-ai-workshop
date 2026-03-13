package verifiers

import (
	"context"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

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
func NewRiddle1Verifier(clientset *kubernetes.Clientset, namespace string) *Riddle1Verifier {
	config, _ := rest.InClusterConfig()
	return &Riddle1Verifier{
		clientset: clientset,
		config:    config,
		namespace: namespace,
	}
}

// Verify runs all 10 checks for Riddle 1
func (v *Riddle1Verifier) Verify(ctx context.Context) (checksPassed, totalChecks int, status string) {
	type checkFunc struct {
		name string
		fn   func(context.Context) bool
	}

	checks := []checkFunc{
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

	totalChecks = len(checks)
	checksPassed = 0

	for i, check := range checks {
		passed := check.fn(ctx)
		if passed {
			checksPassed++
		} else {
			log.Printf("  Riddle1 Check %d/%d FAIL: %s", i+1, totalChecks, check.name)
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

// Check 7: Entry point accessible
func (v *Riddle1Verifier) checkEntryPointAccessible(ctx context.Context) bool {
	// Create fresh client with no connection reuse
	client := &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			DisableKeepAlives:   true,
			MaxIdleConns:        1,
			MaxIdleConnsPerHost: 1,
		},
	}

	// Use service name with namespace
	url := "http://api-gateway." + v.namespace + ":80"

	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		log.Printf("    Check 7 error creating request for %s: %v", url, err)
		return false
	}

	resp, err := client.Do(req)
	if err != nil {
		log.Printf("    Check 7 error accessing %s: %v", url, err)
		return false
	}
	defer resp.Body.Close()

	success := resp.StatusCode >= 200 && resp.StatusCode < 400
	if !success {
		log.Printf("    Check 7 got status code: %d from %s", resp.StatusCode, url)
	}
	return success
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

// Check 10: Dashboard reports "All systems nominal"
func (v *Riddle1Verifier) checkDashboardReportsNominal(ctx context.Context) bool {
	// Create fresh client with no connection reuse
	client := &http.Client{
		Timeout: 10 * time.Second,
		Transport: &http.Transport{
			DisableKeepAlives: true,
		},
	}

	// Use service name with namespace
	url := "http://api-gateway." + v.namespace + ":80"
	resp, err := client.Get(url)
	if err != nil {
		log.Printf("    Check 10 error accessing %s: %v", url, err)
		return false
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("    Check 10 error reading body: %v", err)
		return false
	}

	contains := strings.Contains(string(body), "All systems nominal")
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
