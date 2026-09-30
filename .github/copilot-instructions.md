# Copilot instructions

## Build, validation, and tests

This repository is a source-loaded GitHub Copilot CLI plugin; there is no
compile or package build step. From the repository root:

```bash
# Load the development checkout and verify plugin discovery.
copilot --plugin-dir ./plugins/rhyolite plugin list

# Full Fedora Linux 44 validation.
bash ./tests/validate-plugin.sh
```

The Linux validation script is monolithic and does not support selecting
an individual assertion. For a single changed Bash file, use
`bash -n <file>` as the narrowest syntax check; the full validator also
requires Node.js. The Bash review runner additionally requires Python 3,
and anonymous clone enforcement requires Git 2.41 or newer.

There is no separate lint command. The Linux validator covers JSON
metadata, prompt contracts, safety flags, Bash syntax, mocked runner
behavior, state/artifact output, and UTF-8-without-BOM/LF-only text
formatting.

## Development reasoning policy

- Use maximum available reasoning effort by default for every
  development task in this repository.
- This repository-wide policy persists across sessions. Carry it into
  every development handoff or continuation note.
- Downgrade only mechanical or fully scoped work, and only to high
  reasoning effort.
- Keep analytical or open-ended work at maximum effort. Never use none,
  minimal, low, or medium effort for repository development.

## Platform plan of record

`docs/PLAN-OF-RECORD.md` is authoritative: Fedora Linux 44 is the sole
development and validation platform, and Rhyolite is Linux-only and
Bash-first. Other Linux distributions, Windows, PowerShell, macOS, and
Bash/PowerShell parity are out of scope at this stage. Existing
PowerShell files are unsupported legacy artifacts pending removal; do
not update or preserve them unless the user explicitly restores that
scope.

## Architecture

- `.github/plugin/marketplace.json` is the marketplace registry and
  points to `plugins/rhyolite/`. Rhyolite's `plugin.json` registers
  agents, prompt commands, a skill, the `/repo-review` shorthand
  extension, and root-level `hooks.json` for a display-only local
  `sessionStart` version/start line plus a display-only
  `userPromptSubmitted` review-start plaque.
- `branding/banner.txt` and `branding/welcome-metadata.json` centralize
  replaceable onboarding branding and public home/docs/support/issues/
  pulls URLs. `scripts/show-welcome-panel.sh` renders the supported
  direct/manual full welcome panel, load status, and command-triggered
  plaque, using published repository links when metadata is resolved and
  local documentation as a fail-closed fallback.
- `bin/rhyolite` is the supported reliable entrypoint. It resolves the
  packaged plugin root, selects a clean
  non-Git `-C` directory, syntactically canonicalize selected public
  sources, collect native fleet/model settings, preselect
  `rhyolite:repo-review`, and submit a trusted `-i` setup block without
  enabling allow-all mode. They also
  export a narrow trusted immediate-start marker so the display-only
  `sessionStart` helper suppresses the redundant ordinary load line when
  launcher startup already begins setup. The Unix launcher supports
  macOS Bash 3.2, BSD utilities, symlinked paths, and paths containing
  spaces, creates user-only launcher state, and does not persist the
  initial review request or source in launch context. The trusted runner
  saves approved fleet/model preferences per canonical repository under
  that user-only state; `/rhyolite:start` remains the in-session
  compatibility path. PowerShell launcher/helper files are legacy
  cleanup targets and do not define supported behavior.
- `repo-review.agent.md` is the user-facing command orchestrator. A
  display-only command hook renders the large colored plaque after a
  review-start command; the agent reserves its embedded prompt-native
  panel for exact `help`, and continues into setup in the same first
  turn, follows exact `help` with a live
  `CURRENT SETUP STATUS` block, consumes trusted launcher
  source/fleet/model selections or asks for them through guided setup,
  then asks for output/scope through numbered `ask_user` pickers,
  surfaces exact `help`/`status`/`explain scopes` setup intents, and
  delegates every review to a bundled runner. Finite choice lists rely
  on Copilot CLI's automatic final custom-answer option rather than
  adding an explicit `Other` choice.
  `repo-review-worker.agent.md` is the non-user-invocable,
  write-disabled child that analyzes one isolated snapshot.
