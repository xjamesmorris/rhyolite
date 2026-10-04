# Rhyolite Copilot Plugin

Rhyolite is an evidence-based, read-only GitHub Copilot plugin for
reviewing untrusted public HTTPS Git repositories.

Rhyolite combines:

- The `repo-review` command agent, write-disabled main review worker, and
  dedicated write-disabled research worker.
- Stable namespaced commands: `/rhyolite:start`,
  `/rhyolite:repo-review`, `/rhyolite:status`, `/rhyolite:version`, and
  `/rhyolite:help`.
- The short `/repo-review` guided-start command when extension commands
  are available.
- A Linux Bash launcher that collects public sources, native fleet mode,
  and the review model before selecting the restricted agent from a
  clean non-Git orchestration directory.
- Separate repository-only development validators for finite pickers and
  terminal/runtime UI.
- The `readonly-repository-review` skill.
- A private `research-source-assessment` skill that maps fresh,
  subject-specific community, research, and commercial sources.
- A Bash review runner for the supported Linux workflow.
- A deterministic local stdio MCP research-egress broker implemented with the
  Python 3 standard library under a fixed immutable transport safety floor.
- Separate security and dedicated public-source research passes.
- Centralized welcome branding plus Linux onboarding helpers.
- Local display-only hooks for one load notice or exactly-once launcher
  plaque plus exact manual review-start plaques.
- Persisted plain-text, Markdown, HTML, session, state, and handoff
  artifacts.

## Status

Version `0.5.0` is a public preview release. GitHub Copilot plugins are
currently public-preview features.

The plugin supports anonymously readable public HTTPS Git repositories on
GitHub and other public DNS hosts. It does not review authenticated,
private, or internal repositories, execute target code, modify target
repositories, or use shared service credentials. Scope 2/3 research uses only
the bundled local broker's public-HTTPS direct-fetch, anonymous GitHub, and
fixed anonymous `duckduckgo-html-v1` general-web-search providers. Advanced
direct-runner use may select explicit `none` to opt out; no other web-search
provider or endpoint is configurable.

**Platform support:** Fedora Linux 44 is the sole development and
validation baseline for this release. Runtime support is Linux-only.
Other operating systems and Linux distributions are not currently
validated or supported. See
[docs/PLAN-OF-RECORD.md](docs/PLAN-OF-RECORD.md).

**Review harness support:** GitHub Copilot is the only production runtime
harness. The harness abstraction is a fixed, fail-closed internal seam; it
does not make other CLIs supported. Contributor and coding-agent guidance is
canonicalized in [AGENTS.md](AGENTS.md), with the architecture in
[docs/HARNESS-ARCHITECTURE.md](docs/HARNESS-ARCHITECTURE.md) and the
Contract-v3 implementation playbook in
[docs/ADDING-A-HARNESS.md](docs/ADDING-A-HARNESS.md). The no-op adapter and
worker under `tests/fixtures/harnesses/` are development-only contract
fixtures; they are not registered, packaged, selectable, or exposed in
production.

Rhyolite is licensed under the GNU General Public License version 2
only (`GPL-2.0-only`). See [LICENSE](LICENSE).

## Quick notes

- Recommended model: use a current frontier reasoning model at the
  maximum available reasoning effort and context (as of October 3, 2026,
  examples include Sol 5.6 and Fable 5). Use maximum available reasoning
  effort by default for every repository development task. This policy
  persists across sessions, and development handoffs must carry it
  forward. Downgrade only mechanical or fully scoped work, and only to
  high; keep analytical or open-ended work at maximum effort. Never use
  none, minimal, low, or medium effort.
- Run `copilot login` and complete Copilot sign-in before starting a
  review.
- Use the issue templates in this repository and [SUPPORT.md](SUPPORT.md)
  for questions and feature requests.
- Read [AGENTS.md](AGENTS.md) before contributing, then see
  [DEVELOPERS.md](DEVELOPERS.md) for environment setup and the validation
  matrix.
- Scope `3` is evidence-based provenance review for agentically generated
  code. It is separately opt-in and requires human review before sharing.
- **Strongly recommended:** select `1 - Core repository review` for the
  first run; broader scopes can be resource-intensive and long-running.

## Install for development

The recommended reliable checkout entrypoint is the repository-root
wrapper on Fedora Linux 44:

```bash
./rhyolite --repo https://github.com/owner/repository
```

The optional `--yolo` switch changes the outer Copilot session for that
launch and also affects report handling:

```bash
./rhyolite --repo https://github.com/owner/repository --yolo
```

