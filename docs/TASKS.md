# Rhyolite task tracker

This file tracks open Rhyolite engineering, verification, and release tasks
and their priorities. It records work state only:
[AGENTS.md](../AGENTS.md) remains the canonical development contract, and
[PLAN-OF-RECORD.md](PLAN-OF-RECORD.md) remains the platform plan. Users
still report bugs and request features through the routes in
[SUPPORT.md](../SUPPORT.md).

**Last updated:** 2026-10-27

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
| T25 | P2 | Verify | Observe a reused-scan review and a scan report request live |
| T20 | P3 | Open | Report security-relevant files that the security pass did not open |
| T11 | P3 | Deferred | Deferred review and platform features |

## Tasks

### T25 (P2, Verify): Observe a reused-scan review and a scan report request live

- **Problem:** Run `20261027-000751-3702922ead504995` verified live that a
  compacted scan keeps its report contract: scan C was compacted and still
  returned a valid report. `--reuse-scans` and the same-session scan report
  request are verified with mocked harnesses only; that run did not need the
  report request, and a report request cannot be forced on demand.
- **Next step:** approve a plan with `--reuse-scans` and the folder of a
  failed or interrupted multi-scan run, and confirm that only the missing
  scans ran. In later multi-scan reviews, check `ReportRequest` in each
  `scan-state.json` and record any value other than `NotNeeded`.
- **Done when:** a live reused-scan review completes with the reused
  reports' digests verified, and a live scan report request is recorded or
  the project records that none has occurred.
- **Source:** [RUN-FAILURE-INCIDENT-2026-10-26.md](RUN-FAILURE-INCIDENT-2026-10-26.md).

### T20 (P3, Open): Report security-relevant files that the security pass did not open

- **Problem:** In the T18 comparison neither review opened every
  security-relevant file, and neither report listed the unopened files as a
  limitation, although the security pass requires both. The README now
  documents this limitation; per-report disclosure remains open.
- **Next step:** decide whether the runner can derive a trusted list of
  opened files from the worker session record and compare it with a
  deterministic list of security-relevant tracked files.
- **Done when:** a review discloses security-relevant files that its
  security pass did not open, or the project records why it cannot.
- **Source:** 2026-10-25 T18 comparison.

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