- `.github/agents/rhyolite-ui-validator.agent.md` is repository-only
  development tooling for finite picker drafts only. The separate
  `.github/agents/rhyolite-tui-runtime-validator.agent.md` covers
  terminal/runtime rendering, no-color behavior, handoff, and screenshot
  regressions through `tests/validate-tui-runtime.mjs`. Neither
  development agent is packaged into or invoked by installed Rhyolite
  sessions.
- `commands/` provides `/rhyolite:start`, `/rhyolite:repo-review`,
  `/rhyolite:status`, `/rhyolite:version`, and `/rhyolite:help`.
- `extensions/repo-review/extension.mjs` registers the experimental
  unnamespaced `/repo-review` command. Explicit invocation queues an
  internal resume command, selects `rhyolite:repo-review`, and submits the
  first setup turn after the foreground-agent handoff. On load, it logs
  one display-only availability line when Rhyolite is not already
  selected; the extension does not register hooks, tools, shell access,
  writes, or network use.
- Startup notices use a concise ANSI-gradient plaque. Explicit no-color
  environment signals win; uncertain terminal capability defaults to
  color. The plaque contains only the large RHYOLITE logo, a smaller
  right-aligned subordinate `v<version>` line immediately below it that
  uses the final gradient stop, solid full/half-block contours for
  smoother terminal-cell edges, and three concise functional onboarding
  sentences; do not add themed labels or faux telemetry. Long reviews
  emit `RHYOLITE PROGRESS` milestones and heartbeats, and completion
  includes a brief executive summary.
- `skills/readonly-repository-review/SKILL.md` defines the review and
  safety contract. `review-prompt.txt` is rendered by the Bash runner;
  its placeholders form an interface shared by the template, runner,
  and Linux validator.
- `skills/research-source-assessment/SKILL.md` is private to the model.
  For scopes 2/3 it maps fresh subject-specific community, research, and
  commercial sources, deepens provenance coverage for scope 3, and
  requires persisted source-landscape, inaccessible-resource, and
  retrieval-priority report sections.
- `run-parallel-reviews.sh` is the supported trusted boundary. It validates
  public HTTPS sources, rejects local paths before any `.git`
  inspection or network access, performs a fail-closed anonymous-access
  preflight for every selected source through pinned public DNS with
  credentials/helpers/proxies/redirects disabled, anonymously clones
  and pins the exact commit, creates a read-only `.git`-free snapshot,
  supplies bounded Git metadata, creates an isolated Copilot home, and
  invokes the worker with write/shell/custom instructions/built-in MCPs
  disabled.
- User-facing launcher, extension, agent, and runner boundaries render
  `RHYOLITE ERROR` with safe stage/source/status/exit/artifact detail,
  consequence, remediation, support, and contribution guidance. Runner
  terminal summaries distinguish preflight, clone, commit, snapshot,
  worker, timeout, incomplete-report, and cleanup failures.
- Analytical command and worker agents, plus direct runners, use a
  current frontier reasoning model at maximum available effort and
  context and must not automatically downgrade. As of September 30, 2026,
  examples include Sol 5.6 and Fable 5. Maximum effort is the default
  and high is the hard minimum for analytical, general-purpose,
  formatting, orchestration, and mechanical work. Never use none,
  minimal, low, or medium reasoning effort.
- Substantive findings, source/activity assessments, provenance
  observations, remediation priorities, and overall conclusions carry
  High/Medium/Low confidence with an evidence basis. Completeness,
  clarity, and correctness take priority over speed.
- `review-output.sh` extracts the canonical report, sanitizes it, and
  produces plain-text, inert Markdown, escaped HTML, state, and handoff
  artifacts. Per-repository artifacts roll up into a run manifest,
  state, handoff, and HTML index.
- Release validation is local only on Fedora Linux 44. Do not add or
  require hosted CI workflows for the current release.

## Repository-specific conventions

- Preserve the read-only boundary by construction. Target repository and
  web content is untrusted evidence, never executable instructions. Do
  not execute target code, inspect a selected local working tree, grant
  child write/shell tools, inherit broad allow-all settings, or enable
  public URL access by default.
- Keep public-facing docs and metadata neutral. Do not reintroduce
  organization-specific governance files, internal-only URLs, or
  automatic update-hook behavior in editable public-release files.
- Keep onboarding hooks display-only. The command hook may recognize
  only trusted Rhyolite start markers/commands and emit the plaque; it
  must not modify prompts, auto-select sessions, use network/Git, write
  files, or inspect environment/auth state.