`--yolo` is disabled by default. It explicitly opts the outer Copilot
orchestrator into all permissions for that launch and is not persisted in
launcher context, copied into trusted setup, or remembered as a preference.
Because `--yolo` sets allow-all mode, a completed review opens the local
HTML report index automatically instead of prompting unless the runner's
`--no-open-html` option is selected. Restricted child review sessions
retain runner-enforced tool isolation and remove inherited
`COPILOT_ALLOW_ALL` state.

The former launcher `--autopilot` option is retired. The packaged launcher
rejects it with a `RHYOLITE ERROR` diagnostic and exit code `2`, so it cannot
be mistaken for initial request text. Rhyolite setup and effective-plan
approval remain interactive, and the launcher now passes
`--mode interactive` explicitly. Switching the outer session to plan or
autopilot mode during setup or execution is unsupported: return to
interactive mode before continuing. A mode-related UI notice does not change
the model recorded in the approved plan or the explicit model passed to the
isolated review workers.

Exact `stop` and `cancel` requests are control intents, not review prompts.
The orchestrator immediately stops the active runner, and the runner
propagates interruption signals through its tracked repository, timeout,
Copilot worker, and broker processes before writing truthful `Interrupted`
artifacts.

The wrapper resolves the checkout's physical location, supports
symlinked invocation and paths containing spaces, and forwards every
argument unchanged to the canonical packaged Bash launcher at
`./plugins/rhyolite/bin/rhyolite`.

The checkout wrapper delegates to the packaged launcher, and the
packaged launchers resolve their plugin root, choose a `-C` directory
outside every Git worktree, pass `--plugin-dir`, preselect
`rhyolite:repo-review`, and submit a trusted `-i` setup block while
preserving any optional initial request after removing control
characters. Before Copilot starts, they syntactically canonicalize the
selected public HTTPS repository URLs without removing a terminal `.git`
endpoint, ask whether to use native Copilot fleet mode, and confirm the
validated review runtime. Known model choices are `gpt-5.6-sol` (recommended)
and `claude-fable-5`; the selector can list the live model IDs reported by
`copilot help config`, including `gpt-6-sol` when available. Every model must
match that catalog exactly.
Reasoning effort is selectable as `max` (recommended), `xhigh`, or `high`;
context is selectable as `long_context` (recommended) or `default`. The
launcher displays harness, model, effort, and context together and asks the
user to confirm or modify them. Native mode adds the process-level `--fleet` flag,
and every launch passes the selected `--model`, `--reasoning-effort`,
and `--context`. Because setup starts immediately,
launcher-started sessions suppress the ordinary plugin load line
(`Rhyolite v... loaded — type /rhyolite:start to start.`) and show
automatic-guided-mode copy that tells the user to wait for the first
setup prompt.

The checkout wrapper preserves that trusted launcher/helper behavior by
delegating in place to the canonical packaged launcher. Per-launch
context and logs use `$XDG_STATE_HOME/rhyolite/launcher` on Linux
(falling back to
`~/.local/state/rhyolite/launcher`). The launcher creates that state
with user-only permissions and does not persist the initial review
request or selected source in its context file.
After the user approves the effective plan, the runner atomically saves
only the canonical repository URL, fleet mode, model, reasoning effort,
context tier, and update time
in a user-only hashed preference file below the same launcher state
root. Future launcher runs reuse a preference only when every selected
repository has the same valid setting; mixed, missing, or malformed
preferences are never chosen silently.

To inspect or install the checkout manually:

```bash
copilot --plugin-dir ./plugins/rhyolite plugin list
copilot plugin install ./plugins/rhyolite
```

Installation includes the Bash launcher, Rhyolite agent, skill,
short-command extension, helpers, and local display-only onboarding
hooks. The repository-only validator agents are not packaged. Current
Copilot CLI releases load extension-provided commands in experimental
mode.

If a launcher cannot be used, start manually from outside every Git
worktree:

```text
copilot --experimental -C <clean-directory> --plugin-dir <absolute-path-to-plugins/rhyolite>
```

Then use `/rhyolite:start` as the in-session compatibility path;
`/rhyolite:repo-review` remains an alias, and `/repo-review` is the
shorthand when extension commands are active.
New sessions show one plain versioned line directing users to
`/rhyolite:start`. After a review-start command, a display-only hook
renders the large Rhyolite plaque, then the agent asks for one or more
anonymous public HTTPS Git repository URLs.

## Install from a published marketplace

Register the marketplace repository:

```text
copilot plugin marketplace add https://github.com/xjamesmorris/rhyolite
copilot plugin install rhyolite@rhyolite-tools
```

Do not distribute personal access tokens or store credentials in this
repository. The `/rhyolite:*` commands load with the plugin. Run
`/experimental on` once and start a new session to also load the
`/repo-review` shorthand.

