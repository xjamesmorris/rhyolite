# Rhyolite incident report: review failures of 2026-10-13

**Date:** 2026-10-13 (local time)
**Status:** Root causes confirmed; generic recovery implemented (Harness
Contract v8); follow-up continuation fix applied (see the follow-up below)
**Severity:** High (review reliability and resource efficiency)
**Security impact:** None observed. Every enforcement boundary held; no
substituted output was accepted.
**Confidence:** High, from the retained session event records, timelines,
and runner artifacts of every failed run

## Executive summary

Five review runs failed on 2026-10-13. They fall into four failure classes,
and none was a defect in the reviewed repositories:

1. **Output-size failures (three runs, four repositories).** At maximum
   reasoning effort the final report did not fit in one model response.
   Copilot's per-response output limit was 32,000 tokens, and reasoning
   tokens count toward it. When a response reaches that limit, Copilot CLI
   silently re-requests a continuation without emitting the cut text, so the
   runner received only the last segment of the report. One further run lost
   its final response to repeated service-side stream cuts of the same very
   long answer.
2. **Transient model-service failures (two runs).** A DNS outage and the
   repeated stream cuts ended the sessions after the CLI's own retries. Since
   the Contract-v6 JSON output change, the runner no longer recorded these
   session errors, so `errors.txt` was empty.
3. **A blocked automatic model fallback (one run), reported as a
   "downgraded subagent."** The approved model did not complete a request,
   and Copilot CLI automatically retried it on an older model. Live
   enforcement stopped the worker before that model produced any output,
   but the diagnostic wrongly said the phase was "answered with" the other
   model, and nothing retried on the approved model.
4. **An orchestrator argument error (plan stage).** The runner's `--help`
   listed the legacy research switches as ordinary options. The orchestrator
   combined them with `--scope 3`, and the runner correctly rejected the plan.

The recurring theme is that every failure after expensive analysis was
terminal. Earlier fixes patched individual symptoms; none gave the system a
general way to ask the worker that holds the analysis to fix and resend its
output, or to stay within the per-response output limit.

## Failed runs

| Run | Scope, model | Status | Failure class |
| --- | --- | --- | --- |
| `20261013-004817-579e9869cb4e6cf3` | 3, `claude-fable-5.1` | `ReviewFailed` | Output size: final reply held only the tail of the report |
| `20261013-013616-59b77aa15032f3e7` | 3, `claude-fable-5.1` | `ResearchFailed` | Transient model service (DNS `ENOTFOUND`) |
| `20261013-150134-fa771867545d6252` | 3, `gpt-6.1-sol` | `ReviewFailed` | Transient model service: final response cut five times |
| `20261013-153932-f8e9cdf94a66da7b` | 3, `claude-opus-5.5`, two repositories | `ReviewFailed` | Output size: report cut at the 32,000-token limit |
| `20261013-164847-28c9a86516c17367` | 3, `claude-opus-5.5` | `ReviewFailed` | Blocked automatic model fallback |

The plan-stage argument error produced no run directory.

## Root-cause analysis

### 1. Reports larger than one response

Evidence from the persisted session event records:

- Every affected session recorded `maxOutputTokens: 32000` in its
  `session.usage_record` events.
- At maximum effort, single responses were often all reasoning: several
  turns recorded 32,000 output tokens, all of them reasoning tokens, with no
  visible text.
- When a response reaches the limit, the next request's input grows by about
  32,017 tokens, which shows that Copilot CLI appended the cut response and
  asked the model to continue. No `assistant.message` event is emitted for
  the cut segment, it is absent from the persisted events, and it is absent
  from the `--share` transcript. After about two continuations the CLI emits
  only the last segment as the final message.
- In run `20261013-004817`, one 32,000-token response (11,003 of them
  reasoning) carried the report's beginning; the final message began in the
  middle of a sentence. The runner reported "Final report header or end
  marker was not found."
- In run `20261013-153932`, the last responses used 18,563 and 18,454
  reasoning tokens before about 13,500 visible tokens, so both reports were
  cut before the closing delimiter. Repair was `NotEligible`.
- In run `20261013-150134`, the final turn was cut by the service about
  every 10.5 minutes, five times, before the CLI gave up with "unexpected
  EOF during chunk size line".

The Claude Code adapter had already raised its output limit and stitched
continuations after a similar failure (fix `0fdeab3`), but the Copilot path
had no equivalent. The report contract required the entire report in a
single final message, which cannot be guaranteed at maximum reasoning effort.

### 2. Lost error detail and terminal transient failures

Contract v6 runs Copilot children with `--output-format json`. The structured
stream carries `session.error`, `model.call_failure`, `assistant.turn_retry`,
and the CLI exit code, but the normalizer ignored them. Run
`20261013-150134` therefore ended with an empty `errors.txt`, and the
research failure in run `20261013-013616` reported "No additional safe
detail was returned." Neither failure was retried, so hours of completed
analysis were discarded.

