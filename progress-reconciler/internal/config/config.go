package config

import (
	"context"
	"fmt"
	"log"
	"time"

	"gopkg.in/yaml.v3"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

// Config represents the reconciler configuration
type Config struct {
	ReconciliationInterval time.Duration  `yaml:"reconciliation_interval"`
	ReportMinInterval      time.Duration  `yaml:"report_min_interval"`
	StartupGracePeriod     time.Duration  `yaml:"startup_grace_period"`
	SupabaseURL            string         `yaml:"supabase_url"`
	RetryMaxAttempts       int            `yaml:"retry_max_attempts"`
	RetryBackoffInitial    time.Duration  `yaml:"retry_backoff_initial"`
	Riddles                []RiddleConfig `yaml:"riddles"`
}

// RiddleConfig represents a single riddle/riddle configuration
type RiddleConfig struct {
	RiddleID    string `yaml:"riddle_id"`
	Namespace   string `yaml:"namespace"`
	Enabled     bool   `yaml:"enabled"`
	Description string `yaml:"description"`
	TotalChecks int    `yaml:"total_checks"`
}

// LoadConfig loads configuration from ConfigMap or returns defaults
func LoadConfig(clientset *kubernetes.Clientset) (*Config, error) {
	// Try to load from ConfigMap
	cm, err := clientset.CoreV1().ConfigMaps("progress-reconciler").Get(
		context.Background(),
		"progress-reconciler-config",
		metav1.GetOptions{},
	)
	if err != nil {
		log.Printf("⚠️  ConfigMap not found, using hardcoded defaults: %v", err)
		return GetDefaultConfig(), nil
	}

	configData, ok := cm.Data["config.yaml"]
	if !ok {
		log.Printf("⚠️  config.yaml not found in ConfigMap, using defaults")
		return GetDefaultConfig(), nil
	}

	config := &Config{}
	err = yaml.Unmarshal([]byte(configData), config)
	if err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	log.Printf("✅ Configuration loaded from ConfigMap: %d riddles configured", len(config.Riddles))
	return config, nil
}

// GetDefaultConfig returns hardcoded default configuration
func GetDefaultConfig() *Config {
	return &Config{
		ReconciliationInterval: 15 * time.Second,
		ReportMinInterval:      15 * time.Second,
		StartupGracePeriod:     30 * time.Second,
		SupabaseURL:            "https://hsnxzbyedgzepraxwpar.supabase.co/functions/v1/report-progress",
		RetryMaxAttempts:       3,
		RetryBackoffInitial:    1 * time.Second,
		Riddles: []RiddleConfig{
			{
				RiddleID:    "2eecc00a-79a6-4d8e-92a3-06440b5d08c2",
				Namespace:   "riddle-1",
				Enabled:     true,
				Description: "Cluster Debugging",
				TotalChecks: 10,
			},
			{
				RiddleID:    "24e96064-68d7-4bf9-b222-af29fe2306be",
				Namespace:   "riddle-2",
				Enabled:     true,
				Description: "Scaling Under Pressure",
				TotalChecks: 5,
			},
			{
				RiddleID:    "7d7c5ea7-9b3d-4890-ac40-c79b8f30c778",
				Namespace:   "riddle-3",
				Enabled:     true,
				Description: "The Slow Burn",
				TotalChecks: 5,
			},
		},
	}
}