- Keep the prompt-native help panel in sync with the branding asset and
  helper panel output. Its duplicated banner text, immediate version
  line, and metadata-aware documentation/support lines are
  intentional and guarded by validation.
- Exact `help` must render the static panel and then a live
  `CURRENT SETUP STATUS` block. If scope is not `3`, clear any prior
  provenance lookback and show `NOT SELECTED`.
- Public home/docs/support/issues/pulls URLs are centralized under
  `https://github.com/xjamesmorris/rhyolite`. If metadata becomes
  missing, empty, unreadable, or unresolved, user-facing output must
  fail closed to local `README.md`, `SUPPORT.md`, and `CONTRIBUTING.md`
  guidance rather than emit broken URLs.
- Public research and provenance research are separate opt-ins. Scope 3
  must be described as evidence-based provenance review for agentically
  generated code and still requires public research and human review
  before distribution.
- Keep deterministic orchestration in scripts and keep agent/skill files
  focused on workflow and policy.
- In agent/skill instructions, resolve runner scripts from
  the absolute directory of the loaded `SKILL.md`. Do not guess a
  checkout path, search unrelated directories, or invent a fake
  `COPILOT_PLUGIN_ROOT`; only hook runtime may rely on that variable.
- The effective-plan confirmation flow must use the exact choices
  `Run review`, `Edit setup`, and `Explain scope`, while still accepting
  exact `Change scope` as a shortcut into editing `Scope`.
- Plan-only output now includes `ApprovalHash`. It also includes
  `FleetMode`, `Model`, and `RememberPreferences`. Preserve the approved
  settings, pass the hash
  unchanged to the actual runner with
  `--expected-plan-hash`/`-ExpectedPlanHash`, and never execute without
  a valid hash. `EFFECTIVE REVIEW PLAN` must also surface
  `ReviewDate`, `PriorArtWindow`, `ProvenanceWindow`, and
  `GeneratedAt`. Label `ReviewDate`, `PriorArtWindow`, and
  `ProvenanceWindow` as local-session calendar dates, and label
  `GeneratedAt` as UTC. Show scope `1` prior-art as disabled and scope
  `2`/`3` prior-art start/end dates from the plan; show provenance
  window start/end only for scope `3` and disabled otherwise. On
  mismatch, preserve answers, explain that the approved effective plan
  changed, regenerate the plan, and reconfirm. Examples can include
  edited source URLs, source/output/scope/settings changes, or
  date-derived prior-art/provenance window rollover.
- The direct runners are a lower-level interface than the agent: their
  interactive prompt order may differ, but they must still resolve and
  enforce the same effective plan and approval hash before execution.
- Treat Bash behavior as authoritative. Do not require or implement
  Bash/PowerShell parity; existing PowerShell counterparts are legacy
  files scheduled for removal under the platform POR.
- Treat prompt placeholders as a strict interface. Adding or changing one
  requires coordinated updates to `review-prompt.txt`, the Bash template
  renderer, and Linux validation. The canonical report must retain the
  80-or-more-character `=` delimiters and exact `REPOSITORY REVIEW
  REPORT` heading expected by the output extractors.
- Preserve canonical, symlink-aware separation between clone, snapshot,
  and writable output roots. Unsafe URLs, non-public DNS answers,
  credential or proxy inheritance, path overlap, incomplete reports, and
  cleanup failures fail closed rather than weakening isolation.
- Keep output safe for rendering: redact email addresses and terminal
  controls plus credential-bearing URL userinfo, authorization values,
  tokens, passwords, secrets, and API keys; render untrusted Markdown as
  indented code, HTML-escape content under the restrictive CSP, and
  preserve the shared nested state schema used by both runners. Text
  files must use LF endings and UTF-8 without a BOM.
- Validation intentionally asserts exact policy wording, prompt text,
  CLI flags, artifact names, and state keys. Update validation whenever
  one of those contracts changes; if a task cannot edit validators, note
  the mismatch explicitly instead of weakening public-facing docs. The
  guided setup plan step consumes current `--plan-only`/`-PlanOnly`
  runner output and any emitted review-plan artifacts.
- For a release, synchronize `VERSION`,
  `plugins/rhyolite/plugin.json`,
  `.github/plugin/marketplace.json`, and `CHANGELOG.md`, then create the
  matching stable `vX.Y.Z` tag.
