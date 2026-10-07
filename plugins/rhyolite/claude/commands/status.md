---
description: Show current Rhyolite command, setup, background runner, timing, and output status
disable-model-invocation: true
---

Handle this as an exact Rhyolite status request. Do not start or advance setup,
change stored answers, invoke the runner, or start a subagent.

Do not call Read, Glob, Grep, Bash, Skill, web, or any other content tool.
Use only the current conversation state and the background-task status already
reported to this session; report a field as `UNAVAILABLE` when it is not
reliably present. Report:

```text
RHYOLITE STATUS
Command: <repo-review or NOT STARTED>
Stage: <current stage or NOT STARTED>
Elapsed: <elapsed time since the current Rhyolite command started, or UNAVAILABLE>
Harness: claude
Source: <selected value or NOT SELECTED>
Model: <selected value or NOT SELECTED>
Reasoning effort: <high, xhigh, max, or NOT SELECTED>
Context tier: <default, long_context, or NOT SELECTED>
Remember settings: <YES, NO, or NOT SELECTED>
Output: <effective output directory or NOT SELECTED>
Scope: <selected value or NOT SELECTED>
Provenance lookback months: <selected value or NOT SELECTED>
Research cookies: <OFF, EPHEMERAL, or NOT SELECTED>
Review run: <run id and status, NOT STARTED, or UNAVAILABLE>
Background runner: <running, completed, stopped, failed, NONE, or UNAVAILABLE>
Latest progress: <latest RHYOLITE PROGRESS line already reported, NONE, or UNAVAILABLE>
```

The status request itself is not an active Rhyolite command or stage. In
a fresh session, report `Command: NOT STARTED` and `Stage: NOT STARTED`.
After the block, continue with the pending Rhyolite question only if setup was
already waiting for user input.
