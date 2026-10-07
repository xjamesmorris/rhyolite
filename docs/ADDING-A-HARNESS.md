# Adding a review harness

This is the implementation playbook for the target Rhyolite Harness Contract
version 4. It is written for contributors and coding agents that must change
the harness seam without weakening Rhyolite's read-only repository-review
boundary.

Read [../AGENTS.md](../AGENTS.md) and
[HARNESS-ARCHITECTURE.md](HARNESS-ARCHITECTURE.md) first.

## Status and scope

- The implemented production seam is Contract v4.
- The current review plan is schema 5 and repository/run state is schema 6.
- Production remains GitHub Copilot-only. A contract refactor does not itself
  add another supported harness.
- The no-op adapter and worker under `tests/fixtures/harnesses/` are
  development-only contract fixtures. They are never registered by production
  `common.sh`, copied into the plugin, selectable through the launcher or
  runner in a production checkout, advertised to users, or included in release
  artifacts.

Do not begin by adding a production registry entry. Implement and prove the
complete adapter contract first. Registration is the final enablement step
after all required evidence exists.

## Non-negotiable preconditions

A proposed production harness is eligible only when all of the following are
true:

1. A project decision explicitly approves adding production runtime support.
   Safe ID syntax or a working prototype is not approval.
2. The CLI is installable and testable on Fedora Linux 44.
3. It can run non-interactively from an ordered argv array without shell
   evaluation.
4. It supports a unique isolated runtime home or equivalent configuration
   root that Rhyolite can create, restrict, sanitize, and remove.
5. Rhyolite can deny child write and shell access by construction. A harness
   that cannot enforce the worker tool boundary is unsupported.
6. It can run the bundled write-disabled worker against a read-only,
   `.git`-free snapshot without executing target code.
7. It can use maximum available reasoning effort and long context for every
   supported review model. High is the absolute minimum; automatic downgrade
   is forbidden.
8. Authentication can be passed through a narrow, documented boundary without
   copying broad user configuration or exposing secret values.
9. Its final response can be recovered deterministically from sanitized
   output or a sanitized transcript/final-message artifact.
10. Timeout, interruption, persistence, cleanup, and post-run isolation can
    fail closed with truthful artifacts.
11. Scope 1 remains transport-free. Scope 2/3 is enabled only if the harness
    can support the exact constrained research-worker contract; a similar
    feature name is not enough.
12. The adapter can satisfy every Contract-v4 function and every negative and
    end-to-end test in this playbook.

If any precondition is unresolved, stop. Do not add a partial adapter, a
fallback to Copilot, or a user-facing experimental switch.

## Change boundaries

Harness work crosses a strict set of surfaces:

- `plugins/rhyolite/lib/harness/common.sh`: contract version, complete
  function list, guarded calls, fixed registry, and metadata validation.
- `plugins/rhyolite/lib/harness/<id>.sh`: one complete adapter.
- `run-parallel-reviews.sh`: planning metadata, capability gating, approved
  hash material, lifecycle calls, state, and failure stages.
- Launcher and guided agent surfaces only when the new harness is approved
  for production selection.
- Focused and aggregate validation, including test-only fixtures.
- Plan, repository state, run state, manifest, handoff, HTML summary, and
  preference behavior.
- User and contributor documentation, packaging, release metadata, and
  publication checks when production support changes.

Contract v4 must land as one coordinated behavior change. It retains plan
schema 5, state schema 6, provider identity, preferences, and the Copilot-only
registry while adding the complete bounded-repair lifecycle. Do not register
an adapter before validation understands its complete lifecycle.

## Fixed registry procedure

Harness IDs must match:

```text
^[a-z][a-z0-9-]{0,31}$
```

That check prevents path syntax; it does not grant support. Production support
exists only when `rhyolite_harness_load` contains one explicit ID-to-file map
entry. The implementation remains a fixed `case` or equally explicit closed
map. For a newly approved harness:

1. Choose a stable canonical ID.
2. Add `plugins/rhyolite/lib/harness/<id>.sh`.
3. Implement and test every required function.
4. Prove all metadata and lifecycle validation through a test-owned fixed
   registry.
5. Add exactly one production registry entry as the final enablement change.
6. Verify that every other safe ID still fails without loading a file.

Never:

- interpolate an ID into a source path;
- scan an adapter directory;
- use `PATH`, the current directory, plugin metadata, repository content, or
  an environment-provided path for discovery;
- allow a test environment variable to override the production registry;
- source an adapter before launcher-context and safe-ID validation;
- fall back to Copilot after any resolution, load, metadata, or lifecycle
  failure.

The development no-op adapter must be loaded only by test-owned code, such as
a temporary fixture plugin tree with its own fixed test registry. Production
`common.sh` must reject `--harness noop`.

## Contract-v4 boundary

Set the shared contract version to:

```bash
RHYOLITE_HARNESS_CONTRACT_VERSION=4
```

