# Harness architecture

**Contract version:** 11

**Initial implementation:** I1a

**Supported harnesses:** `copilot` (default) and `claude`

The source tree also contains an unregistered `codex` adapter candidate under
focused development. It is not discoverable or selectable through the
production registry.

## Purpose

Rhyolite separates repository-review orchestration from the command-line
harness that runs the write-disabled worker. The runner keeps ownership of
repository validation, anonymous cloning, snapshot isolation, plan approval,
artifact production, and failure reporting. A selected harness adapter owns
only harness-specific identity, model and capability metadata, authentication
bridging, worker process construction, runtime-home handling, final-response
extraction, and harness-specific isolation checks.

Contract v11 is a fail-closed data-contract and lifecycle seam. It keeps the
Contract-v3 plan/state identity and the Contract-v4 bounded, isolated
report-repair invocation, which can return only a compact confidence-edit
descriptor. Contract v5 moved the dedicated scope 2/3 research worker behind
four adapter functions, so each production adapter builds its own research
worker while the runner keeps broker lifecycle, validation, cleanup, and
artifacts. Contract v6 made the adapter responsible for translating its
CLI's raw worker stdout into a readable narrative plus the exact final
assistant reply for every child phase, with approved model and effort
verification, because print-mode text stdout is not the assistant reply.
Contract v7 adds live enforcement: while a worker runs, the runner polls the
adapter's `harness_detect_worker_violation` every five seconds, and the first
recorded model, reasoning effort, or subagent outside the approved plan
terminates the worker immediately instead of after completion. No worker on
either harness receives a subagent tool, because Copilot CLI lets a `task`
argument override every configured subagent model. Contract v8 adds bounded
same-session recovery: after every worker invocation the adapter classifies
the outcome through `harness_worker_outcome`, and when the adapter has
verified `worker_continuation`, the runner may continue the review worker's
own session, through `harness_worker_continuation_argv`, after a transient
model-service failure, after an automatic model fallback that was blocked
before it produced output, or to fetch missing, truncated, or invalid report
sections in bounded pages (`RHYOLITE_REPORT_DELIVERY_V1`). A continuation
uses the exact approved argv less only its new-session name label (Claude
Code resumes with `--resume` in place of `--session-id`), and the
same environment, runtime home, tools, model, effort, and context, and live
enforcement applies to it. The runner persists the adapter's agent state
after every worker invocation that keeps the runtime home and calls
`harness_verify_isolation` after every continuation, so the adapter's
post-exit verification covers every continuation turn before its reply is
accepted. The contract never
permits a model to rewrite accepted report sections, accepts substituted
output, continues a research session, or falls back to another harness or
model. After the research worker's own transient model-service failure or
blocked automatic fallback, the runner relaunches research at most once
(approval-bound `ResearchRelaunchLimit`) with a fresh broker, runtime,
session, and network log, archives the failed attempt under
`research/attempts/<n>/`, and never passes an archived ledger to a broker.
Contract v9 makes a provider refusal its own outcome. When the model provider
declines a request to the approved model (a content refusal), the adapter's
live detector returns `RHYOLITE_HARNESS_WORKER_REFUSAL_STATUS` (5) and the
runner stops the worker before any automatic harness fallback can answer,
and `harness_worker_outcome` reports `refused` with the number of declined
calls, the approved session's prompt budget, and its largest recorded prompt.
The runner never retries the refusing model and never accepts another
model's output; under the approval-bound `RefusalPolicy` a refused security
scan is skipped and excluded from the required scans, and a refused report
writer or research worker hands over, in a fresh session and runtime home,
to the next approved model that the provider has not declined for the
repository. Contract v10 adds `Compactions` to the worker outcome (schema 3):
the number of context compactions that the harness recorded in the session,
each of which replaces earlier conversation, including the request, with a
model-written summary. The runner records it for every security scan and
names it in failure analysis when a report then fails its contract.

Contract v11 adds explicit snapshot transport selection/configuration without
changing the native Copilot or Claude Code worker tools. The fixed offline
MCP mode reuses the approved bundled Python broker, with Bash owning bounded
snapshot grants and lifecycle. Its policy, exact tools/schemas, limits, and
phase grant profiles are approval-bound `SnapshotTransport` data.
[SNAPSHOT-TRANSPORT.md](SNAPSHOT-TRANSPORT.md) defines the complete interface.
The Codex workstream remains unregistered until all eligibility gates pass.
Transient and token-rate-limit retries use approval-bound increasing
backoff in `WorkerRecoveryPolicy.RetryBackoff`: 30 seconds initially,
doubling to at most 300 seconds within the approved session timeout and
unchanged retry limits, preserving model, effort, context, tools, and session.

[ADDING-A-HARNESS.md](ADDING-A-HARNESS.md) is the normative implementation
playbook for Contract v11 and any future production adapter.

## I1a invariants

- Harness resolution is deterministic:
  1. explicit `--harness ID`
  2. `RHYOLITE_HARNESS`
  3. `copilot`
- `--harness` is a Rhyolite control and is consumed before any downstream
  harness command is built.
- The launcher and runner accept only the separated `--harness ID` form.
  Equals-form inputs such as `--harness=codex` and `--harness=` fail before
  prompt construction, launcher-state creation, CLI discovery, Git, or
  network activity.
- The adapter registry is a fixed map. Harness IDs never become paths and are
  never used for dynamic discovery.
- A harness ID must pass the safe-ID validator and must have an exact registry
  entry. Safe syntax alone does not make an adapter supported.
- Unknown IDs, unsafe IDs, missing adapter files, incomplete adapters, and
  adapter-function failures stop the operation. There is no fallback.
- `bogus` and `codex` do not select Copilot and do not load another adapter.
  In I1a, `claude` was likewise unregistered; it now selects the registered
  Claude Code adapter.
- The Copilot adapter preserves the existing worker and outer-launcher
  argument vectors byte for byte after Rhyolite consumes `--harness`.
- Capability values are exactly `yes`, `no`, or `unverified`.
- Failures are sanitized, explanatory, and nonzero.

Safe IDs match `^[a-z][a-z0-9-]{0,31}$`. They are deliberately path-inert:
no slash, dot, underscore, uppercase character, whitespace, control
character, shell metacharacter, or empty value can pass. The registry remains
the authority even after this syntax check.

## Selection and launcher context

The selected harness and the trusted launcher context are separate inputs.
Resolution happens first. Context validation happens before adapter loading.

The packaged launcher exports:

