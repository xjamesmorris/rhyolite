# Rhyolite task tracker

This file tracks open Rhyolite engineering, verification, and release tasks
and their priorities. It records work state only:
[AGENTS.md](../AGENTS.md) remains the canonical development contract, and
[PLAN-OF-RECORD.md](PLAN-OF-RECORD.md) remains the platform plan. Users
still report bugs and request features through the routes in
[SUPPORT.md](../SUPPORT.md).

**Last updated:** 2026-10-14, for the 0.8.2 release

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
- **Verify:** fixed in a release; live verification is pending.
- **Deferred:** needs an explicit project decision before work starts.

## Summary

| ID | Priority | Status | Task |
| --- | --- | --- | --- |
| T1 | P0 | Verify | Live-verify review resilience with real models |
| T2 | P1 | Open | Offer the highest supported reasoning effort with explicit approval |
| T3 | P1 | Open | Probe Claude Code same-session continuation |
| T4 | P1 | Open | Complete the interactive and remote release smoke tests |
| T5 | P1 | Open | Confirm the public-repository gates |
| T6 | P2 | Needs triage | Clarify multi-repository review behavior |
| T7 | P2 | Verify | Confirm scope-only research selection in a live guided run |
| T8 | P2 | Open | Design research-phase recovery |
| T9 | P3 | Open | Keep the interactive setup session on the selected model |
| T10 | P3 | Open | Make validators independent of symlinked checkout paths |
| T11 | P3 | Deferred | Deferred review and platform features |

## Tasks

### T1 (P0, Verify): Live-verify review resilience with real models

- **Problem:** On 2026-10-13, reviews failed after long analysis. Final
  reports exceeded Copilot's 32,000-token per-response output limit,
  transient model-service failures ended sessions, and a blocked automatic
  model fallback was terminal. See
  [RUN-FAILURE-INCIDENT-2026-10-13.md](RUN-FAILURE-INCIDENT-2026-10-13.md).
- **State:** 0.8.2 ships Harness Contract v8 same-session recovery, paged
  report delivery, and the continuation fix that omits `--name`. Mocked
  end-to-end scenarios and live Copilot CLI argv probes pass, but no
  real-model review has yet recovered a cut report end to end.
- **Next step:** run a multi-repository scope-3 review with the recommended
  Copilot model at maximum effort. Transient-failure and blocked-fallback
  retries are verified when they occur.
- **Done when:** a real-model review whose report exceeded one response
  completes through paged delivery and unchanged strict finalization, as
  its `WorkerRecovery` state records, and the result is added to the
  incident report.
- **Source:** maintainer issue notes and the 2026-10-13 incident report.

### T2 (P1, Open): Offer the highest supported reasoning effort with explicit approval

- **Problem:** Reviews request maximum reasoning effort by default. When the
  harness rejects that effort for the selected model, the worker fails
  closed at the `model availability` stage, and the user must restart setup
  and choose a lower effort manually.
- **Goal:** offer the highest effort that the selected model supports,
  never below `high`, as an explicit, approval-bound plan change. Rhyolite
  must never lower effort automatically or silently.
- **Next step:** design how each adapter learns which efforts a model
  supports and where the user approves the regenerated plan. Cover
  rejection, approval, and decline in the validators.
- **Source:** maintainer issue notes.

### T3 (P1, Open): Probe Claude Code same-session continuation

- **Problem:** Claude Code reports the `worker_continuation` capability as
  `unverified`, so Claude Code reviews do not use same-session recovery. A
  cut report or a transient failure still ends the review.
- **Next step:** probe print-mode continuation live in an isolated runtime
  home with the approved argv. Promote the capability to `yes` only with
  live evidence, tests, and documentation, as
  [ADDING-A-HARNESS.md](ADDING-A-HARNESS.md) requires.
- **Source:** 2026-10-13 incident report, remaining limits.

### T4 (P1, Open): Complete the interactive and remote release smoke tests

- **Problem:** The interactive and remote checks in
  [PUBLISHING.md](PUBLISHING.md) are not yet recorded for the current
  release. They cover the exported package's agents in a new Copilot CLI
  session (load status, plaque, and exact setup controls), the Claude Code
  session checks, and a fresh remote install plus a manual update from the
  prior release. The remote checks were blocked while the repository was
  private; it is now public.
- **Done when:** maintainer release checklist steps 6 and 9 and canonical
  release workflow steps 10 and 11 pass for the current release.

### T5 (P1, Open): Confirm the public-repository gates

- **Problem:** The repository is now public, so every pre-publication gate
  in [PUBLISHING.md](PUBLISHING.md) applies. Confirm branch protection for
  `main` without hosted-CI requirements, the published support routes,
  including the issue forms and the private conduct contact, and a smoke
  test of the published support and release paths. GitHub private
  vulnerability reporting is enabled.
- **Done when:** every pre-publication gate is confirmed.

### T6 (P2, Needs triage): Clarify multi-repository review behavior

- **Report:** "can't understand multiple repos?"
- **Context:** One run can review several repositories. Each repository is
  reviewed in its own isolated snapshot by its own worker and produces its
  own report. Run-level artifacts index the per-repository results, but no
  step analyzes the repositories together.
- **Next step:** reproduce a guided multi-repository setup, confirm that
  every source reaches the effective plan and the executive summary, and
  decide whether cross-repository analysis is in scope. Any such analysis
  must keep per-repository isolation and the neutral-assessment rules.
- **Source:** maintainer issue notes.

### T7 (P2, Verify): Confirm scope-only research selection in a live guided run

- **Problem:** An orchestrator combined `--scope 3` with the legacy research
  switches, and the runner correctly rejected the plan before cloning.
- **State:** fixed in 0.8.2. The runner's `--help` marks the legacy switches
  as aliases that cannot be combined with `--scope`, and both orchestrators
  select research only with `--scope`.
- **Done when:** a live guided scope-2 or scope-3 setup, such as the T1 run,
  generates its plan with `--scope` alone.
- **Source:** maintainer issue notes.

### T8 (P2, Open): Design research-phase recovery

- **Problem:** Research is never continued or relaunched automatically. The
  broker keeps exactly one network log per repository phase and refuses to
  start over an existing one, so a transient research failure ends that
  repository's review.
- **Next step:** design a broker lifecycle for a bounded research retry
  that keeps an auditable network log for every attempt and preserves the
  rule that retained ledgers are never reloadable state.
- **Source:** 2026-10-13 incident report, remaining limits.

### T9 (P3, Open): Keep the interactive setup session on the selected model

- **Problem:** When the selected model is unavailable, Copilot CLI may run
  the launcher's interactive setup session on its default model, as the
  README documents. Review, research, and repair workers are unaffected
  because they fail closed.
- **Next step:** check whether newer Copilot CLI releases can keep the
  interactive session on the selected model, then update the launcher and
  the README.

### T10 (P3, Open): Make validators independent of symlinked checkout paths

- **Problem:** Validation has failed the Copilot outer-launcher argv
  baseline in `tests/validate-harness-contract.sh` when the checkout was
  reached through a symlinked parent directory. Running the validators
  from the physical checkout path avoids the failure.
- **Next step:** reproduce it, find the comparison that keeps the logical
  path, canonicalize it, and add a regression check.

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
