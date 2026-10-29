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
| T17 | P2 | Open | Complete Codex harness gates after the offline snapshot proof |
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

### T17 (P2, Open): Complete Codex harness gates after the offline snapshot proof

- **Problem:** The Codex workstream targets the official CLI, scopes 1-3,
  the launcher, and native installation/entrypoints. Initial Codex 0.163.0
  probes could produce a zero-tool request but no ordinary file-read/search
  tools with shell disabled, including after a synthetic catalog advertised
  those tools. The adapter cannot proceed under the current design by
  granting shell access or adding an unapproved broker.
- **Progress:** the maintainer approved the existing broker's separate
  offline snapshot MCP mode. The bounded runtime, Bash grants/lifecycle,
  Contract-v11 seam, and negative tests are implemented on the development
  branch; [SNAPSHOT-TRANSPORT.md](SNAPSHOT-TRANSPORT.md) defines the contract.
  On 2026-10-21, credential-free Codex 0.163.0 captures proved the complete
  seven-tool inventory and twelve scripted read/search/resource/denial
  operations, using only exact per-tool preapprovals with global approval
  still disabled. Additional synthetic cases proved exact final bytes,
  native UUID history restoration, and fresh zero-tool replies, and exposed
  model-reroute/context-evidence caveats. The earlier full Fedora validation
  gate passed, and the current broker suite has 67 passing tests. A private
  Git-free candidate also passed
  existing-harness installation, prior-version update, and public-release
  sandbox tests. A maintainer-run authenticated native smoke returned exact
  output without reroute/rate/quota/timeout warnings. Offline catalog evidence
  fixes the delegation-safe maximum at `max` and the long-context setting at
  872,000 configured / 828,400 usable tokens. Native local plugin/picker,
  combined snapshot/research MCP, and adapter-built review/snapshot lifecycle
  probes now pass. The complete adapter remains unregistered, and these are
  not production Rhyolite native-package or all-scope proofs.
  The authenticated adapter-built `max`/long-context smoke now also passes:
  exact snapshot read/reply, native session verification, zero retries, no
  reroute/rate/quota/timeout warning, clean broker exit, and complete runtime
  cleanup. The recommended handoff is now selected: unregistered native setup
  and approval skills plus a strict per-stage Bash helper are implemented and
  fixture-validated without shell or runner-control MCP authority. The
  Bash-owned plan/approval/execution controller and an unreachable staged
  launcher branch now also pass fixture plan-hash, edit/explain structure,
  exact status, and verified stop-path tests. A pinned-CLI PTY probe also
  installed the actual staged plugin and completed the real setup skill's two
  Default-mode native pickers with only `request_user_input`.
  On 2026-10-22, a connected controller/stage-helper PTY regression reproduced
  and fixed discarded native UI stdout: setup and approval now retain their
  terminal while result paths stay off controller stdout. This is fixture
  evidence, not a live staged run. The CLI is now installed and verified at
  0.163.0. On 2026-10-23 (UTC), local comparison confirmed that the supplied
  credential matches the native API-key login, and a fresh API-key-only
  runtime passed native login-status inspection, but its actual zero-tool
  model request returned HTTP 401 from the native default OpenAI endpoint.
  No custom provider or Azure endpoint was selected in this environment.
  A subsequent metadata-only capture from the working terminal confirmed
  the same native-default OpenAI provider, no explicit Azure endpoint, and
  no API-key environment variables or routing overrides. Installation,
  key-file access, and context capture are no longer blockers; backend
  authorization for the intended provider remains unresolved. No credential
  values were added to repository artifacts or documentation.
  On 2026-10-27 the branch merged the 0.9.0 release line. The shared seam is
  now Contract v11 (the shipped Contract-v10 refusal and compaction outcomes
  plus the snapshot functions), and the Codex adapter writes outcome schema 3:
  pinned 0.163.0 source fixes its refusal evidence (the `HighRiskCyberActivity`
  reroute, content-filter stops, and policy errors) and its rollout records
  for prompt sizes and compactions. Codex has one verified model, so it keeps
  the integrated security pass; offline-transport plans with more than one
  security scan fail before planning. The same evening, the authenticated
  adapter smoke passed again at Contract v11 with an explicitly configured
  provider, and the outcome classifier reported `completed` from the real
  session record. The first live guided setup failed at its stage validator,
  which rejected the model's reasoning items; the validator now accepts them
  and names any failed check, and the live rerun with that fix passed.
  The first live scope-1 review then failed before its worker launched: the
  adapter wrote its worker instructions while building argv, before the
  runner creates the runtime home. Runtime-home preparation now writes them,
  and a mocked end-to-end runner test with the real snapshot broker covers
  the whole review path. The live rerun passed on 2026-10-28. Inspection
  then found that research-enabled review instructions forbade every MCP
  tool and required direct path reads of the dossier, which an offline
  snapshot reader cannot do; they now allow exactly the harness-supplied
  read-only snapshot tools and name the dossier grants. The first live
  scope-2 review then failed before its research worker launched: the
  adapter compared the broker's compact research tool list with a spaced
  rebuild as exact strings. The comparison now ignores JSON whitespace, and
  the mocked end-to-end test also covers the scope-2 research launch with
  both real brokers. Two later scope-2 reruns proved live research and
  dossier acceptance. One failed on provider errors because the adapter
  disabled Codex's own retries, which it now keeps with retry-notice
  handling; the other failed on a cookie false positive in the shared
  research validation, which now verifies cookie attributes against the
  private ledger. With both fixes, the live scope-2 review passed on
  2026-10-28, and the mocked end-to-end test now also drives a real report
  repair through a fresh tool-less Codex session. The live scope-3 review
  passed the same day, with Codex's built-in retries absorbing six provider
  rate-limit rejections during research. An offline continuation probe with
  the pinned CLI then found that a resumed session could not restart the
  snapshot broker in its runtime root; the broker now allows a later
  lifecycle after a recorded clean exit, and the probe passes. The live
  continuation probe passed on 2026-10-29, after a first attempt whose
  synthetic prompt the provider's content filter declined, so Codex now
  reports `worker_continuation` as `yes`. Enabling it exposed that the
  normalizer reported every failed turn as an adapter failure, which blocked
  transient recovery; an ordinary failed turn now normalizes with an empty
  reply, and the mocked end-to-end test covers same-session recovery.
- **Next step:** complete the stop/timeout/interrupt lifecycle gate,
  including what Codex records for an interrupted turn, and the
  hostile-configuration isolation gate, then production enablement. Live
  report repair remains fixture-proven until a live run needs one. Keep
  production registration absent until the full contract and live evidence
  pass.
- **Done when:** all three scopes, native setup/package behavior,
  enforcement, recovery, repair, isolation, and cleanup satisfy the harness
  playbook and Fedora validation without regressing existing harnesses.
- **Source:** [CODEX-HARNESS-EVIDENCE.md](CODEX-HARNESS-EVIDENCE.md).

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