```text
RHYOLITE_LAUNCHER_HARNESS=copilot
```

If `RHYOLITE_LAUNCHER_HARNESS` is set, it must:

1. be nonempty;
2. be a valid safe harness ID; and
3. exactly equal the selected harness.

Any violation fails at stage `harness <selected> context`. This check occurs
before adapter loading, output creation, workspace creation, or harness CLI
discovery.

An entirely unset marker is the direct-terminal compatibility exception. It
allows users and lower-level callers to run the review runner directly with
the default or an explicit valid harness. An empty exported marker is not
equivalent to an unset marker.

The explicit CLI option always wins over `RHYOLITE_HARNESS`. For example,
`--harness copilot` selects Copilot even if the inherited
`RHYOLITE_HARNESS` has another value. The launcher then exports the marker for
the resolved selection and does not forward `--harness` to Copilot.

The launcher validates an inherited `RHYOLITE_LAUNCHER_HARNESS` before it
discovers Copilot or creates launcher state. A malformed marker and a valid but
mismatched marker use the same fail-closed stage with remediation that tells
the caller either to unset the inherited marker in a fresh environment or
restart through the trusted launcher with the same supported harness selected
in both contexts.

## Fixed adapter loading

The shared resolver and loader live in
`plugins/rhyolite/lib/harness/common.sh`. The Copilot adapter lives in
`plugins/rhyolite/lib/harness/copilot.sh` and the Claude Code adapter in
`plugins/rhyolite/lib/harness/claude.sh`. The loader performs these steps in
order:

1. Resolve the selected harness.
2. Validate the launcher marker when it is set.
3. Validate the selected ID as a safe identifier.
4. Resolve the ID through the fixed adapter map.
5. Source the mapped adapter file.
6. Assert every required Contract-v11 function exists.
7. Invoke adapter functions only through the guarded contract boundary.

The common boundary captures scalar output without exposing adapter stderr and
invokes status/array functions in the current shell so their structured error
detail remains available for sanitized reporting. The runner rejects empty,
malformed, duplicated, or otherwise invalid contract values before using them.

In addition to the loader's identity and tri-state capability checks, the
runner validates adapter-provided display and CLI names, the offline model
catalog, default and explicit model IDs, selected reasoning effort, selected
context tier, resume policy, strict provider JSON, and the protected
secret-environment list. Provider JSON must contain exactly
`Id`, `Host`, and `ForwardedEnvVarNames`; the forwarded names must exactly
match the unique shell identifiers returned by
`harness_auth_secret_env_vars`. Planning may invoke only the local harness CLI
help surface needed to obtain and validate its model catalog; it does not
prepare run-time authentication context. Execution performs authentication and
worker checks only after the approved plan still matches.

A missing or unreadable mapped adapter, an unknown ID, an incomplete adapter,
or invalid load-time identity/capability metadata fails at stage:

```text
harness <id> load
```

After a successful load, an adapter function that fails or returns an invalid
contract value fails at stage:

```text
harness <id> <function>
```

Diagnostics at all three harness stages pass through Rhyolite's normal
sanitization boundary before they reach stderr.

## Contract-v11 functions

Every mapped adapter must define all functions below.

