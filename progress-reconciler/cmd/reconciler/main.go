package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"

	"progress-reconciler/internal/config"
	"progress-reconciler/internal/reconciler"
	"progress-reconciler/internal/reporter"
	"progress-reconciler/internal/verifiers"
	"progress-reconciler/pkg/health"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "verify" {
		os.Exit(runVerify(os.Args[2:]))
	}

	runReconciler()
}

// runVerify runs a single verification pass from the CLI and exits.
func runVerify(args []string) int {
	fs := flag.NewFlagSet("verify", flag.ExitOnError)
	riddle := fs.Int("riddle", 0, "Riddle number (1, 2, or 3)")
	namespace := fs.String("namespace", "", "Kubernetes namespace to verify")
	format := fs.String("format", "text", "Output format: text or json")
	fs.Parse(args)

	if *riddle < 1 || *riddle > 3 {
		fmt.Fprintf(os.Stderr, "Error: --riddle must be 1, 2, or 3\n")
		return 1
	}
	if *namespace == "" {
		*namespace = fmt.Sprintf("riddle-%d", *riddle)
	}

	// Build kubeconfig: try in-cluster first, fall back to ~/.kube/config
	cfg, err := rest.InClusterConfig()
	if err != nil {
		kubeconfig := os.Getenv("KUBECONFIG")
		if kubeconfig == "" {
			kubeconfig = filepath.Join(os.Getenv("HOME"), ".kube", "config")
		}
		cfg, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: cannot build kubeconfig: %v\n", err)
			return 1
		}
	}

	clientset, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: cannot create kubernetes client: %v\n", err)
		return 1
	}

	// Silence log output in CLI mode so only the result is printed
	log.SetOutput(os.Stderr)

	var verifier verifiers.Verifier
	switch *riddle {
	case 1:
		verifier = verifiers.NewRiddle1Verifier(clientset, cfg, *namespace)
	case 2:
		verifier = verifiers.NewRiddle2Verifier(clientset, *namespace)
	case 3:
		verifier = verifiers.NewRiddle3Verifier(clientset, *namespace)
	}

	result := verifier.Verify(context.Background())

	switch *format {
	case "json":
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		enc.Encode(result)
	default:
		for _, c := range result.Checks {
			mark := "PASS"
			if !c.Passed {
				mark = "FAIL"
			}
			fmt.Printf("  [%s] %s\n", mark, c.Name)
		}
		fmt.Printf("\n%d/%d checks passed — %s\n", result.ChecksPassed, result.TotalChecks, result.Status)
	}

	if result.ChecksPassed == result.TotalChecks {
		return 0
	}
	return 1
}

// runReconciler is the original in-cluster reconciliation loop.
func runReconciler() {
	log.Println("🚀 Starting Progress Reconciler...")

	// Create in-cluster config
	cfg, err := rest.InClusterConfig()
	if err != nil {
		log.Fatalf("❌ Failed to create in-cluster config: %v", err)
	}

	// Create clientset
	clientset, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		log.Fatalf("❌ Failed to create clientset: %v", err)
	}

	// Get cluster UID from kube-system namespace
	kubeSystem, err := clientset.CoreV1().Namespaces().Get(
		context.Background(),
		"kube-system",
		metav1.GetOptions{},
	)
	if err != nil {
		log.Fatalf("❌ Failed to get kube-system namespace: %v", err)
	}
	clusterUID := string(kubeSystem.UID)
	log.Printf("🆔 Cluster UID: %s", clusterUID)

	// Load configuration
	appConfig, err := config.LoadConfig(clientset)
	if err != nil {
		log.Fatalf("❌ Failed to load config: %v", err)
	}
	log.Printf("⚙️  Configuration loaded: %d riddles configured", len(appConfig.Riddles))

	// Create reporter
	supabaseReporter := reporter.NewSupabaseReporter(
		clusterUID,
		appConfig.SupabaseURL,
		appConfig.RetryMaxAttempts,
		appConfig.RetryBackoffInitial,
	)

	// Start reporter worker
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	supabaseReporter.Start(ctx)

	// Report initial cluster connection
	boolTrue := true
	supabaseReporter.QueueReport(reporter.ReportMessage{
		ClusterConnected: &boolTrue,
	})

	// Create reconciler
	rec := reconciler.NewReconciler(
		clientset,
		cfg,
		appConfig,
		supabaseReporter,
	)

	// Start health server
	healthServer := health.NewServer(rec)
	go func() {
		log.Println("🏥 Starting health server on :8080")
		if err := healthServer.Start(":8080"); err != nil {
			log.Printf("❌ Health server error: %v", err)
		}
	}()

	// Start reconciliation loop
	go rec.Run(ctx)

	log.Println("✅ Progress Reconciler started successfully")

	// Wait for shutdown signal
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGINT, syscall.SIGTERM)
	<-sigChan

	log.Println("🛑 Shutting down gracefully...")
	cancel()
	time.Sleep(2 * time.Second) // Allow pending reports to complete
	log.Println("👋 Shutdown complete")
}
