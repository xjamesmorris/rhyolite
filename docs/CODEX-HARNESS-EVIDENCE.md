# Codex harness discovery evidence

## Status

Codex is not a supported production Rhyolite harness. Its adapter candidate
remains unregistered, with no production registry or root marketplace entry.

Initial discovery found no ordinary snapshot file-read or search tools in
the tested shell-free Codex configuration. Advertising those tools in a
local model catalog did not add them. On October 20, 2026 the maintainer
approved a separate offline snapshot-read MCP mode in the existing bundled
Python broker. Its runtime, bounded grants, negative tests, and shared
snapshot-transport seam (first numbered Contract v9 on the development branch,
now Contract v11 after the merge of the shipped refusal and compaction
contracts) are implemented on the development branch. On October 21,
credential-free probes captured the complete Codex inventory with that
transport and exercised its read/search and denial boundaries. The
same day's additional synthetic probes verified exact final-message bytes,
explicit-thread history restoration, and a fresh zero-tool session. These
are bounded interface proofs, not completed review/recovery/repair protocols.
A single maintainer-run authenticated call then returned the exact expected
reply without a timeout, rate limit, quota error, or reroute warning. An
unregistered adapter candidate now implements the Contract-v11 functions and
passes focused fixture validation plus an exact pinned-CLI snapshot integration.
The remaining live eligibility and product-integration gates are still
unverified.

This record describes Codex CLI 0.163.0 only. It does not establish the
behavior of another release, an internally configured provider, or a
completed Rhyolite review.

## Environment and provenance

- Fedora Linux 44, Linux x86-64, Node.js 22.22.2.
- Official `@openai/codex@0.163.0`, installed into a private probe directory,
  with install scripts disabled and package integrity verified. No global
  installation or user configuration was changed.
- Source tag `rust-v0.163.0`, resolved to commit
  `83086188ae0614bd882818ff1aa23f3194962012`. Inspected source blobs were
  checked against the pinned Git tree and Git blob hashes.
- Every execution used fresh synthetic `HOME` and `CODEX_HOME` directories,
  an explicit clean environment, and a local non-Git fixture directory.
- No credentials, real model service, or target-code execution were used.
  Scripted tool calls reached only synthetic fixtures through the bundled
  snapshot broker. Raw diagnostic files remain private; only normalized
  observations are recorded here.
- The one authenticated probe was executed separately by the maintainer from
  an already authenticated shell. Its saved summary contains no endpoint,
  credential, account, or raw provider error.

## Probe method

A fixed loopback HTTP fixture captured the CLI's outgoing Responses request.
Inventory-only probes supplied no model generation or tool calls. A later
scripted probe supplied synthetic Responses events to exercise actual CLI
tool routing, without invoking a model. Both methods deliberately returned
HTTP 503 after capture. Consequently, CLI exit status 1 was expected:
successful probe assertions do not mean that a model invocation or review
completed.

The invocation used `codex exec` with `--ignore-user-config`,
`--strict-config`, `--ignore-rules`, JSON output, the read-only sandbox, and
`approval_policy="never"`. Shell/unified execution, JavaScript execution,
agents, plugins, skill discovery, web search, plan updates, and questions
were disabled. The provider and model were synthetic fixture values.

The utility-exclusion, catalog, and snapshot cases additionally disabled
`features.goals` and `features.view_image`. The catalog case loaded a synthetic model with
`shell_type="disabled"`, no patch tool, and
`experimental_supported_tools` containing `read_file`, `grep_files`, and
`list_dir`. A unique instruction marker verified that the catalog was
actually loaded rather than silently ignored.

Snapshot probes configured only the fixed bundled stdio launcher, the four
exact broker tools, and runner-created grants for one read-only fixture
snapshot. Native `approval_mode="approve"` was set separately for each of
those four tools; global `approval_policy="never"` and the read-only sandbox
remained unchanged. Neither a server-wide nor a blanket approval grant was
used. The earlier per-tool value `auto` was accepted as configuration but
still denied these unannotated tools with an approval-required error.

