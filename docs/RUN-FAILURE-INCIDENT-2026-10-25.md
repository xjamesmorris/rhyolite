# Rhyolite incident report: security scan refusal of 2026-10-25

**Date:** 2026-10-25 (local time)
**Status:** Root cause confirmed; provider-refusal handling implemented
(Harness Contract v9 and `RefusalPolicy`) and verified live on 2026-10-25
(see the follow-up below)
**Severity:** Medium (review reliability; scan A's completed findings
were not consolidated)
**Security impact:** None observed. No output from a model outside the
approved plan was accepted.
**Confidence:** High, from the retained scan session event records, worker
outcome, scan state, and the installed Copilot CLI 1.0.104-3 schemas

## Executive summary

A scope 1 review of `https://github.com/riscv-software-src/opensbi` with two
multi-model security scans failed after 1 hour 48 minutes, 1 hour 33
minutes of it while the host was asleep. Scan A completed with 12 findings. Scan B, on `claude-opus-5.5` at `max` reasoning
effort with the `long_context` tier, ended with:

    Execution failed: Request exceeds the model's prompt budget after
    reserving output (134437 tokens; limit 128000). Reduce context or
    compact before continuing.

The approved plan required both scans, so consolidation never started and
the repository failed.

The error did not describe the approved model. Scan B never approached its
own budget: every one of its 19 model calls recorded a prompt budget
(`maxPromptTokens`) of 968,000 tokens, and its largest prompt was 185,172
tokens. On the 19th call the model provider declined the response (a
content refusal). Copilot CLI then started its automatic refusal fallback,
which re-issues the conversation on another model. The CLI's own pre-flight
check rejected that re-issued request against the fallback model's
128,000-token budget before any fallback call was made, and the session
ended with the error above.

Rhyolite recognized a blocked fallback only when another model appeared in
the event stream. None did, so the scan was classified as an ordinary
`failed` outcome, which is never relaunched.

## Evidence

From the scan B session record and worker outcome:

| Signal | Value |
| --- | --- |
| Approved model, effort, tier | `claude-opus-5.5`, `max`, `long_context` |
| Prompt budget on every call | 968,000 tokens |
| Largest prompt (call 19) | 185,172 tokens |
| Call 19 `finishReason` | `content_filter` |
| Call 19 `contentFilterTriggered` | `true` |
| Call 19 output | 2,837 tokens, all reasoning |
| Time from call 19 to the error | 1 ms |
| Models recorded in the session | `claude-opus-5.5` only |
| Worker outcome | `failed`, not retryable |

Copilot CLI's session-event schema documents that it reports an Anthropic
`refusal` stop reason as `finishReason: content_filter`, and that a
`refusal_fallback` model change switches to a configured fallback model. The
account's Copilot CLI experiment cache enabled
`copilot_cli_anthropic_refusal_fallback`. In the October 13 incident the same
fallback targeted `claude-opus-4.8`.

Both scans also stalled at the same moment for 93 minutes, from 12:55 to
14:29 local time, and then logged "Response was interrupted due to a server
error. Retrying...". The operator confirmed that the laptop running the review
was asleep for that period. Copilot CLI retried after resume, so the sleep
cost wall-clock time but did not cause the failure.

## Root cause

1. **No refusal outcome.** The worker outcome had no class for a provider
   refusal. A refusal was visible only indirectly, as an attempted fallback
   model, and this run recorded none.
2. **Misleading harness error.** The only session error named a prompt
   budget, which reads as a context-size problem with the approved model.
3. **All-or-nothing scan quorum.** With the default minimum of every scan,
   one refused scan discarded the completed scan and the consolidation pass.

## Fixes

- **Harness Contract v9.** `harness_worker_outcome` adds the `refused`
  outcome and schema 2 with `ContentRefusals`, `PromptBudget`, and
  `PeakPromptTokens`. Copilot recognizes approved-model usage records with
  `finishReason: content_filter`, `refusal_fallback` model changes, and the
  CLI's refusal notice; Claude Code recognizes `refusal` stops and
  `model_refusal_fallback` handovers. A recorded refusal explains the
  harness's fallback model in any event order. Live detection returns
  `RHYOLITE_HARNESS_WORKER_REFUSAL_STATUS` (5), so the runner stops a
  refused worker before any fallback can answer.
- **Approval-bound `RefusalPolicy`.** Rhyolite never retries a refusing
  model for the repository and never accepts output from a model outside the
  approved plan. A declined scan is skipped and excluded from the required
  scans; consolidation still runs, even when every scan was declined. A
  declined report writer or research worker hands over, in a fresh session,
  to the next approved model that has not been declined, in plan order:
  consolidation model, review model, then the scan B and C models.
- **Reporting.** `ProviderRefusals` appears in repository and run state, the
  manifest, handoffs, and the HTML index, and the executive summary names any
  refusal or handover. Failure analysis adds `provider-refusal`, which
  explains a fallback model's prompt-budget error, and `context-limit` for a
  genuine overflow of the approved model's budget.
