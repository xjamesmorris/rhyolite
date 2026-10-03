# Harness architecture

**Implemented production contract:** 1

**Next contract target:** 2

**Current research-aware schemas:** review plan 3, state 4

**Contract-v2 schemas:** review plan 4, state 5

**Production harnesses:** `copilot` only

**Development fixture:** planned no-op adapter under `tests/fixtures`; never
registered or packaged

## Purpose

Rhyolite separates repository-review orchestration from the command-line
harness that runs the write-disabled worker. The trusted runner owns source
validation, anonymous cloning, snapshot isolation, research transport, plan
approval, worker policy, artifact production, redaction, cleanup, and failure
reporting. A selected harness adapter owns only harness-specific identity,
capability and model metadata, authentication bridging, worker process
construction, runtime-home handling, final-response extraction, and
harness-specific isolation checks.

The seam is fail closed. It exists to make harness-specific behavior explicit
and testable; it does not make every CLI a supported runtime. Production
support remains GitHub Copilot-only.

[ADDING-A-HARNESS.md](ADDING-A-HARNESS.md) is the normative implementation
playbook for Contract v2 and any future production adapter.

## Current implementation and target delta

Contract v1 introduced a fixed adapter seam without changing execution
identity in plans or state. The current production implementation:

- resolves only `copilot`;
- uses a scalar provider summary ID;
- keeps harness, provider, and reasoning effort out of plan schema 3,
  approval-hash material, state schema 4, manifests, handoffs, and
  preferences;
- preserves existing Copilot worker and launcher vectors;
- has no production no-op, Codex, Claude, or dynamically discovered adapter.

Contract v2 makes execution identity explicit while preserving the same
read-only boundary:

- `RHYOLITE_HARNESS_CONTRACT_VERSION` becomes `2`;
- `harness_provider_summary` returns a validated object with `Id`, `Host`, and
  `ForwardedEnvVarNames`;
- plan schema 4 adds approval-bound `Harness`, `Provider`, and
  `ReasoningEffort`;
- state schema 5 propagates safe harness/provider/model/effort identity through
  repository state, run state, manifests, handoffs, and summaries;
- approval hashing binds the harness ID, provider fields and ordered forwarded
  environment-variable names, model, and reasoning effort;
- plan-only resolution still performs no CLI discovery or authentication
  preparation;
- a test-only no-op adapter proves generic orchestration without becoming
  production support.

Default Copilot selection and explicit `--harness copilot` must still resolve
to the same effective plan and approval hash.

## Selection and launcher context

Harness resolution is deterministic:

1. explicit `--harness ID`;
2. `RHYOLITE_HARNESS`;
3. `copilot`.

`--harness` is a Rhyolite control. The launcher and runner accept only the
separated `--harness ID` form and consume it before any downstream harness
argv is built. Equals-form values such as `--harness=codex` and
`--harness=` fail before prompt construction, launcher-state creation, CLI
discovery, Git, DNS, network, or output activity.

Safe IDs match:

```text
^[a-z][a-z0-9-]{0,31}$
```

The syntax is deliberately path-inert: no slash, dot, underscore, uppercase
character, whitespace, control character, shell metacharacter, or empty value
passes. Safe syntax alone never makes an adapter supported. The fixed registry
is authoritative.

The packaged launcher exports:

```text
RHYOLITE_LAUNCHER_HARNESS=copilot
```

When set, `RHYOLITE_LAUNCHER_HARNESS` must be nonempty, safe, and exactly
equal to the selected harness. A malformed or mismatched marker fails at:

```text
harness <selected> context
```

This occurs before adapter loading, output creation, workspace creation, or
CLI discovery. An entirely unset marker is the lower-level direct-runner
compatibility exception. An empty exported marker is invalid.

The marker authenticates consistency of Rhyolite's own launcher handoff. It is
not a provider credential and does not authorize a repository.

## Fixed adapter loading

The shared resolver and loader are in
`plugins/rhyolite/lib/harness/common.sh`. The production Copilot adapter is
`plugins/rhyolite/lib/harness/copilot.sh`.

The loader performs these steps in order:

1. Resolve the selected harness.
2. Validate launcher context when a marker is set.
3. Validate the selected ID as a safe identifier.
4. Resolve the ID through the fixed production map.
5. Source the exact mapped adapter file.
6. Assert every required contract function exists.
7. Validate load-time identity and all tri-state capabilities.
8. Invoke later functions only through the guarded contract boundary.