| Function | Adapter responsibility |
| --- | --- |
| `harness_id` | Return the adapter's canonical registry ID. It must equal the selected ID. |
| `harness_display_name` | Return the user-facing harness name. |
| `harness_cli_name` | Return the executable name used for discovery and invocation. |
| `harness_require_cli` | Verify that the required CLI is available without starting it. |
| `harness_capability` | Return exactly `yes`, `no`, or `unverified` for the requested capability. |
| `harness_default_model` | Return the adapter's default model ID. |
| `harness_list_models` | Return the model IDs in the harness CLI's offline local help/config catalog. |
| `harness_validate_model_id` | Return 0 only for an exact member of the offline catalog, without substitution. Return `RHYOLITE_HARNESS_MODEL_UNLISTED_STATUS` (3) only for a safe ID that is absent from a successfully discovered catalog, is not a selector that permits substitution, and that the harness's non-interactive workers reject without substitution when it is unavailable. Any other nonzero status rejects. |
| `harness_model_choices` | Return the adapter-owned guided model choices. |
| `harness_max_reasoning_effort` | Return the strongest supported reasoning-effort value for the supplied model. |
| `harness_reasoning_effort_choices` | Return the ordered guided effort choices. |
| `harness_validate_reasoning_effort` | Accept only an explicitly supported effort token. |
| `harness_default_context_tier` | Return the recommended context tier. |
| `harness_context_choices` | Return the ordered guided context choices. |
| `harness_validate_context_tier` | Accept only an explicitly supported context tier. |
| `harness_auth_secret_env_vars` | Return the exact inherited secret-variable allowlist protected from disclosure. |
| `harness_login_remediation` | Return harness-specific, non-automatic sign-in remediation. |
| `harness_provider_summary` | Return a JSON object with exactly `Id`, `Host`, and `ForwardedEnvVarNames`. |
| `harness_resume_policy` | Return the safe adapter-specific continuation policy stored under the generic session `ResumePolicy`. |
| `harness_prepare_run` | Prepare run-wide adapter context exactly once, including any ephemeral authentication bridge metadata. |
| `harness_prepare_worker_home` | Create and secure an isolated runtime home containing only adapter-approved settings and ephemeral authentication bridge data. |
| `harness_snapshot_transport` | Return exactly `native` or the fixed `local-stdio-mcp-snapshot-read-v1` mode; the runner validates it before approval. |
| `harness_configure_snapshot_transport` | Translate the runner's phase, approved argv array, isolated home, new config path, fixed launcher, broker argument array, and exact tools into phase-specific MCP configuration. Native adapters reject it; repair never receives it. |
| `harness_worker_argv` | Build the ordered worker argument vector. |
| `harness_worker_env` | Build the ordered worker environment/unset vector. |
| `harness_report_repair_argv` | Build the ordered argv for one fresh, tool-less report-repair session in an empty trusted working directory. |
| `harness_report_repair_env` | Build normal worker environment clears plus a fresh harness-specific runtime home, without serializing authentication values. |
| `harness_write_research_mcp_config` | Write the ephemeral mode-0600 MCP configuration that starts the runner-supplied local broker launcher with the runner-supplied arguments and tool list, in the adapter's own MCP schema. |
| `harness_research_worker_argv` | Build the ordered research-worker argv: the bundled research worker, the approved model/effort/context, snapshot read/search tools, and exactly the runner-supplied broker tools from the written MCP configuration. |
| `harness_research_worker_env` | Build the ordered research-worker environment for the runtime home prepared with phase `research`. |
| `harness_finalize_research_session` | After the research child exits and before its runtime home is removed, export the research transcript and fail when the session record shows substitution or isolation loss; a no-op must still return success explicitly. |
| `harness_normalize_worker_output` | For phase `review`, `research`, or `report-repair`, translate the raw worker stdout into a new mode-0600 readable narrative file and a new mode-0600 exact final-reply file, verifying that every recorded model call used the approved model and reasoning effort. Copilot parses its `--output-format json` event stream and fails closed on a substituted model or effort and on any recorded subagent event, because no Rhyolite worker receives a subagent tool; Claude Code's print mode already writes the exact reply, so it copies the raw output to both files. Never reconstruct the reply from a rendered transcript or terminal-rendered text. |
| `harness_detect_worker_violation` | For phase `review`, `research`, or `report-repair`, while the worker is still running: scan only the complete lines appended to the recorded output since the offset saved in the runner-owned cursor file, return 0 when nothing outside the approved plan is recorded yet, return `RHYOLITE_HARNESS_WORKER_VIOLATION_STATUS` (4) with a sanitized detail on the first recorded model, reasoning effort, or subagent other than the approved plan, return `RHYOLITE_HARNESS_WORKER_REFUSAL_STATUS` (5) with a sanitized detail when the provider declined a request to the approved model (a recorded refusal outranks the fallback model it caused, but not a subagent), and return 1 for any other failure, which the runner records once as a warning while the post-exit normalization stays authoritative. Copilot scans its JSONL stdout; Claude Code scans its private session record under the isolated runtime home and reports nothing until that record exists. The runner polls every five seconds and terminates the worker's process tree on the first violation or refusal. |
| `harness_worker_outcome` | After every worker invocation, write one schema-2 JSON outcome with exactly the documented keys: the outcome class (`completed`, `transient-failure`, `fallback-blocked`, `refused`, `substituted`, `failed`, or `unknown`), whether it is retryable, the CLI exit code when recorded, up to five sanitized session errors, model-call failure and retry counts, how many responses reached the per-response output token limit, the fallback model of a blocked automatic fallback or of a refusal, the number of approved-model calls the provider declined, the approved session's prompt budget, and its largest recorded prompt. The runner validates it before use; an adapter whose CLI records no structured evidence may call `rhyolite_harness_worker_outcome_unknown`. |
| `harness_worker_continuation_argv` | Return the argv that resumes the same worker session with the exact approved model, effort, context, tools, and isolation, or fail when the adapter has not verified `worker_continuation`. |
| `harness_render_request` | Render the worker request without evaluating repository content. |
| `harness_extract_final_report` | Extract the canonical report and apply the adapter's safe transcript fallback. |
| `harness_extract_report_repair` | Extract only the latest compact confidence-edit reply from sanitized repair output or the latest assistant transcript response. |
| `harness_verify_isolation` | Perform any adapter-specific post-run isolation verification; a no-op must still return success explicitly. |
| `harness_persist_agent_state` | Persist only the adapter's allowlisted, sanitized continuation state, including what the adapter's post-exit verification reads; the runner calls it again after every continuation. |
| `harness_sanitize_runtime_home` | Remove or sanitize the temporary runtime home and fail if cleanup cannot be completed. |
| `harness_allow_all_detected` | Retain compatibility detection of the outer harness's allow-all state without propagating it to the worker. The runner must not use this signal to open reports. |

The runner treats function output as data. It does not evaluate adapter output,
accept success-shaped fallbacks, or continue after malformed values.
`harness_prepare_worker_home` receives the new runtime-home path plus the
approved reasoning effort and context tier. Its optional fourth phase is
`research` or `report-repair`; an omitted phase preserves normal review-worker
behavior. For every review, security-scan, and research worker the runner
builds the worker argv first, then creates the runtime home and calls
`harness_prepare_worker_home`, then builds the environment; worker argv
functions therefore never depend on a runtime home. Report repair prepares
its fresh home before its argv. The runner calls the five research functions
only for scope 2/3, and only when the adapter reports `web_research=yes`;
otherwise scope 2/3 fails at stage `harness <id> harness_capability` before
any broker or worker activity.
Multi-model security scans add no adapter function or phase. Each scan is a
fresh normal review-worker invocation, phase `review`, that the runner builds
with `harness_worker_argv`, `harness_prepare_worker_home`,
`harness_worker_env`, `harness_detect_worker_violation`,
`harness_worker_outcome`, `harness_normalize_worker_output`,
`harness_verify_isolation`, `harness_persist_agent_state`, and
`harness_sanitize_runtime_home`, on that scan's approved model and effort in
its own runtime home, and with `harness_render_request` for the scan
request. The ledger request after consolidation is an ordinary counted
review-worker continuation.
Array-producing functions receive the destination array name first.

## Capabilities

Capabilities describe what the selected adapter can support; they do not relax
runner safety policy.

- `yes`: implemented and supported by the adapter.
- `no`: explicitly unsupported.
- `unverified`: the adapter cannot establish support safely at selection time.

No other spelling, empty output, multiple values, or successful exit with an
invalid value is accepted. A future adapter must not report `yes` merely
because its CLI has a similarly named option.

Contract v5 retains these capability keys:

| Capability | Copilot | Claude Code |
| --- | --- | --- |
| `structured_questions` | `yes` | `yes` |
| `subagents` | `no` | `no` |
| `builtin_security_specialist` | `no` | `no` |
| `builtin_research_specialist` | `yes` | `yes` |
| `web_research` | `yes` | `yes` |
| `shell_denial` | `yes` | `yes` |
| `final_message_file` | `no` | `no` |
| `worker_continuation` | `yes` | `yes` |

Copilot reports `subagents` and `builtin_security_specialist` as `no` since
Contract v7. A live probe showed that a `task` call's `model` argument
overrides every configured `subagents.agents.<name>.model` value
(`taskModelSource: "task_argument"`, `modelSelectionSource:
"explicit_override"`), so no specialist can be bound to the approved model by
configuration. The review worker therefore receives no `task`,
`list_agents`, or `read_agent` tool, performs the dedicated security pass
itself, and any recorded subagent event fails the phase.

[CLAUDE-HARNESS-EVIDENCE.md](CLAUDE-HARNESS-EVIDENCE.md) records the probe and
real-run evidence behind each Claude Code value.

An unknown capability returns `unverified`; it is never silently promoted to
`yes`.

