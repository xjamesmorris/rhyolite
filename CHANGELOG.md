# Changelog

## Unreleased

- Changed the recommended GitHub Copilot CLI review model to `gpt-6-astra`.
  The launcher and the Copilot setup questions now offer `claude-opus-5.5`
  and then `claude-fable-5.1` as the alternates, replacing `gpt-5.6-sol` and
  `claude-fable-5`. Saved model preferences are unchanged, and Claude Code
  keeps `claude-opus-5-5` with `claude-opus-5` as its alternate. The
  launcher now builds each harness's model menu from its own ordered list.
  Prompts and documentation name GPT-6 Astra, Claude Opus 5.5, and Claude
  Fable 5.1 as current frontier-model examples.
- Fixed a complete review being discarded when the worker wrapped a required
  assessment field label across two lines. The longest label,
  `Source/docs/commit/ref metadata poisoning and dataset/benchmark poisoning:`,
  is 74 characters, so a worker wrapping near 72 columns split it, strict
  validation reported the label missing, and no repair applied.
- Added approval-bound, model-free `wrapped-field-labels` normalization to
  `ReportRepairPolicy.DeterministicNormalizations`. When strict validation
  reports a missing required assessment field label that is wrapped exactly
  once across one line break at a space inside its own section, and is not
  also present intact there, the runner rejoins the two lines, keeps every
  word, and revalidates. A split inside a word, at a hyphen or slash, or
  outside the label's section stays ineligible and now fails with that
  reason. `ReportRepair` state adds `LabelNormalization` and
  `LabelsRejoined`. Each normalization runs at most once in the order strict
  revalidation reports its diagnostic, so a confidence-delimiter error in an
  earlier section no longer hides a wrapped label in a later one. The policy
  object is approval-hash material, so plans generated before this change
  must be regenerated.
- The worker request, its self-check, and the worker agents now say that a
  heading or field label is never wrapped or hyphenated, even past the wrap
  width.

## 0.8.0 - 2026-10-08

- Added Claude Code as a second production review harness. Use
  `rhyolite --harness claude`, or `--harness claude` with the direct runner,
  to run the guided setup, plan approval, scopes 1-3 with dedicated research,
  report repair, and the usual artifacts through Claude Code (validated with
  2.1.292). The default model is `claude-opus-5-5` and the guided alternate is
  `claude-opus-5`; Rhyolite keeps its own offline Claude Code model list
  because Claude Code has no local catalog. The plugin now ships a Claude Code
  manifest and marketplace registry: run
  `claude plugin marketplace add https://github.com/xjamesmorris/rhyolite`
  and `claude plugin install rhyolite@rhyolite-tools`.
- Claude Code workers run `claude -p --restricted` with only `Read`, `Glob`,
  and `Grep`, plus the five local broker tools for research. Repository
  `CLAUDE.md`, `AGENTS.md`, and `.claude/` files, hooks, memory, slash
  commands, and subagents are disabled. A review fails closed when the
  session record shows a model or effort other than the approved one,
  including a Claude Code safeguard handover to another model, or a subagent
  turn. Workers raise the per-response output limit to the model's maximum,
  and a reply that Claude Code still resumes after the limit is joined with
  disclosed separators before strict validation.
- When no supported Claude Code authentication variable is set, each Claude
  Code worker receives a private copy of `.credentials.json` in its temporary
  runtime home. The copy is deleted with that home and never persisted.
  Exporting `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` avoids the copy.
- Harness Contract v5 moves the dedicated scope 2/3 research worker behind
  four adapter functions and gates scope 2/3 on each adapter's `web_research`
  capability. The Copilot research worker command is unchanged.
- Added approval-bound, model-free `confidence-level-delimiters`
  normalization to `ReportRepairPolicy.DeterministicNormalizations`. When an
  assessment `Confidence:` value has one level directly followed by
  explanatory words, the runner inserts the accepted ` - ` delimiter, keeps
  every word, and revalidates before any model edit. The policy object is
  approval-hash material, so plans generated before this change must be
  regenerated.
