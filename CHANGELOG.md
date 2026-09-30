# Changelog

## 0.4.0 - Unreleased

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
- Added the `bin/rhyolite` launcher that resolves the
  plugin root, move Copilot orchestration outside Git worktrees,
  preselect the restricted agent, collect public source/fleet/model
  settings, preserve a sanitized initial request, and never enable
  allow-all mode or persist that request/source in launch context.
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
