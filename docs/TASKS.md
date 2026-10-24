# Rhyolite task tracker

This file tracks open Rhyolite engineering, verification, and release tasks
and their priorities. It records work state only:
[AGENTS.md](../AGENTS.md) remains the canonical development contract, and
[PLAN-OF-RECORD.md](PLAN-OF-RECORD.md) remains the platform plan. Users
still report bugs and request features through the routes in
[SUPPORT.md](../SUPPORT.md).

**Last updated:** 2026-10-24

## Priorities

| Priority | Meaning |
| --- | --- |
| P0 | Blocks confidence in the current release or a safety boundary. Do next. |
| P1 | A user-facing failure without a workaround, a missing release verification, or a public-repository gap. Schedule soon. |
| P2 | A reliability or usability improvement with a workaround, or a report that needs triage. |
| P3 | Deferred design work, a documented limitation, or a contributor convenience. |

Status values:

- **Open:** work has not started.
- **Needs triage:** confirm the problem statement before work starts.
- **Verify:** fixed; live verification is pending.
- **Deferred:** needs an explicit project decision before work starts.

## Summary

| ID | Priority | Status | Task |
| --- | --- | --- | --- |
| T16 | P2 | Open | Remove runtime homes left by a hard-killed runner |
| T11 | P3 | Deferred | Deferred review and platform features |

## Tasks

### T16 (P2, Open): Remove runtime homes left by a hard-killed runner

- **Problem:** A runner stopped with `SIGKILL` cannot run its exit trap, so
  each isolated harness runtime home under `TMPDIR` keeps its ephemeral
  authentication bridge, for Copilot a copy of the login token entries from
  `config.json`, until something removes the directory. The homes are mode
  0700, so only the same user can read them. Until 2026-10-19 the validation
  suite's hard-kill fixtures also left such homes, with the contributor's
  real Copilot token entries, in `/tmp`; they now use fixture authentication
  and a fixture `TMPDIR`. A launcher stopped the same way during its
  pre-launch model check leaves its `model-check-<n>` home, with the same
  bridge, in that launch's session directory under launcher state.
- **Next step:** design a safe sweep, for example at the next runner or
  launcher start, that removes only the current user's stale
  `rhyolite-repo-*` runtime homes and launcher `model-check-*` homes whose
  recorded process is gone, and document the manual cleanup.
- **Source:** 2026-10-19 validation run.

### T11 (P3, Deferred): Deferred review and platform features

Each item needs an explicit project decision before work starts:

- A controlled triage verdict and machine-readable triage fields.
- A conference or CFP context input.
- Broker or provider changes, such as authenticated code search.
- Scope renames.
- Additional platform support and private repository support, as
  [DEVELOPERS.md](../DEVELOPERS.md) describes.

## Updating this file

Give a new task the next free ID, keep the summary table sorted by
priority, and record each task's source and its next step or done-when
condition. Remove a task in the change that completes it, and record
user-facing changes in [CHANGELOG.md](../CHANGELOG.md).
