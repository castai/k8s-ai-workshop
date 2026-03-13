package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"

	"progress-reconciler/internal/config"
	"progress-reconciler/internal/reconciler"
	"progress-reconciler/internal/reporter"
	"progress-reconciler/pkg/health"
)

func main() {
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