### 3. The "downgraded subagent"

In run `20261013-164847`, turn 5 started on the approved `claude-opus-5.5`.
About 100 seconds later the stream shows `model.call_start` for
`claude-opus-4.8`, a `model.call_failure` whose error mentions a fallback
credit token for "the original refused request", a second attempt, and then
an abort before the first token. This is Copilot CLI's automatic refusal
fallback. No subagent was involved, and the older model produced no output.
The live monitor correctly stopped the worker, but:

- the scanner treated an attempted call like produced output and reported
  that Copilot "answered" the phase with the other model; and
- the runner had no way to retry the same request on the approved model.

Copilot CLI exposes no setting that disables this fallback.

### 4. Orchestrator argument error

The orchestrator ran the runner's `--help` before building its command. The
help listed `--enable-public-research` and `--enable-provenance-research`
next to `--scope` without saying that they are legacy aliases that cannot be
combined with it. The runner rejected the combination as designed, and the
orchestrator corrected itself on the next call.

## Why earlier repairs did not prevent this

The report-validation class had been "fixed" several times since
2026-10-05:

| Change | What it handled |
| --- | --- |
| `cc1cea8` (0.6.0) | One isolated, tool-less edit of exactly one invalid confidence field |
| `a9b4338` (0.7.0) | Model-free conversion of Markdown tables outside field sections |
| `3b481bf` | Model-free rejoining of a field label wrapped once |
| `0e39dd7` | Model-free confidence delimiter insertion |
| `0fdeab3` | Claude Code only: raised output limit and stitched continuations |
| `58194d2`, `0d76b91` | Prompt-level self-check and exact final-reply extraction |

Each change addressed the diagnostic that had just been observed, and each
was gated on that exact diagnostic class. The underlying reasons recurred:

1. **Symptom-specific eligibility.** Repair ran only when the first strict
   diagnostic matched one narrow class, for example "exactly one invalid
   confidence field". Any other mistake, or two mistakes, was terminal.
2. **Fail-fast validation.** The strict validator stops at its first
   violation, so even an eligible repair saw one defect at a time.
3. **A context-free repair worker.** The repair child receives only the
   candidate, without the snapshot, research, or session. It can edit one
   field but cannot regenerate a missing or truncated section, so truncation
   was always ineligible.
4. **No feedback to the worker.** The worker that holds the full analysis was
   never told that its report failed validation, and it was never asked to
   resend anything.
5. **No deterministic self-validation for the worker.** The self-check is a
   prompt instruction; only the trusted runner can validate deterministically,
   and it did so once, after the session had ended.
6. **No output-size strategy for Copilot.** Nothing bounded the size of a
   single response, and nothing detected the silent continuation.
7. **No resilience to transient service failures.** Any session error after
   the CLI's own retries was terminal and, since Contract v6, undiagnosed.

The 2026-10-05 incident analysis had recommended a general bounded repair
of up to two attempts for any correctable contract error. What shipped was
the single confidence edit.

## Fixes

Harness Contract v8 and the approval-bound `WorkerRecoveryPolicy` replace
symptom-specific recovery with one general, bounded, deterministic loop:

- **Same-session continuation.** `harness_worker_outcome` classifies every
  worker invocation from structured evidence (`completed`,
  `transient-failure`, `fallback-blocked`, `substituted`, `failed`, or
  `unknown`), including sanitized session errors and how many responses
  reached the output limit. The runner validates the outcome strictly. When
  the adapter has verified `worker_continuation` (Copilot: the same
  `--session-id` and runtime home resume a non-interactive session, verified
  live), the runner continues the worker's own session with the exact
  approved argv less only its new-session `--name` label (see the follow-up
  below), and the same environment, tools, model, effort, and context,
  under live enforcement.
- **Paged report delivery (`RHYOLITE_REPORT_DELIVERY_V1`).** When the final
  report is missing, cut, or invalid, the runner keeps every section that
  passes strict validation verbatim and asks the same session to resend only
  the missing or invalid sections, at most three per page with `FINDINGS`
  alone, with a 250-line budget per reply and continuation parts for longer
  pages. Each request lists every collect-mode validator diagnostic for its
  sections. Each page must use exact begin and end markers and passes the
  same strict contract program. The runner assembles the envelope in
  canonical order and promotes only a report that passes unchanged strict
  finalization. Limits: 2 resubmission rounds, 2 transient retries, 20
  continuations, and the remaining approved session time.
- **Collect-mode validation.** The strict validator gained a collect mode
  that reports every violation with its section, while strict mode keeps its
  exact first diagnostic.