The shared loader must require all functions in this document before calling
any adapter behavior. Required functions are not optional based on
capabilities. A no-op implementation must still return an explicit successful
status where the operation truly has no adapter-specific work.

Use the existing guarded boundaries:

- capture scalar or JSON stdout through `rhyolite_harness_capture`;
- invoke status and array functions in the current shell through
  `rhyolite_harness_invoke`;
- clear `RHYOLITE_HARNESS_ERROR_DETAIL` before every call;
- preserve adapter-set safe detail on failure;
- replace absent detail with the runner's generic function-stage error;
- never expose raw adapter stderr to the user.

### Common output rules

- Scalar output is UTF-8, one logical line, nonempty unless this playbook says
  an empty list is valid, and contains no control characters.
- JSON output is one complete JSON object, not JSON Lines, comments, or
  shell syntax.
- List output is newline-delimited data. No item may contain a newline or
  control character.
- Array-producing functions receive the destination Bash array name as their
  first argument and populate it directly. They do not print shell-escaped
  commands.
- Status functions return zero on success and nonzero on failure. They do not
  emit structured data.
- An adapter failure sets a short, sanitized
  `RHYOLITE_HARNESS_ERROR_DETAIL`. It never includes secret values, raw
  provider responses, terminal controls, repository content, or broad local
  paths.
- Adapter output is data. The runner never uses `eval`, `bash -c`, `sh -c`,
  unquoted expansion, or command-string reconstruction to consume it.

## Required functions and exact shapes

### Identity, CLI, and capabilities

| Function | Signature and output | Required validation |
| --- | --- | --- |
| `harness_id` | No arguments. Print the canonical harness ID followed by one newline. | Must match the selected safe ID and the fixed registry entry exactly. |
| `harness_display_name` | No arguments. Print one user-facing name. | Nonempty, bounded, no controls. It is explanatory text, never a command. |
| `harness_cli_name` | No arguments. Print one executable name. | Match the runner's executable-name grammar; no slash, whitespace, arguments, or shell syntax. |
| `harness_require_cli` | No arguments. Status only. | Check availability without starting the CLI, logging in, writing state, or accessing the network. It is execution-only and is not called for plan-only mode. |
| `harness_capability` | One capability key. Print exactly `yes`, `no`, or `unverified`. | Unknown keys return `unverified`. Empty or alternate spellings fail validation. |

Contract-v4 capability keys remain:

```text
fleet
structured_questions
subagents
builtin_security_specialist
builtin_research_specialist
web_research
shell_denial
final_message_file
```

Capabilities describe proven adapter behavior; they do not relax runner
policy. `unverified` is not `yes`. A production adapter must report
`shell_denial=yes`. Scope 2/3 must fail closed unless the capabilities needed
for the dedicated research worker and its exact local tools are `yes`.
Native fleet mode must fail or remain unavailable when `fleet` is not `yes`;
it must not be silently translated into another mode.

### Models and effort

| Function | Signature and output | Required validation |
| --- | --- | --- |
| `harness_default_model` | No arguments. Print one model ID. | Must pass the same adapter validator used for explicit models. |
| `harness_list_models` | No arguments. Print the model IDs in the offline catalog, one per line. | Use only a local non-interactive help/config surface; reject empty, unsafe, or duplicated IDs. A static help catalog can omit models that an account can use. |
| `harness_validate_model_id` | One model ID. Status only: `0`, `RHYOLITE_HARNESS_MODEL_UNLISTED_STATUS` (`3`), or another nonzero rejection. | Return `0` only for exact membership in the offline catalog. Never substitute, normalize, alias, or silently downgrade it. Reject selectors that let the CLI choose a model, such as Copilot `auto`, before testing membership. Return `3` only for a safe ID that is absent from a successfully discovered catalog and that the harness's non-interactive workers reject without substitution when unavailable; the runner accepts it only with explicit `--allow-unlisted-model`. |
| `harness_model_choices` | No arguments. Print one or more ordered picker labels, one per line. | The first choice is the recommended default and one choice may list the offline catalog. Do not print an explicit `Other`; Copilot CLI owns the final custom-answer option. |
| `harness_max_reasoning_effort` | One already validated model ID. Print one effort token. | The value must be safe, supported by that model, and the strongest available setting. It is the default approval-bound effort. |
| `harness_reasoning_effort_choices` | No arguments. Print ordered guided effort labels. | Include only supported values at or above the project hard minimum. |
| `harness_validate_reasoning_effort` | One effort token. Status only. | Accept only exact supported values. |
| `harness_default_context_tier` | No arguments. Print the recommended context tier. | Must pass the context validator. |
| `harness_context_choices` | No arguments. Print ordered guided context labels. | The recommended tier is first. |
| `harness_validate_context_tier` | One context token. Status only. | Accept only exact supported values. |

Model, effort, and context selection remain adapter-owned, but the runner owns
plan approval. Changing the harness, model, selected effort, or selected
context after approval is a plan mismatch.

### Authentication and provider summary

