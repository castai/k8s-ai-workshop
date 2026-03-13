#!/usr/bin/env bash

# Riddle 3: Resource Right-Sizing - Verification & Scoring
# Checks if OOMKill issues are resolved and resources are properly configured

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

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

# ── Check Conditions ──────────────────────────────────────────────────

PASS=0
FAIL=0

check_result() {
    local name="$1"
    local result="$2"
    if [ "$result" = "true" ]; then
        echo -e "  ${GREEN}✓${NC} $name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $name"
        FAIL=$((FAIL + 1))
    fi
}

echo "Running checks..."
echo ""

# Check 1: No OOMKilled pods currently
NO_OOMKILL="true"
OOMKILL_COUNT=0
while IFS= read -r line; do
    status=$(echo "$line" | awk '{print $3}')
    if [ "$status" = "OOMKilled" ]; then
        NO_OOMKILL="false"
        OOMKILL_COUNT=$((OOMKILL_COUNT + 1))
    fi
done < <(kubectl get pods -l app=stress-app -n riddle-3 --no-headers 2>/dev/null)
check_result "No pods in OOMKilled state" "$NO_OOMKILL"

# Check 2: All pods are Running and Ready
ALL_RUNNING="true"
RUNNING_COUNT=0
TOTAL_PODS=0
while IFS= read -r line; do
    TOTAL_PODS=$((TOTAL_PODS + 1))
    ready=$(echo "$line" | awk '{print $2}')
    status=$(echo "$line" | awk '{print $3}')
    if [ "$status" = "Running" ] && [ "$ready" = "1/1" ]; then
        RUNNING_COUNT=$((RUNNING_COUNT + 1))
    else
        ALL_RUNNING="false"
    fi
done < <(kubectl get pods -l app=stress-app -n riddle-3 --no-headers 2>/dev/null)
check_result "All pods Running and Ready ($RUNNING_COUNT/$TOTAL_PODS)" "$ALL_RUNNING"

