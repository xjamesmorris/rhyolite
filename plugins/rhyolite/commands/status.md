---
name: status
description: Show current Rhyolite command, setup, task, subagent, timing, and output status
agent: rhyolite:repo-review.agent
allowed-tools: ["agent"]
disable-model-invocation: true
---

Handle this as an exact Rhyolite status request. Do not start or advance setup,
change stored answers, invoke the runner, or spawn a subagent.

Use the current conversation state and read-only task/subagent introspection
already available to the selected agent. Report:

Do not call read, search, execute, shell, web, skill, or any other content
tool. Do not spawn or message an agent. Use only read-only task/subagent
listing when it is available; otherwise report those fields as `UNAVAILABLE`.

```text
RHYOLITE STATUS
Command: <repo-review or NOT STARTED>
Stage: <current stage or NOT STARTED>
Elapsed: <elapsed time since the current Rhyolite command started, or UNAVAILABLE>
Harness: copilot
Source: <selected value or NOT SELECTED>
Fleet mode: <native, standard, or NOT SELECTED>
Model: <selected value or NOT SELECTED>
Remember settings: <YES, NO, or NOT SELECTED>
Output: <effective output directory or NOT SELECTED>
Scope: <selected value or NOT SELECTED>
Provenance lookback months: <selected value or NOT SELECTED>
Review run: <run id and status, NOT STARTED, or UNAVAILABLE>
Tasks: <concise current/completed/failed counts and names, or NONE>
Subagents: <concise running/idle/completed/failed counts and names, or NONE>
```

The status request itself is not an active Rhyolite command or stage. In
a fresh session, report `Command: NOT STARTED` and `Stage: NOT STARTED`.
Use `UNAVAILABLE` rather than guessing any value that is not reliably present.
After the block, continue with the pending Rhyolite picker only if setup was
already waiting for user input.