## Copilot adapter baseline

Copilot was the only mapped I1a adapter and remains the default harness.

- Canonical ID: `copilot`
- Display name: `Copilot`
- CLI: `copilot`
- Default model: `gpt-5.6-sol`
- Guided alternate models: `claude-opus-5.5`, then `claude-fable-5.1`
- Model catalog: parsed from local `copilot help config`, a static list built
  into the CLI rather than the account's live catalog; safe syntax alone is
  not availability
- Unlisted models: a safe ID outside that catalog returns status 3 and is
  accepted only with explicit `--allow-unlisted-model`, disclosed as
  approval-bound `ModelCatalogMembership` `unlisted`; `auto` is always
  rejected. Non-interactive review, research, and repair children fail
  closed when Copilot reports `Model "<id>" from --model flag is not
  available.`, `Reasoning effort "<effort>" is not supported for model
  "<id>".`, or `Model "<id>" does not support reasoning effort
  configuration`, and the runner reports a `model availability` stage; an
  effort rejection is classified `effort-unsupported` with the next highest
  effort, never below `high`, that only a newly approved plan may use. A
  child that starts but whose structured output records another model or
  `reasoning_effort` is rejected at the `approved model enforcement` stage. The
  launcher's interactive orchestrator session would instead fall back to
  Copilot's default model (re-verified with Copilot CLI 1.0.100), so the
  launcher first checks the selected model and effort with one isolated
  non-interactive request and asks for another model, the next highest
  effort, or quit when Copilot rejects them.
- Reasoning effort: `max` recommended; `xhigh` and `high` selectable
- Context tier: `long_context` recommended; `default` selectable
- Provider summary ID: `github-copilot`
- Provider host summary: `managed-provider`
- Forwarded provider environment names: exactly the protected
  authentication-variable contract below
- Resume policy: continue only through the trusted Rhyolite runner; do not
  invoke `copilot --resume` directly
- Login remediation: run `copilot login` from a clean non-Git directory and
  retry; Rhyolite never starts login automatically.
- Provider boundary: the current environment, system credential store, GitHub
  CLI fallback, configured provider, or the narrow ephemeral Copilot auth
  bridge may authenticate the isolated worker.

The protected Copilot authentication-variable contract remains:

```text
COPILOT_GITHUB_TOKEN
GH_TOKEN
GITHUB_TOKEN
COPILOT_PROVIDER_API_KEY
COPILOT_PROVIDER_BEARER_TOKEN
ANTHROPIC_API_KEY
AZURE_OPENAI_API_KEY
OPENAI_API_KEY
CAPI_HMAC_KEY
COPILOT_HMAC_KEY
GITHUB_COPILOT_API_TOKEN
```

The adapter keeps the existing worker restrictions, including the read-only
worker agent, approved reasoning/context settings, disabled custom
instructions and built-in MCPs, denied write and shell tools, disabled
temporary-directory access and remote export, and no direct public URL access.
When public research is enabled, only the dedicated research worker reaches
the network, and only through the constrained local stdio broker; the main
review worker receives a validated sanitized dossier and network summary.
The broker's fifth tool accepts an optional complete dossier candidate,
permits at most three corrections in that broker session, and records only an
acceptance digest and byte count. The adapter preserves raw print-mode stdout;
the runner verifies the proof against that raw final reply before privacy
sanitization, deletes the raw copy, and promotes only the sanitized dossier.

The child environment removes inherited Copilot allow-all state and inherited
skill/custom-instruction discovery variables. The isolated runtime home keeps
hooks disabled and local-only agent discovery enabled. Persisted agent state is
limited to sanitized configuration plus files under `session-state` and
`session-store`; unrelated runtime-home content and authentication bridge data
are not retained.

The bounded repair child uses a separate empty trusted working directory,
fresh session ID, fresh runtime home, and the approved model/effort/context.
Its argv excludes every supported tool-inventory category with
`--excluded-tools builtin:* mcp:* custom:*`, explicitly denies read, write,
shell, and URL permissions, and grants no tool permission. It does not pass
`--available-tools`: Copilot CLI 1.0.91 normalizes its zero-value form to an
unspecified allowlist, so it is not an empty-inventory control. It selects no
plugin or agent, disables built-in MCPs, custom instructions, dynamic skill
retrieval, Bash environment import, remote export/control, automatic updates,
and experimental behavior, forces interactive mode, and omits attachments,
additional directories, fleet, autopilot, resume, and continue flags. No
allow-all, allow-tool, or availability flag is valid in this vector.

Before the adapter prepares the repair home or invokes the CLI, the runner
canonicalizes both repair directories, proves each is outside every Git
repository, rejects controls, and verifies both are physically disjoint from
`RUN_WORKSPACE` and `RUN_RESULTS`. The adapter then independently requires an
existing nonsymlink empty workdir and existing nonsymlink runtime home.

The runner permits at most one repair attempt. Its effective timeout is
`min(300, SessionTimeoutMinutes * 60)` seconds: ordinary scope defaults retain
the 300-second maximum, while an approved one-minute session caps repair at 60
seconds. The compact `ReportRepairPolicy` records the returned bound with key
order `Mode`, `ProtocolVersion`, `AttemptLimit`, `TimeoutSeconds`,
`DeterministicNormalizations`; that exact object is approval-hash material.
Timer creation and enforcement remain runner-owned and adapters receive no
timeout argument. The `markdown-table-rows`,
`confidence-level-delimiters`, and `wrapped-field-labels` normalizations are
also runner-owned: they convert eligible Markdown tables, insert the accepted
` - ` delimiter after a single assessment confidence level, and rejoin a
wrapped required assessment field label without invoking any harness function
or model.

The repair environment uses the same clearing vector as the normal review
worker: unset inherited Copilot allow-all and skill/custom-instruction
discovery variables, then bind only `COPILOT_HOME` to the fresh runtime home.
It does not use `env -i`, rebind `HOME` or XDG/cache paths, replace `PATH`, or
serialize authentication values into the environment-data array. The runner
applies this data with `env` before starting `timeout`, so inherited
authentication/provider/offline settings remain process environment rather
than appearing in the long-lived timeout argv. Preserving the parent
home/cache and loader path keeps GitHub CLI fallback, BYOK/offline behavior,
and the already resolved Copilot CLI installation unchanged. Repair settings
retain the narrow authentication bridge while setting hooks disabled,
`memory` to `false`, and `ide.autoConnect` to `false`. Repair session state is
never persisted and the analysis runtime home is never copied into the repair
home.

