package verifiers

import "context"

// CheckResult holds the outcome of a single verification check.
type CheckResult struct {
	Name   string `json:"name"`
	Passed bool   `json:"passed"`
}

// VerifyResult holds the full output of a riddle verification run.
type VerifyResult struct {
	ChecksPassed int               `json:"checks_passed"`
	TotalChecks  int               `json:"total_checks"`
	Status       string            `json:"status"`
	Checks       []CheckResult     `json:"checks"`
	Metadata     map[string]string `json:"metadata,omitempty"`
}

// Verifier defines the interface for riddle verification
type Verifier interface {
	// Verify runs all checks for a riddle and returns a VerifyResult.
	Verify(ctx context.Context) VerifyResult
}

// DetermineStatus returns a status string based on pass/total counts.
func DetermineStatus(passed, total int) string {
	if passed == 0 {
		return "not_started"
	}
	if passed < total {
		return "in_progress"
	}
	return "completed"
}