- The runner now retries a blob-filtered clone checkout twice when the host
  transiently refuses the anonymous lazy fetch, and explains an
  authentication challenge plainly instead of Git's password prompt error.
- Help and `status` output now include a `Harness:` line for both harnesses.
- The bug report form asks which review harness ran the review.

- Added an explicit `--allow-unlisted-model` option to the launcher and the
  direct runner. Rhyolite validates models against the list printed by
  `copilot help config`, which is built into the CLI and can omit models
  that an account can use. With the option, a safe model ID outside that
  offline catalog is accepted, `auto` is always rejected, and the effective
  plan binds the new `ModelCatalogMembership` field (`listed` or `unlisted`)
  into approval. Copilot checks availability when the review starts, and an
  unavailable model fails the review without substituting another model.
  Copilot may still run the launcher's interactive setup session on its
  default model in that case. The trusted launcher block carries
  `AllowUnlistedModel=true` only when the option is used.
- Added a `model availability` failure stage with model-specific
  remediation. It replaces sign-in guidance when Copilot rejects the approved
  model as unavailable.
- Corrected documentation that described `copilot help config` as Copilot's
  live model catalog.
- Simplified the end-of-run summary to one path: the run output folder,
  which contains the HTML index, every report, and the other run artifacts.
  The runner no longer prints the workspace, plan, manifest, state, handoff,
  and HTML index paths at the end of a run, and the agent shows only that
  folder after `RHYOLITE EXECUTIVE SUMMARY`. The agent finds each canonical
  report through the folder's `manifest.json`. Failure blocks still name the
  affected repository's state, errors, and timeline files.

## 0.7.0 - 2026-10-07

- Fixed completed reviews that failed at report finalization when the review
  worker copied the Copilot CLI security-review summary table into
  `FINDINGS`. The review prompt, worker agent, and skill now keep that
  caller-contract table, with its severity emoji and numeric scores, out of
  the canonical report and require plain-text numbered findings instead.
- Added approval-bound, model-free Markdown-table normalization as
  `ReportRepairPolicy.DeterministicNormalizations` value
  `markdown-table-rows`. When strict validation rejects table syntax, the
  trusted runner converts each well-formed table outside the field-validated
  assessment sections into labeled plain-text rows, keeps every cell
  verbatim, and changes no other line. Malformed, field-section, or
  action-menu tables stay ineligible. The normalized candidate must pass the
  unchanged strict validator, or it becomes the input to the one bounded
  confidence edit. `ReportRepair` state adds `TableNormalization`,
  `TablesConverted`, and normalized candidate/diagnostic artifacts; plan
  schema 5 and state schema 6 are unchanged.
- Corrected the report-repair eligibility diagnostic for non-contract
  failures, which previously claimed that the rejected report already
  satisfied strict validation.
- Fixed an interruption race in which the run-level `state.json` could be
  finalized while a repository process was still writing its own
  `Interrupted` state, which could produce invalid JSON or a stale
  `ReportRepair` status. After an interrupt, the runner now waits for each
  tracked repository process to exit before writing run-level artifacts; a
  second interrupt still escalates to a forced stop.
- Restored first-class prior-art, originality, and community coverage from
  the original review contract. Every report now requires exact
  `CLAIMS AND REPUTATION INTEGRITY ASSESSMENT` and
  `COMMUNITY HEALTH ASSESSMENT` sections; scope 1 derives them only from the
  snapshot and wrapper Git metadata and states that external corroboration
  was not requested. Scopes 2/3 add `PRIOR ART AND ORIGINALITY ASSESSMENT`,
  and scope 3 adds `CODE AND ARCHITECTURE PROVENANCE ASSESSMENT` for code and
  architecture lineage, license and attribution consistency, and chronology.
  Each section has exact labeled fields plus confidence and evidence basis.
  Strict validation rejects missing, duplicated, out-of-order, or
  out-of-scope sections and missing, duplicated, or empty fields.