## Update

This build uses manual updates only. After publication, update both the
marketplace checkout and the installed plugin:

```text
copilot plugin marketplace update rhyolite-tools && copilot plugin update rhyolite@rhyolite-tools
```

Verify the installed version with:

```text
copilot plugin list
```

After updating, start a new Copilot CLI session before testing the
startup plaque or welcome panel.

If a pre-Rhyolite build is installed, remove its legacy registration
before installing Rhyolite so both onboarding hooks do not load:

```text
copilot plugin uninstall repository-review
copilot plugin marketplace remove repository-review-tools
```

## Use interactively

Prefer the checkout wrapper shown above. The canonical packaged launcher
at `./plugins/rhyolite/bin/rhyolite` remains equivalent when you need to
exercise that path directly. For an already-running Copilot CLI session
started from a clean directory that is not inside any Git worktree, use
the compatibility path:

```text
copilot --experimental -C <clean-directory>
```

Type `/rhyolite:start`, optionally followed by a public HTTPS Git URL or
other initial request. The command explicitly enters the already-loaded
Rhyolite agent and must not invoke `skill(start)`.
`/rhyolite:repo-review` remains a compatibility alias. When extension
commands are available, `/repo-review` is the equivalent shorthand. The
compatibility agent path is
`/agent rhyolite:repo-review`, followed by `start`.

| Command | Purpose |
| --- | --- |
| `/rhyolite:start` | In-session compatibility start for the guided, read-only review session. |
| `/rhyolite:repo-review` | Compatibility alias for `/rhyolite:start`. |
| `/repo-review` | Experimental shorthand for the same review session. |
| `/rhyolite:status` | Show command stage, elapsed time, selections, output, review run, tasks, and visible subagents. |
| `/rhyolite:version` | Show the installed Rhyolite version. |
| `/rhyolite:help` | Show Rhyolite command help. |

The installed plugin contributes local, display-only onboarding hooks.
In an ordinary new outer Copilot CLI session, `sessionStart` emits one
plain line with the installed version and `/rhyolite:start`. Launcher
startup instead receives the full launcher plaque from `sessionStart`
exactly once. Neither path performs network access, Git commands,
writes, prompt mutation, or environment/auth inspection.

After `/rhyolite:start`, compatible `/rhyolite:repo-review`, or the
`/repo-review` shorthand, a display-only prompt hook recognizes only the
exact manual start command and emits the large plaque. It ignores
internal resumes, marker-bearing continuations, launcher prompts, and
unrelated user text; it does not modify the prompt or persist state. The
visual treatment is limited to
the large RHYOLITE wordmark, a smaller right-aligned `v<version>` line
immediately beneath it, full/half-block contours that approximate
antialiasing in a terminal cell grid, and the wordmark's blue-family
TrueColor gradient, with the version line using the final subordinate
gradient stop. The accompanying copy remains three concise functional
sentences. Manual starts describe Rhyolite and the start/help/status
commands. Launcher starts instead identify automatic guided mode and
tell the user to wait for the first setup prompt; neither mode contains
themed labels or faux telemetry.

Color is explicitly disabled through `NO_COLOR`,
`COPILOT_NO_COLOR=1`, `FORCE_COLOR=0`, or `TERM=dumb`; uncertain
capability defaults to color. Exact in-session `help` uses the plain
prompt-native panel.

User-facing launcher, extension, and runner failures use a consistent
`RHYOLITE ERROR` block. It identifies the failed stage and source,
preserves sanitized underlying detail and exit status, explains the
consequence, gives specific remediation, and lists any state/error/
timeline/handoff artifacts. Control sequences, email addresses, and
credential-like values are redacted before error detail is repeated.
Published metadata directs these blocks and the help panel to the
Rhyolite repository. If metadata is missing, unreadable, empty, or
contains an unresolved public placeholder, user-facing output falls
back to local `README.md`, `SUPPORT.md`, and `CONTRIBUTING.md` guidance
rather than printing an unusable URL.

Do not start the orchestrator inside the repository being reviewed;
repository hooks can run before the plugin can isolate its worker. An
active outer Copilot session is the initial authentication check. Each
isolated child then verifies its actual authentication path when invoked;
if that fails, run `copilot login` from a clean non-Git directory,
complete sign-in, and retry.

Launcher-guided setup collects one or more anonymously readable public
HTTPS Git repository URLs, fleet mode, and model before Copilot starts.
Manual in-session setup asks for the same source and model information;
because native fleet mode is process-level, choosing it from a manual
session requires restarting through the launcher. Rhyolite does not
discover local repositories, inspect local origins, or offer filesystem
paths as review sources. If the orchestration directory is inside a Git
worktree, the runner stops and requires a clean restart before planning
or review execution.

