package verifiers

import "context"

// Verifier defines the interface for riddle verification
type Verifier interface {
	// Verify runs all checks for a riddle and returns:
	// - checksPassed: number of checks that passed
	// - totalChecks: total number of checks
	// - status: "not_started" (0 checks), "in_progress" (some checks), or "completed" (all checks)
	Verify(ctx context.Context) (checksPassed, totalChecks int, status string)
}