- Added claims and reputation coverage that supports reviewer triage, such
  as conference program-committee review of proposals and projects. It
  compares capability, maturity, security, and roadmap claims with the
  implementation and covers conference, CFP, proposal, and paper-submission
  indicators with local commit chronology; media, endorsement, award, and
  affiliation claims; adoption and engagement authenticity;
  reputation-building pattern indicators; and supply-chain precursor
  indicators, which are risk indicators, never findings of intent. When such
  concerns exist, the executive summary begins with one advisory triage
  sentence. The scope-3 generation assessment now explicitly covers every
  tracked asset, including documentation and proposal, pitch, CFP, and paper
  material, with unchanged heading, fields, and verdicts. The README
  documents conference and CFP review triage by scope.
- Added required `COMMUNITY HEALTH EVIDENCE`, `CLAIM VERIFICATION EVIDENCE`,
  and `PRIOR ART AND LINEAGE EVIDENCE` research-dossier sections for scopes
  2/3. Community-health evidence may use anonymous public GitHub REST
  metadata through the existing broker `fetch_public_url` tool within
  existing budgets; the broker, providers, and research policy are
  unchanged.
- Extended the bounded confidence edit to the new assessment sections, gated
  by the approved scope. Missing, duplicated, or empty labels and tables in
  assessment sections still fail explicitly.
- Added safeguards: these assessments evaluate claims, artifacts, and
  aggregate public signals, never a person's character or intent; use
  neutral terms; never research or characterize named individuals quoted in
  endorsements; report engagement and contributor data only as counts and
  date distributions; and require human review before external sharing.
  Plan schema 5 and state schema 6 are unchanged.

## 0.6.1 - 2026-10-06

- First tagged 0.6.x release. It includes the untagged 0.6.0 changes below.
- Fixed completed reviews that failed at report finalization because of an
  eligible malformed `Confidence:` value. The trusted runner now stages
  extracted reports as noncanonical candidates and may make one fresh,
  tool-less report-repair attempt, bounded to at most 300 seconds and capped
  by the session timeout, under the already-approved harness, provider,
  model, reasoning effort, and context tier. Research is never rerun or
  exposed to repair.
- The repair child returns only an exact JSON edit descriptor. The runner
  checks it against the original section, occurrence, value hash, and lowest
  explicitly stated confidence level, keeps the original confidence detail
  verbatim, and changes no other report bytes. The unchanged strict validator
  must accept the candidate before canonical promotion. Unsupported errors,
  invalid descriptors, failed revalidation, timeout, interruption, and
  cleanup failure remain explicit failures with truthful state.
- Added the fixed `ReportRepairPolicy` to the effective review plan and its
  approval hash, plus an additive `ReportRepair` object across repository
  state, manifest entries, run-state repositories, handoffs, and the HTML
  index. Candidates, diagnostics, and repair transcripts stay under a
  private noncanonical `report-repair/` directory, and `RHYOLITE PROGRESS`
  distinguishes validation, repair, and revalidation or exhaustion.
- Advanced the harness contract to version 4 with required report-repair
  argv, environment, and reply-extraction functions. Plan schema 5 and state
  schema 6 are unchanged. The repair child uses a fresh, isolated Copilot
  home with hooks, memory, custom instructions, skills, MCP, and
  model-visible tools disabled.
- Clarified the single-level `Confidence:` grammar in the review prompt and
  added report-repair regression coverage to the aggregate validation gate.

## 0.6.0 - 2026-10-05

- Consolidated canonical Bash launcher-state resolution, report/dossier
  extraction, and streaming output sanitization without changing safety
  boundaries, artifact schemas, or supported runtime behavior. Added focused
  regression coverage for extraction failures, control/redaction handling,
  and state-path resolution.