During guided setup, these exact setup intents remain available at any
stage without resetting collected answers:

- `help` **without a leading slash** reruns the full static panel, then
  immediately shows a
  `CURRENT SETUP STATUS` block with live `Source`, `Fleet mode`,
  `Model`, `Remember settings`, `Output`, `Scope`, and
  `Provenance lookback months` and `Research cookies` values or
  `NOT SELECTED`.
- `status` **without a leading slash** shows the same live
  `CURRENT SETUP STATUS` block.
- `explain scopes` **without a leading slash** restates the scope `1`/`2`/`3`
  resource/network/provenance differences.

`/help` and other leading-slash commands belong to Copilot CLI, not
Rhyolite.

If scope changes away from `3`, the previous provenance lookback is
cleared immediately and shown as `NOT SELECTED`.

You can then ask:

```text
Review https://gitlab.com/owner/repository without modifying or executing it.
Include public prior-art and community research, but do not perform provenance
analysis.
```

The agent asks one question at a time:

1. Which source to review.
2. Whether to continue in standard mode or restart through the launcher
   for native fleet mode when setup did not come from the launcher.
3. Which available review model to use, with an option to list live model IDs.
4. Which reasoning effort to use.
5. Which context tier to use.
6. Whether to confirm the validated harness/model/effort/context settings or
   modify one of them.
7. Whether to remember fleet/model/effort/context settings for the selected
   repositories after plan approval.
8. Whether the output parent is the current directory, home directory,
   or a custom location.
9. Which review scope to use.
10. For scope `3`, which provenance lookback to use.
11. For scope `2` or `3`, whether research cookie replay remains off or
   uses a fresh per-repository ephemeral jar.
12. After those answers are collected, the agent requests the runner's
   authoritative planning output and presents an `EFFECTIVE REVIEW PLAN`.
   It then asks whether to `Run review`, `Edit setup`, or `Explain scope`.

Every finite setup or confirmation decision uses Copilot CLI's native
numbered `ask_user` picker rather than a prose list. The CLI adds the
final `Other` custom-answer option automatically and owns its exact
display wording (current versions show `Other (type your answer)`).
Freeform follow-ups are used only for values such as repository URLs,
custom output paths, or instructions describing what to do differently.

The initial model picker and `Edit setup` -> `Model` use the same ordered
choices:

```text
1. GPT-5.6 Sol (Recommended) - gpt-5.6-sol
2. Claude Fable 5 - claude-fable-5
3. List available model IDs
4. Other (wording supplied by Copilot CLI)
```

The final custom-answer option accepts a model ID containing only letters,
numbers, dots, underscores, and hyphens. Rhyolite does not hard-allowlist
models or silently replace a selected custom ID.

The output picker resolves and displays these full paths:

```text
1. Current directory - <absolute PWD>/rhyolite-output/repo-review
2. Home directory - <absolute home>/rhyolite-output/repo-review
3. Other (wording supplied by Copilot CLI)
```

The selected command directory then contains run and per-repository
subdirectories.

The scope UI first prints these as separate lines:

```text
Scope 1 covers source, history, architecture, quality, and a security specialist with the lowest AI-credit use and only anonymous Git network access.
Scope 2 adds public prior-art/community research, public network requests, and materially higher resource use.
Scope 3 adds whole-repository provenance evidence gathering, uses the most model/subagent/network resources, and requires human review before sharing.
All timing ranges are rough and can increase substantially for large repositories or broad topics.
```

The numbered picker immediately below uses matching Scope 1, Scope 2,
and Scope 3 labels. For scope `3`, `Provenance lookback months [6]` is
also a numbered picker: `6 months (Recommended)`, `3 months`, `12
months`, and `24 months`; use the final custom-answer option for any
other whole-number value from `1` through `60`.

For scope `2` or `3`, the next picker uses:

```text
1. Do not replay research cookies (Recommended)
2. Allow a fresh per-repository research cookie jar
3. Other (wording supplied by Copilot CLI)
```

Either mode records raw Set-Cookie values only in a private
per-repository transport ledger for local analysis. Raw values are never
shown to a model or rendered report. The optional jar starts empty,
replays only bounded exact-host Secure cookies, is isolated per
repository/run, and is never imported or reused.