| Function | Signature and output | Required validation |
| --- | --- | --- |
| `harness_auth_secret_env_vars` | No arguments. Print zero or more environment-variable names, one per line. Empty stdout is a valid empty list. | Every name is a unique shell identifier. The runner must consume an empty list without creating an empty item. Values are never printed. |
| `harness_login_remediation` | No arguments. Print one safe remediation sentence or paragraph. | Nonempty, no controls, no automatic login command execution, no secret echo. |
| `harness_provider_summary` | No arguments. Print one compact JSON object with exactly `Id`, `Host`, and `ForwardedEnvVarNames`. | Validate structure, types, values, uniqueness, order, and correspondence with the authentication allowlist before planning. |

The provider object is:

```json
{
  "Id": "github-copilot",
  "Host": "managed-provider",
  "ForwardedEnvVarNames": [
    "COPILOT_GITHUB_TOKEN",
    "GH_TOKEN",
    "GITHUB_TOKEN"
  ]
}
```

The example is abbreviated; the production Copilot adapter must report its
complete protected allowlist.

Provider validation rules:

- The object has exactly the three required keys. Missing or unknown keys
  fail.
- `Id` is a stable safe identifier, not a display name or secret-derived
  value.
- `Host` is a stable lower-case DNS-style host with no scheme, path, port,
  query, fragment, userinfo, wildcard, whitespace, or control character.
- `ForwardedEnvVarNames` is an array of unique shell identifiers in stable
  adapter-defined order.
- The array is exactly the set and order returned by
  `harness_auth_secret_env_vars`.
- The object contains names only, never environment values, token state,
  usernames, account IDs, credential-store paths, or raw provider responses.
- The runner canonicalizes the validated object for approval hashing and
  state. JSON key order or insignificant whitespace from the adapter must not
  create ambiguous hash material.
- The summary is resolved during planning without requiring the CLI, opening a
  credential store, reading secrets, or preparing the runtime authentication
  bridge.

For the development no-op fixture, use a reserved non-production description
such as:

```json
{
  "Id": "fixture-noop",
  "Host": "fixture.invalid",
  "ForwardedEnvVarNames": []
}
```

That object is test evidence only. It must never appear in production plans or
release artifacts.

### Run preparation, request, argv, and environment

| Function | Signature and output | Required behavior |
| --- | --- | --- |
| `harness_prepare_run` | No arguments. Status only; no contract data on stdout. | Run once after approved-plan verification and protected-name validation. Prepare only run-wide ephemeral adapter context. |
| `harness_render_request` | Template path, request path, repository URL, snapshot path, exact commit, review dates/windows, scope, output path, bounded metadata, research instructions, dossier path, network-summary path, and transport instructions. Status only. | Write the request file without evaluating template or repository content. |
| `harness_worker_argv` | Destination array name, session root, plugin root, session name, session ID, model, reasoning effort, context tier, comma-separated protected variable names, available tools, transcript path, and public-research flag. Status only. | Populate the exact ordered CLI argument array. |
| `harness_worker_env` | Destination array name. Status only. | Populate the exact ordered `env` argument array, including unsets and the isolated home binding. |
| `harness_report_repair_argv` | Destination array name, empty trusted workdir, fresh session name, fresh session ID, approved model, approved reasoning effort, approved context tier, comma-separated protected variable names, and fresh transcript path. Status only. | Populate the exact ordered tool-less repair argument array. |
| `harness_report_repair_env` | Destination array name and fresh runtime-home path. Status only. | Populate the repair `env` data array using normal worker clearing semantics and a fresh `COPILOT_HOME`, without serializing authentication values. |

`harness_prepare_run` may inspect only the adapter's approved local
configuration source. It must:

- be idempotent within one runner process;
- read configuration at most once unless the contract explicitly requires
  otherwise;
- copy only an allowlisted authentication bridge;
- fail soft to no bridge for malformed optional configuration when that is
  safe;
- fail closed when required preparation cannot be completed;
- never clone, access target URLs, create review output, start login, or print
  secret-bearing diagnostics.

Request rendering must:

- treat every repository field, Git field, dossier field, and external page
  as inert untrusted data;
- replace only the exact trusted placeholders;
- preserve the canonical report and dossier headings/delimiters;
- never use `eval`, source the template, execute substitutions, or expand
  repository-provided text;
- write only to the runner-supplied request path;
- contain no credential value or broad local configuration.

Worker argv must:

- be an array with one argument per element;
- consume `--harness` entirely at the Rhyolite boundary;
- select only the bundled write-disabled worker;
- pass the approved model and maximum effort unchanged;
- request long context;
- disable custom instructions and built-in MCPs;
- deny write and shell tools;
- disable temporary-directory access and remote export;
- avoid allow-all mode and broad URL approval;
- use only the runner-supplied session, transcript, plugin, and tool values;
- preserve Copilot's existing golden vector unless an intentional,
  independently reviewed contract change requires otherwise.

Worker environment must:

- be an ordered array for `env`, never a shell command string;
- unset inherited allow-all state and harness-specific skill/custom-instruction
  discovery variables;