- Expanded Linux installation tests to verify the complete packaged payload,
  Git-free marketplace installation, prior-version manual updates, installed
  launcher/helper behavior through symlinked paths with spaces, and
  fail-closed malformed, incomplete, corrupted, or unsupported packages.
  Fixture configuration and state remain isolated from the user's Copilot
  installation.
- Preserved selected terminal `.git` endpoints as canonical source identity.
  Anonymous pinned-TLS Git discovery may follow at most three explicit
  same-origin HTTPS 301 hops without replacing the approved source or
  weakening credential, redirect, or DNS isolation.
- Added a temporary visible `Beta` suffix to user-facing `vX.Y.Z` displays
  while keeping `VERSION` and JSON version fields at machine semver `X.Y.Z`,
  stable tags at `vX.Y.Z`, and approval data bound to independent plan/state
  schema versions.
- Repositioned Rhyolite as an open-source software analysis platform with
  `repo-review` as its initial/default and currently only shipped module,
  while preserving this release as a GitHub Copilot plugin with Copilot-only
  production harness support.
- Made successful completion terminal and review-only: Rhyolite now reads the
  trusted report, prints `RHYOLITE EXECUTIVE SUMMARY`, lists artifacts
  including the HTML index, and ends without retrieval/opening questions or
  offers to modify the reviewed repository. The runner now defaults
  `OpenHtmlPolicy` to `never`; only explicit direct-runner `--open-html` may
  open the index, and allow-all state no longer affects opening.
- Validated every selected review model against the live model catalog exposed
  by the installed Copilot CLI. The launcher and guided setup can list exact
  available IDs, including `gpt-6-sol` when present, and runtime agent
  frontmatter no longer overrides the validated CLI model.
- Added approval-bound reasoning-effort and context-tier selection with
  explicit confirmation/modification flows. Model, effort, and context now
  propagate through launcher preferences, plan hashes, workers, nested-agent
  settings, state, manifests, and handoffs.
- Advanced the harness contract to version 3, plan schema to 5, state schema
  to 6, and launcher preferences to schema 3. Launcher and runner help now
  list the registered `copilot` harness while preserving `--harness ID`
  selection.

## 0.5.0 - 2026-10-03

- Added a fixed, fail-closed Contract-v2 review-harness boundary while
  retaining GitHub Copilot as the only production runtime. Harness identity,
  resolved reasoning effort, strict provider metadata, and adapter-owned
  resume policy are now recorded across approved plans and review artifacts.
- Advanced the approval-bound plan schema to 4 and state schema to 5. Approval
  hashes now bind the harness and provider identity, preventing an approval
  generated for one harness or earlier schema from authorizing another.
- Advanced launcher preferences to schema 2 with harness identity. Legacy
  schema-1 preferences remain readable as Copilot-only, and saved-state reads
  now reject unsafe ownership, symlink, and directory-permission chains.
- Added canonical coding-agent guidance in `AGENTS.md`, a contributor pointer
  in `CLAUDE.md`, and an executable harness-porting playbook in
  `docs/ADDING-A-HARNESS.md`.
- Added a deterministic development-only no-op adapter and worker fixture that
  proves the full harness contract, approval-hash separation, artifact
  identity, isolation, cleanup, and production rejection without advertising
  or packaging another supported runtime.

- Fixed launcher sessions that could render the Rhyolite plaque again during a
  `Shift+Tab` mode transition. Launcher startup now owns one `sessionStart`
  plaque, while the prompt hook matches only exact manual start commands and
  ignores internal resumes and marker-bearing continuations.
- The launcher now passes `--mode interactive` explicitly. Rhyolite treats
  plan/autopilot transitions as unsupported during guided setup or execution,
  preserves the approval-bound worker model, and no longer auto-opens reports
  merely because the outer session entered autopilot.
