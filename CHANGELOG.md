# Changelog

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
