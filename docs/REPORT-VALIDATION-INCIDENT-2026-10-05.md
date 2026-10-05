# Rhyolite incident report: completed review rejected without bounded recovery

**Date:** 2026-10-05 UTC
**Status:** Confirmed product reliability defect; repair explicitly deferred
**Severity:** High (review reliability and resource efficiency)
**Security impact:** No security-boundary failure observed
**Confidence:** High

## Executive summary

A scope-3 Rhyolite repository review completed anonymous preflight, clone,
exact-commit snapshot creation, dedicated public research, provenance research,
and main analysis. The worker produced a complete report, which the runner
recovered from the sanitized session transcript. Final report validation then
rejected one malformed `Confidence:` value. The runner had no bounded repair or
re-prompt path, marked the repository `ReviewFailed`, and exited after about
30 minutes without producing a canonical report.

The validator behaved consistently with the documented report grammar. The
reliability bug is at the orchestration boundary: a nondeterministic but
recoverable model-formatting miss is immediately terminal even when the report,
research dossier, exact-commit snapshot, session state, and specific validator
diagnostic are all available.

The strict validator should not be weakened. A later repair should add a
bounded, isolated report-repair phase that revalidates every candidate and does
not rerun research, expose private evidence, or silently normalize ambiguous
semantics.

## Incident identity

- **Run ID:** `20261004-211856-37b7690410c84c19`
- **Source:** `https://github.com/xjamesmorris/rhyolite-test-1`
- **Reviewed commit:** `9c3106ca268c61081fa27d3dd5907f3c4b12a75e`
- **Scope:** 3
- **Model:** `gpt-5.6-sol`
- **Reasoning effort:** `max`
- **Context tier:** `long_context`
- **Research status:** `Completed`
- **Repository status:** `ReviewFailed`
- **Run status:** `Failed`
- **Started:** `2026-10-04T21:18:56Z`
- **Completed:** `2026-10-04T21:49:23Z`
- **Elapsed:** approximately 30 minutes 27 seconds

## Expected behavior

When main analysis returns a complete report that fails a correctable output
contract check, Rhyolite should preserve strict validation and attempt a small,
bounded correction using the existing report and exact validator diagnostic.
Only a successfully revalidated candidate should become canonical. If bounded
repair is exhausted, the run should fail truthfully while preserving all
attempts and diagnostics.

## Actual behavior

1. Anonymous public-access preflight succeeded.
2. The repository was cloned and exact commit `9c3106ca268c` was resolved.
3. A read-only source snapshot was prepared.
4. Dedicated research ran for approximately 11 minutes and completed with a
   validated dossier and sanitized network summary.
5. Main analysis ran for approximately 19 minutes.
6. The runner received an agent response and recovered a complete report from
   the sanitized session transcript.
7. Final report contract validation rejected this value:

   `Confidence: High for the two observed constructs; Medium for absence outside normalized text.`

8. The runner wrote the validator error, set exit code 1, finalized failed-run
   artifacts, and returned `ReviewFailed`.
9. No automatic correction, re-prompt, isolated repair worker, or bounded
   continuation was attempted.

## Direct failure evidence

The repository error artifact records:

> Final report contract validation failed: AGENT-TARGETING AND REVIEW
> MANIPULATION ASSESSMENT has an invalid confidence level: High for the two
> observed constructs; Medium for absence outside normalized text.

The generated section also contained a later valid section-level value,
`Confidence: Medium.`, but the contract intentionally validates every repeated
`Confidence:` label. One invalid repeated label therefore invalidates the
section.

## Root-cause analysis

### 1. The generated value violated the documented grammar

The review prompt requires each `Confidence:` value to begin with exactly one
of `High`, `Medium`, or `Low`. Any explanation must follow an approved
punctuation delimiter such as `. `, `; `, `: `, `, `, or ` - `. The failing
text begins `High for`, uses no approved delimiter, and embeds two different
confidence levels in one field.

Evidence:

- `plugins/rhyolite/skills/readonly-repository-review/review-prompt.txt:210-227`
  defines the accepted forms and explicitly rejects ambiguous bare prefixes.
- `plugins/rhyolite/skills/readonly-repository-review/scripts/review-output.sh:488-538`
  finds every repeated confidence label, accepts only `High|Medium|Low`, and
  validates the remainder against the delimiter grammar.