- Added exact `stop`/`cancel` control handling and targeted INT/TERM/HUP
  propagation through repository shells, timeout wrappers, Copilot workers,
  and research brokers. Interrupted runs now finalize truthful `Interrupted`
  repository/run state and artifacts instead of leaving detached work alive.
- Retired the Rhyolite launcher `--autopilot` option. The parser now rejects
  the legacy spelling with a `RHYOLITE ERROR` diagnostic and exit code `2`;
  guided setup and effective-plan approval remain interactive. Users can still
  independently enable Copilot's own in-session autonomy mode after startup.
- Standardized the initial and edited model pickers on ordered
  `gpt-5.6-sol` (recommended) and `claude-fable-5` choices while preserving
  syntax-validated custom model IDs and per-repository preference round trips.
  Launcher and direct-runner help now list both known IDs and custom-ID
  support.
- Added deterministic trusted navigation to `review.md` and `review.html`
  using only exact allowlisted report headings. Canonical report body chunks
  remain inert, fixed sibling/run-index links are generated locally, and a
  deduplicated external-reference block accepts only conservatively validated
  HTTPS URLs. HTML retains a restrictive CSP, adds a no-referrer policy, and
  performs no rendering-time network access.
- Added a required all-scope `AGENT-TARGETING AND REVIEW MANIPULATION
  ASSESSMENT` covering prompt injection, reviewer-directed instructions,
  metadata/dataset/benchmark poisoning, encoded instructions/tool-call bait,
  tarpits, trackers/sensors, evidence limitations, confidence, and evidence
  basis. Git metadata collection/wrapping is trusted, while ref names and
  commit subjects remain attacker-controlled evidence.
- Added the scope-3 `GENERATED-CODE PROVENANCE ASSESSMENT` with exact
  generation, direct model, non-attributive heuristic model candidate,
  heuristic confidence, direct effort, direct harness, coverage, alternative,
  confidence, and evidence fields. Direct attribution remains commit-bound;
  heuristic candidates concern repository assets rather than people, prefer
  family-level identification, require counterevidence and alternatives, and
  can be only Not applicable/Low/Medium confidence. Fail-closed validation
  rejects omissions, High heuristic confidence, inconsistent no-candidate
  values, and human-generation inference from absent evidence.
- Hardened report/output validation so delimited confidence explanations count
  as inline evidence, generation verdicts require an exact allowed value or a
  punctuation-delimited explanation, tracker suppression canonicalizes host,
  default-port, query, fragment, and trailing-slash variants, and bounded Git
  metadata redacts complete logical fields before whole-record 64 KiB
  aggregation with deterministic omission markers.
- Replaced child `web_fetch`/`--allow-all-urls` research with a dedicated
  write-disabled research worker and deterministic local stdio MCP egress
  broker. The main review worker now receives only a validated read-only
  sanitized dossier and network summary.
- Added the versioned `research-policy.json` contract and Python 3
  standard-library broker with immutable HTTPS/public-DNS/DNS-pinning/
  verified-TLS/no-auth/no-proxy controls, bounded redirects and resources,
  safe HTML/text/JSON/XML/RSS/Atom normalization, anonymous GitHub search,
  and a fixed anonymous `duckduckgo-html-v1` general-web-search provider with
  explicit `none`. The provider uses a closed fixed-endpoint GET adapter,
  unwraps and revalidates result URLs, deduplicates bounded URL/title/summary
  output, and fails structurally on challenges or malformed responses without
  bypass or fallback. Broker version is now `1.1` and the default policy ID is
  `rhyolite-public-research-v2`.
- Added explicit scope 2/3 cookie consent. Replay defaults off; optional
  ephemeral replay uses a fresh bounded exact-host Secure jar per repository
  and run. Raw Set-Cookie values are retained only in a mode-0600 private
  ledger in either mode and are never exposed to a model or rendered report.
- Added structured DNS, TLS, HTTP, redirect, rate-limit, cookie, timeout,
  format, and ownership-aware transport evidence. TLS verification failures
  may trigger only a metadata-only diagnostic handshake that sends no HTTP
  request.