During development, the repository-only `rhyolite-ui-validator` agent
checks only finite-picker lead-ins, questions, option order, mappings,
defaults, and native Other/custom-answer behavior. The separate
repository-only `rhyolite-tui-runtime-validator` checks ANSI/TrueColor
rendering, width, no-color behavior, command handoff, and screenshot
regressions. `tests/validate-tui-runtime.mjs` provides the deterministic
Linux artifact contract used by the Fedora validator.
Neither development agent is packaged with or invoked by installed
Rhyolite sessions.

When public research is enabled, the trusted runner launches a dedicated
research worker before the main reviewer. The worker receives snapshot
read/search access and exactly five local broker tools:
`research_capabilities`, `fetch_public_url`, `search_public_github`,
`search_public_web`, and `research_network_summary`. Built-in MCPs,
direct `web_fetch`, broad URL approval, shell, and writes remain
disabled.

The local Python broker is the only research egress path. It permits
GET/HEAD to validated public HTTPS destinations, resolves and pins every
initial and redirect host, verifies TLS and hostnames, rejects URL
userinfo, IP literals, private DNS, plaintext, authentication, inherited
proxies/netrc/cookies/client certificates, and applies bounded request,
redirect, timing, header, wire-body, normalized-output, host-rate, and
cookie policy. It normalizes HTML, text, JSON, XML, RSS, and Atom as
untrusted evidence. Unsupported bodies are retained privately as
content-addressed `.bin` files and are never parsed, rendered, indexed,
linked individually, or exposed to a model.

General web search uses a closed in-code `duckduckgo-html-v1` adapter with a
fixed HTTPS endpoint, fixed headers, no credentials, no caller-supplied
headers, no request body, no inherited proxy, no CAPTCHA/challenge bypass, and
no fallback provider. Provider redirect URLs are decoded, every result URL is
revalidated through the same public-HTTPS policy, duplicates are removed, and
only bounded URL/title/summary records are returned. Explicit `none` remains a
fail-closed opt-out.

The dedicated worker builds a source landscape for the repository's
subject areas. It extends mailing-list archives, blogs, conferences,
standards, academic sources, forums, ecosystem sources, and commercial
venues. Each source records its check date, latest observed activity,
coverage, freshness, and ownership. Scope `3` performs a thorough second
provenance-focused pass. The runner validates the dossier, broker
capability record, event ledger, cleanup, and at least one successful
public response before the main worker starts. The main worker receives
only a read-only sanitized dossier and network summary and has no direct
network tool.

Reports preserve `RESEARCH SOURCE LANDSCAPE`,
`INACCESSIBLE RESOURCE REGISTER`, and
`TOP USER RETRIEVAL PRIORITIES` sections, plus
`RESEARCH TRANSPORT OBSERVATIONS`. Rhyolite does not bypass
paywalls, authentication, robots restrictions, removals, or network
policy. It brings inaccessible high-priority sources to the user's
attention and offers a picker to display the ranked sources most useful
to retrieve.

Every scope includes an exact
`AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT`. It covers prompt
injection and reviewer-directed instructions; source, documentation,
commit/ref metadata, dataset, and benchmark poisoning; encoded or invisible
instructions and tool-call bait; recursive/resource-exhaustion tarpits;
tracking pixels, callback beacons, trackers, and sensors; and limitations of
the available evidence. Checked-in source and documentation are inspected as
inert text. Resource URLs are not activated merely to test tracking behavior,
and normalized external pages can limit sensor detection.

Scope `3` also requires an exact
`GENERATED-CODE PROVENANCE ASSESSMENT` with generation, direct model,
non-attributive heuristic model candidates, heuristic confidence, direct
effort, direct harness, coverage/window, alternative-explanation, confidence,
and evidence-basis fields. Generation verdicts are limited to `Confirmed`,
`Evidence supports assisted generation`, `Indeterminate`, or
`No supporting evidence found`. An absence of evidence never establishes
human generation. Direct model, effort, or harness attribution requires
commit-bound evidence such as an attestation, transcript, provenance record,
or explicit disclosure.

Heuristic model candidates concern repository assets, never people, and are
not attribution. They prefer family-level identification, cite exact paths,
commits, or dated public evidence, preserve counterevidence and alternatives,
and use only `Not applicable`, `Low`, or `Medium` confidence, never `High`.
`No candidate identified` and `Not appropriate` are the controlled
no-candidate values. Tool configuration, style, quality, verbosity, test
density, bulk commits, and generic fingerprints alone are not proof.

Substantive findings and assessment points include High, Medium, or Low
confidence with a concise evidence basis. Low-confidence possibilities
remain limitations, unresolved questions, or retrieval needs rather
than established defects or provenance conclusions. Completeness,
clarity, and correctness take priority over speed.

