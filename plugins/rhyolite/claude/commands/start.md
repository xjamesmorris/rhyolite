---
description: Start Rhyolite's initial and default repo-review module
argument-hint: "[public HTTPS repository URL or initial review request]"
disable-model-invocation: true
---

<!-- RHYOLITE_START_COMMAND_V1 -->

This is an already-loaded Rhyolite prompt command.
Do not invoke the Skill tool and do not look up a skill named `start` or
`repo-review`.

If your instructions are the `rhyolite:repo-review` orchestrator, enter
Rhyolite's guided `repo-review` setup directly in this session now. Treat
the following command arguments as the user's initial review request. If they
are empty, begin with source selection.

Otherwise, do not start a review, read files, or run commands. Reply with
exactly this text and stop:

```text
Rhyolite guided setup runs only in the rhyolite:repo-review agent.
Restart with: rhyolite --harness claude
Or start Claude Code with: claude --plugin-dir <rhyolite plugin> --agent rhyolite:repo-review
```

$ARGUMENTS
