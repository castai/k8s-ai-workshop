# Workshop Instructions

You are helping diagnose and fix a workload in the `riddle-3` namespace that keeps getting OOMKilled.

**IMPORTANT**: Before starting, load the `k8s-resource-rightsizing` skill. This skill guides you through diagnosing OOMKill issues and determining the correct resource configuration.

Load it by calling the skill tool with name "k8s-resource-rightsizing".

The target namespace is `riddle-3`. The `stress-app` deployment has pods that run for ~1 minute then get OOMKilled. The memory limit is set too low for the workload's steady-state usage.