During execution, the runners emit `RHYOLITE PROGRESS` milestones for
run start, anonymous access preflight, anonymous clone, exact commit,
read-only snapshot, analysis, periodic elapsed-time heartbeat, artifact
creation, finalization, and completion. `/rhyolite:status` reflects the
latest known stage.

At completion, Rhyolite displays a brief three-to-five-bullet
`RHYOLITE EXECUTIVE SUMMARY`, preserving report confidence and material
limitations, before listing artifact paths.

These are rough planning ranges. Large repositories and broad research
topics can take substantially longer.

The guided plan step uses the runner's `--plan-only` mode and
corresponding review-plan artifacts.
Plan-only is syntax-only and offline: it performs no DNS, curl, or Git
transport and preserves the selected canonical source, including a terminal
`.git` endpoint, as the plan and approval identity.
The plan JSON also supplies an `ApprovalHash`, which the agent must
retain and pass back unchanged to the actual runner with
`--expected-plan-hash`. The actual review must reuse
the same resolved inputs that were accepted in the `EFFECTIVE REVIEW
PLAN`. Fleet mode, model, and whether settings will be remembered are
part of the plan and approval hash. The `EFFECTIVE REVIEW PLAN` summary
shows prior-art as disabled
for scope `1`, or the authoritative scope-`2`/`3` prior-art start/end
window from `PriorArtWindow`. It also labels `ReviewDate`,
`PriorArtWindow`, and `ProvenanceWindow` as local-session calendar
dates, while `GeneratedAt` is labeled as UTC. For scope `3`, it shows
the authoritative provenance start/end window from `ProvenanceWindow`;
for other scopes, provenance window is shown as disabled. If the user
selects `Edit setup`, the agent uses another numbered picker for
`Source`, `Model`, `Output`, `Scope`, or `Research cookies`, re-asks
only that field, preserves the others, clears provenance when scope is
not `3`, clears cookies for scope `1`, and regenerates the plan. Fleet
mode cannot change in an already-running process.
Exact `Change scope` is still accepted as a shortcut into editing `Scope`.

Scope 2/3 plans also surface and hash `ResearchTransport`:
dedicated-worker mode, broker and policy schema versions, provider IDs,
effective policy digest and resource profile, exact tools, anonymous
GitHub/no-auth behavior, selected general-web-search provider and
availability, cookie replay choice, private raw Set-Cookie retention,
private unsupported-body retention, and network-log policy.

If the runner reports a plan-hash mismatch, the agent
preserves the answers, explains that the approved effective plan
changed, regenerates the plan, and reconfirms. Examples can include
edited source URLs, source/output/scope/settings changes, or
date-derived prior-art/provenance window rollover. The agent does not
start the review until the user selects exact `Run review`.

Remote clones are anonymous: SSH, HTTP, embedded credentials, credential
helpers, `_netrc`/`.netrc`, inherited auth variables, proxies, and automatic
curl/Git redirects are disabled. During execution only, the trusted runner
may manually follow at most three HTTP 301 smart-Git discovery hops when each
target remains on the original HTTPS origin, compared as normalized DNS host
plus effective numeric port. Host comparison is case-insensitive, implicit
port 443 equals explicit port 443, and changed hosts, ports, or subdomains are
forbidden. Other 3xx responses, downgrade, credentials,
IP/local/reserved/private targets, unsafe encodings, queries, fragments,
paths, loops, and hop exhaustion fail closed before following. The runner
reuses the original all-public DNS pins at every hop and for later Git
`ls-remote`, clone, and fetch operations. A final same-origin effective
endpoint is internal transport state; it never replaces the selected source,
including its `.git` endpoint, in the plan, approval, persisted state, or
preferences. Git 2.41 or newer is required.

Local repository paths are not supported input. The runners accept only
anonymously readable public HTTPS Git repository URLs and reject local
paths before any `.git` inspection, origin/`HEAD` resolution, DNS
lookup, or network access.

For programmatic invocation, installed plugin agents are namespaced:

```text
copilot --agent rhyolite:repo-review --prompt "..."
```

## Use the batch runner directly

```bash
./plugins/rhyolite/skills/readonly-repository-review/scripts/run-parallel-reviews.sh \
  --repo https://github.com/owner/repository-one \
  --repo https://gitlab.com/owner/repository-two \
  --output-root "$HOME/rhyolite-output/repo-review" \
  --scope 2
```

For one exact commit, add `--commit <full-sha>`. Session timeouts
default by scope to 60, 120, and 240 minutes respectively;
`--timeout-minutes` overrides the default up to 720 minutes.

Repository-list files must contain only public HTTPS URLs, one per line.
Local paths are rejected explicitly. The global commit option is valid
only for one remote URL.