- **Prevention.** The dedicated security pass and the scan request ask for
  the attacker's position, preconditions or trust boundary, and triggering
  input at source level, and forbid exploit code, payloads, shellcode, and
  step-by-step attack instructions.

Under these rules, this run would have skipped scan B, consolidated scan A's
12 findings with the consolidation model's own security pass, and completed
with the refusal disclosed.

## Remaining limits

- Prompt budgets cannot be checked before a run. Copilot CLI's offline
  catalog lists only model IDs; the budget appears only in each session's
  usage records, and the CLI already compacts against the approved tier.
- A repository can provoke refusals in some models to remove their scans.
  Rhyolite discloses every refusal and keeps the consolidation pass, but the
  review then reflects fewer independent models.
- Copilot CLI exposes no documented setting that disables its refusal
  fallback, so Rhyolite stops the worker instead.
- Rhyolite does not keep the host awake. A host that sleeps during a review
  pauses model work, and the runner measures the session time remaining for
  same-session recovery and the ledger request with the wall clock, so sleep
  counts against them.

## Validation

- `tests/validate-harness-contract.sh`: this run's exact usage records,
  the refusal fallback in both event orders, a refusal followed by a clean
  finish, a genuine overflow, refusal-fallback model changes and notices,
  live refusal status, and outcome schema 2 validation.
- `tests/harness-contract-claude.sh`: Claude Code `refused` transcripts,
  live detection, research finalization, and a refused single-model review.
- `tests/validate-plugin.sh`: a declined scan, every scan declined, a
  report-writer handover, a declined review with no other approved model,
  a research handover, and the plan's `RefusalPolicy`.

## Follow-up: live verification (2026-10-25)

Run `20261025-222910` repeated the review on the fixed runner, from 22:29 to
23:07 local time with the host awake. The approved plan was unchanged: scan A
and the consolidation on `gpt-5.6-sol` at `max`, scan B on `claude-opus-5.5`
at `max`, both with `long_context`, at OpenSBI commit
`bcf587a987573057968a11b941729d70799947f4`.

- The provider again declined scan B, on its 40th call, 8 minutes 21 seconds
  in, with a largest prompt of 327,413 of 968,000 tokens. Copilot CLI's
  refusal fallback again failed its own pre-flight check (229,462 tokens;
  limit 128,000) and ended the session within 0.1 seconds, before the
  5-second live poll, so the post-exit worker outcome classified it as
  `refused`.
- Rhyolite recorded scan B as `Refused`, did not retry `claude-opus-5.5`, and
  lowered the required scans from 2 to 1. Scan A completed with 9 findings
  in 25 minutes 45 seconds.
- The consolidation review validated its ledger (8 confirmed, 1 refined) and
  completed the review in 38 minutes 41 seconds with 3 model sessions. Its
  report includes the DBTR update-path privilege-check defect as finding 3.
- `state.json` `ProviderRefusals`, the manifest, both handoffs, the HTML
  index, and the executive summary named the declined model: "The provider
  declined Claude Opus 5.5 for scan B; GPT-5.6 Sol wrote the canonical
  consolidation report."

At this point, `claude-opus-5.5` had declined both security scans of this
repository, so the run consolidated one scan's findings; a live review in
which two scans both contributed findings had not yet been observed.
The live refusal stop was not exercised, because the CLI ended both refused
sessions itself.

## Follow-up: 0.9.0 live release verification (2026-10-26)

Two scope 1 reviews exercised the local 0.9.0 runtime candidate
`59be9fa9049712407e5999d6633af977e8e24031` on Fedora Linux 44 through
GitHub Copilot CLI. Both reviewed the public `xjamesmorris/rhyolite-test-1`
repository at commit `a91e8de960a3343a126ae7c5603ada1b90473310`, with
maximum reasoning effort, `long_context`, and research disabled. Each plan
was explicitly approved before execution.

- Run `20261026-164429-29405e429bd3d20f` used `gpt-6.1-sol` for scan A and
  consolidation, and `claude-fable-5.1` for scan B. Scan B was recorded as
  refused after 20 seconds; it was skipped without retry, and the required
  scans were reduced from two to one. Scan A contributed four findings,
  all confirmed in a validated ledger. The canonical report passed without
  repair, and the repository completed in 20 minutes 55 seconds. This
  verified refusal recovery, not the two-contributing-scan path.
- Run `20261026-172136-a99c97c89ae64581` explicitly pinned the same source
  commit and used `gpt-6.1-sol` for scan A and consolidation, with
  `gpt-6-sol` for scan B. Both scans completed in one attempt: A contributed
  three finding IDs and B contributed four. The validated ledger classified
  all seven IDs exactly once: one confirmed, five merged, one refined, and
  none rejected. Each entry referenced a numbered finding in the canonical
  report. The report passed unchanged with 14 findings, including four
  security findings, and the repository completed in 21 minutes 43 seconds.
  No refusal, relaunch, continuation, or report-repair invocation was needed.

The second run closes the live two-contributing-scan release verification
gap. Its two models are in the same GPT family; this establishes the live
collection and consolidation path, not cross-vendor coverage or exhaustive
defect detection. The documented host-sleep and security-file-coverage
limitations remain unchanged.