- bind the unique runtime home explicitly;
- forward only the approved provider environment-variable names;
- never copy all inherited variables into an intermediate file;
- never inherit proxy, netrc, cookie, target, or repository configuration into
  anonymous Git or research boundaries;
- contain no test-only override in production.

Report-repair argv is a separate golden vector. It must:

- use a fresh session name and ID and a runner-created empty trusted workdir;
- use the approved model, reasoning effort, and context unchanged;
- pass the protected authentication-name CSV as one literal argument;
- exclude all supported inventory categories with the literal ordered vector
  `--excluded-tools builtin:* mcp:* custom:*`;
- explicitly deny read, write, shell, and URL permissions;
- contain no `--allow-tool`, allow-all flag, plugin, agent, MCP, skill,
  attachment, add-directory, fleet, autopilot, resume, or continue grant;
- disable custom instructions, built-in MCPs, temporary-directory access,
  remote export/control, Bash environment import, automatic update,
  experimental behavior, and dynamic skill retrieval;
- force interactive mode so inherited plan/autopilot settings cannot apply;
- write only the fresh transcript and return its reply on standard output.

Do not pass a zero-value `--available-tools`. In Copilot CLI 1.0.91 it parses
as boolean `true`, is normalized to an unspecified filter, and leaves every
tool visible. A bare `*` exclusion is also not a supported wildcard. The three
category patterns above are the supported exhaustive visibility filter;
permission denials remain separate defense in depth.

Report-repair environment must:

- match normal worker clearing semantics: unset inherited Copilot allow-all
  and skill/custom-instruction discovery variables;
- bind only the harness-specific home (`COPILOT_HOME` for Copilot) to the fresh
  repair runtime home;
- contain no authentication, provider-key, token, or credential value;
- preserve inherited `HOME`, XDG/cache paths, `PATH`, provider selection,
  offline mode, and authentication environment so BYOK, GitHub CLI fallback,
  offline behavior, and the resolved CLI loader remain unchanged;
- be applied by the runner before `timeout`, never as `env NAME=value`
  arguments inside the long-lived timeout command;
- keep source snapshots, research files, target metadata, and analysis runtime
  homes out of both the data vector and repair workdir.

### Runtime home, persistence, cleanup, and isolation

| Function | Signature and output | Required behavior |
| --- | --- | --- |
| `harness_prepare_worker_home` | Runner-created runtime-home path, reasoning effort, context tier, and optional phase. Status only. | Restrict the directory and write only minimal approved configuration/auth bridge data. Omitted phase preserves normal behavior; `report-repair` writes repair-only settings. |
| `harness_persist_agent_state` | Runtime-home path and destination agent-state directory. Status only. | Copy only an explicit sanitized continuation allowlist. |
| `harness_sanitize_runtime_home` | Runtime-home path. Status only. | Remove or sanitize the entire temporary home; be safe when called by normal flow or the exit trap. |
| `harness_verify_isolation` | Sanitized timeline path. Status only. | Perform adapter-specific post-run isolation checks. An explicit no-op is allowed only when the adapter has no additional invariant to verify. |
| `harness_allow_all_detected` | No arguments. Boolean status: zero means detected, one means not detected. | Retain the compatibility signal without forwarding it to the child. Do not print its value or use it to open reports. |

Runtime-home requirements:

- The runner creates the unique directory under a trusted temporary root.
- Before home preparation or child invocation, the runner canonicalizes the
  repair workdir and runtime home, proves both are non-Git, rejects control
  characters, and verifies both are physically disjoint from `RUN_WORKSPACE`
  and `RUN_RESULTS`.
- The adapter verifies and sets mode 0700 before use.
- Configuration and bridge files are mode 0600.
- The home contains no target checkout, writable report output, arbitrary user
  configuration, hook, project instruction, or unapproved plugin.
- The child has hooks disabled and only the required local bundled agent
  discovery.
- Authentication bridge material is ephemeral and never persisted.
- A `report-repair` home keeps hooks disabled, writes `memory: false` and
  `ide.autoConnect: false`, omits review-agent/subagent settings, and retains
  only the same narrow ephemeral authentication bridge.
- The repair home is fresh. It is never initialized by copying the analysis
  home and is never passed to `harness_persist_agent_state`.

Persistence requirements:

- Define a positive allowlist of files/directories needed for trusted
  continuation.
- Recreate directories at mode 0700 and files at mode 0600.
- Replace live configuration with sanitized configuration.
- Exclude tokens, cookies, keychain exports, auth bridge data, provider
  responses, caches, logs with secrets, hooks, arbitrary extensions, and
  unrelated runtime-home content.
- Saved session IDs are evidence for handoff, not permission to bypass the
  trusted Rhyolite runner.

Cleanup requirements:

- Delete or overwrite credential-bearing configuration before broad removal
  when possible.
- Use bounded retries and explicit paths.
- Be idempotent because normal flow and an exit trap may both call cleanup.
- Treat inability to sanitize/remove the home as a review failure with
  truthful state and handoff artifacts.
