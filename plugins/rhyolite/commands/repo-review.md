---
name: repo-review
description: Compatibility alias for the guided Rhyolite review session
agent: rhyolite:repo-review.agent
disable-model-invocation: true
---

<!-- RHYOLITE_START_COMMAND_V1 -->

This is an already-loaded Rhyolite prompt command alias.
Do not invoke the skill tool.
Do not invoke `skill(start)` or `skill(repo-review)`.
Do not look up or call any skill named `start` or `repo-review`.
Enter the same guided `repo-review` setup directly in the current
`rhyolite:repo-review` session now, with the same behavior as
`/rhyolite:start`.

Treat the following command arguments as the user's initial review request.
If they are empty, begin with source selection.

$ARGUMENTS