- Added private content-addressed retention for unsupported/binary response
  bodies, with mode-0700 private directories, mode-0600 files, no executable
  extensions, and no model/render/index links.
- Added `ResearchTransport` to plan JSON/text, approval hashes, repository/run
  state, manifests, handoffs, and HTML summaries; this established plan
  schema 3 and state schema 4 before the Contract-v2 harness migration.
- Added distinct `ResearchCapabilityFailed` and `ResearchFailed` boundaries,
  two-phase progress reporting, broker/MCP/runtime cleanup enforcement, and
  fail-closed validation requiring exact tools, capability evidence, a valid
  dossier, and at least one successful public response before main analysis.
- Added offline broker protocol/policy/DNS/TLS/cookie/body/provider/budget
  tests, including fixed web-search parsing/challenge fixtures, plus
  deterministic runner assertions for scope 1 isolation, exact MCP arguments,
  provider opt-out plan/hash binding, two-phase ordering, source-level
  failures, system-wide transport failure, private-evidence non-disclosure,
  permissions, cleanup, approval-hash changes, heuristic provenance
  validation, and multi-repository cookie isolation.
- Finalized the `xjamesmorris/rhyolite` public repository metadata,
  public-preview status, CODEOWNERS, private vulnerability reporting
  route, and conduct contact while preserving a fail-closed local-link
  fallback for incomplete metadata.
- Licensed Rhyolite under GNU GPL version 2 only (`GPL-2.0-only`).
- Renamed the public plugin and user-facing agent to Rhyolite.
- Added an extension-provided `/repo-review` command that explicitly
  selects Rhyolite and begins guided setup.
- Added an immediate, display-only Rhyolite availability notice when
  extension mode is active.
- Changed all finite guided-setup and confirmation inputs to Copilot
  CLI's numbered `ask_user` picker, including provenance lookback and
  the final run/edit/explain decision. The standard final custom-answer
  option remains available.
- Established Rhyolite as the plugin/tool namespace and `repo-review`
  as one workflow, with the bundled Bash launcher as the
  recommended reliable entrypoint, `/rhyolite:start` as the in-session
  compatibility entrypoint, `/rhyolite:repo-review` as an alias, and
  `/repo-review` as the extension shorthand.
- Added the `bin/rhyolite` launcher, which resolves the plugin root,
  moves Copilot orchestration outside Git worktrees, preselects the
  restricted agent, collects public source/fleet/model settings, and
  preserves a sanitized initial request without persisting that request
  or source in launch context. `--yolo` is not enabled by default; an
  explicit per-launch selection gives the outer Copilot orchestrator all
  permissions without persisting that choice in launcher context, copying it
  into trusted setup, or remembering it as a preference. Child restrictions
  stay unchanged, including runner-enforced tool isolation and removal of
  inherited `COPILOT_ALLOW_ALL`.
- Added native launcher `--fleet`/`--model` selection and versioned,
  user-only per-repository fleet/model preferences. Approved settings
  are included in the plan hash and are saved atomically only after plan
  approval.
- Added `/rhyolite:status`, `/rhyolite:version`, and `/rhyolite:help`.
- Added a repository-only, development-time `rhyolite-ui-validator`
  agent plus static release checks for finite-choice UI consistency.
- Added a separate repository-only `rhyolite-tui-runtime-validator`
  agent and deterministic `tests/validate-tui-runtime.mjs` contract for
  plaque width/color/reset/no-color behavior and runtime handoff checks.
- Moved the default command output under
  `$HOME/rhyolite-output/repo-review/`.
- Added a private research-source assessment skill that maps fresh,
  subject-specific community, research, and commercial venues, deepens
  coverage for provenance scope, and persists inaccessible-resource and
  user-retrieval priorities.
- Added High/Medium/Low confidence plus evidence-basis requirements for
  substantive assessment points.