The scripted probe made twelve calls: the four snapshot tools, resource
and resource-template listings, two resource-read denials, and four denied
reads covering traversal, an absolute private-fixture path, an unavailable
research grant, and an oversized byte limit. Every outgoing request retained
the same complete tool inventory and synthetic model/effort settings.
The snapshot instruction marker and private-fixture contents did not reach
the captured model context. The trusted Bash cleanup helper verified the
broker lifecycle and removed its transient runtime.

## Results

| Probe | Observed result | Meaning |
| --- | --- | --- |
| Version and help | Version 0.163.0; `exec`, explicit-session resume, plugin commands, JSON output, and final-message output were present. | Candidate interfaces exist; their full Rhyolite behavior remains unverified. |
| Invalid tool configuration | A boolean supplied where `tools.update_plan` requires an object was rejected before any request. The corrected form uses `tools.update_plan.enabled`. | Configuration types matter; a similarly named flag or setting is not evidence that a restriction is applied. |
| Shell-free inventory before utility-tool exclusions | `create_goal`, `get_goal`, `update_goal`, and `view_image`. | Shell tools were absent from this request, but the request was not tool-less and had no ordinary file-read/search tools. |
| Utility exclusions applied | Empty `tools` array; requested effort `xhigh`. | A zero-tool request can be constructed. This is not yet proof of the complete repair protocol or actual service-side model/effort identity. |
| Read-tool metadata alternative | Catalog marker present, but the `tools` array was still empty. | Catalog advertising did not provide a native snapshot reader. It is not a workaround for the missing interface. |
| Complete snapshot MCP inventory | Four functions in namespace `mcp__rhyolite_snapshot`, plus `list_mcp_resources`, `list_mcp_resource_templates`, and `read_mcp_resource`. | The complete inventory is seven tools, not only the four configured MCP functions. No shell, write, patch, agent, direct-web, or ordinary filesystem tool appeared. |
| Exact native tool grants | Per-tool `auto` denied invocation; per-tool `approve` allowed the four explicitly listed snapshot tools while global approval remained `never`. | Native preapproval must name each allowed tool; accepting a configuration value alone does not prove that the tool is usable. |
| Scripted snapshot operations | Capabilities, listing, reading, and literal search returned the expected synthetic fixture data. | The pinned CLI can route usable shell-free snapshot operations through the approved transport. |
| Resource-helper boundaries | Both listings were empty; reading a private fixture URI through the snapshot server returned method-not-found, and an unregistered server was rejected. | The automatic resource helpers did not provide an alternate filesystem reader in this configuration. |
| Denied snapshot arguments | Traversal and absolute paths, the absent research grant, and `maxBytes=262145` were rejected without revealing the private marker. | Broker runtime enforcement remains effective after Codex schema translation. |
| Model-facing schema translation | Codex omitted numeric bounds and string-length constraints from the outgoing tool schemas. | Do not claim byte-for-byte schema passthrough. The broker retains and enforces the approval-bound schemas and limits. |
| Exact final response | `--output-last-message` and the last JSON `agent_message` preserved the scripted UTF-8 text, indentation, numbering, table/fence text, trailing spaces, and absence of a final newline. An earlier commentary message was distinct. | Deterministic final-message interfaces exist; rendered stdout must not replace them. |
| Explicit native continuation | An exact UUID resumed with the same thread ID, retained the earlier fixture reply in the next request, and kept zero tools, requested model/effort, and read-only settings. | Native continuation is possible. Adapter-owned thread mapping, isolation verification, and live recovery remain required. |
| Fresh tool-less session | A separate synthetic home/thread exposed zero tools and did not inherit the earlier fixture context. | A fresh tool-less interface exists; the bounded confidence-edit protocol and live repair are not yet proven. |
| Hostile synthetic discovery | A synthetic user config selected another model, broad sandbox, and an extra MCP command; parent/current-directory instruction markers were also planted. Ignored configuration plus explicit restrictions retained the requested model, read-only sandbox, zero tools, and marker-free requests. | This covers those fixture paths only, not every plugin, hook, rule, memory, or managed-configuration surface. |
| Header-reported substitution | A different `OpenAI-Model` response header produced a native JSON error-item warning beginning `model rerouted:`, but the CLI still returned the reply and exit 0. The native turn context retained the requested model. | The adapter must reject this warning during live monitoring and post-exit validation; matching turn context or exit 0 is insufficient. |
| Body-only model difference | With no model header, a different response-body `model` produced no reroute warning in the tested native JSON/journal records, and the CLI returned the reply and exit 0. | Actual provider/model verification is still open. Do not infer backend identity from requested settings or a successful response. |
| Context override without model metadata | The neutral fixture model used fallback metadata; requesting a 1,000,000-token context still produced native token records reporting 258,400. | A configured context limit is not proof of the effective window or a backend's capacity. Verify model metadata and actual provider behavior independently. |
| Authenticated native smoke | Codex 0.163.0 exited 0, returned the exact requested reply, recorded the requested `gpt-5.6-sol` and `xhigh`, exposed no model-visible tool call, used zero client retries, emitted no reroute/rate/quota/timeout warning, and removed its temporary runtime. | Basic authenticated provider operation is proven. The summary explicitly does not claim backend identity, and this was not a review or maximum-settings test. |
| Bundled offline catalog | `codex debug models --bundled` lists `gpt-5.6-sol` with a 272,000-token default, an 872,000-token maximum override, 95% usable headroom, and efforts through `ultra`. | The CLI has an offline machine-readable catalog. The effective default/maximum usable windows are 258,400/828,400. |
| Delegation-safe maximum effort | With multi-agent disabled, requesting `ultra` produced wire effort `max`; requesting `max` preserved `max`, zero tools, known-model metadata, and an 828,400-token recorded usable window. | `max` is the strongest enforceable Rhyolite effort. The adapter rejects `ultra` because that catalog choice is coupled to automatic delegation. |
| Native local plugin and picker | A private local marketplace installed, listed, and removed an inert namespaced plugin. Its exact skill reached the model; with worktrees/daemon disabled, the normal Default-mode request exposed only `request_user_input`, rendered a finite native picker, returned the recommended answer, and exited cleanly. One separate zero-tool title request occurred. | Codex-native installation and structured normal-mode questions have viable interfaces. The production Rhyolite package/entrypoint is not yet implemented or tested. |
| Combined research inventory | Snapshot plus research configuration exposed exactly four snapshot functions, five research functions, and the three automatic resource helpers. Fourteen scripted calls exercised every function, both servers' resource-read denial, and an unknown server; invalid/disabled arguments caused no public retrieval. | The dedicated research worker can be constrained to the approved two-server inventory. A live successful public response and accepted dossier remain separate gates. |
| Adapter-built review integration | The unregistered adapter generated the isolated config, shell-free direct-MCP model catalog, argv, environment, snapshot grants, and exact per-tool approvals used by pinned Codex 0.163.0. The request exposed only the four snapshot functions plus three resource helpers, used `gpt-5.6-sol`/`max`, recorded 828,400 usable context, returned exact bytes, verified the session record, and removed the runtime. | Core review translation is implemented and tested without production registration or a real model call. |
| Authenticated adapter maximum-settings smoke | The maintainer ran the exact repository adapter from the authenticated shell. It used `gpt-5.6-sol`, `max`, 872,000 configured / 828,400 recorded usable context, read one synthetic snapshot file through the supervised broker, returned the exact expected reply, verified the native session, used zero client retries, emitted no reroute/rate/quota/timeout warning, and removed both runtime and private work tree. | Provider eligibility for the approved model, strongest delegation-safe effort, long-context configuration, snapshot routing, exact output, and graceful cleanup is proven for this bounded call. The summary still makes no independent backend-identity claim. |
| Supervised stdio lifecycle | Pinned source shows Codex terminates its MCP process group and escalates after two seconds. A direct child could be killed during the broker's atomic clean-exit write. The bundled Bash supervisor moves only the broker into a separate process group, preserves stdio, monitors the trusted runner PID/start time, and exits with the broker; a regression simulates client-group termination. | Normal Codex shutdown now permits exact clean-exit verification without allowing a detached broker to survive loss of its trusted runner owner. |
| Staged native setup/approval and controller | An unregistered Codex manifest contains only two setup skills. The setup skill collects output/scope/provenance/cookie choices through `request_user_input`; the approval skill returns only run/edit/explain/cancel. One Bash helper installs those assets into a private per-stage Codex home, validates the exact native session record and strict JSON result, then destroys the home. A pinned-CLI PTY probe installed the actual staged plugin, loaded the real setup skill, rendered two native pickers in Default mode with only `request_user_input`, selected output and scope, and verified the final setup JSON/session. A second Bash controller generates the authoritative plan, displays it, preserves setup across edit or date/hash rollover, owns execution, accepts exact `/rhyolite:status`, `stop`, and `cancel`, and uses only the runner's verified `--request-stop` path after the run folder exists. The shared launcher's Codex branch is tested only in a copied plugin whose fixed registry is modified for that fixture. | The recommended two-stage native setup plus Bash-owned execution design is implemented without shell/MCP runner authority. No root Codex marketplace manifest or production registry entry exists, so the branch remains unreachable in production. |
| Staged controller terminal handoff | On October 22, a connected controller/stage-helper PTY regression reproduced setup failure when the controller discarded helper stdout: the native CLI no longer had terminal stdout. The stage helper now routes native UI stdout to its terminal stderr, reserving helper stdout for the validated result path. A terminal-checking fixture CLI exercises both setup and approval, plan-hash execution, and per-stage runtime removal with controller stdout captured separately. | This closes the deterministic terminal-descriptor handoff regression. The fixture is not a real Codex CLI or an authenticated staged controller review. |
| Current native API-key readiness | On October 23 (UTC), the installed 0.163.0 CLI was verified and the supplied credential was compared locally with its saved API-key-only login without displaying either value. A fresh owner-only runtime with only that API-key credential passed native login-status inspection, recorded the requested `gpt-5.6-sol`/`max` and 828,400-token usable context, and made no tool calls, but the actual model request returned HTTP 401 from the native default OpenAI endpoint. Local effective-config inspection found no selected custom provider or Azure endpoint. A subsequent metadata-only capture from the working terminal confirmed the same native-default provider and no API-key environment variables or routing overrides. Transient credentials and raw output were removed. | Local credential loading is proven; current backend authorization is not. This does not invalidate the earlier explicitly configured-provider smoke, establish a bad key, or justify guessing another endpoint. Establish the intended provider and successful backend authorization before another live gate; another context capture is not required. |
| Contract-v11 outcome classification | On October 27, the merged branch moved the candidate to Contract v11 and outcome schema 3. Pinned 0.163.0 source fixes the evidence: exec JSON reports a reroute only as `model rerouted: FROM -> TO (REASON)`, whose only reason is `HighRiskCyberActivity`; a `response.incomplete` with reason `content_filter` surfaces as the fixed message `stream disconnected before completion: Incomplete response returned, reason: content_filter`; cyber, bio, and misalignment policy errors fall back to fixed messages and HTTP 400 bodies keep their error code; error events are never written to the session rollout; and the rollout records `token_count` usage per response plus one `compacted` record per compaction window. Synthetic fixtures cover a refusal reroute, a content-filter turn, a policy fallback, a transient 429 retry-limit failure, a quota failure, prompt budget and peak, and deduplicated compactions. | A refusal of the approved model is `refused`, detected live and after exit, never retried, and its fallback output is never accepted. A policy message worded by the server without those forms stays an ordinary failure. This is pinned-source and fixture evidence, not a live refusal. |
| Contract-v11 authenticated adapter smoke | On October 27, the maintainer ran the exact adapter at the Contract-v11 merge (`adf5ec9`) against an explicitly configured provider: `gpt-5.6-sol`, `max`, long context, one snapshot read through the supervised broker, exact reply bytes, a verified native session, zero client retries, no reroute, rate-limit, quota, or timeout signal, and clean broker and runtime teardown. The outcome-schema-3 classifier reported `completed` with an 828,400-token prompt budget, a 21,651-token largest prompt, no compactions, and no refusals. | The outcome classifier works on a real session record, and the explicitly configured provider resolves the earlier HTTP 401 from the native default endpoint. Backend identity is still not independently claimed. |
| First live guided setup | The same evening, the real native setup stage ran with an inert runner and failed at the guided controller; the run kept no diagnostic. Pinned source shows that an interactive session persists every completed turn item, including the model's `Reasoning` items, while the stage validator accepted only user and agent messages, which a real model at maximum effort cannot satisfy; synthetic probes produced no reasoning items. The validator now also accepts `Reasoning` and `FunctionCallOutput` items, still rejects every other item and tool call, names the failed check, and records it beside the stage result. | The cause is inferred from pinned source, not observed. The live guided gate stays open until a rerun passes. |
| Live guided setup rerun | Later on October 27, the rerun at `e0fef33`, whose only change was the corrected validator, passed: the native plugin installed into a private stage home, the real setup and approval skills completed with `gpt-5.6-sol` at `max`, both strict JSON results validated, and the Bash controller generated the plan and invoked the inert runner exactly twice, with `--harness codex`, one security scan, scope 1, and the approved hash. | The live staged native setup and approval gate passes, and the pass with only the validator change supports the inferred cause. No repository review or research ran. |
| First live scope-1 review | Late on October 27, the first real scope-1 review through a private test-owned registry, at `3894b1c`, failed about one second after its repository started, before the worker launched. The runner builds every worker's argv before it creates that worker's runtime home, but the Codex review argv wrote its instruction bundle into the not-yet-prepared home and so tried to write at the filesystem root; the research argv had the same defect. Every earlier probe and fixture had called the adapter with the home prepared first. The argv functions now only record the trusted instruction sources, runtime-home preparation writes the bundle and names it as `model_instructions_file` in that home's `config.toml` (pinned source reads the key from the same configuration as a `-c` override), and the worker environment fails closed when the current home has no instructions. A new mocked end-to-end test drives the real runner through the adapter with a fake Codex worker that starts the real snapshot broker from the adapter-built arguments; it reproduced the live failure at `3894b1c` and passes with the fix. It also found the exact final-message file left unsanitized in the run output, which the normalizer now removes after reading it. | The failure is observed, and the fixed path is proven with the real runner and broker but a fake Codex worker. No model request was made. The live scope-1 review gate stays open until a rerun passes. |
| Live scope-1 review rerun | On October 28, the rerun at `b6a5d9f` completed in about three and a half minutes against the pinned commit of a one-file public repository: anonymous preflight and exact-commit clone, `gpt-5.6-sol` at `max` with long context, one native session whose single recorded turn matched the approved model, effort, read-only sandbox, and 828,400-token usable window, and no reroute, refusal, error, or subagent; the turn's 120,464 input tokens stayed far below the 784,800-token compaction limit. The worker used only the snapshot tools: capabilities, two listings (the broker rejected a `.` path, and the model retried with the empty root path), and one complete read. The canonical report passed strict validation without repair or recovery and keeps the scope-1 sections only, the dedicated security pass with its defect checklist, and confidence with evidence basis throughout. State, manifest, handoff, and HTML agree; the run output holds no final-message file, credential-shaped value, or email address; and no runtime home, broker root, or lock remained. | The live scope-1 review gate passes. Requested and natively recorded identity match; backend identity is still not independently attested. |
| Scope 2/3 dossier access | Before any research-enabled Codex review, inspection found that the review prompt, the shared review skill, both review-worker agents, and the runner's research transport instructions told the main worker to read the dossier and network summary by path and to call no MCP tool. An offline-transport worker reads everything, including both research files, only through the snapshot MCP tools. The shared texts now forbid only MCP tools other than the harness-supplied read-only snapshot tools and defer dossier access to the transport instructions, which for an offline transport name grants `research-dossier` and `research-network-summary`; native transports keep their path instructions word for word. | This is an offline correction with regressions; no live research-enabled review has run yet. |
| First live scope-2 review | On October 28, the first live scope-2 review at `b928055` failed about two seconds after its snapshot was prepared, before the research worker launched, so no model request was made. The runner passes the broker's compact policy tool list (`["research_capabilities","fetch_public_url",...]`), but the Codex research argv rebuilt the list with `", "` separators and compared the two as exact strings; its unit fixture used the spaced form. The adapter now compares the lists without JSON whitespace, every argv guard names the check that failed, and the unit fixture takes the tool list from the broker's own policy description. The mocked end-to-end test now also runs scope 2: the adapter-built research worker starts with its own instructions, both real brokers serve their exact tool lists, the research broker records a real capability check, and the fixture worker then stops, so the run must end as a research-worker failure with clean broker and runtime teardown. That test reproduced the live failure at `b928055`. The runner also reported a missing broker lifecycle exit and a cleanup failure, its existing fail-closed response when no broker exit record exists, which follows any research failure before launch. | The failure is observed and the research launch path is proven offline with both real brokers and a fake Codex worker. Live research, dossier acceptance, and the research-enabled review remain unverified until a scope-2 rerun passes. |
| Live scope-2 reruns | On October 28, two scope-2 reruns at `249ecc5` ran research live. In the first, the provider reported high demand 25 seconds into research, and a stream disconnect with a server error ended the single approved relaunch after about 32 minutes. The adapter then configured zero client retries, so each error ended its attempt, and research failed after its one relaunch; pinned 0.163.0 source classifies both errors as retryable. In the second, research completed: 94 broker requests, 81 successful public responses, 25 cookies observed and none replayed, and the broker accepted the 45,792-byte dossier on its first submission. The runner's transport validation then failed closed because a date-valued cookie's value appeared inside another site's same-day `Expires` attribute, which the sanitized event ledger records by design; no cookie value was exposed. With only that check relaxed, every other validation of the real bundle passed. | Live Codex research, broker retrieval, and dossier acceptance are proven. The research-enabled review has not run yet. |
| Cookie attribute coincidences | Research validation now recomputes each cookie event's published attributes from its own private `Set-Cookie` header, requires an exact match, skips only those verified attributes in the raw-value scan, and still fails when an attribute contains a value from its own header. The dossier, the network summary, and every other event field are still scanned. The real second-rerun bundle now validates, and tampered copies of it fail with an attribute mismatch or an escape. Mock regressions cover the coincidence, a tampered attribute, and a cookie value inside its own attribute. The check is shared by every harness. | Offline correction, proven on the real bundle and on synthetic bundles. |
| Codex built-in retries | The adapter now keeps Codex's own bounded retries: 4 request and 5 stream retries, the 0.163.0 defaults. Pinned source shows that a stream retry re-sends the same request within the same turn and announces it as a top-level `Reconnecting... n/max` error event; WebSocket transport stays disabled, so every retry is announced. The live monitor ignores a plain retry notice, the outcome counts it as `TurnRetries` instead of a failed turn, and normalization accepts a turn that completed after retries. A retry notice that carries a refusal still stops the worker and classifies the session as `refused`, so no later output is accepted. Codex also retries content-filter stops, so it may re-send one request to the same model before the monitor stops the worker. | Pinned-source and fixture evidence, including a retried turn through the full runner; a live retried turn has not been observed yet. |
| Live scope-2 review | On October 28, the rerun at `48ff65a` completed in about 14 minutes against the pinned commit. Research completed in one attempt of about 11 minutes: 85 broker requests, 75 successful public responses, 39 cookies observed and none accepted or sent, and the 35,248-byte dossier accepted on its first submission; the cookie attribute verification passed for all 39 cookie events. The review session, one native turn on `gpt-5.6-sol` at `max` in the read-only sandbox, read the dossier through grant `research-dossier` in eight pages, the network summary through `research-network-summary`, and the snapshot. The canonical report passed strict validation without repair or recovery and contains every scope-2 section, from the research source landscape through the prior-art assessment, and no provenance section. No retry notice, refusal, or error occurred. The run output held no final-message file, credential-shaped value, or email address, and no runtime home, broker root, or lock remained. | The live scope-2 review gate passes, including live research, dossier acceptance, and offline-transport dossier access. Codex's built-in retries were not needed. Requested and natively recorded identity match; backend identity is still not independently attested. |
| Report repair end to end | The mocked end-to-end test now drives a real confidence edit. The review returns the compound confidence value of an earlier production incident, which no deterministic normalization accepts, so the runner hands it to a fresh `--ephemeral` Codex session with no MCP server, no worker instructions, and an empty working directory. That session returns the exact expected descriptor, and the edited report passes unchanged strict validation with `ReportRepair` `Succeeded`. | Fixture evidence through the real runner; no live Codex review has needed a repair yet. |
| Live scope-3 review | On October 28, the scope-3 run at `66df7d5` completed in about 18 minutes against the pinned commit, with a six-month provenance window. Research completed in one attempt of about 14.5 minutes: 119 broker requests, 104 successful public responses, 30 cookies observed and none accepted or sent, and the 49,324-byte dossier accepted on its second submission within the three-attempt limit. The provider rejected six research requests for its token rate limit; Codex's built-in retries absorbed all six, and one request succeeded only on its fifth and final retry. The review, one native turn on `gpt-5.6-sol` at `max` in the read-only sandbox, read the dossier through its grant in six pages, the network summary, and the snapshot. The canonical report passed strict validation without repair or recovery and contains every scope-3 section, including both provenance assessments: no direct model, effort, or harness attribution, no heuristic model candidate, heuristic confidence `Not applicable`, full asset and window coverage, and alternative explanations. No refusal or error occurred, and the hygiene checks matched scope 2. | The live scope-3 review gate passes, and Codex's built-in retries are observed live. The provider's token rate limit nearly exhausted one request's retries; that is an operating capacity limit of the configured deployment, not an adapter defect. |
| Offline continuation mechanics | On October 28, a two-turn probe ran the exact adapter flow with the real Codex 0.163.0 CLI against a local mock Responses endpoint, a fixture provider, and no credentials: worker argv, runtime home, environment, snapshot transport, then a resume with the argv from `harness_worker_continuation_argv`, which differs from the approved argv only by `resume` and the native thread ID. The first attempt exposed a defect: Codex restarts every required MCP server when it resumes a session, and the snapshot broker refused a second lifecycle in the same runtime root because its process-identity record survived the first exit, so the resumed session failed before any model request. The broker now permits a later lifecycle only after the previous one recorded a clean exit, retiring the old records first, and the runner waits up to 30 seconds for the previous broker before each continuation. With that fix the probe passed: the resumed request carried the first turn's history and an identical tool inventory, the same native thread continued in a single rollout file with two `gpt-5.6-sol`/`max` read-only turns, adapter session verification passed after the continuation, and the broker exited cleanly after both lifecycles. | The adapter-built continuation mechanics are proven with the pinned CLI and no model. `worker_continuation` stays `unverified` until the live probe proves context retention with the real model and provider. |