- **Accurate fallback handling.** Copilot's scanner distinguishes a model that
  was only attempted from one that produced output. A blocked fallback is
  reported accurately and may be continued on the approved model;
  substituted output still fails closed.
- **Error surfacing.** Failed invocations append their sanitized session
  errors and outcome to `errors.txt`, and research failures append them to
  `research-errors.txt`. New `model service` and `worker recovery` failure
  stages describe these outcomes.
- **Failure analysis.** Every failed repository gets a deterministic
  `failure-analysis.md` and `failure-analysis.json` with the failure class,
  root cause, evidence, recovery already attempted, and recommended repair
  actions, and the run gets an index. `RHYOLITE ERROR` blocks name the file.
- **Orchestrator.** `--help` marks the legacy research switches, the
  rejection message explains the fix, and both orchestrators select research
  only with `--scope`.
- **Defense in depth.** Copilot children set `continueOnAutoMode` to
  `false` explicitly.

## Remaining limits and follow-ups

- Claude Code reports `worker_continuation` as `unverified` until a live
  probe proves same-session print-mode continuation, so Claude Code reviews
  do not yet use same-session recovery. Its higher output limit and
  continuation stitching remain in place.
- Research is not continued or relaunched automatically. The broker keeps
  exactly one network log per repository phase and refuses to start over an
  existing one, so a research retry needs its own broker-lifecycle design.
  Research failures now record their exact session errors and are classified
  as `model service` when transient.
- A refusal of the approved model can repeat for the same content. Recovery
  then exhausts its two retries and fails truthfully; Rhyolite never switches
  models automatically.
- The research dossier was already protected against a cut final reply: the
  broker validates the dossier when the worker submits it and persists the
  accepted candidate, which becomes canonical even if the final research
  reply is cut (Contract v6). The report-repair worker returns only a compact
  edit descriptor.

## Validation

- `tests/test-report-delivery.sh`: collect-mode validation, page planning,
  truncation, invalid and partial pages, continuation parts, round
  exhaustion, invalid UTF-8, and byte-for-byte reassembly.
- `tests/validate-harness-contract.sh`: Contract-v8 unit cases for outcome
  classification and validation, fallback diagnostics, and continuation
  argv, plus end-to-end runner scenarios for a cut report, a transient
  failure, a blocked fallback, and exhausted recovery with its failure
  analysis.
- `tests/validate-plugin.sh` and `tests/test-report-repair.sh`: existing
  contracts, updated for the new terminal stage when recovery exhausts.
- The full `bash ./tests/validate-all.sh` gate.

## Follow-up: first live continuation rejected by Copilot CLI 1.0.98-2

Run `20261013-224846-8087d3672af9ddf1` (scope 3, `claude-opus-5.5`, two
repositories) was the first live run of same-session recovery. One review
completed. In the other, three responses reached the 32,000-token output
limit, and the final reply held only the last 8 of the 16 required report
sections. Recovery started as designed (trigger `missing`, first page request
`R1P1.1`), but Copilot CLI rejected that first continuation before it reached
the model:

    error: option '-n, --name <name>' cannot be used with option '--session-id <id>' when it resolves to an existing or remote session or task.

The continuation produced no output, its outcome was `unknown`, and
recovery failed after one continuation, so no report was produced.

- **Root cause.** `harness_worker_continuation_argv` returned the approved
  worker argv verbatim, including `--name`. `--name` only labels a
  brand-new session, and Copilot CLI 1.0.98-2 rejects it when
  `--session-id` resolves to an existing session.
- **Why validation missed it.** The Contract-v8 live probe resumed a session
  without `--name`. The unit test used a synthetic source argv without
  `--name`, and the mocked CLIs accepted any argv on resume, so nothing
  exercised the real worker argv against the real CLI rule.
- **Misleading analysis.** The deterministic failure analysis classified the
  failure by its trigger as `output-limit`. It recommended a rerun, which
  would have failed the same way, and a smaller page budget, which was
  irrelevant.
- **Fix.** The Copilot continuation argv is now the approved worker argv
  without its `--name` pair. Any other session-name spelling fails closed.
  The deterministic failure analysis now classifies a harness CLI option
  rejection as `harness-invocation` and advises against a rerun until the
  adapter matches the installed CLI.
- **Live re-verification (Copilot CLI 1.0.98-2).** The probe used the
  adapter-built worker argv, an isolated runtime home, and a low-cost model:
  - Replaying the argv verbatim reproduced the rejection (exit code 1).
  - The same argv without `--name` resumed the session (`session.resume`),
    with its context and only the approved model.
- **Regression tests.**
  - The contract unit test derives the expected continuation from the
    golden worker argv.
  - Both mocked CLIs reject `--name` for an existing session, as the real
    CLI does, so the end-to-end recovery scenarios fail on the old behavior.
  - `tests/test-report-delivery.sh` replays this run's errors through the
    failure analysis.