`harness_prepare_run` reads the source Copilot `config.json` at most once per
run. Only a valid JSON object contributes allowlisted bridge keys. JSON `null`,
arrays, strings, malformed JSON, invalid UTF-8, unreadable files, and
parsing/type errors fail soft to an empty bridge with plaintext-token mode
disabled; they do not abort the review or copy unrelated configuration.

Copilot's final-report path first examines sanitized standard output, then the
sanitized final Copilot transcript response when the standard output is
missing or incomplete. The runner still owns the canonical delimiter,
completeness, and artifact validation rules.

Repair extraction is deliberately narrower. The adapter prefers a single pure
JSON object from sanitized stdout. If stdout is not a pure descriptor, it
extracts only the latest assistant reply from the fresh sanitized transcript;
user, tool, information, system, transcript framing, prose, and fenced output
are not accepted as the response. Copilot CLI 1.0.91 assistant blocks begin at
`### Copilot`; strict repair framing recognizes exact `### User`,
`### Info`, `### System`, and `### Copilot`; backticked tool headings with an
optional status suffix such as `### \`view\`` and
`### \`view\` — Failed`; and named status headings such as
`### task (Completed)`. The optional trailing separator and real footer
`<sub>Generated by [GitHub Copilot CLI](https://github.com/features/copilot/cli)</sub>`
are removed before descriptor selection. The adapter writes that raw reply
only. The runner-owned output helper validates and applies the exact protocol
object:

```json
{"ProtocolVersion":1,"Section":"OVERALL ASSESSMENT","Field":"Confidence:","Occurrence":1,"OriginalValueSha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","ConservativeLevel":"Low"}
```

The key set is exactly `ProtocolVersion`, `Section`, `Field`, `Occurrence`,
`OriginalValueSha256`, and `ConservativeLevel`; `Field` is exactly
`Confidence:`. The adapter does not construct a report or interpret an edit.
These boundaries apply only to descriptor repair extraction. Main
`harness_extract_final_report` behavior remains the last `### Copilot` block
through end of transcript, so internal assistant-report headings such as
`### Alert 1` are preserved.

## Claude Code adapter baseline

- Canonical ID: `claude`
- Display name: `Claude Code`
- CLI: `claude` (validated with Claude Code 2.1.292)
- Default model: `claude-opus-5-5`
- Guided alternate model: `claude-opus-5`
- Model catalog: Claude Code exposes no local catalog surface, so the adapter
  owns an offline list: `claude-opus-5-5`, `claude-fable-5-1`,
  `claude-sonnet-5-5`, `claude-fable-5`, `claude-opus-5`, and
  `claude-sonnet-5`. It can omit models that an account can use.
- Aliases such as `opus`, `sonnet`, `fable`, `default`, and `opusplan` are
  rejected. A safe `claude-` ID outside the list returns status 3 and is
  accepted only with explicit `--allow-unlisted-model`. An unavailable model
  fails with Claude Code's `[claude-code:unrecognized_model]` marker on
  stderr, and the runner reports a `model availability` stage.
- Reasoning effort: `max` recommended; `xhigh` and `high` selectable; the
  worker passes `--effort` and inline `effortLevel` settings.
- Context tier: `long_context` is the only guided choice; `default` stays
  valid. Every catalog model has a 1M-token context window.
- Provider summary ID: `anthropic-claude-code`; host summary
  `managed-provider`, because inherited Claude Code provider settings choose
  the endpoint.
- Protected authentication variables: `ANTHROPIC_API_KEY`,
  `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`,
  `ANTHROPIC_CUSTOM_HEADERS`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
  `AWS_SESSION_TOKEN`, `AWS_BEARER_TOKEN_BEDROCK`,
  `GOOGLE_APPLICATION_CREDENTIALS`, and `ANTHROPIC_FOUNDRY_API_KEY`.
- Resume policy: continue only through the trusted Rhyolite runner; do not
  invoke `claude --resume` directly.
- Login remediation: run `claude auth login` from a clean non-Git directory,
  or export `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`) or
  `ANTHROPIC_API_KEY`, then retry.
- Authentication bridge: inherited environment or cloud-provider
  authentication takes precedence. Otherwise `harness_prepare_run` locates
  `${CLAUDE_CONFIG_DIR:-~/.claude}/.credentials.json` (a regular,
  non-symlink file), and each runtime home receives a mode-0600 copy that
  cleanup deletes first.

Each worker runtime home is a mode-0700 `CLAUDE_CONFIG_DIR` that contains only
`settings.json` and, when the bridge applies, `.credentials.json`. The review
worker argv is:

```text
-p --model <model> --effort <effort> --session-id <uuid> --name <name>
--output-format text --permission-mode dontAsk --permission-prompts none
--restricted --settings <inline-json> --strict-mcp-config
--tools Read,Glob,Grep
--disallowedTools Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch,Agent,Skill,AskUserQuestion,TodoWrite,ToolSearch
--disable-slash-commands --plugin-dir <plugin-root>
--agent rhyolite:repo-review-worker
--append-system-prompt-file <plugin-root>/skills/readonly-repository-review/SKILL.md
```

Settings are passed inline because the runner builds argv before it creates
the runtime home and `--restricted` ignores the runtime home's own settings
file. They set `disableAllHooks`, disable auto memory and co-author lines,
exclude `**/CLAUDE.md`, `**/CLAUDE.local.md`, `**/AGENTS.md`, and
`**/.claude/**`, set `effortLevel`, and deny the same tools. The environment
vector starts with `-C <session-root>`, unsets
`CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD`, `ANTHROPIC_MODEL`,
`CLAUDE_CODE_EFFORT_LEVEL`, `MAX_THINKING_TOKENS`,
`CLAUDE_CODE_RESUME_INTERRUPTED_TURN`, and `CLAUDE_CODE_SIMPLE`, and sets
`CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1`,
`DISABLE_AUTOUPDATER=1`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`,
`CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`, `NO_COLOR=1`, and
`CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000`, which Claude Code caps at the model's
own maximum. It does not use `env -i`.

The research worker replaces the worker agent with
`rhyolite:repo-research-worker`, appends the `research-source-assessment`
skill, passes `--mcp-config <path> --strict-mcp-config`, and adds
`--allowedTools` for exactly the five `mcp__rhyolite-research__*` broker
tools. Its MCP configuration has `type: stdio` with only the broker command
and arguments, and its environment adds `MCP_TOOL_TIMEOUT=120000`.

The report-repair child runs in an empty trusted working directory with
`--restricted --output-format json --tools '' --no-session-persistence`,
denies `Read`,
`Glob`, `Grep`, and every review-denied tool, and selects no plugin or agent.
Its descriptor comes from the JSON envelope only when `modelUsage` lists only
the approved model; otherwise the adapter falls back to the latest assistant
reply in the rendered transcript.

Claude Code writes its session record to
`CLAUDE_CONFIG_DIR/projects/<cwd-slug>/<session-id>.jsonl`. The adapter
renders it as `session.md` with `### User`, `### Claude`,
`### Tool call: <name>`, `### Tool result`, and `### Claude Code notice`
frames. It persists only `settings.json` and a filtered, redacted copy of the
record that keeps user, assistant, system, title, and agent-name records and
drops attachments such as the account email. `harness_verify_isolation` fails
the review if any main-thread assistant turn used another model (including
`model_refusal_fallback` safeguard handovers and advisor models) or another
effort, if a subagent turn appears, if the record is unreadable, or if a
report arrives without a record. Rhyolite never passes `--fallback-model`.

