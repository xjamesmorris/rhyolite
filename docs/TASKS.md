# Rhyolite task tracker

This file tracks open Rhyolite engineering, verification, and release tasks
and their priorities. It records work state only:
[AGENTS.md](../AGENTS.md) remains the canonical development contract, and
[PLAN-OF-RECORD.md](PLAN-OF-RECORD.md) remains the platform plan. Users
still report bugs and request features through the routes in
[SUPPORT.md](../SUPPORT.md).

**Last updated:** 2026-10-25

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
| T19 | P2 | Verify | Verify multi-model security scans in a live run |
| T20 | P3 | Open | Report security-relevant files that the security pass did not open |
| T11 | P3 | Deferred | Deferred review and platform features |

## Tasks

### T19 (P2, Verify): Verify multi-model security scans in a live run

- **Problem:** Independent runs of different models on the same commit
  report materially different security defects. In the T18 comparison of
  OpenSBI commit `131bda944704293fa75295060aec96061cdb3749`, both scope 3
  reviews reported a High DBTR update-path privilege-check defect that the
  scope 1 review missed, although its worker read the whole file; the
  scope-invariant inputs matched, so the difference was model variance.
- **State:** Up to three isolated, parallel security scans per repository
  with consolidation and a validated ledger are implemented and covered by
  mocked validation. The security pass now also names update paths that
  skip install-time checks. No live multi-model review has run.
- **Next step:** from a clean directory, run
  `./rhyolite --repo https://github.com/riscv-software-src/opensbi --auto-defaults`
  and approve the plan; with the direct runner, pin the commit above with
  `--commit`. Check that every scan completes, the ledger validates, and
  the consolidated report covers the DBTR update-path defect or records an
  evidence-based rejection.
- **Done when:** a live two- or three-scan review completes with a
  validated ledger, and its wall time and model-session count are recorded
  here.
- **Source:** 2026-10-24 maintainer request.

### T20 (P3, Open): Report security-relevant files that the security pass did not open

- **Problem:** In the T18 comparison neither review opened every
  security-relevant file, and neither report listed the unopened files as a
  limitation, although the security pass requires both.
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