Confidence is **High** for the captured pinned-CLI request inventories and
configuration results: they came from the pinned executable, not a model's
description of its tools. Adapter fixture validation and the terminal-handoff
regression are separately labeled and do not establish live CLI behavior.
No conclusion is claimed for untested versions or unrecorded provider behavior.

## Source cross-check

At the pinned commit:

- `codex-rs/core/src/tools/spec_plan.rs:1245-1291` gates shell-tool
  registration on the shell feature and model metadata.
- `codex-rs/core/src/tools/spec_plan.rs:1307-1452` handles utility tools and
  selected metadata-driven tools; it does not register the advertised
  `read_file`, `grep_files`, or `list_dir` names.
- `codex-rs/core/src/tools/handlers/mod.rs:1-37` lists the core handlers and
  has no ordinary file-read/search handler corresponding to those names.
- `codex-rs/core/src/mcp_tool_call.rs` applies the native per-tool approval
  policy before dispatching an MCP call.
- `codex-rs/core/src/tools/handlers/mcp_resource.rs` and its
  `read_mcp_resource.rs` child route resource operations through configured
  MCP servers rather than reading local filesystem URIs directly.
- `codex-rs/rmcp-client/src/stdio_server_launcher.rs` sends `SIGTERM` to the
  owned MCP process group and escalates to a kill after two seconds.
