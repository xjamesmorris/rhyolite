---
description: Show Rhyolite commands and guided-input help
disable-model-invocation: true
---

Reply with exactly this plain-text help:

```text
Rhyolite commands

/rhyolite:start        Start the initial/default read-only repo-review module.
/rhyolite:repo-review  Compatibility alias for /rhyolite:start.
/rhyolite:version      Show the installed Rhyolite version.
/rhyolite:status       Show current command, background runner, timing, and output status.
/rhyolite:help         Show this help.

Guided setup runs in the rhyolite:repo-review agent; start it with
rhyolite --harness claude. Finite choices use Claude Code's question picker,
which always adds its own free-text answer. Inside repo-review setup, type
help, status, or explain scopes without a leading slash for live setup
guidance.
```
