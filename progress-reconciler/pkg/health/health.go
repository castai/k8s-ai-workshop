package health

import (
	"encoding/json"
	"net/http"
	"time"

	"progress-reconciler/internal/reconciler"
)

// Server provides health check endpoints
type Server struct {
	reconciler *reconciler.Reconciler
}

// NewServer creates a new health server
func NewServer(r *reconciler.Reconciler) *Server {
	return &Server{reconciler: r}
}

// Start starts the health HTTP server
func (s *Server) Start(addr string) error {
	mux := http.NewServeMux()

	mux.HandleFunc("/health", s.handleHealth)
	mux.HandleFunc("/ready", s.handleReady)
	mux.HandleFunc("/status", s.handleStatus)

	return http.ListenAndServe(addr, mux)
}

// handleHealth returns a simple OK response (liveness probe)
func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

// handleReady returns Ready when server is ready (readiness probe)
func (s *Server) handleReady(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("Ready"))
}

// handleStatus returns current riddle states as JSON
func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	states := s.reconciler.GetStates()

	response := map[string]interface{}{
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"riddles":   states,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}