Final-report extraction reads `-p` standard output first, then the last
`### Claude` block of the rendered transcript. When Claude Code stops a reply
at its output token limit and sends its `Output token limit hit.` resume
prompt, the renderer joins the resumed text into the same block. It inserts
no separator when either side already has whitespace, a line break when the
resumed text opens a heading, delimiter, field, list item, or table row, and
otherwise a space, and it adds a notice that names every inserted separator.
Strict report validation still runs on the joined report.

The outer launcher starts Claude Code from a clean non-Git directory with
`--plugin-dir`, `--agent rhyolite:repo-review`, the approved `--model` and
`--effort`, `--strict-mcp-config`, a permission rule that pre-approves only
`bash <runner> ...`, `--permission-mode default`, and the trusted
`RHYOLITE_LAUNCHER_SETUP_V1` block in `--append-system-prompt`. `--yolo` adds
`--dangerously-skip-permissions`.

## Lifecycle

1. **Resolve** the harness from CLI, environment, or default.
2. **Validate context** against `RHYOLITE_LAUNCHER_HARNESS` when the marker is
   set.
3. **Load and validate** the fixed-map adapter and its complete function set.
4. **Resolve and validate planning metadata** such as CLI identity, model,
   effort, capabilities, resume policy, and strict provider metadata.
5. **Validate runner inputs and paths**, and require the selected harness CLI
   only for an actual execution.
6. **Plan and approve** the review using plan schema `5`; harness identity,
   resolved reasoning effort, provider metadata, and the plan schema version
   are approval-hash material.
7. **Resolve execution metadata and call `harness_prepare_run` once**,
   including the protected secret-variable allowlist and any adapter-owned
   authentication bridge metadata.
8. **Perform the runner-owned anonymous preflight, clone, exact-commit
   resolution, and read-only snapshot construction.**
9. **Render** the trusted request, build the ordered worker argv, prepare a
   unique user-only runtime home, and build the ordered worker environment.
10. **Invoke** the selected harness CLI under the existing timeout and
    repository-isolation boundary.
11. **Persist** only allowlisted sanitized agent state.
12. **Sanitize and remove** the temporary runtime home.
13. **Sanitize worker output, verify adapter-specific isolation, and extract
    and validate** the canonical report.
14. **If strict report validation identifies one eligible confidence-grammar
    correction, run at most one isolated repair session.** The runner creates
    a fresh empty workdir/home/session, sends the bounded prompt on stdin,
    validates the descriptor, applies the one deterministic edit, revalidates
    the whole report, and cleans the repair runtime before promotion.
15. **Finalize** the existing report, state, handoff, and index artifacts.

If rendering, argv construction, runtime-home preparation, or environment
construction fails before the worker command is launched, final state and
handoff artifacts clear the session ID/name and state that setup did not reach
a child session. Once the child command has launched, worker, timeout,
isolation, persistence, and cleanup failures retain the real session identity.

## Trust boundaries

### Resolver and loader

Trusted Rhyolite code owns precedence, safe-ID validation, the fixed map,
launcher-marker validation, required-function validation, guarded invocation,
and sanitized harness-stage failures. Environment variables and CLI values are
untrusted selection inputs.

### Harness adapter

The selected adapter is trusted packaged code, but its CLI output, runtime
files, provider responses, and authentication failures are untrusted data.
The adapter may translate between the generic runner and one known CLI; it may
not change repository-source policy, grant worker write/shell access, weaken
path isolation, or bypass plan approval.

### Runner

The runner remains the authority for public-source validation, credential-free
Git access, DNS pinning, exact-commit snapshots, concurrency/time limits,
read-only worker policy, report validation, redaction, and artifact schemas.
It also validates adapter outputs before using them and records the exact
adapter lifecycle stage for execution failures. An adapter cannot redefine
these controls.

### Launcher

The launcher selects and marks the outer harness before starting the outer
session. The marker authenticates consistency of Rhyolite's own handoff; it is
not a credential and does not authorize a repository or provider.

### Direct invocation

The marker-unset exception exists only for compatibility with direct runner
invocation. It does not skip safe-ID validation, fixed-map lookup, complete
contract validation, CLI checks, or any repository-review safety control.

## Historical I1a baseline

The original I1a seam did not:

- add `Harness`, `Provider`, or `ReasoningEffort` to plan JSON, approval-hash
  material, launcher preferences, repository state, run state, manifests, or
  handoffs;
- change plan schema version `2` or state schema version `3`;
- change the approved plan hash for default Copilot versus explicit
  `--harness copilot`;
- move plugin assets;
- add Codex or Claude adapters;
- add dynamic adapter discovery;
- add automatic harness fallback;
- change the Copilot worker or outer-launcher argv;
- broaden worker tools, inherited environment, network access, or persisted
  runtime state.

Contract v2 introduced harness/provider approval identity. Contract v3 extends
that data contract:

- plan schema is `5` and state schema is `6`;
- plan JSON/text, review-plan artifacts, repository/run state, manifests, and
  handoffs record `Harness`, `Model`, selected `ReasoningEffort`,
  `ContextTier`, and strict `Provider` metadata where identity matters;
- the generic session `ResumePolicy` is adapter-owned, with Copilot retaining
  its trusted-runner-only continuation behavior;
- approval hashes include the plan schema and all harness identity metadata,
  so hashes from earlier plans cannot authorize contract-v3 plans;