- Never report success while a secret-bearing runtime home remains.

Isolation verification occurs after stdout, stderr, and transcripts have been
sanitized. It must not inspect or emit unsanitized provider output. Generic
source/output/path isolation remains runner-owned; adapter verification adds
only harness-specific checks.

### Final report extraction

| Function | Signature and output | Required behavior |
| --- | --- | --- |
| `harness_extract_final_report` | Sanitized timeline path, sanitized transcript path, temporary final-message path, and destination report path. Status only. | Recover a candidate canonical report from the harness-specific final response and remove temporary extraction files. |
| `harness_extract_report_repair` | Sanitized repair stdout timeline, sanitized fresh repair transcript, and destination reply path. Status only. | Write only one raw compact confidence-edit reply, preferring pure JSON stdout and otherwise using only the latest assistant transcript reply. |

The runner first attempts extraction from sanitized stdout. The adapter
fallback runs only when stdout is absent or incomplete. It must:

- read sanitized artifacts only;
- select the final worker response deterministically;
- never restore redacted data;
- never treat tool chatter or earlier messages as the final response;
- write a candidate report, not declare it valid;
- leave canonical heading, closing delimiter, UTF-8, required-section, and
  scope-specific contract validation to the runner;
- fail nonzero when its transcript format cannot be recognized;
- remove temporary final-message files on success and failure.

A harness with a dedicated final-message file still implements this function.
Its capability may be `yes`, but the file remains untrusted and must pass the
same sanitization and canonical report validation.

Repair extraction is not report generation. The model may return only one
compact JSON object with exactly these keys:

```json
{"ProtocolVersion":1,"Section":"OVERALL ASSESSMENT","Field":"Confidence:","Occurrence":1,"OriginalValueSha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef","ConservativeLevel":"Low"}
```

The adapter performs only response selection. It must:

- prefer stdout only when the sanitized stdout is one pure JSON-looking
  descriptor and no surrounding prose or framing;
- otherwise select only the latest assistant reply from the fresh sanitized
  transcript;
- recognize Copilot CLI 1.0.91 assistant framing at `### Copilot`; stop before
  exact `### User`, `### Info`, `### System`, or `### Copilot`; backticked
  headings with optional status suffixes such as `### \`view\`` and
  `### \`view\` — Failed`; or named status headings such as
  `### task (Completed)`; and
  remove the trailing `---` plus linked GitHub Copilot CLI footer;
- reject user, tool, information, system, earlier-assistant, transcript-frame,
  fenced, or prose content as the response;
- write the selected reply as raw text without constructing or rewriting a
  report;
- fail nonzero with sanitized detail when the format is unsupported or no
  descriptor-like reply exists;
- remove partial reply files on failure.

Keep this boundary parser repair-only. Main final-report fallback must preserve
the historical last-`### Copilot`-through-EOF behavior; do not stop it at a
catch-all `### ` heading because canonical assistant reports may contain
internal headings such as `### Alert 1`.

The runner-owned output helper validates JSON syntax, the exact key set,
`ProtocolVersion=1`, `Field="Confidence:"`, occurrence/hash/level values, and
equality to the expected descriptor. It alone constructs the deterministic
candidate report and proves exact preservation before promotion.

### Repair policy and timeout

The runner permits one repair attempt. The effective repair timeout is:

```text
min(300, SessionTimeoutMinutes * 60)
```

Default scope timeouts therefore retain a 300-second repair maximum, while an
approved `--timeout-minutes 1` plan uses 60 seconds. The compact policy object
keeps exact key order:

```json
{"Mode":"isolated-confidence-edit","ProtocolVersion":1,"AttemptLimit":1,"TimeoutSeconds":60,"DeterministicNormalizations":["markdown-table-rows"]}
```

`DeterministicNormalizations` lists runner-owned, model-free corrections that
run before any repair invocation. Adapters never implement or receive them.

`TimeoutSeconds` is the effective returned bound, not a constant. The complete
policy object is approval-hash material and appears consistently in plan/run
state. Timeout selection and the timer remain runner-owned; do not add timeout
arguments to any harness API or hard-code 300 seconds in a repair-aware
timeout fixture.

## Capability and feature decisions

Before implementation, record a table for every capability with:

- the exact CLI behavior that proves `yes`;
- the reason for `no`;
- the unresolved evidence for `unverified`;
- the scope or guided-setup behavior affected;
- the negative test that proves unsupported behavior fails closed.

Do not use capability values as decorative metadata. They must gate behavior:

- `fleet`: whether native process-level fleet mode can be selected.
- `structured_questions`: whether the outer guided experience can use the
  required structured picker behavior.
- `subagents`: whether the worker can delegate to bundled specialists.
- `builtin_security_specialist`: whether the required security pass can run.
- `builtin_research_specialist`: whether research delegation is available
  where required.
- `web_research`: whether the harness can use the exact Rhyolite local broker
  contract for the dedicated research worker.