- Required maximum reasoning effort by default for every repository
  development task across sessions, including explicit handoff
  carry-forward. Only mechanical or fully scoped work may downgrade, and
  only to high; analytical or open-ended work remains at maximum effort.
- Replaced the broken `/rhyolite:banner` command with
  `/rhyolite:start` as the stable in-session review-session entry point.
- Added a large terminal-aware RHYOLITE logo with a blue-family ANSI
  TrueColor gradient, six-row full/half-block contours for smoother
  terminal-cell edges, a smaller right-aligned `v<version>` line
  immediately beneath the wordmark, concise functional onboarding copy,
  and explicit no-color handling. Plugin load remains a single plain
  version/start line.
- Suppressed the redundant `Rhyolite v... loaded — type /rhyolite:start
  to start.` `sessionStart` line for launcher-started sessions that
  immediately enter guided setup, while preserving that load line for
  ordinary plugin-loaded sessions.
- Changed launcher-start plaque copy to identify automatic guided mode
  and tell the user to wait for the first setup prompt instead of
  suggesting another `/rhyolite:start`.
- Added live runner milestones and periodic elapsed-time heartbeats for
  long reviews, plus a brief executive summary at completion.
- Added a fail-closed anonymous repository-accessibility preflight
  before clone/snapshot/worker start, with explicit inaccessible-source
  reporting and no authentication attempts.
- Added consistent explanatory `RHYOLITE ERROR` summaries across
  launchers, extension handoff, command orchestration, and runner
  failures. Summaries retain sanitized stage/source/status/exit/artifact
  detail, give specific remediation, redact credentials and controls,
  and suppress unresolved public issue/pull-request URLs in favor of
  local support documentation.
- Made first-turn onboarding continue from the banner directly into the
  first setup question in the same turn.
- Clarified that Rhyolite's `help`, `status`, and `explain scopes`
  prompts do not use a leading slash, avoiding collisions with Copilot
  CLI commands.
- Removed repository-specific update hooks and hosting-policy files.
- Added public repository governance files, issue forms, and a pull
  request template.
- Reframed Scope 3 as opt-in, evidence-based provenance review for
  agentically generated code.
- Added centralized welcome metadata, a replaceable ASCII onboarding
  banner, Linux welcome helpers, and a display-only local
  `sessionStart` availability hook.
- De-scoped the release to Fedora Linux 44 and Bash, removed hosted CI
  and alternate-platform artifacts, and made local Fedora validation
  the release gate.
- Updated the user-facing agent to reserve its prompt-native welcome
  panel for help, while display-only helpers render the review-start
  plaque and load status.
- Added guided setup help/status/explain-scopes behavior plus
  authoritative `EFFECTIVE REVIEW PLAN` instructions for the
  orchestrator and skill.
- Refined setup help to include `CURRENT SETUP STATUS`, added
  `Edit setup`/`Change scope` plan editing guidance, and documented
  approval-hash-confirmed execution.
- Added the authoritative `PriorArtWindow` contract to the effective
  plan summary and generalized approval-hash mismatch guidance to any
  approved effective-plan change.
- Clarified that `ReviewDate`, `PriorArtWindow`, and
  `ProvenanceWindow` are local-session calendar dates, while
  `GeneratedAt` is UTC, and that effective-plan summaries must label
  them accordingly.
- Documented the local onboarding hook, new-session loading behavior,
  child-hook isolation, the startup plaque, and
  current review-plan artifacts.

## 0.3.1 - First public release summary

- Source-loaded Copilot plugin for evidence-based, read-only review of
  untrusted public HTTPS Git repositories.
- Scope 1 provides core repository review; Scope 2 adds public prior-art
  and community research; Scope 3 adds evidence-based provenance review
  for agentically generated code.
- Runners preserve anonymous cloning, isolated read-only snapshots, and
  persisted local artifacts without executing or modifying target code.