An ID is never converted into a path, and no directory is scanned. Unknown
IDs, missing or unreadable mapped files, syntax failures, incomplete adapters,
wrong reported IDs, and malformed load-time metadata stop the operation.
There is no automatic fallback to Copilot.

Load failures use:

```text
harness <id> load
```

After load, adapter call failures use:

```text
harness <id> <function>
```

Diagnostics at every harness stage pass through Rhyolite's normal
sanitization boundary before reaching stderr or artifacts.

The development no-op adapter is not a production map entry. Focused tests may
stage a temporary plugin root with a test-owned fixed registry. Production
`common.sh` must reject `noop`.

## Contract-v2 function surface

Contract v2 retains the complete v1 function surface and tightens the provider
and schema contracts. Every mapped adapter defines every function.

| Function | Adapter responsibility and output |
| --- | --- |
| `harness_id` | Print the canonical registry ID. It must equal the selected ID. |
| `harness_display_name` | Print the bounded user-facing harness name. |
| `harness_cli_name` | Print the executable name used for discovery and invocation; no path or arguments. |
| `harness_require_cli` | Status-only execution-time availability check without starting or authenticating the CLI. |
| `harness_capability` | Print exactly `yes`, `no`, or `unverified` for the requested capability. |
| `harness_default_model` | Print the adapter default model ID. |
| `harness_validate_model_id` | Accept or reject an exact user-supplied model ID without substitution. |
| `harness_model_choices` | Print ordered guided model labels, one per line; no explicit `Other`. |
| `harness_max_reasoning_effort` | Print the strongest supported effort value for the validated model. |
| `harness_auth_secret_env_vars` | Print zero or more unique protected environment-variable names, one per line. Empty output is a valid empty list. |
| `harness_login_remediation` | Print safe, non-automatic sign-in remediation. |
| `harness_provider_summary` | Print one validated JSON object with exactly `Id`, `Host`, and `ForwardedEnvVarNames`. |
| `harness_prepare_run` | Prepare run-wide ephemeral adapter/auth context exactly once after approval. |
| `harness_prepare_worker_home` | Secure and populate one runner-created isolated runtime home. |
| `harness_worker_argv` | Populate the ordered worker argv array supplied by name. |
| `harness_worker_env` | Populate the ordered `env` unset/assignment array supplied by name. |
| `harness_render_request` | Render the trusted worker request without evaluating repository content. |
| `harness_extract_final_report` | Recover a candidate canonical report from sanitized harness-specific final output. |
| `harness_verify_isolation` | Perform adapter-specific post-run isolation verification; an explicit no-op succeeds only when no extra check exists. |
| `harness_persist_agent_state` | Persist only an explicit sanitized continuation-state allowlist. |
| `harness_sanitize_runtime_home` | Remove or sanitize the temporary runtime home and fail when cleanup cannot complete. |
| `harness_allow_all_detected` | Return boolean status for outer allow-all detection without forwarding that state. |

The runner treats every adapter output as data. It does not evaluate output,
accept success-shaped fallback values, continue after malformed values, or
expose raw adapter stderr. Array functions run in the current shell so they
can populate destination arrays and preserve safe error detail.

## Provider summary

Contract v2 changes the provider summary from the v1 scalar ID to this exact
object shape:

```json
{
  "Id": "github-copilot",
  "Host": "github.com",
  "ForwardedEnvVarNames": [
    "COPILOT_GITHUB_TOKEN",
    "GH_TOKEN",
    "GITHUB_TOKEN"
  ]
}
```

The example list is abbreviated.

Validation requires:

- exactly the three keys shown;
- a stable safe provider ID;
- a lower-case DNS-style host with no scheme, port, path, userinfo, wildcard,
  whitespace, or control character;
- an ordered array of unique shell identifiers;
- exact ordered equality between `ForwardedEnvVarNames` and
  `harness_auth_secret_env_vars`;
- names only, never values, account identifiers, token state, provider
  responses, or credential-store paths.

The runner resolves this object during planning without CLI discovery,
authentication preparation, or secret access. It canonicalizes the object
before approval hashing and reuses the approved values for state and handoff
output.

## Capabilities

Capabilities describe proven adapter behavior and never relax runner policy.

- `yes`: implemented, tested, and supported.
- `no`: explicitly unsupported.
- `unverified`: support cannot be established safely at selection time.