- `shell_denial`: whether child shell denial is enforceable; production
  requires `yes`.
- `final_message_file`: whether deterministic final output is available as a
  dedicated artifact.

If a capability changes the effective review, it must be resolved before plan
approval and either represented directly in approval-bound data or
deterministically implied by the approved harness and contract version.

## Plan schema 5 and approval hash

Contract v4 retains the Contract-v3 approved runtime selection and plan
schema 5. It includes these exact top-level fields:

```json
{
  "SchemaVersion": 5,
  "Harness": "copilot",
  "Provider": {
    "Id": "github-copilot",
    "Host": "managed-provider",
    "ForwardedEnvVarNames": [
      "COPILOT_GITHUB_TOKEN",
      "GH_TOKEN",
      "GITHUB_TOKEN"
    ]
  },
  "Model": "gpt-5.6-sol",
  "ModelCatalogMembership": "listed",
  "ReasoningEffort": "max",
  "ContextTier": "long_context"
}
```

The provider array shown above is abbreviated.

Requirements:

- Resolve and validate `Harness`, `Provider`, `Model`,
  `ModelCatalogMembership`, `ReasoningEffort`, and `ContextTier` before
  computing the plan. `ModelCatalogMembership` is `listed` for an exact
  offline-catalog member and `unlisted` only for an adapter status-3 ID
  accepted with explicit `--allow-unlisted-model`.
- Surface them in both JSON and text `EFFECTIVE REVIEW PLAN` output.
- Add them to approval-hash material field by field. Hash the harness ID,
  provider ID, provider host, every forwarded variable name with its stable
  index, model, model catalog membership, reasoning effort, and context tier.
  Never hash or serialize secret values. The opt-in flag alone must not change
  the hash of a listed model.
- Keep default Copilot and explicit `--harness copilot` plans byte-equivalent
  apart from ordinary non-hash timestamps, with the same approval hash.
- Any adapter, provider summary, forwarded-name order, model, model catalog
  membership, effort, or context change invalidates the approved plan.
- Plan-only mode may use only the local CLI help/config surface required to
  validate the model catalog; it does not prepare authentication.
- Actual execution re-resolves the metadata and refuses to run if it no longer
  matches the approved plan.
- Preserve all existing source, path, date-window, research-transport,
  concurrency, timeout, preference, and open-HTML hash material.

Do not use a display name, executable path, environment value, account name,
or runtime-home path as approval identity.

## State schema 6, manifests, and handoffs

Repository state, run state, manifest entries, and generated handoffs move
together to state schema 6. They must carry safe execution identity sufficient
to explain how the approved review ran:

```json
{
  "SchemaVersion": 6,
  "Harness": "copilot",
  "Provider": {
    "Id": "github-copilot",
    "Host": "managed-provider",
    "ForwardedEnvVarNames": [
      "COPILOT_GITHUB_TOKEN",
      "GH_TOKEN",
      "GITHUB_TOKEN"
    ]
  },
  "Model": "gpt-5.6-sol",
  "ReasoningEffort": "max",
  "ContextTier": "long_context"
}
```

Requirements:

- Use the same validated values as the approved plan; do not query the
  provider again while finalizing.
- Include the fields in success, failure, timeout, interruption, incomplete
  report, and cleanup-failure state.
- Propagate them through repository state, run state, manifest rollups,
  handoff prose, and any HTML summary that exposes execution identity.
- Never add secret values, token presence, account information, raw auth
  errors, or runtime-home paths to state.
- Update every schema validator and consumer at the same time. Do not accept
  mixed schema 5/6 output as success.

## Preference implications

Current launcher preference schema 3 stores a canonical repository, harness,
fleet mode, model, reasoning effort, context tier, and update time. Schemas 1
and 2 remain readable with `max`/`long_context` defaults; saved values are
reused only when the stored harness matches and the model remains available.

Before any second production harness can remember settings:

- keep preference identity harness-aware or disable remembering for that
  harness;
- never reuse a Copilot model/fleet preference for another harness;
- preserve the canonical harness ID in the stored and validated record;
- bump the preference schema again if its on-disk meaning or fields change;
- define migration or rejection behavior for old files;
- scope preference lookup so two harnesses cannot collide for one repository;
- keep `RememberPreferences` and all resulting behavior approval-bound;
- test malformed, mixed-harness, missing, stale, and symlinked preference
  files.

Do not silently reinterpret schema-1 files as generic cross-harness settings.
The development no-op fixture never reads or writes user preferences.

## Development-only no-op fixture

The no-op harness exists to prove that runner orchestration is generic without
claiming another production integration. Its adapter is
`tests/fixtures/harnesses/noop.sh`, and its deterministic worker is
`tests/fixtures/harnesses/noop-worker.sh`.

The focused validator copies the production plugin surfaces into an isolated
temporary tree, explicitly replaces only that copied tree's fixed registry
helper with a two-entry `copilot`/`noop` map, and invokes the copied runner
directly. Production `common.sh` continues to map exactly `copilot`.

