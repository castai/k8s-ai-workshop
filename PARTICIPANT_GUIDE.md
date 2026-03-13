================================================================================
   AUTONOMOUS KUBERNETES WORKSHOP - PARTICIPANT GUIDE
================================================================================

Welcome! This guide is your companion throughout the workshop.
Keep it open in a terminal: cat PARTICIPANT_GUIDE.md | less

Duration: 90 minutes
Format: Hands-on riddles with AI-powered operations


================================================================================
QUICK ACCESS LINKS
================================================================================

TBD


================================================================================
BEFORE YOU START - SETUP OPENCODE
================================================================================

IMPORTANT: Complete this setup BEFORE starting Riddle 1!

This workshop uses OpenCode with Kubernetes MCP (Model Context Protocol)
to enable AI-powered operations on your cluster via the Qwen model.

Step 1: Install and Configure OpenCode
---------------------------------------
Run the setup script from the workshop root:

  ./riddles/common/setup-opencode.sh

What this script does:
  - Installs OpenCode if not already installed
  - Configures Qwen model via CAST AI AI Enabler
  - Sets up kubernetes MCP server (kubectl access)

NOTE: Riddle 1 does NOT require a CAST AI API key. The setup script
will skip the API key prompt. You only need a CAST AI API key for
Riddles 2 and 3 (configured separately before those riddles).

Step 2: Verify Setup
---------------------
After running the script:
  1. Run: opencode
  2. Ask: "Can you list the nodes in my Kubernetes cluster?"
  3. OpenCode should be able to run kubectl commands and show your nodes

If verification fails:
  - Check that kubectl works: kubectl get nodes
  - Run: opencode mcp list (should show kubernetes + castai servers)
  - Check ai-integration/README.md for manual setup
  - Ask the instructor for help

Once verified, you're ready to start Riddle 1!


================================================================================
RIDDLE 1: TBD
================================================================================

Location: riddles/01-cluster-debugging/

Challenge
---------
TBD

Your Mission
------------
TBD

Success Criteria
----------------
TBD

Commands to Start
-----------------
  cd riddles/01-cluster-debugging
  ./setup.sh

NOTE: setup.sh automatically deploys the Progress Reconciler (see
progress-reconciler/deploy.sh) before setting up the riddle. Your name
should become green in the progress dashboard once it's running.

  kubectl get pods -n riddle-1

Getting Unstuck
---------------
  Check hints.md in the riddle directory
  Run ./reset.sh to start fresh
  Ask the instructor


================================================================================
BEFORE RIDDLE 2 - SETUP CAST AI
================================================================================

IMPORTANT: Complete this setup BEFORE starting Riddle 2!

Riddle 2 uses CAST AI platform integration to demonstrate advanced
Kubernetes optimization and cost management capabilities.

Step 1: Create CAST AI Account
-------------------------------
  1. Go to https://console.cast.ai
  2. Sign up for a free account

Step 2: Create API Key and Configure OpenCode
-----------------------------------------------
If you haven't configured your API key yet, or need to update it:

  ./riddles/common/setup-opencode.sh --with-castai

The --with-castai flag will prompt for your CAST AI API key. To get one:
  1. Go to https://console.cast.ai/user/api-access
  2. Click "Create access key"
  3. Copy the API key and paste it into the script prompt

Step 3: Onboard Your Cluster to CAST AI Console
------------------------------------------------
After creating the API key, you need to connect your cluster to CAST AI:

  Read-only onboarding:
  1. Go to https://console.cast.ai
  2. Click "Connect cluster"
  3. Select EKS as the provider
  4. Copy the provided script and run it locally in your terminal
  5. Wait for the script to complete

  Full onboarding:
  1. After the read-only onboarding completes, click the green
     "Enable CAST AI" button in the console UI
  2. Copy the provided script and run it locally
  3. Wait for it to finish

  Once both scripts complete, your cluster is fully onboarded to CAST AI!
  You should see your cluster appear in the CAST AI console.

Step 4: Verify Setup
---------------------
After onboarding:
  1. Run: opencode
  2. Ask: "List Cast AI MCP tools"
  3. OpenCode should be able to interact with CAST AI platform

If verification fails:
  - Verify your API key is correct
  - Run: opencode mcp list (should show castai server)
  - Check that both onboarding scripts completed successfully
  - Check ai-integration/README.md for manual setup
  - Ask the instructor for help

Once verified, you're ready to start Riddle 2!


================================================================================
RIDDLE 2: TBD
================================================================================

Location: riddles/02-autoscaler-rebalancing/

Challenge
---------
TBD
Your Mission
------------
TBD

Success Criteria
----------------
TBD

Commands to Start
-----------------
  cd riddles/02-autoscaler-rebalancing
  ./setup.sh
  kubectl get pods -n riddle-2

Key Metrics to Watch
--------------------
TBD

Key Learning Points
-------------------
TBD


================================================================================
RIDDLE 3: TBD
================================================================================

Location: riddles/03-autoscaling/

Challenge
---------
TBD

Your Mission
------------
TBD

Success Criteria
----------------
TBD

Commands to Start
-----------------
  cd riddles/03-autoscaling
  ./setup.sh
  kubectl top pods -n riddle-3
  ./cost-analysis.sh

Prometheus Queries
------------------
TBD

Key Learning Points
-------------------
TBD


Example AI Prompts
------------------

TBD 


AI Best Practices
-----------------
DO:
  - Review AI-suggested commands before running
  - Understand what the AI is doing
  - Use AI to speed up investigation
  - Learn from AI's systematic approach

DON'T:
  - Blindly trust AI without verification
  - Run destructive commands without understanding
  - Skip learning by letting AI do everything
  - Ignore errors because "AI said so"


================================================================================
TROUBLESHOOTING COMMON ISSUES
================================================================================

Pods Stuck in Pending
---------------------
  kubectl describe nodes
  kubectl describe pod <pod-name> -n <namespace>
  kubectl describe resourcequota -n <namespace>

ImagePullBackOff
----------------
  kubectl describe pod <pod-name> -n <namespace>
  kubectl edit deployment/<name> -n <namespace>

CrashLoopBackOff
----------------
  kubectl logs <pod-name> -n <namespace> --previous
  kubectl describe pod <pod-name> -n <namespace> | grep -A 5 State
  kubectl describe pod <pod-name> -n <namespace> | grep -A 10 Liveness

Service Not Reachable
---------------------
  kubectl get svc -n <namespace>
  kubectl get endpoints -n <namespace>
  kubectl describe svc <svc-name> -n <namespace>
  kubectl get pods -n <namespace> --show-labels

Getting Unstuck
---------------
Stuck on a riddle?
  1. Check hints.md in the riddle directory
  2. Run ./reset.sh to start fresh
  3. Review riddle README carefully
  4. Ask the instructor or a neighbor
  5. Check riddles/common/troubleshooting.md

Cluster completely broken?
  kind delete cluster --name workshop-cluster
  ./setup/install-kind.sh
  ./setup/install-monitoring.sh


================================================================================
WORKSHOP ETIQUETTE
================================================================================

  - Ask questions anytime - there are no stupid questions
  - Help your neighbor - teaching reinforces learning
  - Experiment freely - you can always reset
  - Take notes - capture insights for later
  - Share discoveries - found something cool? Tell the group