- `tests/validate-plugin.sh:3907-4010` exercises repeated labels, valid inline
  forms, invalid repeated values, and ambiguous prefixes.

**Conclusion:** The strict rejection is expected. Accepting the compound value
would weaken a deliberate machine-readable contract and preserve an ambiguous
confidence statement.

### 2. Validation is single-shot and immediately terminal

After extracting or transcript-recovering the report, the runner checks the
closing delimiter, Markdown-table prohibition, and report contract exactly
once. Any contract error is appended to `errors.txt` and immediately changes
the worker result to failure.

Evidence:

- `plugins/rhyolite/skills/readonly-repository-review/scripts/run-parallel-reviews.sh:5209-5248`
  performs report extraction and transcript fallback.
- `run-parallel-reviews.sh:5262-5271` performs one contract-validation call and
  sets `exit_code=1` on failure.
- There is no repair loop between validation and failure finalization.

**Conclusion:** The primary product defect is the absence of bounded recovery
for a completed report with a specific, potentially correctable contract
error.

### 3. The harness contract has no report-repair capability

The harness interface supports worker construction, report extraction,
isolation verification, agent-state persistence, and a human-facing resume
policy. It does not expose a constrained report-repair operation.

Evidence:

- `plugins/rhyolite/lib/harness/common.sh:8-37` lists all required harness
  functions; none performs contract repair or restricted continuation.
- `plugins/rhyolite/lib/harness/copilot.sh:267-270` states that continuation
  must occur through the trusted runner and that direct CLI resume is unsafe.

**Conclusion:** Recovery cannot be added safely as an ad hoc direct resume. It
requires an explicit trusted-runner and harness contract.

## Why this is a Rhyolite bug

Model output is nondeterministic, while the final report schema is intentionally
strict. Rhyolite owns the boundary between those two properties. A production
orchestration layer should expect occasional correctable schema misses and
handle them with bounded validation-driven recovery. Treating the first format
miss as terminal discards completed high-cost work and makes successful runs
unnecessarily dependent on perfect first-pass formatting.

This is not evidence that the reviewed repository failed analysis. It is not an
authentication, clone, research, timeout, or security-isolation failure. It is
a Rhyolite report-finalization reliability failure.

## Impact

- Approximately 30 minutes of review execution did not yield a canonical
  report.
- Dedicated research completed successfully but cannot currently be promoted
  into a successful run without rerunning the trusted workflow.
- The user receives a failure even though the substantive report was complete.
- Repeating the whole scope-3 run consumes additional model, network, and user
  time and can produce different research or analysis output.
- The invalid candidate remains useful evidence but must not be presented as a
  canonical report.
- No source checkout modification, credential exposure, private-evidence
  exposure, or target-repository security impact was observed.

## Contributing factors

1. The prompt permits repeatable per-item confidence labels, increasing the
   number of independently validated fields.
2. The prompt explains valid syntax but does not explicitly show this exact
   compound-confidence anti-pattern.
3. The worker does not perform a validator-backed self-check before returning.
4. The runner validates only after the worker process has exited.
5. The harness contract has no constrained repair or continuation primitive.
6. The failure occurs after expensive research and analysis rather than before
   those phases.

## Deferred repair recommendation

Repair was not performed as part of this incident report.

The preferred future design is:

1. Keep the current strict validator unchanged.
2. On a report-contract failure, preserve the invalid candidate and exact
   sanitized diagnostic.
3. Start a bounded repair phase, preferably one attempt by default and at most
   two.
4. Give the repair phase only the invalid report, scope, report contract, and
   validator diagnostic. It should not receive network tools, repository write
   access, credentials, raw cookie ledgers, unsupported bodies, or unrelated
   filesystem access.
5. Instruct repair to change only contract-invalid presentation and to preserve
   substantive findings, citations, confidence intent, and required sections.
6. Re-run all existing finalization checks after every attempt: UTF-8,
   delimiters, forbidden tables/content, exact section order and fields,
   confidence grammar, provenance grammar, and safety restrictions.
7. Promote only a fully valid candidate to canonical `review.txt`,
   `review.md`, and `review.html`.
8. Preserve failed candidates and repair diagnostics as noncanonical artifacts.
9. Emit explicit progress milestones for validation failure, repair attempt,
   successful revalidation, or repair exhaustion.
10. If all attempts fail, retain the current truthful `ReviewFailed` outcome.