- launcher preferences use schema `3` with harness/model/effort/context;
  schemas `1` and `2` remain readable with `max` and `long_context` defaults,
  and preferences are reused only for a matching harness and available model;
- preference and launcher-state paths reject wrong ownership, symlink
  components, and group/world-writable components.

Contract v4 retained plan schema `5`, state schema `6`, provider identity,
preference schema, and the then Copilot-only fixed registry. It added only the
three required repair lifecycle functions, the optional `report-repair` home
phase, and their fail-closed extraction/isolation contract. A backward-compatible
amendment adds the optional unlisted-model status for
`harness_validate_model_id` and the additive approval-bound plan field
`ModelCatalogMembership` (`listed` or `unlisted`); adapters that never
return that status keep exact-catalog behavior.

Contract v5 keeps plan schema `5`, state schema `6`, and preference schema
`3`. It adds the research functions, the optional `research` home phase, and
capability-based scope 2/3 gating. The fixed registry maps `copilot` and
`claude`.

Contract v6 keeps the same schemas and registry. It retires the raw-stdout
`harness_extract_research_reply` seam and adds
`harness_normalize_worker_output`, which the runner calls after every review,
research, and report-repair child exits. Copilot's review, research, and
repair argv vectors gain `--output-format json`; the adapter parses the JSONL
stream for the exact final `assistant.message` content and rejects any
`model` or `reasoning_effort` that differs from the approved plan, including
subagent metrics. The runner extracts the canonical report, the research
dossier, and the repair descriptor from that exact reply first and keeps the
readable timeline and rendered transcript as fallbacks. The research broker
persists the accepted canonical dossier bytes in its transient runtime root so
the canonical dossier never depends on the worker reproducing the candidate.

Contract v7 keeps the same schemas and registry and adds
`harness_detect_worker_violation <phase> <raw_output> <approved_model>
<approved_effort> <cursor_path>`. The runner's shared monitored wait calls it
every five seconds while a review, research, or report-repair child runs; the
adapter scans only the complete lines appended since the offset in the
runner-owned cursor file and returns `RHYOLITE_HARNESS_WORKER_VIOLATION_STATUS`
(4) on the first recorded model, effort, or subagent outside the approved
plan. The runner then terminates the child's process tree, records the
`harness_detect_worker_violation` failure stage with the detail and the
elapsed time, and still runs the post-exit normalization, which rejects the
same evidence. Both outcomes surface as the `approved model enforcement`
failure stage, as do the Claude Code session-record rejections from
`harness_verify_isolation` and `harness_finalize_research_session`. Contract
v7 also removes every subagent tool from the Copilot review worker, because
the live failure that motivated it was a `security-review` subagent started
from a `task` call whose explicit `model` argument overrode the adapter's
`inherit` subagent settings while the main session itself used the approved
model.

Contract v8 keeps the same schemas and registry and adds two functions and
one capability. `harness_worker_outcome <phase> <raw_output> <runtime_home>
<session_id> <approved_model> <approved_effort> <outcome_output>` writes one
JSON object with exactly the keys `Schema`, `Phase`, `Outcome`, `Retryable`,
`ExitCode`, `SessionErrors`, `ModelCallFailures`, `TurnRetries`,
`OutputLimitHits`, `OutputTokenLimit`, `FinalReplyAtOutputLimit`, and
`FallbackModel`. `Outcome` is `completed`, `transient-failure`,
`fallback-blocked`, `substituted`, `failed`, or `unknown`, and `Retryable` is
true only for the first two retryable outcomes. The runner validates the
object with `rhyolite_harness_validate_outcome_json` before it uses any value,
appends the sanitized session errors to `errors.txt` for a failed invocation,
and treats a malformed or missing outcome as `unknown`, which never continues
a session. `harness_worker_continuation_argv <destination> <source_argv_name>`
returns the argv that resumes the same session; Copilot CLI resumes a
non-interactive JSON session when it is invoked again with the same
`--session-id` and runtime home (verified live with Copilot CLI 1.0.98-2), so
the Copilot adapter returns the exact approved worker argv without its
`--name` pair. `--name` only labels a brand-new session, and Copilot CLI
1.0.98-2 rejects it when `--session-id` resolves to an existing session; any
other session-name spelling in the source argv fails closed. Claude Code
resumes a print-mode session with `--resume <id>` under the same runtime home
(verified live with Claude Code 2.1.303: the resumed worker kept its context,
appended to the same session record, and recorded only the approved model and
effort), and the original `--session-id` argv fails once the session exists,
so the Claude Code adapter replaces the `--session-id` pair with `--resume`
and drops the `--name` pair. Because Claude Code verifies the model and
effort from its rendered session record rather than from stdout, the runner
persists the adapter's agent state after every worker invocation that keeps
the runtime home and calls `harness_verify_isolation` after every
continuation, and a continuation re-selects the review runtime home even
after a report-repair child prepared its own.

The live failures that motivated Contract v8 were reports cut at Copilot's
32,000-token per-response output limit, where reasoning tokens count toward
the limit and Copilot CLI re-requests a cut response without emitting the cut
text; a final response that the service cut repeatedly; a DNS outage; and an
automatic refusal fallback to an older model that live enforcement blocked
before it produced output. See
[RUN-FAILURE-INCIDENT-2026-10-13.md](RUN-FAILURE-INCIDENT-2026-10-13.md).
Copilot's scanner now distinguishes a model that only appears in
`model.call_start`, `model.call_failure`, or `agent.interrupted` events (an
attempted fallback, reported accurately as such) from a model that produced
messages or tool calls (substituted output); both still fail the invocation
closed.

Contract v9 keeps the same functions, schemas, and registry. It adds
`RHYOLITE_HARNESS_WORKER_REFUSAL_STATUS` (5), the `refused` outcome, and
worker-outcome schema 2, which adds the keys `ContentRefusals`,
`PromptBudget`, and `PeakPromptTokens`. `refused` requires at least one
declined call and is never retryable; `FallbackModel` may be set only for
`fallback-blocked`, which requires it, or `refused`; the two token counts are
positive integers or null. Copilot recognizes a refusal from an
approved-model usage event whose `finishReason` is `content_filter` (Copilot
reports an Anthropic `refusal` stop that way) or whose
`contentFilterTriggered` is true, from a `refusal_fallback` model change, and
from the CLI's refusal notice naming the approved model; its usage events
also carry `maxPromptTokens` and `inputTokens`. Claude Code recognizes an
approved-model `refusal` stop and the `model_refusal_fallback` safeguard
handover, and reports no prompt budget. Each harness's automatic refusal
fallback is the only recorded way a worker leaves the approved model after a
refusal, so a recorded refusal explains that model in any event order, while
a subagent or an approved-model effort change still fails as enforcement.
A refusal that the session recovered from on the approved model stays
`completed`.

