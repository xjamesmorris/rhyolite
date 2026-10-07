# Harness architecture

**Contract version:** 4

**Initial implementation:** I1a

**Supported harnesses:** `copilot` only

## Purpose

Rhyolite separates repository-review orchestration from the command-line
harness that runs the write-disabled worker. The runner keeps ownership of
repository validation, anonymous cloning, snapshot isolation, plan approval,
artifact production, and failure reporting. A selected harness adapter owns
only harness-specific identity, model and capability metadata, authentication
bridging, worker process construction, runtime-home handling, final-response
extraction, and harness-specific isolation checks.

Contract v4 is a fail-closed data-contract and lifecycle seam. It preserves
the Copilot-only runtime and Contract-v3 plan/state identity while adding one
bounded, isolated report-repair invocation that can return only a compact
confidence-edit descriptor. It does not make additional harnesses available,
resume the review worker, or permit a model to rewrite the report.

[ADDING-A-HARNESS.md](ADDING-A-HARNESS.md) is the normative implementation
playbook for Contract v4 and any future production adapter.

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
- `bogus`, `codex`, and `claude` do not select Copilot and do not load another
  adapter in I1a.
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
`plugins/rhyolite/lib/harness/common.sh`. The I1a Copilot adapter lives in
`plugins/rhyolite/lib/harness/copilot.sh`. The loader performs these steps in
order:

1. Resolve the selected harness.
2. Validate the launcher marker when it is set.
3. Validate the selected ID as a safe identifier.
4. Resolve the ID through the fixed adapter map.
5. Source the mapped adapter file.
6. Assert every required Contract-v4 function exists.
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

## Contract-v4 functions

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
| `harness_worker_argv` | Build the ordered worker argument vector. |
| `harness_worker_env` | Build the ordered worker environment/unset vector. |
| `harness_report_repair_argv` | Build the ordered argv for one fresh, tool-less report-repair session in an empty trusted working directory. |
| `harness_report_repair_env` | Build normal worker environment clears plus a fresh harness-specific runtime home, without serializing authentication values. |
| `harness_render_request` | Render the worker request without evaluating repository content. |
| `harness_extract_final_report` | Extract the canonical report and apply the adapter's safe transcript fallback. |
| `harness_extract_report_repair` | Extract only the latest compact confidence-edit reply from sanitized repair output or the latest assistant transcript response. |
| `harness_verify_isolation` | Perform any adapter-specific post-run isolation verification; a no-op must still return success explicitly. |
| `harness_persist_agent_state` | Persist only the adapter's allowlisted, sanitized continuation state. |
| `harness_sanitize_runtime_home` | Remove or sanitize the temporary runtime home and fail if cleanup cannot be completed. |
| `harness_allow_all_detected` | Retain compatibility detection of the outer harness's allow-all state without propagating it to the worker. The runner must not use this signal to open reports. |

The runner treats function output as data. It does not evaluate adapter output,
accept success-shaped fallbacks, or continue after malformed values.
`harness_prepare_worker_home` receives the new runtime-home path plus the
approved reasoning effort and context tier. Its optional fourth phase is
`report-repair`; an omitted phase preserves normal review-worker behavior.
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

Contract v4 retains these capability keys:

| Capability | Copilot I1a |
| --- | --- |
| `fleet` | `yes` |
| `structured_questions` | `yes` |
| `subagents` | `yes` |
| `builtin_security_specialist` | `yes` |
| `builtin_research_specialist` | `yes` |
| `web_research` | `yes` |
| `shell_denial` | `yes` |
| `final_message_file` | `no` |

An unknown capability returns `unverified`; it is never silently promoted to
`yes`.

## Copilot adapter baseline

Copilot is the only mapped I1a adapter.

- Canonical ID: `copilot`
- Display name: `Copilot`
- CLI: `copilot`
- Default model: `gpt-5.6-sol`
- Guided alternate model: `claude-fable-5`
- Model catalog: parsed from local `copilot help config`, a static list built
  into the CLI rather than the account's live catalog; safe syntax alone is
  not availability
- Unlisted models: a safe ID outside that catalog returns status 3 and is
  accepted only with explicit `--allow-unlisted-model`, disclosed as
  approval-bound `ModelCatalogMembership` `unlisted`; `auto` is always
  rejected. Non-interactive review, research, and repair children fail
  closed when Copilot reports `Model "<id>" from --model flag is not
  available.`, and the runner reports a `model availability` stage. The
  launcher's interactive orchestrator session instead falls back to
  Copilot's default model, so it cannot prove availability.
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
timeout argument. The `markdown-table-rows` and
`confidence-level-delimiters` normalizations are also runner-owned: they
convert eligible Markdown tables and insert the accepted ` - ` delimiter after
a single assessment confidence level without invoking any harness function or
model.

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

Contract v4 retains plan schema `5`, state schema `6`, provider identity,
preference schema, and the Copilot-only fixed registry. It adds only the three
required repair lifecycle functions, the optional `report-repair` home phase,
and their fail-closed extraction/isolation contract. A backward-compatible
amendment adds the optional unlisted-model status for
`harness_validate_model_id` and the additive approval-bound plan field
`ModelCatalogMembership` (`listed` or `unlisted`); adapters that never
return that status keep exact-catalog behavior.

## Adding a future adapter

A future adapter is a separate implementation phase. It must be added without
weakening the fail-closed boundary:

1. Assign a safe canonical ID.
2. Add one explicit ID-to-file entry to the fixed registry.
3. Implement every Contract-v4 function; do not inherit missing behavior from
   Copilot.
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

An adapter that cannot satisfy any required function remains unavailable. The
correct failure mode is a sanitized nonzero error, not Copilot fallback or a
partially initialized run.

## Validation

The focused contract-v4 validator is:

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
identity, Copilot-specific research rejection, and injected lifecycle failure
stages. Production `common.sh`, manifests, help, and plugin assets remain
Copilot-only.

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

The I1a fail-fast suite entrypoint runs the focused contract validator first,
then the existing plugin validator:

```bash
bash ./tests/validate-all.sh
```

This is the standard Fedora Linux 44 development and release gate. Public
release export and preflight invoke the same `tests/validate-all.sh` entrypoint.
`tests/validate-plugin.sh` remains the legacy monolithic second stage and is
not the authoritative full-gate command by itself. No hosted CI is added or
required.
