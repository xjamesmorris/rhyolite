# Rhyolite task tracker

This file tracks open Rhyolite engineering, verification, and release tasks
and their priorities. It records work state only:
[AGENTS.md](../AGENTS.md) remains the canonical development contract, and
[PLAN-OF-RECORD.md](PLAN-OF-RECORD.md) remains the platform plan. Users
still report bugs and request features through the routes in
[SUPPORT.md](../SUPPORT.md).

**Last updated:** 2026-10-20

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
| T12 | P2 | Open | Keep the launcher setup block intact in native fleet mode |
| T16 | P2 | Open | Remove runtime homes left by a hard-killed runner |
| T17 | P2 | Open | Implement Codex after proving a safe snapshot-read interface |
| T11 | P3 | Deferred | Deferred review and platform features |

## Tasks

### T12 (P2, Open): Keep the launcher setup block intact in native fleet mode

- **Problem:** With `--fleet-mode native`, Copilot CLI delivered the
  launcher's first turn as a single line prefixed with `Fleet deployed:` and
  added fleet instructions to dispatch subagents and track todos. The
  orchestrators expect the exact multi-line `RHYOLITE_LAUNCHER_SETUP_V1`
  block and must not start subagents of their own, so they have to tolerate
  a flattened block and conflicting instructions. The observed sessions,
  including a 2026-10-14 run, still recognized the block. On 2026-10-20,
  Copilot CLI 1.0.101-0 still flattened the block in native mode, and the
  orchestrator still recognized it, kept the launcher source unchanged, and
  started no subagents.
- **Next step:** decide whether the launcher should deliver the setup block
  another way in native mode or whether the orchestrators should explicitly
  accept the flattened form and ignore fleet dispatch instructions.
- **Source:** the 2026-10-13, 2026-10-14, and 2026-10-20 native-fleet
  sessions.

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

### T17 (P2, Open): Implement Codex after proving a safe snapshot-read interface

- **Problem:** The Codex workstream targets the official CLI, scopes 1-3,
  the launcher, and native installation/entrypoints. Initial Codex 0.163.0
  probes could produce a zero-tool request but no ordinary file-read/search
  tools with shell disabled, including after a synthetic catalog advertised
  those tools. The adapter cannot proceed under the current design by
  granting shell access or adding an unapproved broker.
- **Next step:** decide on an approved constrained snapshot-read interface
  or runner-mediated input protocol, or pause Codex support. Keep production
  registration absent until the full contract and live evidence pass.
- **Done when:** all three scopes, native setup/package behavior,
  enforcement, recovery, repair, isolation, and cleanup satisfy the harness
  playbook and Fedora validation without regressing existing harnesses.
- **Source:** [CODEX-HARNESS-EVIDENCE.md](CODEX-HARNESS-EVIDENCE.md).

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