The fixture should:

- use safe ID `noop`;
- report a clearly test-only display name and provider object;
- require no credentials and return an empty authentication list;
- use a deterministic fixture model and maximum effort token;
- expose truthful minimum capabilities;
- build deterministic argv and environment arrays;
- write only inside runner-supplied temporary/output paths;
- emit a complete deterministic canonical report without network access;
- create and clean a minimal runtime home;
- persist only explicit harmless fixture state, or explicitly persist
  nothing;
- verify its fixture isolation invariant;
- expose a distinct `report-repair` invocation mode that receives the request
  on stdin, extracts the one expected descriptor embedded in that trusted
  prompt, and returns that exact object by default;
- keep the repair workdir empty, write no source/research artifact, create no
  resumable fixture session state, and capture repair argv/environment/runtime
  inventory separately from the normal review worker;
- provide deterministic response controls for pure-stdout, transcript
  fallback, missing, user-only, system-only, info-only, backticked-tool,
  failed-tool, and task-status replies;
- support injected failures for every lifecycle function.

The fixture must not:

- be added to the production adapter map;
- be copied under `plugins/rhyolite`;
- appear in plugin or marketplace metadata;
- become a launcher choice;
- be accepted by production `--harness noop`;
- access Git, DNS, public research, credentials, the user's Copilot home, or
  the target repository outside the supplied read-only snapshot;
- survive public-release export.

Tests may stage a temporary plugin root with a fixed test registry that maps
`noop` to the fixture. That registry is test data, not a runtime extension
mechanism.

## Required negative tests

At minimum, add deterministic coverage for:

### Resolution and loading

- empty, unsafe, path-like, uppercase, whitespace, control-bearing, and
  overlength IDs;
- safe but unknown IDs;
- explicit CLI precedence over `RHYOLITE_HARNESS`;
- malformed, empty, and mismatched `RHYOLITE_LAUNCHER_HARNESS`;
- missing, unreadable, syntax-failing, wrong-ID, and incomplete adapters;
- production rejection of `noop`, `codex`, `claude`, and other unregistered
  IDs before output, CLI discovery, Git, DNS, or network activity;
- proof that no ID becomes a path and no fallback occurs.

### Metadata

- empty/control-bearing display and remediation text;
- invalid CLI names;
- invalid default and explicit model IDs;
- invalid or downgraded effort values;
- invalid capability values and unknown-capability behavior;
- empty-list handling and invalid/duplicate authentication names;
- malformed JSON, non-object JSON, missing/extra provider keys, invalid
  provider IDs/hosts, non-array forwarded names, duplicates, invalid names,
  secret values, and mismatch with the authentication list.

### Planning and schemas

- plan schema exactly 5 and state schema exactly 6;
- presence and exact capitalization of `Harness`, `Provider`, `Model`,
  `ReasoningEffort`, and `ContextTier`;
- provider fields and ordered forwarded names in approval-hash material;
- a one-field harness/provider/model/effort/context change causing plan-hash
  mismatch;
- default versus explicit Copilot equivalence;
- plan-only operation with no harness CLI and no authentication preparation;
- state/manifest/handoff values matching the approved plan on all terminal
  statuses;
- no secret values in plan, state, handoff, HTML, timeline, transcript, or
  errors.

### Lifecycle and isolation

- injected failure at every required function with the exact sanitized
  `harness <id> <function>` stage;
- argv and environment injection attempts;
- no shell evaluation of adapter output;
- runtime-home permissions and minimal contents;
- empty-auth no-op execution;
- persistence allowlist enforcement;
- normal cleanup, trap cleanup, repeated cleanup, and forced cleanup failure;
- no stale session ID when failure occurs before child launch;
- retained real session identity after a started worker fails;
- allow-all detection in the outer session and removal from the child;
- sanitized stdout, stderr, transcript, metadata, provider failure, and
  extraction fallback;
- timeout, interruption, incomplete report, and isolation-verification
  failure.
- exact zero-tool report-repair argv and normal-clearing environment vectors;
- fake authentication/provider values remaining inherited process environment
  while absent from repair argv, environment-data arrays, and timeout argv;
- default 300-second and one-minute/60-second repair-policy plans, including
  distinct approval identity for the effective bound;
- repair-phase settings and runtime inventory, including no persisted session
  state or copied analysis home;
- stdout precedence, latest-assistant transcript fallback, and rejection of
  user/tool/transcript text;
- injected repair-argv, repair-env, repair-extraction, and cleanup failures;
- cleanup success, idempotence, and promotion blocked on cleanup failure.

### Packaging and support boundaries

- plugin discovery still reports only supported production assets;
- public-release export excludes `tests/fixtures` and the no-op adapter;
- production help, README usage, launcher choices, and metadata remain
  Copilot-only until a real adapter is approved;
- no hosted CI or alternate-platform path is introduced.

## Required end-to-end tests

The focused validator must cover both production Copilot compatibility and the
generic seam:

