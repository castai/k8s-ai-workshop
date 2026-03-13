package reporter

import (
	"sync"
	"time"
)

// RateLimiter prevents too-frequent reports for the same riddle
type RateLimiter struct {
	lastReportTime map[string]time.Time
	minInterval    time.Duration
	mu             sync.Mutex
}

// NewRateLimiter creates a new rate limiter
func NewRateLimiter(minInterval time.Duration) *RateLimiter {
	return &RateLimiter{
		lastReportTime: make(map[string]time.Time),
		minInterval:    minInterval,
	}
}

// ShouldReport checks if enough time has passed since last report for this riddle
func (rl *RateLimiter) ShouldReport(riddleID string) bool {
	rl.mu.Lock()
	defer rl.mu.Unlock()

	lastReport, exists := rl.lastReportTime[riddleID]
	if !exists || time.Since(lastReport) >= rl.minInterval {
		rl.lastReportTime[riddleID] = time.Now()
		return true
	}

	return false
}

// Reset clears rate limit history (useful for testing)
func (rl *RateLimiter) Reset() {
	rl.mu.Lock()
	defer rl.mu.Unlock()
	rl.lastReportTime = make(map[string]time.Time)
}