When an output root or scope is omitted in a terminal, the runner offers
the safe default and scope guidance interactively. Use
`--non-interactive` for automation; automation defaults to scope 1.
The direct runner is a lower-level interface than the agent: its
interactive prompt order can differ, but it still resolves and enforces
the same effective plan and plan approval hash before execution.

The runner does not guess whether authentication will work. It gives each
child the current environment-token, system-keychain, GitHub CLI fallback,
or BYOK path and lets the actual child invocation verify it. Login
metadata and any configured plaintext Copilot token are copied only into a
unique user-only temporary runtime home, never into the read-only
checkout. Authentication variables are marked secret for child tools.
After the child exits, the runner persists only sanitized settings and
allowlisted session-state/session-store files, then deletes the temporary
runtime home.

The Bash runner also requires Python 3 for public DNS classification and the
bundled stdio research broker, plus curl for trusted-runner-only anonymous
smart-Git execution preflight. curl does not grant child agents web access or
enable research; scope 1 remains research-off. The broker is the explicitly
approved constrained exception to the Bash-first architecture and uses only
the Python standard library.

The legacy Bash research switches remain available. Public research is
opt-in and uses only the constrained local broker. Evidence-based
provenance review for agentically generated code is separately opt-in:

```text
--enable-public-research --enable-provenance-research
```

Advanced direct-runner options are:

```text
--research-provider local-broker
--research-policy default|<trusted-policy.json>
--research-web-search-provider duckduckgo-html-v1|none
--research-cookies off|ephemeral
```

Provider and policy selection are not guided pickers. A custom policy
must be trusted, outside Git worktrees and target/output roots, and can
only select bundled adapters, tighten bounded behavior, or explicitly
enumerate additional TLS-only ports under the hard safety floor. It
cannot enable HTTP, private destinations, authentication, proxies,
arbitrary executables, TLS bypass, or cross-run state.

Provenance output is evidence-only and must receive human review before it
is shared.

At the end of an interactive run, the runner asks whether to open the
local HTML index. Use `--open-html` to open it automatically or
`--no-open-html` to disable opening. Allow-all/YOLO sessions also open
it automatically unless disabled.

## Output

The default hierarchy separates the Rhyolite tool, command, run, and
repository:

```text
~/rhyolite-output/repo-review/<run-id>/<repository-subdirectory>/
```

Run-level index, manifest, state, and handoff files live under
`<run-id>/`; each reviewed repository has its own child directory.

Each repository output directory creates:

- `review.txt`: final UTF-8, LF-only canonical report for Linux inline
  email; it remains simple plain text.
- `review.md`: safe Markdown with trusted generated navigation for exact
  allowlisted report headings, fixed links to sibling formats and the run
  index, inert indented-code report chunks, and a deduplicated external
  references block containing only conservatively validated public HTTPS
  URLs.
- `review.html`: escaped local HTML with the same trusted generated
  navigation/reference surfaces, fixed sibling/run-index links, no scripts or
  remote assets, a restrictive CSP, and a no-referrer policy. External links
  use `noopener`, `noreferrer`, `nofollow`, `external`, and
  `referrerpolicy="no-referrer"`.
- `analysis-timeline.txt`: complete sanitized agent progress output.
- `session.md`: Copilot session transcript wrapped as inert Markdown text.
- `request.txt`: exact rendered request.
- `errors.txt`: sanitized standard error output.
- `state.json`: source kind, public remote URL, requested and resolved
  commits, status, scope, `ResearchTransport`, research status/paths, and
  saved session IDs.
- `handoff.md`: safe continuation guidance, research/private-evidence
  warning, and artifact inventory.
- `agent-state/`: isolated Copilot home and persisted session state.
- `research/` for scope `2`/`3`:
  - canonical plain-text `research.txt`, plus `research-timeline.txt`,
    `research-session.md`,
    `research-errors.txt`, and `research-state.json`.
  - `network/summary.json` and `network/events.jsonl`, the sanitized
    transport evidence available to synthesis.
  - mode-0700 `network/private/` with mode-0600 `cookies.jsonl`,
    `body-manifest.jsonl`, and content-addressed
    `bodies/<sha256>.bin`.
- `review-plan.json` and companion review-plan artifacts, when produced
  by the installed runner's plan-only mode, containing the authoritative
  pre-run plan shown as `EFFECTIVE REVIEW PLAN`.

The run directory adds `manifest.json`, `state.json`, `handoff.md`, and
`index.html`, plus any run-level review-plan artifacts emitted by the
installed runner during guided setup.