- `codex-rs/protocol/src/protocol.rs` defines `HighRiskCyberActivity` as the
  only `ModelRerouteReason`; `codex-rs/exec/src/event_processor_with_jsonl_output.rs`
  renders a reroute as an `error` item and drops structured error information
  from exec JSON.
- `codex-rs/codex-api/src/sse/responses.rs`, `sse/responses_error.rs`, and
  `api_bridge.rs` map content-filter, cyber, bio, and misalignment refusals;
  `codex-rs/protocol/src/error.rs` fixes their messages.
- `codex-rs/rollout/src/policy.rs` keeps `token_count`, `compacted`, and turn
  context records, omits error events from the rollout, and in paginated
  history persists every completed turn item; `codex-rs/protocol/src/items.rs`
  defines those item types, including `Reasoning`.

Official source references:

- `https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/spec_plan.rs`
- `https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/mod.rs`
- `https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/mcp_tool_call.rs`
- `https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/mcp_resource/read_mcp_resource.rs`
- `https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/rmcp-client/src/stdio_server_launcher.rs`

## Approved snapshot transport and remaining gates

Do not enable shell commands as a substitute for snapshot reads, introduce
an unapproved broker/runtime, or register a partial harness.

The selected interface is specified in
[SNAPSHOT-TRANSPORT.md](SNAPSHOT-TRANSPORT.md). It reuses the bundled broker
in a distinct offline mode with bounded listing, reading, and literal
search, no resource/prompt/network authority, and runner-owned phase grants
and cleanup. Scope 1 remains research-free and repair remains zero-tool.
Automated tests cover traversal/symlink/hard-link/special-file rejection,
malformed and oversized MCP framing, strict manifests, private grant
boundaries, pagination/budgets, minimal environment, and verified process
cleanup. Copilot and Claude Code retain native reads.

