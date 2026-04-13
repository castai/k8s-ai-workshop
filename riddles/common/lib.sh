#!/usr/bin/env bash
# Shared library for workshop scripts — colors, step runner, checks, state file.
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#   or:  source "$SCRIPT_DIR/lib.sh"

# --- Colors ---------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# --- Step runner -----------------------------------------------------------
# Runs a command silently. Shows [✓] on success, [✗] + captured output on failure.
# Usage: step "Install thing" command arg1 arg2
step() {
  local label="$1"; shift
  printf "  [ ] %s" "$label"
  local output exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  if [ $exit_code -eq 0 ]; then
    printf "\r  ${GREEN}[✓]${NC} %s\n" "$label"
  else
    printf "\r  ${RED}[✗]${NC} %s\n" "$label"
    if [ -n "$output" ]; then
      echo "$output" | sed 's/^/      /'
    fi
    return 1
  fi
}

# --- Check runner ----------------------------------------------------------
# For verify scripts. Runs a check, shows PASS/FAIL, updates counters.
# Callers must initialise CHECK_PASS=0 CHECK_FAIL=0 CHECK_TOTAL=0 before use.
# Usage: check "Pods are running" kubectl get pods ...
CHECK_PASS=0
CHECK_FAIL=0
CHECK_TOTAL=0

check() {
  local label="$1"; shift
  CHECK_TOTAL=$((CHECK_TOTAL + 1))
  local output exit_code=0
  output=$("$@" 2>&1) || exit_code=$?
  if [ $exit_code -eq 0 ]; then
    CHECK_PASS=$((CHECK_PASS + 1))
    printf "  ${GREEN}[✓]${NC} %s\n" "$label"
  else
    CHECK_FAIL=$((CHECK_FAIL + 1))
    printf "  ${RED}[✗]${NC} %s\n" "$label"
    if [ -n "$output" ]; then
      echo "$output" | sed 's/^/      /'
    fi
  fi
}

check_summary() {
  echo ""
  if [ "$CHECK_FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}${BOLD}All ${CHECK_PASS}/${CHECK_TOTAL} checks passed!${NC}"
  else
    echo -e "  ${RED}${CHECK_FAIL}/${CHECK_TOTAL} check(s) failed.${NC}"
  fi
  echo ""
  [ "$CHECK_FAIL" -eq 0 ]
}

# --- State file ------------------------------------------------------------
# Tracks completed bootstrap/setup steps locally so re-runs skip them.
# Plain text, one "key timestamp" per line, grep-friendly.
WORKSHOP_STATE_FILE="${WORKSHOP_STATE_FILE:-$HOME/.config/workshop/state}"

_state_init() {
  mkdir -p "$(dirname "$WORKSHOP_STATE_FILE")"
  touch "$WORKSHOP_STATE_FILE"
}

# state_done "key" — returns 0 if step was already completed
state_done() {
  [ -f "$WORKSHOP_STATE_FILE" ] && grep -q "^$1 " "$WORKSHOP_STATE_FILE" 2>/dev/null
}

# state_mark "key" — records step as completed
state_mark() {
  _state_init
  if ! state_done "$1"; then
    echo "$1 $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$WORKSHOP_STATE_FILE"
  fi
}

# state_reset — clears all state (full re-run)
state_reset() {
  rm -f "$WORKSHOP_STATE_FILE"
}

# --- Verifier binary -------------------------------------------------------
# Builds the Go verifier binary if missing or source is newer.
# Sets VERIFIER_BIN to the path of the built binary.
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER_BIN="${_LIB_DIR}/../../progress-reconciler/reconciler"
_RECONCILER_DIR="${_LIB_DIR}/../../progress-reconciler"

ensure_verifier() {
  if [ ! -x "$VERIFIER_BIN" ] || [ "$(find "$_RECONCILER_DIR" -name '*.go' -newer "$VERIFIER_BIN" 2>/dev/null | head -1)" ]; then
    if ! command -v go &>/dev/null; then
      printf "  ${RED}[✗]${NC} Go compiler not found (required to build verifier)\n" >&2
      printf "      Install Go from https://go.dev/dl/ or use your package manager\n" >&2
      return 1
    fi
    printf "  ${DIM}Building verifier...${NC}" >&2
    if ! (cd "$_RECONCILER_DIR" && go build -o reconciler ./cmd/reconciler) 2>/dev/null; then
      printf "\r  ${RED}[✗]${NC} Failed to build verifier binary\n" >&2
      return 1
    fi
    printf "\r  ${GREEN}[✓]${NC} Verifier built            \n" >&2
  fi
}

# run_verifier <riddle-number> <namespace>
# Runs the Go verifier and prints the raw JSON to stdout.
# Stderr goes to a temp file so errors are shown on failure.
run_verifier() {
  local riddle="$1" ns="$2"
  ensure_verifier || return 1

  if ! command -v python3 &>/dev/null; then
    printf "  ${RED}[✗]${NC} python3 not found (required to parse verifier output)\n" >&2
    return 1
  fi

  local stderr_file
  stderr_file=$(mktemp)
  local output
  output=$("$VERIFIER_BIN" verify --riddle "$riddle" --namespace "$ns" --format json 2>"$stderr_file")
  local rc=$?

  if [ -z "$output" ] && [ -s "$stderr_file" ]; then
    echo -e "${RED}Verifier error:${NC}" >&2
    cat "$stderr_file" >&2
  fi
  rm -f "$stderr_file"

  echo "$output"
}