The runners anonymously clone every target into a separate workspace, pin
the reviewed commit, and create a read-only `.git`-free source snapshot
under a clean, non-Git session root. Before that clone, they perform a
real anonymous accessibility preflight with pinned public DNS and disabled
credentials, helpers, proxies, and automatic redirects. Only the bounded
explicit same-origin HTTP 301 discovery described above is allowed.
Repository hooks, custom instructions, and project skills cannot become
executable child configuration. Child agents deny write and shell tools. The
research worker receives only snapshot-contained reads/searches and the exact
broker tools; the main worker receives snapshot reads/searches plus the
sanitized dossier and network summary. Automatic
temporary-directory access and remote export are disabled; the trusted
wrapper supplies a bounded, sanitized, exact-commit collection of Git
metadata in the request. The collection and wrapping are trusted; ref names,
paths, author and committer names, commit subjects, and selected sanitized
commit trailer values remain attacker-controlled evidence. The history is
limited to the latest 100 commits and excludes email addresses and full commit
bodies. Each logical field is sanitized before its rendered-line bound is
applied; the 64 KiB aggregate keeps whole newest-first commit records and emits
an inert marker when older records are omitted.

The workspace root itself must not be inside a Git worktree. The trusted
runner alone writes the artifact workspace, which must be physically
disjoint from the clone workspace. Text artifacts remove terminal controls
and redact email addresses; Markdown treats untrusted content as code
text except for the fixed trusted navigation and syntax-validated HTTPS
reference block. HTML escapes all report and metadata content. Rendering does
not perform DNS or network access and never emits remote images, scripts, or
styles.

Saved session IDs are evidence for handoff, not an invitation to run
`copilot --resume` directly. A direct resume may omit the original path,
tool, network, and environment restrictions; continue through the trusted
`repository-review` workflow.

## Security and privacy

Read [SECURITY.md](SECURITY.md), [PRIVACY.md](PRIVACY.md), and
[docs/THREAT-MODEL.md](docs/THREAT-MODEL.md) before using the plugin.

Important defaults:

- Repository files and web pages are untrusted input.
- Target code is never built, installed, or executed.
- Target repositories are never modified.
- Local repository paths are rejected; supply only public HTTPS Git
  repository URLs.
- The outer onboarding hooks are local and display-only. They perform no
  network access, Git commands, writes, prompt mutation, or
  environment/auth inspection.
- The full welcome panel appears only when the
  `rhyolite:repo-review` agent handles exact `help`, and it is rendered
  directly from the agent prompt.
- Anonymous clone processes cannot read user Git credentials or proxy
  settings.
- Review artifacts are written only to a separately approved local
  workspace.
- Checkout and output workspace roots cannot be inside Git worktrees.
- Public research is disabled unless explicitly requested. Scope 1
  creates no broker process, MCP config, cookie jar, or research/network
  artifact.
- Scope 2/3 research never imports credentials, cookies, proxies, netrc
  state, browser state, client certificates, or target-provided provider
  settings.
- Scope 2/3 general web search defaults to the fixed anonymous
  `duckduckgo-html-v1` provider. Explicit `none` disables that interface
  fail-closed.
- Raw Set-Cookie values and unsupported bodies are private local evidence
  and never appear in model inputs or rendered reports.
- Scope 3 provenance review for agentically generated code is disabled
  unless explicitly requested.
- Every scope validates the required agent-targeting/review-manipulation
  section. Scope 3 additionally fails closed if the generated-code provenance
  section or any required field is missing, or if heuristic model confidence
  is `High` or inconsistent with the controlled no-candidate values.
- Reports omit author email addresses and avoid unsupported attribution.
- Isolated child review homes still set `disableAllHooks`, so nested
  review sessions do not inherit the onboarding hook.
- Users run under their own Git and Copilot identity.
- No telemetry or report upload is implemented by this plugin.

## Validate

Run validation on Fedora Linux 44:

```bash
bash ./tests/validate-all.sh
```

The fail-fast validation gate runs the focused harness contract checks
before the legacy monolithic plugin validator. Together they cover
manifests, launcher smoke tests, public-source rejection order,
anonymous preflight and clone arguments, source-aware state, prompt
placeholders, split picker/TUI runtime validation, Bash syntax, line
endings, and forbidden permission defaults. They do not execute code
from a reviewed repository.

`AGENTS.md` is the canonical development contract. Harness changes must also
follow `docs/ADDING-A-HARNESS.md`; production support remains Copilot-only
until a separately approved adapter satisfies that playbook in full.

## Name

The project name references the historical RHYOLITE
signals-intelligence satellite program. This software is unrelated to
that program.

## Publishing

See [docs/PUBLISHING.md](docs/PUBLISHING.md).
