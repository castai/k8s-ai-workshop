package reconciler

import "time"

// RiddleState tracks the state of a single riddle/riddle
type RiddleState struct {
	RiddleID       string
	Namespace      string
	LastStatus     string // "not_started", "in_progress", "completed"
	ChecksPassed   int
	TotalChecks    int
	LastReportTime time.Time
	FirstSeenTime  time.Time
}