1. Compare default and explicit Copilot selection.
2. Preserve Copilot worker argv and relevant environment exactly unless the
   approved change intentionally updates the golden contract.
3. Produce plan schema 5, state schema 6, and identical approved
   harness/provider/model/effort/context values through plan, execution, repository
   state, manifest, run state, handoff, and summary output.
4. Exercise the no-op fixture through a test-owned fixed registry from plan to
   deterministic canonical report, persistence, cleanup, state, and handoff.
5. Prove production `--harness noop` fails before side effects.
6. Exercise scope 1 with no research process or artifact.
7. For an adapter without required research capabilities, prove scope 2/3
   fails before broker/worker activity rather than degrading to scope 1.
8. Exercise every lifecycle failure stage with truthful artifact identity.
9. Verify sanitization with terminal controls, credentials, URL userinfo,
   authorization values, tokens, email addresses, and hostile transcript
   content.
10. Exercise one fresh, tool-less bounded repair, exact descriptor extraction,
    deterministic application, full report revalidation, and cleanup without
    resuming or persisting the repair session.
11. Run the full Fedora gate:

```bash
bash ./tests/validate-all.sh
```

## User documentation and release surfaces

While production remains Copilot-only:

- README and usage examples continue to identify GitHub Copilot as the only
  supported runtime harness.
- `docs/HARNESS-ARCHITECTURE.md` may describe the generic seam and target
  contract, but must label the no-op adapter development-only.
- `DEVELOPERS.md`, `AGENTS.md`, and this playbook expose contributor workflow.
- `CLAUDE.md` remains a contributor pointer and explicitly does not advertise
  Claude Code runtime support.
- Plugin, marketplace, command, launcher, help, support, publishing, version,
  and changelog surfaces do not list a second harness.

When a real production adapter is separately approved, review and update all
affected surfaces:

- launcher options, trusted context marker, agent setup, status/help, and
  direct-runner usage;
- README, developer guide, architecture, threat model, security/privacy
  statements, support guidance, and publishing instructions;
- plugin packaging and public-release allowlists;
- install and discovery tests;
- `VERSION`, `plugins/rhyolite/plugin.json`,
  `.github/plugin/marketplace.json`, and `CHANGELOG.md` for the release;
- the matching stable tag after local Fedora validation and public preflight.

Do not change version or release metadata merely to add internal test
fixtures.

## Forbidden shortcuts

- Dynamic adapter discovery, path interpolation, or environment-selected
  adapter files.
- Automatic fallback to Copilot.
- Registering an adapter with missing functions or `unverified` safety
  controls.
- Treating a CLI flag name as proof of a capability.
- Reusing Copilot argv, home, auth, extraction, or persistence behavior
  without proving it matches the new CLI.
- Command strings, `eval`, shell-escaped stdout, or repository-controlled
  arguments interpreted as code.
- Broad environment forwarding or copying an entire user runtime home.
- Provider summaries containing values, account identity, or token presence.
- Authentication, login, CLI discovery, Git, DNS, network, or output creation
  during plan-only resolution.
- Executing target code or using a selected local working tree.
- Granting child write/shell tools, inherited allow-all state, custom
  instructions, hooks, broad URLs, remote export, or temporary-directory
  access.
- Letting report repair use any tool grant, plugin, agent, MCP, skill,
  attachment, source snapshot, research artifact, analysis home, resume path,
  or complete-report rewrite.
- Scope downgrade, model substitution, effort downgrade, or research fallback
  without a new approved plan.
- Schema changes without synchronized writers, readers, fixtures,
  documentation, and tests.
- Reusing Copilot-only preferences for another harness.
- Packaging or documenting the no-op fixture as runtime support.
- Adding PowerShell parity, another broker runtime, alternate-platform
  branches, or hosted CI.
- Weakening exact validation wording or deleting negative tests to make an
  adapter pass.

## Evidence required for completion

An implementation is not complete until the change supplies:

- a fixed-registry diff and proof that all other IDs fail;
- the complete Contract-v4 function inventory for the adapter;
- a capability decision table with evidence;
- model, effort, authentication, and provider-summary examples;
- exact argv and environment captures;
- runtime-home and persisted-state file/permission inventories;
- exact report-repair argv/env vectors, repair-home inventory, raw descriptor
  extraction cases, and cleanup/failure evidence;
- plan schema 5 and state schema 6 examples;
- approval-hash tests showing every new field is bound;
- default/explicit selection equivalence;
- negative results for every failure class above;
- a no-op fixture end-to-end result plus production rejection of `noop`;
- Copilot compatibility results;
- package/export evidence showing test fixtures are absent;
- `git diff --check`;
- focused harness validation;
- the full `bash ./tests/validate-all.sh` result on Fedora Linux 44;
- plugin discovery and, when release surfaces change, install/public-release
  validation;
- synchronized documentation and release files appropriate to the actual
  support claim.

If any required evidence is missing, keep the adapter unregistered and
unsupported.
