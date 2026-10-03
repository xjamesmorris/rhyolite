# Harness architecture

**Contract version:** 2

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

Contract v2 is a fail-closed data-contract seam. It preserves the I1a Copilot
execution behavior while binding harness, resolved reasoning effort, and
strict provider metadata into approved plans and persisted artifacts. It does
not make additional harnesses available.

[ADDING-A-HARNESS.md](ADDING-A-HARNESS.md) is the normative implementation
playbook for Contract v2 and any future production adapter.

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
6. Assert every required Contract-v2 function exists.
7. Invoke adapter functions only through the guarded contract boundary.

The common boundary captures scalar output without exposing adapter stderr and
invokes status/array functions in the current shell so their structured error
detail remains available for sanitized reporting. The runner rejects empty,
malformed, duplicated, or otherwise invalid contract values before using them.

In addition to the loader's identity and tri-state capability checks, the
runner validates adapter-provided display and CLI names, default and explicit
model IDs, maximum reasoning effort, resume policy, strict provider JSON, and
the protected secret-environment list. Provider JSON must contain exactly
`Id`, `Host`, and `ForwardedEnvVarNames`; the forwarded names must exactly
match the unique shell identifiers returned by
`harness_auth_secret_env_vars`. Plan-only resolution does not require the
selected harness CLI and does not prepare run-time authentication context;
execution performs those checks only after the approved plan still matches.

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

## Contract-v2 functions

Every mapped adapter must define all functions below.

| Function | Adapter responsibility |
| --- | --- |
| `harness_id` | Return the adapter's canonical registry ID. It must equal the selected ID. |
| `harness_display_name` | Return the user-facing harness name. |
| `harness_cli_name` | Return the executable name used for discovery and invocation. |
| `harness_require_cli` | Verify that the required CLI is available without starting it. |
| `harness_capability` | Return exactly `yes`, `no`, or `unverified` for the requested capability. |
| `harness_default_model` | Return the adapter's default model ID. |
| `harness_validate_model_id` | Accept or reject a user-supplied model ID without substitution. |
| `harness_model_choices` | Return the adapter-owned guided model choices. |
| `harness_max_reasoning_effort` | Return the strongest supported reasoning-effort value for the supplied model. |
| `harness_auth_secret_env_vars` | Return the exact inherited secret-variable allowlist protected from disclosure. |
| `harness_login_remediation` | Return harness-specific, non-automatic sign-in remediation. |
| `harness_provider_summary` | Return a JSON object with exactly `Id`, `Host`, and `ForwardedEnvVarNames`. |
| `harness_resume_policy` | Return the safe adapter-specific continuation policy stored under the generic session `ResumePolicy`. |
| `harness_prepare_run` | Prepare run-wide adapter context exactly once, including any ephemeral authentication bridge metadata. |
| `harness_prepare_worker_home` | Create and secure an isolated runtime home containing only adapter-approved settings and ephemeral authentication bridge data. |
| `harness_worker_argv` | Build the ordered worker argument vector. |
| `harness_worker_env` | Build the ordered worker environment/unset vector. |
| `harness_render_request` | Render the worker request without evaluating repository content. |
| `harness_extract_final_report` | Extract the canonical report and apply the adapter's safe transcript fallback. |
| `harness_verify_isolation` | Perform any adapter-specific post-run isolation verification; a no-op must still return success explicitly. |
| `harness_persist_agent_state` | Persist only the adapter's allowlisted, sanitized continuation state. |
| `harness_sanitize_runtime_home` | Remove or sanitize the temporary runtime home and fail if cleanup cannot be completed. |
| `harness_allow_all_detected` | Detect the outer harness's allow-all state without propagating it to the worker. |

The runner treats function output as data. It does not evaluate adapter output,
accept success-shaped fallbacks, or continue after malformed values.
`harness_prepare_worker_home` receives only the new runtime-home path.
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

Contract v2 defines these capability keys:

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
- Maximum reasoning effort: `max`
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
worker agent, maximum reasoning/context settings, disabled custom
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

`harness_prepare_run` reads the source Copilot `config.json` at most once per
run. Only a valid JSON object contributes allowlisted bridge keys. JSON `null`,
arrays, strings, malformed JSON, invalid UTF-8, unreadable files, and
parsing/type errors fail soft to an empty bridge with plaintext-token mode
disabled; they do not abort the review or copy unrelated configuration.

Copilot's final-report path first examines sanitized standard output, then the
sanitized final Copilot transcript response when the standard output is
missing or incomplete. The runner still owns the canonical delimiter,
completeness, and artifact validation rules.

## Lifecycle

1. **Resolve** the harness from CLI, environment, or default.
2. **Validate context** against `RHYOLITE_LAUNCHER_HARNESS` when the marker is
   set.
3. **Load and validate** the fixed-map adapter and its complete function set.
4. **Resolve and validate planning metadata** such as CLI identity, model,
   effort, capabilities, resume policy, and strict provider metadata.
5. **Validate runner inputs and paths**, and require the selected harness CLI
   only for an actual execution.
6. **Plan and approve** the review using plan schema `4`; harness identity,
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
14. **Finalize** the existing report, state, handoff, and index artifacts.

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

Contract v2 intentionally changes only the data contract around that baseline:

- plan schema is `4` and state schema is `5`;
- plan JSON/text, review-plan artifacts, repository/run state, manifests, and
  handoffs record `Harness`, resolved `ReasoningEffort`, and strict `Provider`
  metadata where identity matters;
- the generic session `ResumePolicy` is adapter-owned, with Copilot retaining
  its trusted-runner-only continuation behavior;
- approval hashes include the plan schema and all harness identity metadata,
  so hashes from earlier plans cannot authorize contract-v2 plans;
- launcher preferences use schema `2` with `harness`; schema `1` is read as
  Copilot-only, and preferences are reused only for a matching harness;
- preference and launcher-state paths reject wrong ownership, symlink
  components, and group/world-writable components.

## Adding a future adapter

A future adapter is a separate implementation phase. It must be added without
weakening the fail-closed boundary:

1. Assign a safe canonical ID.
2. Add one explicit ID-to-file entry to the fixed registry.
3. Implement every Contract-v2 function; do not inherit missing behavior from
   Copilot.
4. Return only tri-state capability values and document any `unverified`
   result.
5. Define exact model validation, choices, maximum effort, protected secret
   variables, provider summary, and login remediation.
6. Build deterministic argv/env arrays with no Rhyolite-only selection
   arguments downstream.
7. Use a unique isolated runtime home and persist only an explicit state
   allowlist.
8. Prove that allow-all state is detected for outer-session behavior but
   removed from the child.
9. Implement safe request rendering, report extraction/fallback, cleanup, and
   isolation verification.
10. Add golden contract tests, default/explicit vector comparisons,
    context-mismatch tests, failure-stage tests, and schema/hash
    non-regression coverage before adding the map entry.

An adapter that cannot satisfy any required function remains unavailable. The
correct failure mode is a sanitized nonzero error, not Copilot fallback or a
partially initialized run.

## Validation

The focused contract-v2 validator is:

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
