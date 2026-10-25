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
| T18 | P2 | Verify | Confirm in a live run that scope 1 runs the same security pass as scope 3 |
| T11 | P3 | Deferred | Deferred review and platform features |

## Tasks

### T18 (P2, Verify): Confirm in a live run that scope 1 runs the same security pass as scope 3

- **Problem:** Scope 1 could run a lighter dedicated security pass than
  scope 3. Its default session timeout was 60 minutes instead of 240, the
  worker request named scope 3 "Full review" with no rule about security
  depth, and nothing required covering every security-relevant file, while
  scope 3's whole-repository provenance work made its worker read more of
  the tree.
- **State:** Every scope now defaults to a 240-minute session timeout. The
  review prompt, shared skill, and both worker agents carry one rule that
  the security pass is identical in every scope and inspects every
  security-relevant tracked file instead of sampling. Validation checks that
  the rendered security instructions are byte-identical in scope 1 and
  scope 3 requests. No live scope 1 review has run since the change.
- **Next step:** review one public repository at one exact commit in
  scope 1 and in scope 3 with the same model, reasoning effort, and context.
  The direct runner's `--commit` option pins the commit. Compare the two
  reports' security findings.
- **Done when:** both reports cover the same security-relevant areas and
  report the same critical and high security findings, or each difference is
  traced to model variance rather than to a scope-dependent input.
- **Source:** 2026-10-24 maintainer request.

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