# Check 3: No recent OOMKill restarts (restart count should be 0 or pods were replaced)
NO_RECENT_OOM="true"
for pod in $(kubectl get pods -l app=stress-app -n riddle-3 -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    LAST_REASON=$(kubectl get pod "$pod" -n riddle-3 -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null || echo "")
    if [ "$LAST_REASON" = "OOMKilled" ]; then
        NO_RECENT_OOM="false"
        break
    fi
done
check_result "No recent OOMKill terminations" "$NO_RECENT_OOM"

# Check 4: Memory request is reasonable (>= 120Mi for stable 120Mi workload)
# WOOP modifies pod spec directly, so check actual running pods
MEM_REQ_OK="false"
MEM_REQ="0"
# Get a running pod (WOOP modifies pod spec, not deployment)
POD_NAME=$(kubectl get pods -l app=stress-app -n riddle-3 --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD_NAME" ]; then
    MEM_REQ=$(kubectl get pod "$POD_NAME" -n riddle-3 -o jsonpath='{.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "0")
fi
MEM_REQ_MI=0
if echo "$MEM_REQ" | grep -qE '^[0-9]+Mi$'; then
    MEM_REQ_MI=$(echo "$MEM_REQ" | sed 's/Mi//')
elif echo "$MEM_REQ" | grep -qE '^[0-9]+Gi$'; then
    MEM_REQ_MI=$(($(echo "$MEM_REQ" | sed 's/Gi//') * 1024))
elif echo "$MEM_REQ" | grep -qE '^[0-9]+M$'; then
    MEM_REQ_MI=$(echo "$MEM_REQ" | sed 's/M//')
fi
if [ "$MEM_REQ_MI" -ge 120 ] 2>/dev/null; then
    MEM_REQ_OK="true"
fi
check_result "Memory request >= 120Mi (current: $MEM_REQ)" "$MEM_REQ_OK"

# Check 6: WOOP applied recommendations (check for Recommendation CR or CAST AI annotations)
WOOP_APPLIED="false"

# Method 1: Check for Recommendation CRs targeting stress-app
REC_COUNT=$(kubectl get recommendations -n riddle-3 -o json 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
count=0
for item in d.get('items',[]):
    ref = item.get('spec',{}).get('targetRef',{})
    if ref.get('name') == 'stress-app':
        count += 1
print(count)
" 2>/dev/null || echo "0")
if [ "$REC_COUNT" -gt 0 ]; then
    WOOP_APPLIED="true"
fi

# Method 2: Check for CAST AI annotations on the deployment or pod template
if [ "$WOOP_APPLIED" = "false" ]; then
    CAST_ANNS=$(kubectl get deployment stress-app -n riddle-3 -o json 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
anns = d.get('metadata',{}).get('annotations',{})
template_anns = d['spec']['template'].get('metadata',{}).get('annotations',{})
all_anns = {**anns, **template_anns}
cast_keys = [k for k in all_anns if 'cast' in k.lower() or 'woop' in k.lower() or 'workload-autoscaling.cast.ai' in k]
print(len(cast_keys))
" 2>/dev/null || echo "0")
    if [ "$CAST_ANNS" -gt 0 ]; then
        WOOP_APPLIED="true"
    fi
fi

# Method 3: Check for PodMutation resources targeting riddle-3
if [ "$WOOP_APPLIED" = "false" ]; then
    POMU_COUNT=$(kubectl get podmutations -A -o json 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
count=0
for item in d.get('items',[]):
    spec = item.get('spec',{})
    ns = spec.get('namespaceSelector',{}).get('matchNames',[])
    labels = spec.get('selector',{}).get('matchLabels',{})
    if 'riddle-3' in ns or labels.get('app') == 'stress-app':
        count += 1
print(count)
" 2>/dev/null || echo "0")
    if [ "$POMU_COUNT" -gt 0 ]; then
        WOOP_APPLIED="true"
    fi
fi

check_result "WOOP applied resource recommendations" "$WOOP_APPLIED"

# ── Calculate Score ───────────────────────────────────────────────────

echo ""
echo "=================================================="
echo -e "  Result: ${BLUE}$PASS/$((PASS+FAIL)) checks passed${NC}"
echo "=================================================="
echo ""

SCORE=0
MAX_SCORE=1000

# Check 1-2: Pods healthy - no OOM, all running (300 pts)
HEALTHY_SCORE=0
if [ "$NO_OOMKILL" = "true" ] && [ "$ALL_RUNNING" = "true" ]; then
    HEALTHY_SCORE=300
elif [ "$NO_OOMKILL" = "true" ] || [ "$ALL_RUNNING" = "true" ]; then
    HEALTHY_SCORE=150
fi
SCORE=$((SCORE + HEALTHY_SCORE))

# Check 3: No recent OOM (100 pts)
if [ "$NO_RECENT_OOM" = "true" ]; then
    SCORE=$((SCORE + 100))
fi

# Check 4: Resource configuration correct (200 pts)
if [ "$MEM_REQ_OK" = "true" ]; then
    SCORE=$((SCORE + 200))
fi

# Check 5: WOOP applied (400 pts bonus)
if [ "$WOOP_APPLIED" = "true" ]; then
    SCORE=$((SCORE + 400))
fi

echo -e "  ${BOLD}Final Score: ${YELLOW}$SCORE${NC} / $MAX_SCORE"
echo ""
echo "  Resource Configuration:"
echo "    - Memory request: $MEM_REQ"
echo "    - Running pods:   $RUNNING_COUNT/$TOTAL_PODS"
if [ "$WOOP_APPLIED" = "true" ]; then
    echo -e "    - WOOP:           ${GREEN}Recommendations applied${NC}"
else
    echo -e "    - WOOP:           ${YELLOW}No recommendations detected${NC}"
fi
echo ""

if [ "$PASS" -eq $((PASS+FAIL)) ]; then
    echo -e "${GREEN}All checks passed! Resource right-sizing complete.${NC}"
    echo ""
    exit 0
else
    echo -e "${YELLOW}$FAIL check(s) still pending.${NC}"
    echo ""
    if [ "$NO_OOMKILL" = "false" ] || [ "$ALL_RUNNING" = "false" ]; then
        echo "Hints:"
        echo "  - Check pod status:    kubectl get pods -n riddle-3"
        echo "  - Describe pod:        kubectl describe pod -l app=stress-app -n riddle-3"
        echo "  - Check events:        kubectl get events -n riddle-3 --sort-by='.lastTimestamp'"
    fi
    if [ "$MEM_REQ_OK" = "false" ]; then
        echo "  - Check resources:     kubectl get deploy stress-app -n riddle-3 -o yaml | grep -A 8 resources"
    fi
    if [ "$WOOP_APPLIED" = "false" ]; then
        echo "  - Check WOOP status:   kubectl get recommendations -n riddle-3"
    fi
    echo ""
    exit 1
fi