No other spelling, empty output, multiple values, or successful exit with an
invalid value is accepted. `unverified` is never promoted to `yes`.

Contract v2 capability keys are:

| Capability | Copilot production baseline |
| --- | --- |
| `fleet` | `yes` |
| `structured_questions` | `yes` |
| `subagents` | `yes` |
| `builtin_security_specialist` | `yes` |
| `builtin_research_specialist` | `yes` |
| `web_research` | `yes` |
| `shell_denial` | `yes` |
| `final_message_file` | `no` |

An unknown capability returns `unverified`. Production requires
`shell_denial=yes`. Scope 2/3 must fail closed if the selected adapter cannot
support the exact dedicated research-worker and local-broker contract.

## Copilot production baseline

Copilot remains the only production adapter.

- Canonical ID: `copilot`
- Display name: `Copilot`
- CLI: `copilot`
- Default model: `gpt-5.6-sol`
- Guided alternate model: `claude-fable-5`
- Maximum reasoning effort: `max`
- Provider ID: `github-copilot`
- Provider host: `github.com`
- Login remediation: run `copilot login` from a clean non-Git directory and
  retry; Rhyolite never starts login automatically.
- Authentication boundary: current environment, system credential store,
  GitHub CLI fallback, configured provider, or the narrow ephemeral Copilot
  authentication bridge.

The complete protected environment-variable contract is:

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

Contract v2's Copilot provider object reports these names in this exact order.
It never reports their values.

The adapter preserves the worker restrictions: bundled read-only agent,
maximum reasoning and long context, disabled custom instructions and built-in
MCPs, denied write and shell tools, disabled temporary-directory access and
remote export, and optional public research only through the runner-created
local broker path.

The child environment removes inherited Copilot allow-all state and inherited
skill/custom-instruction discovery variables. The isolated runtime home keeps
hooks disabled and local-only agent discovery enabled. Persisted state is
limited to sanitized configuration plus explicitly allowlisted session state;
unrelated runtime-home content and authentication bridge data are not retained.

`harness_prepare_run` reads source Copilot configuration at most once per run.
Only a valid JSON object contributes allowlisted bridge keys. JSON `null`,
arrays, strings, malformed JSON, invalid UTF-8, unreadable files, and
parsing/type errors fail soft to an empty bridge when safe; they do not copy
unrelated configuration.

Copilot final-report recovery examines sanitized standard output first, then
the sanitized final Copilot transcript response when stdout is missing or
incomplete. The runner still owns canonical delimiter, completeness, UTF-8,
required-section, and scope validation.

## Development-only no-op fixture

The planned no-op adapter demonstrates that the runner is not accidentally
hard-coded to Copilot. It belongs under `tests/fixtures` and uses only
test-owned loading.

The fixture:

- has safe ID `noop`;
- reports a clearly test-only display name;
- uses a deterministic fixture model and effort;
- requires no credentials;
- reports provider `fixture-noop`, host `fixture.invalid`, and an empty
  forwarded-name array;
- performs no Git, DNS, public network, login, preference, or user-home access;
- emits a deterministic complete canonical report;
- supports injected failures across the complete lifecycle;
- proves runtime-home, persistence, extraction, cleanup, and isolation
  behavior.

The fixture is never:

- entered in the production fixed registry;
- copied under `plugins/rhyolite`;
- accepted by production `--harness noop`;
- exposed through launcher, command, help, plugin, or marketplace metadata;
- described as user-facing runtime support;
- included in a public-release export.

## Lifecycle

1. Resolve the harness from CLI, environment, or default.
2. Validate `RHYOLITE_LAUNCHER_HARNESS` when set.
3. Load and validate the fixed-map adapter and complete function set.
4. Resolve safe display/CLI names, capabilities, model, maximum effort,
   protected environment-variable names, provider summary, and remediation.
5. Validate runner inputs, trusted paths, research policy, and source URLs.
6. Build plan schema 4, including `Harness`, `Provider`, `Model`, and
   `ReasoningEffort`, then compute the approval hash.
7. For plan-only mode, emit the plan without requiring the CLI or preparing
   authentication.
8. Before execution, re-resolve the effective plan and require the expected
   hash.
9. Require the selected CLI and call `harness_prepare_run` exactly once.
10. Perform runner-owned anonymous preflight, clone, exact-commit resolution,
    and read-only snapshot construction.
11. Render the trusted request, build argv, create a unique user-only runtime
    home, prepare it, and build the worker environment.
