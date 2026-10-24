# Rhyolite task tracker

This file tracks open Rhyolite engineering, verification, and release tasks
and their priorities. It records work state only:
[AGENTS.md](../AGENTS.md) remains the canonical development contract, and
[PLAN-OF-RECORD.md](PLAN-OF-RECORD.md) remains the platform plan. Users
still report bugs and request features through the routes in
[SUPPORT.md](../SUPPORT.md).

**Last updated:** 2026-10-23 (UTC)

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
| T17 | P2 | Open | Complete Codex harness gates after the offline snapshot proof |
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

### T17 (P2, Open): Complete Codex harness gates after the offline snapshot proof

- **Problem:** The Codex workstream targets the official CLI, scopes 1-3,
  the launcher, and native installation/entrypoints. Initial Codex 0.163.0
  probes could produce a zero-tool request but no ordinary file-read/search
  tools with shell disabled, including after a synthetic catalog advertised
  those tools. The adapter cannot proceed under the current design by
  granting shell access or adding an unapproved broker.
- **Progress:** the maintainer approved the existing broker's separate
  offline snapshot MCP mode. The bounded runtime, Bash grants/lifecycle,
  Contract-v9 seam, and negative tests are implemented on the development
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
- **Next step:** establish the intended provider and obtain a successful
  API-key-authenticated isolated model response, then run the native
  setup/approval/controller path from a private
  staged package, then complete live research, continuation/recovery, repair,
  all-scope, and stop/timeout gates. Keep production registration absent until
  the full contract and live evidence pass.
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
