package reporter

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

// ReportMessage represents a progress report to Supabase
type ReportMessage struct {
	ClusterUID       string `json:"cluster_uid"`
	RiddleID         string `json:"riddle_id,omitempty"`
	Status           string `json:"status,omitempty"`
	ChecksPassed     int    `json:"checks_passed,omitempty"`
	TotalChecks      int    `json:"total_checks,omitempty"`
	ClusterConnected *bool  `json:"cluster_connected,omitempty"`
	Timestamp        string `json:"timestamp"`
}

// SupabaseReporter handles reporting to Supabase with retry logic
type SupabaseReporter struct {
	client         *http.Client
	baseURL        string
	clusterUID     string
	reportQueue    chan ReportMessage
	retryAttempts  int
	retryBackoff   time.Duration
}

// NewSupabaseReporter creates a new Supabase reporter
func NewSupabaseReporter(clusterUID, baseURL string, retryAttempts int, retryBackoff time.Duration) *SupabaseReporter {
	return &SupabaseReporter{
		client: &http.Client{
			Timeout: 10 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        10,
				IdleConnTimeout:     30 * time.Second,
				DisableKeepAlives:   false,
				MaxIdleConnsPerHost: 5,
			},
		},
		baseURL:       baseURL,
		clusterUID:    clusterUID,
		reportQueue:   make(chan ReportMessage, 100),
		retryAttempts: retryAttempts,
		retryBackoff:  retryBackoff,
	}
}

// Start begins the async reporter worker
func (r *SupabaseReporter) Start(ctx context.Context) {
	go func() {
		for {
			select {
			case msg := <-r.reportQueue:
				r.ReportWithRetry(msg)
			case <-ctx.Done():
				log.Println("Reporter worker stopped")
				return
			}
		}
	}()
}

// QueueReport adds a report to the async queue (non-blocking)
func (r *SupabaseReporter) QueueReport(msg ReportMessage) {
	// Set cluster UID and timestamp
	msg.ClusterUID = r.clusterUID
	msg.Timestamp = time.Now().UTC().Format(time.RFC3339)

	select {
	case r.reportQueue <- msg:
		// Queued successfully
	default:
		log.Printf("⚠️  Report queue full, dropping message for riddle_id=%s", msg.RiddleID)
	}
}

// ReportWithRetry attempts to report with exponential backoff
func (r *SupabaseReporter) ReportWithRetry(msg ReportMessage) {
	backoff := r.retryBackoff

	for attempt := 1; attempt <= r.retryAttempts; attempt++ {
		err := r.ReportProgress(msg)
		if err == nil {
			return // Success
		}

		log.Printf("⚠️  Report failed (attempt %d/%d): %v", attempt, r.retryAttempts, err)

		if attempt < r.retryAttempts {
			time.Sleep(backoff)
			backoff *= 2 // Exponential backoff
		}
	}

	log.Printf("❌ Failed to report after %d attempts, giving up (riddle_id=%s)", r.retryAttempts, msg.RiddleID)
}

// ReportProgress sends a single report to Supabase
func (r *SupabaseReporter) ReportProgress(msg ReportMessage) error {
	jsonData, err := json.Marshal(msg)
	if err != nil {
		return fmt.Errorf("marshal error: %w", err)
	}

	req, err := http.NewRequest("POST", r.baseURL, bytes.NewBuffer(jsonData))
	if err != nil {
		return fmt.Errorf("request creation error: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := r.client.Do(req)
	if err != nil {
		return fmt.Errorf("http error: %w", err)
	}
	defer resp.Body.Close()

	// Read response body
	body, readErr := io.ReadAll(resp.Body)
	if readErr != nil {
		log.Printf("⚠️  Warning: could not read response body: %v", readErr)
	}

	if resp.StatusCode >= 400 {
		return fmt.Errorf("server error %d: %s", resp.StatusCode, string(body))
	}

	// Log successful report with response details
	if msg.ClusterConnected != nil && *msg.ClusterConnected {
		log.Printf("✅ Reported cluster connection: cluster_uid=%s | HTTP %d | Response: %s",
			msg.ClusterUID, resp.StatusCode, string(body))
	} else if msg.RiddleID != "" {
		log.Printf("✅ Reported progress: riddle_id=%s, status=%s, checks=%d/%d | HTTP %d | Response: %s",
			msg.RiddleID, msg.Status, msg.ChecksPassed, msg.TotalChecks, resp.StatusCode, string(body))
	}

	return nil
}