12. Invoke the selected CLI under timeout and repository-isolation controls.
13. Persist only allowlisted sanitized state.
14. Sanitize and remove the temporary runtime home.
15. Sanitize worker output, verify adapter-specific isolation, recover a
    candidate report, and validate the canonical report contract.
16. Finalize state schema 5 report, research, state, handoff, manifest, and
    index artifacts.

If request rendering, argv construction, runtime-home preparation, or
environment construction fails before launch, final artifacts clear child
session ID/name and state that no child session started. Once launch occurs,
worker, timeout, isolation, persistence, extraction, and cleanup failures
retain the real session identity.

## Plan, state, hash, and preferences

Plan schema 4 adds:

```text
Harness
Provider.Id
Provider.Host
Provider.ForwardedEnvVarNames[]
ReasoningEffort
```

These values are approval-hash material. The provider array is hashed in
stable order; no secret value is ever hashed or persisted. Any change between
planning and execution produces a plan-hash mismatch and requires a new plan
and approval.

State schema 5 carries the same approved safe identity, plus the selected
model, through every terminal status in repository state, run state, manifest
rollups, handoffs, and summaries.

Launcher preference schema 1 remains explicitly Copilot-specific while
production remains Copilot-only. Before a second production harness may
remember settings, preferences must become harness-aware or remembering must
be disabled for that harness. Copilot fleet/model preferences must never be
silently applied to another harness.

## Trust boundaries

### Resolver and loader

Trusted Rhyolite code owns precedence, safe-ID validation, launcher-marker
validation, the fixed map, complete function validation, guarded invocation,
metadata validation, and sanitized harness-stage failures. CLI and environment
selection values are untrusted.

### Harness adapter

The selected adapter is trusted packaged code. Its CLI output, runtime files,
provider responses, authentication failures, and saved transcripts are
untrusted data. The adapter may translate between the generic runner and one
known CLI. It may not redefine source policy, plan approval, worker tools,
research egress, path isolation, redaction, or artifact schemas.

### Runner

The runner remains authority for public-source validation, credential-free
Git, DNS pinning, exact-commit snapshots, concurrency and timeout limits,
read-only worker policy, constrained research, report validation, redaction,
schema production, and artifact finalization. It validates adapter outputs
before use and records the exact lifecycle failure stage.

### Launcher

The launcher selects and marks the outer harness before starting the outer
session. The marker proves only Rhyolite handoff consistency. It carries no
provider secret or repository authority.

### Direct invocation

The marker-unset exception supports lower-level direct runner use. It does not
skip safe-ID validation, fixed-map lookup, complete contract validation, CLI
checks for execution, plan approval, or any repository-review safety control.

### Test fixtures

Test adapters and fake CLIs are trusted development fixtures only. They may be
loaded through test-owned fixed maps in temporary trees. They must not create a
production injection point or survive packaging.

## Validation

The focused harness validator is:

```bash
bash ./tests/validate-harness-contract.sh
```

Contract-v2 coverage must include:

- fixed-map resolution and launcher-context failures;
- every required function and every invalid output shape;
- canonical provider-object validation;
- plan schema 4, state schema 5, and new approval-hash material;
- default versus explicit Copilot equivalence;
- Copilot golden argv/environment compatibility;
- plan-only behavior without CLI or authentication preparation;
- test-only no-op end-to-end execution and production rejection of `noop`;
- injected failures for every lifecycle stage;
- permission, persistence, cleanup, timeout, interruption, isolation, and
  extraction behavior;
- sanitization of credentials, URL userinfo, authorization data, email,
  terminal controls, transcript content, and trusted Git metadata;
- release/package exclusion of test fixtures.

The authoritative Fedora Linux 44 gate is:

```bash
bash ./tests/validate-all.sh
```

It runs the focused harness validator first, then the legacy monolithic plugin
validator. Public-release export and preflight use the same full entrypoint.
`tests/validate-plugin.sh` alone is not the full gate. No hosted CI is added or
required.

## Adding production support

A future production adapter is a separate approved implementation and release,
not a registry-only change. Follow every step and evidence requirement in
[ADDING-A-HARNESS.md](ADDING-A-HARNESS.md). An adapter that cannot satisfy any
required function or safety invariant remains unavailable. The correct failure
mode is a sanitized nonzero error, not fallback, scope downgrade, model
substitution, or a partially initialized run.