The live failure that motivated Contract v9 was a security scan on
`claude-opus-5.5` with a 968,000-token long-context prompt budget and a
185,172-token largest prompt. The provider declined one response; Copilot
CLI's automatic refusal fallback then rejected its own request against the
fallback model's 128,000-token budget before any fallback call, so no other
model was recorded, the scan was classified as an ordinary failure, and the
review failed below its required scans. See
[RUN-FAILURE-INCIDENT-2026-10-25.md](RUN-FAILURE-INCIDENT-2026-10-25.md).

Contract v10 keeps the same functions, statuses, and registry. It adds
worker-outcome schema 3, which adds the key `Compactions`, a non-negative
count. Copilot counts each `session.compaction_complete` event with
`success: true` and outcome `applied` once by its `compactionAttemptId`,
whether the event stream, the persisted session events, or both recorded it.
Claude Code counts each `compact_boundary` system record of the session
record once by its UUID. A continuation reports the session's cumulative
count.

The live failure that motivated Contract v10 was a security scan on
`gemini-4-argon` with a 983,040-token long-context prompt budget. Copilot CLI
compacted the session at 82% of that budget and replaced the scan request,
the only definition of the scan report contract, with a summary; the scan
then returned a report in a layout of its own, and the review failed below
its required scans. Both worker agents now repeat the scan report contract in
their own instructions, which compaction keeps, and the runner asks the same
scan session once for a conforming report. See
[RUN-FAILURE-INCIDENT-2026-10-26.md](RUN-FAILURE-INCIDENT-2026-10-26.md).

Contract v11 keeps the same statuses, outcome schema 3, plan schema 5, state
schema 6, and registry. It adds the required functions
`harness_snapshot_transport` and `harness_configure_snapshot_transport`. The
Copilot and Claude Code adapters report `native`, keep their existing worker
tools and argv, and reject offline configuration. An adapter that reports
`local-stdio-mcp-snapshot-read-v1` reads the snapshot only through the
bundled broker's offline snapshot mode, under runner-created grants that
[SNAPSHOT-TRANSPORT.md](SNAPSHOT-TRANSPORT.md) defines. Only such plans carry
the approval-bound `SnapshotTransport` object; native plans and states keep
their existing bytes. The work that motivated Contract v11 is the
unregistered Codex adapter candidate, whose shell-free configuration has no
other snapshot reader; that candidate does not change the supported
harnesses.

## Adding a future adapter

A future adapter is a separate implementation phase. It must be added without
weakening the fail-closed boundary:

1. Assign a safe canonical ID.
2. Add the adapter file without a production registry entry.
3. Implement every Contract-v11 function; do not inherit missing behavior from
   Copilot or Claude Code.
4. Return only tri-state capability values and document any `unverified`
   result.
5. Define model-catalog discovery, exact model validation, model/effort/context
   choices and validators, protected secret variables, provider summary, and
   login remediation.
6. Build deterministic argv/env arrays with no Rhyolite-only selection
   arguments downstream.
7. Use a unique isolated runtime home and persist only an explicit state
   allowlist.
8. Prove that allow-all compatibility detection does not drive runner policy
   and that inherited allow-all state is removed from the child.
9. Implement safe request rendering, report extraction/fallback, bounded
   confidence-edit extraction, cleanup, and isolation verification.
10. Add golden contract tests, default/explicit vector comparisons,
    context-mismatch tests, failure-stage tests, and schema/hash
    non-regression coverage before adding the map entry.
11. Only after the complete eligibility evidence and validation pass, add
    one explicit ID-to-file entry to the fixed production registry.

An adapter that cannot satisfy any required function remains unavailable. The
correct failure mode is a sanitized nonzero error, not Copilot fallback or a
partially initialized run.

## Validation

The focused Contract-v11 validator is:

```bash
bash ./tests/validate-harness-contract.sh
```

It exercises the common loader and Copilot adapter directly, then runs the real
runner with hermetic Git, Python, and Copilot fixtures. It also copies the
plugin into an isolated temporary tree, replaces only that copy's explicit
fixed-registry helper with a `copilot`/`noop` map, and runs the development
fixtures from `tests/fixtures/harnesses/` end to end. The no-op proof covers
distinct approval hashes, cross-harness approval rejection in both directions,
empty authentication, adapter-owned argv/environment/runtime-home/persistence/
cleanup/extraction, diagnostic non-review output, state/manifest/handoff
identity, capability-based research rejection, and injected lifecycle failure
stages. Production `common.sh` registers only `copilot` and `claude`; the
no-op fixture never enters production manifests, help, or plugin assets.

The Claude Code section, `tests/harness-contract-claude.sh`, runs inside the
same validator. It pins the Claude worker, research, and repair argv,
environment, and settings vectors, and covers session rendering, persistence,
isolation verification, and output-limit joins. It also drives the real
runner through a mock `claude` for completed, recovered, substituted,
unavailable, unsafe, repaired, and research runs, and checks the launcher
and hooks.

The Copilot runner-level checks compare captured worker argv and relevant
environment exactly against the golden contract, compare default and explicit
selection, cover public research, preserve plan/hash/schema invariants,
validate strict provider and resume metadata, exercise schema-1/schema-2
preferences and unsafe state-path rejection, inject adapter lifecycle
failures, exercise production cleanup through a scoped failing `rm`, and prove
the launcher rejects equals-form and inconsistent inherited harness context
before state or CLI activity.

A started-worker sanitization fixture injects raw authorization, URL userinfo,
email, CR, BS, VT, FF, SO, DEL, and ANSI bytes into worker stdout, stderr,
transcript output, and trusted Git metadata. It verifies the bytes and secrets
never reach terminal output or user-facing artifacts while visible safe text
survives in the timeline, session transcript, and rendered request.

The fail-fast suite entrypoint runs the paged report-delivery regressions,
focused harness contract validator, confidence-edit regressions, and existing
plugin validator, in that order:

```bash
bash ./tests/validate-all.sh
```

This is the standard Fedora Linux 44 development and release gate. Public
release export and preflight invoke the same `tests/validate-all.sh` entrypoint.
`tests/validate-plugin.sh` remains the legacy monolithic final stage and is
not the authoritative full-gate command by itself. No hosted CI is added or
required.