The complete model-visible snapshot inventory, including automatic
MCP-resource helpers, and the scripted boundaries above have been captured
offline. This resolves the initial shell-free snapshot-access prerequisite
for the pinned CLI and tested configuration only. It does not prove
research-phase integration, broader hostile-configuration isolation, native
installation/setup, live provider operation, or actual model/effort/context.

Exact bytes, native UUID continuation, a fresh zero-tool reply, native local
plugin/picker behavior, combined MCP boundaries, and the adapter-built review
path are proven with synthetic events. Both a basic native call and the exact
adapter-built `max`/long-context snapshot smoke passed under authentication,
the smoke again at Contract v11.
Complete hostile configuration isolation, adapter-built live
continuation/recovery, a live report repair, and the stop/timeout lifecycle
remain unverified. Live public research with an accepted dossier and live
reviews in all three scopes are now proven. The
first live guided run failed at the stage validator; the rerun with the
corrected validator passed the real staged native setup, approval, and
controller path.
The first live scope-1 review failed before its worker launched because the
adapter built worker arguments that depended on a runtime home the runner
had not yet created; after that fix, the live rerun passed. The first live
scope-2 review failed before its research worker launched because of a
tool-list format comparison in the adapter; that is fixed and covered by an
end-to-end research-launch test. Two later scope-2 reruns proved live
research and dossier acceptance; one failed on provider errors without
client retries and the other on a cookie false positive in the shared
research validation, and both causes are now fixed. The rerun with those
fixes passed the live scope-2 review, and the scope-3 review then passed
live as well, with Codex's built-in retries absorbing six provider
rate-limit rejections during research.
The earlier HTTP 401 came from the native default endpoint; with the
explicitly configured provider, the adapter smoke passed. Do not substitute
an endpoint or authentication method.
Production enablement still requires the complete
[harness playbook](ADDING-A-HARNESS.md), automated coverage, real-run
evidence, and Fedora validation.
