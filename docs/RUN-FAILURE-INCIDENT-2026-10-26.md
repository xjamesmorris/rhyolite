# Rhyolite incident report: security scan compaction failure of 2026-10-26

**Date:** 2026-10-26 (local time)
**Status:** Root cause confirmed; fixes implemented for 0.9.0 (Harness
Contract v10); live verification pending
**Severity:** Medium (review reliability; two completed scans and a third
scan's findings were not consolidated)
**Security impact:** None observed. No output from a model outside the
approved plan was accepted, and the read-only boundary held.
**Confidence:** High, from the retained scan C session events and
compaction checkpoint, the scan report, the runner code, and the
compaction prompt in Copilot CLI 1.0.104-4

## Executive summary

A scope 1 review of `https://github.com/signalapp/libsignal` at commit
`fc90b90fa2b9c37822fa47ba0e0dcdf387a0c071` (run
`20261026-170519-4448ff3f62cd4db9`) with three security scans failed after
33 minutes 55 seconds. Scan A (`example-unlisted-model`, `max`) and scan B
(`gpt-6-astra`, `max`) completed with 5 and 4 findings. Scan C
(`gemini-4-argon`, `high`, `long_context`) ran for 33 minutes 51 seconds and
returned a 39 KB report that describes seven findings, but in a layout of its
own. The runner rejected it:

    The scan report must contain the section SCAN CONTEXT exactly once.

The runner treated an invalid scan report as final. The approved plan
required all three scans, so consolidation never started and the
repository failed.

Scan C lost its report contract to Copilot CLI's automatic context
compaction. After its 40th model call the session reached 809,055 of
983,040 prompt tokens (82%), and Copilot replaced the conversation history,
including the trusted `RHYOLITE_SECURITY_SCAN_V1` request and the skill text
loaded at the start, with a 16,217-character summary written by the model.
The request was the only place that defined the scan report contract, and
the summary kept only "return the exact `REPOSITORY SECURITY SCAN REVIEW
REPORT` format". The only Rhyolite instructions that survive compaction are
the worker agent's system-prompt instructions. They deferred to "the
contract that the request defines" and otherwise described the canonical
review report, with numbered plain-text findings and
`PRIORITIZED REMEDIATION`. Scan C followed those cues for its last 21 model
calls.

The long-context tier was in effect: Rhyolite passed `--context
long_context`, the session recorded `contextTier: long_context`, and every
model call had a 983,040-token prompt budget. The scan genuinely used about
800,000 tokens over 450 tool calls. Scans A and B, also on `long_context`
with 922,000-token budgets, peaked at 591,934 and 496,442 tokens and were
never compacted.

## Evidence

From the scan C session record, compaction checkpoint, worker outcome, and
scan report:

| Signal | Value |
| --- | --- |
| Model, effort, tier | `gemini-4-argon`, `high`, `long_context` |
| Prompt budget | 983,040 tokens on all 65 model calls |
| Compaction trigger | `threshold`, at 809,055 tokens, after call 40 of 65 |
| Compaction result | 315 of 353 messages removed; context reduced to 84,802 tokens |
| Contract in the summary | "the exact `REPOSITORY SECURITY SCAN REVIEW REPORT` format", with no section or field names |
| Largest prompt | 868,467 tokens |
| Tool calls | 450 |
| Transient server errors | 3, retried by Copilot CLI; not causal |
| Report sections | `SECURITY POSTURE SUMMARY`, `TRUST BOUNDARIES AND ATTACK SURFACE`, `SECURITY FINDINGS`, `LIMITATIONS AND UNINSPECTED AREAS`, `PRIORITIZED REMEDIATION` |
| Required sections | `SCAN CONTEXT`, `SECURITY FINDINGS`, `COVERAGE`, `LIMITATIONS` |
| Finding format | `1. [HIGH] <title>` with its own labels, not `Finding 1:` with the seven required fields |
| Worker outcome | `completed`, exit 0, no refusal or fallback |

Copilot CLI 1.0.104-4's compaction prompt tells the model: "The history is
being compacted so moving forward, all conversation history will be removed
and you'll only have this summary to work from." After compaction, scan C
never reopened the skill or the prompt template, and its final reasoning
drafted the report layout without naming any required heading.
Post-compaction calls still carried the worker agent instructions as the
`selected_agent_instructions` system-prompt segment.

The three scans used about 7,270 AIU of AI credits (A 3,185, B 3,472,
C 610), all of it discarded by the failed quorum.

## Root cause

1. **The scan report contract existed only in the request.**
   `security-scan-prompt.txt` alone defined the four section headings, the
   finding fields, and the no-findings sentence, and the skill and both
   worker agents deferred to it. Automatic compaction removes the request
   with the rest of the history, so a long scan could lose its contract
   mid-session. Claude Code compaction has the same effect on the request.
2. **No recovery for a malformed scan report.** The runner treated
   `invalid-report` and `missing-report` as final. It neither asked the same
   session to resend the report, although both production harnesses support
   same-session continuation and the main review and the consolidation
   ledger already used it, nor relaunched the scan. It also removed the
   scan's runtime home before it validated the report, so no continuation
   was possible.
3. **All-or-nothing quorum without a launcher override.** With the default
   minimum of every scan, one failed scan discarded two completed scans and
   the consolidation pass. Only the direct runner could lower
   `MinimumSuccessfulScans` or pin a commit, and no path could reuse the
   completed scans of the failed run.

## Fixes

- **The scan contract survives compaction.** The scan report contract now
  sits between `RHYOLITE_SECURITY_SCAN_REPORT_CONTRACT_V1` and
  `END_RHYOLITE_SECURITY_SCAN_REPORT_CONTRACT_V1` in the scan prompt and,
  byte for byte, in both worker agents' own instructions, which stay in the
  system prompt when the conversation is compacted. The contract also names
  the deviations seen here: no summary, posture, attack-surface, or
  remediation section, and no numbered-list or bracketed-severity findings.
  Validation keeps the three copies identical and in step with the runner's
  scan report validator and its 60-finding limit.
- **One same-session report request.** The runner now validates a scan's
  report before it removes the runtime home. When the session ended
  normally on the approved model without a valid report, it continues that
  session once, under the adapter's continuation argv and live enforcement,
  with a `RHYOLITE SECURITY SCAN REPORT REQUEST` that carries the runner's
  exact diagnostic and the full contract, and asks for only the report. The
  limit is approval-bound as `SecurityScans.ScanReportRecovery`, and scan
  state records `ReportRequest` (`NotNeeded`, `Recovered`, `Failed`,
  `NotCompleted`, `Unavailable`, `Exhausted`, or `NotReached`). A
  continuation that itself fails is classified by its own failure, never as
  a report the model declined to correct. For this run, scan C would
  have resent its seven findings in one short turn.
- **Two of three scans by default.** A three-scan plan now requires two
  successful scans by default; a two-scan plan still requires both. The
  launcher accepts `--min-successful-scans` and `--commit`, and editing the
  security scans at plan approval asks how many must succeed.
- **Compaction in worker outcomes (Harness Contract v10).** Worker outcome
  schema 3 adds `Compactions`. Copilot counts applied
  `session.compaction_complete` events once by attempt ID; Claude Code
  counts `compact_boundary` records. Scan state records the count, and a
  scan or review report that failed its contract names the compaction in
  its diagnostic and failure analysis.
- **Reuse of completed scans.** `--reuse-scans <run output folder>`, in the
  launcher and the direct runner, reuses the validated reports of completed
  scans from an earlier run of the same repository and commit when the
  harness, context tier, scan protocol, model, and effort match. It pins the
  earlier commit, binds each reused report's SHA-256 digest into the
  approval hash, and verifies each copy again before consolidation, so only
  the missing scans and the consolidation run again. Failure analysis now
  names the run folder whenever completed scans can be reused.

Rejected alternatives: Copilot's `preCompact` hook or summary focus
instructions would make a hook mutate model context, which the display-only
hook policy forbids; raising the compaction threshold only delays the same
failure; a model-free conversion of scan C's layout would have to invent the
missing structure.

## Recovering run 20261026-170519-4448ff3f62cd4db9

The failed run could not be resumed in place: the runner then had no
resume or scan-reuse path, and continuing scan C's Copilot session directly
would bypass the runner's approved-model enforcement and isolation. The
operator repeated the review separately. With these fixes, a new plan with
`--reuse-scans` and the failed run's folder would reuse scans A and B and
run only scan C and the consolidation.

## Validation

- `tests/validate-plugin.sh`: the contract block is identical in the scan
  prompt and both worker agents and matches the runner's validator; a
  compacted scan that answers in its own layout is recovered by one
  same-session report request, and a resend that still breaks the contract
  fails only that scan under the default two-of-three quorum; plan JSON and
  text for `ScanReportRecovery`, the quorum default, and reuse; reuse that
  runs only the missing scan, its plan-time rejections, and an approval hash
  that changes when a reused report changes.
- `tests/validate-harness-contract.sh`: outcome schema 3 vectors, Copilot
  compaction counting from the stream and persisted events (verified against
  scan C's retained `events.jsonl`, which yields one compaction), Claude
  Code `compact_boundary` counting, and the launcher's
  `--min-successful-scans`, `--commit`, and `--reuse-scans` options.

Live verification of a compacted scan's report request and of a reused-scan
review remains open; see [TASKS.md](TASKS.md).

## Follow-up: libsignal review on the fixed runner (2026-10-26)

Run `20261026-225132-482122841a28901c` repeated the libsignal review at the
same commit on candidate `a574d7697b3ce26d6246b124544f9587f3aeb223` with two
scans: `example-unlisted-model` (scan A and the review model) and
`gpt-6-astra` (scan B), consolidated by `claude-fable-5.1`. Both scans
completed in one attempt with 2 and 5 finding IDs. Neither was compacted,
so no scan report request was needed. The validated ledger confirmed 2,
refined 4, and rejected 1 of the 7 IDs, and the report passed with 8
findings; the repository completed in 45 minutes 25 seconds. This exercises
the fixed scan path on the same large repository, but not a compaction.
