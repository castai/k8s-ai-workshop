#!/usr/bin/env bash

# Riddle 3: Resource Right-Sizing - Verification & Scoring
# Checks if OOMKill issues are resolved and resources are properly configured

set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../common/lib.sh
source "$SCRIPT_DIR/../common/lib.sh"

echo ""
echo -e "${CYAN}==================================================${NC}"
echo -e "${CYAN}  Riddle 3: Resource Right-Sizing - Verification${NC}"
echo -e "${CYAN}==================================================${NC}"
echo ""

# ── Validate Setup ────────────────────────────────────────────────────

if ! kubectl get namespace riddle-3 &>/dev/null; then
    echo -e "${RED}Namespace 'riddle-3' not found. Run ./setup.sh first${NC}"
    exit 1
fi

if ! kubectl get deployment stress-app -n riddle-3 &>/dev/null; then
    echo -e "${RED}Deployment 'stress-app' not found in riddle-3${NC}"
    exit 1
fi

# ── Run Go verifier ───────────────────────────────────────────────────

RESULT=$(run_verifier 3 riddle-3)
if [ -z "$RESULT" ]; then
    echo -e "${RED}Verifier returned no output. Is your kubeconfig configured?${NC}"
    exit 1
fi

echo "Running checks..."
echo ""

# Parse check results
# Check order: 0=NoOOM, 1=AllRunning, 2=NoRecentOOM, 3=MemReq, 4=WOOP
readarray -t NAMES < <(echo "$RESULT" | python3 -c "
import sys, json
for c in json.load(sys.stdin)['checks']:
    print(c['name'])
")
readarray -t PASSED < <(echo "$RESULT" | python3 -c "
import sys, json
for c in json.load(sys.stdin)['checks']:
    print(c['passed'])
")

TOTAL=${#NAMES[@]}
PASS=0
for i in $(seq 0 $((TOTAL - 1))); do
    if [ "${PASSED[$i]}" = "True" ]; then
        echo -e "  ${GREEN}✓${NC} ${NAMES[$i]}"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} ${NAMES[$i]}"
    fi
done

FAIL=$((TOTAL - PASS))

# Map check results to named booleans for scoring
NO_OOMKILL="${PASSED[0]}"
ALL_RUNNING="${PASSED[1]}"
NO_RECENT_OOM="${PASSED[2]}"
MEM_REQ_OK="${PASSED[3]}"
WOOP_APPLIED="${PASSED[4]}"

# ── Gather display info from cluster ──────────────────────────────────

MEM_REQ="unknown"
RUNNING_COUNT=0
TOTAL_PODS=0
POD_NAME=$(kubectl get pods -l app=stress-app -n riddle-3 --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD_NAME" ]; then
    MEM_REQ=$(kubectl get pod "$POD_NAME" -n riddle-3 -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "unknown")
fi
TOTAL_PODS=$(kubectl get pods -l app=stress-app -n riddle-3 --no-headers 2>/dev/null | wc -l | tr -d ' ')
RUNNING_COUNT=$(kubectl get pods -l app=stress-app -n riddle-3 --no-headers 2>/dev/null | grep -c 'Running' || true)

# ── Calculate Score ───────────────────────────────────────────────────

echo ""
echo "=================================================="
echo -e "  Result: ${BLUE}$PASS/$TOTAL checks passed${NC}"
echo "=================================================="
echo ""

SCORE=0
MAX_SCORE=1000

# Check 1-2: Pods healthy - no OOM, all running (300 pts)
if [ "$NO_OOMKILL" = "True" ] && [ "$ALL_RUNNING" = "True" ]; then
    SCORE=$((SCORE + 300))
elif [ "$NO_OOMKILL" = "True" ] || [ "$ALL_RUNNING" = "True" ]; then
    SCORE=$((SCORE + 150))
fi

# Check 3: No recent OOM (100 pts)
if [ "$NO_RECENT_OOM" = "True" ]; then
    SCORE=$((SCORE + 100))
fi

# Check 4: Resource configuration correct (200 pts)
if [ "$MEM_REQ_OK" = "True" ]; then
    SCORE=$((SCORE + 200))
fi

# Check 5: WOOP applied (400 pts bonus)
if [ "$WOOP_APPLIED" = "True" ]; then
    SCORE=$((SCORE + 400))
fi

echo -e "  ${BOLD}Final Score: ${YELLOW}$SCORE${NC} / $MAX_SCORE"
echo ""
echo "  Resource Configuration:"
echo "    - Memory request: $MEM_REQ"
echo "    - Running pods:   $RUNNING_COUNT/$TOTAL_PODS"
if [ "$WOOP_APPLIED" = "True" ]; then
    echo -e "    - WOOP:           ${GREEN}Recommendations applied${NC}"
else
    echo -e "    - WOOP:           ${YELLOW}No recommendations detected${NC}"
fi
echo ""

if [ "$PASS" -eq "$TOTAL" ]; then
    echo -e "${GREEN}All checks passed! Resource right-sizing complete.${NC}"
    echo ""
    exit 0
else
    echo -e "${YELLOW}$FAIL check(s) still pending.${NC}"
    echo ""
    if [ "$NO_OOMKILL" = "False" ] || [ "$ALL_RUNNING" = "False" ]; then
        echo "Hints:"
        echo "  - Check pod status:    kubectl get pods -n riddle-3"
        echo "  - Describe pod:        kubectl describe pod -l app=stress-app -n riddle-3"
        echo "  - Check events:        kubectl get events -n riddle-3 --sort-by='.lastTimestamp'"
    fi
    if [ "$MEM_REQ_OK" = "False" ]; then
        echo "  - Check resources:     kubectl get deploy stress-app -n riddle-3 -o yaml | grep -A 8 resources"
    fi
    if [ "$WOOP_APPLIED" = "False" ]; then
        echo "  - Check WOOP status:   kubectl get recommendations -n riddle-3"
    fi
    echo ""
    exit 1
fi