A prompt-only clarification is worthwhile but insufficient. Add an explicit
anti-example such as a confidence field containing both `High` and `Medium`,
and require exactly one level per label. The runner must still recover because
prompt compliance cannot be guaranteed.

## Required regression coverage for later repair

1. A mock worker emits the observed compound confidence value; the first
   validation fails, bounded repair returns one valid level, and the run
   completes.
2. Research executes exactly once; report repair does not rerun or broaden
   research.
3. The repaired report passes the unchanged strict validator.
4. Repair exhaustion remains `ReviewFailed` and preserves every candidate and
   diagnostic.
5. A repair attempt that changes substantive findings or introduces prohibited
   output is rejected.
6. Scope 1, 2, and 3 required headings and fields remain enforced.
7. Repair receives no private research evidence and no repository write tools.
8. Cancellation and timeout during repair produce truthful state and cleanup.
9. Progress, state, manifest, handoff, and HTML index distinguish initial
   analysis from report repair.
10. The existing transcript-fallback path continues to work before repair.

## Acceptance criteria for later repair

- The reproduced run does not fail solely because of a correctable confidence
  formatting error.
- Strict report validation remains unchanged or becomes stricter, never looser.
- Repair attempts are bounded and observable.
- No research rerun is required for report-only correction.
- No direct CLI resume command is exposed to the user.
- Canonical artifacts are generated only from a fully validated report.
- Exhausted repair remains an explicit failure with complete preserved evidence.

## Repository-state caveat

The Rhyolite checkout was on `main` at
`23dcf11cf28a497246f9509d50fe56853246a5f8` with substantial pre-existing
uncommitted changes when this incident was investigated. Relevant observations:

- `review-output.sh`, which contains the confidence validator, was not modified
  relative to `HEAD`.
- `run-parallel-reviews.sh` had unrelated current-worktree changes, but its
  single-shot report-validation block showed no repair path.
- `review-prompt.txt` and `tests/validate-plugin.sh` had pre-existing local
  modifications; later repair work must first establish the intended branch and
  reconcile those changes.
- This investigation did not modify the Rhyolite repository.

## Preserved artifacts

- Run state: `/home/jamorris/src/github/rhyolite-output/repo-review/20261004-211856-37b7690410c84c19/state.json`
- Run handoff: `/home/jamorris/src/github/rhyolite-output/repo-review/20261004-211856-37b7690410c84c19/handoff.md`
- Run manifest: `/home/jamorris/src/github/rhyolite-output/repo-review/20261004-211856-37b7690410c84c19/manifest.json`
- Repository state: `/home/jamorris/src/github/rhyolite-output/repo-review/20261004-211856-37b7690410c84c19/github--xjamesmorris--rhyolite-test-1/state.json`
- Repository errors: `/home/jamorris/src/github/rhyolite-output/repo-review/20261004-211856-37b7690410c84c19/github--xjamesmorris--rhyolite-test-1/errors.txt`
- Analysis timeline and recovered candidate: `/home/jamorris/src/github/rhyolite-output/repo-review/20261004-211856-37b7690410c84c19/github--xjamesmorris--rhyolite-test-1/analysis-timeline.txt`
- Repository handoff: `/home/jamorris/src/github/rhyolite-output/repo-review/20261004-211856-37b7690410c84c19/github--xjamesmorris--rhyolite-test-1/handoff.md`
- Research state: `/home/jamorris/src/github/rhyolite-output/repo-review/20261004-211856-37b7690410c84c19/github--xjamesmorris--rhyolite-test-1/research/research-state.json`
- Research dossier: `/home/jamorris/src/github/rhyolite-output/repo-review/20261004-211856-37b7690410c84c19/github--xjamesmorris--rhyolite-test-1/research/research.txt`
- Sanitized network summary: `/home/jamorris/src/github/rhyolite-output/repo-review/20261004-211856-37b7690410c84c19/github--xjamesmorris--rhyolite-test-1/research/network/summary.json`

## Final assessment

The incident is confirmed as a Rhyolite orchestration defect. The report
validator correctly prevented an ambiguous confidence statement from becoming
canonical, but the runner incorrectly made that first recoverable formatting
miss terminal. Future repair should preserve strict validation and introduce a
small, isolated, approval-compatible repair phase rather than accepting the
invalid syntax or rerunning the entire review.
