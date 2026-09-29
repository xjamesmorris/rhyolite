---
name: help
description: Show Rhyolite commands and guided-input help
allowed-tools: []
disable-model-invocation: true
---

Reply with exactly this plain-text help:

```text
Rhyolite commands

/rhyolite:repo-review  Start the guided, read-only repository-review command.
/rhyolite:start        Start the guided review session (recommended).
/repo-review           Shorthand when Rhyolite extension commands are available.
/rhyolite:version      Show the installed Rhyolite version.
/rhyolite:status       Show current command, task, subagent, timing, and output status.
/rhyolite:help         Show this help.

Guided finite choices use Copilot CLI's numbered picker and automatic final
Other custom-answer option. Inside repo-review setup, type help, status, or
explain scopes without a leading slash for live setup guidance.
```
