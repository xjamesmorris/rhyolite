# Developer guide

Rhyolite is developed, validated, and released on **Fedora Linux 44**.
Other Fedora versions and Linux distributions may work, but all validation
so far has been on Fedora Linux 44. Contributions and test reports from
other Linux flavors are welcome; Fedora Linux 44 remains the release
validation baseline. Non-Linux operating systems remain unsupported.
See [docs/PLAN-OF-RECORD.md](docs/PLAN-OF-RECORD.md).
Read [AGENTS.md](AGENTS.md) first; it is the canonical repository-wide
development contract for human contributors and coding agents.

## Development model

Rhyolite is source-loaded by GitHub Copilot CLI and by Claude Code. There is
no compile or package build step. Bash is the canonical implementation language for
launchers, helpers, review orchestration, artifact rendering, and
validation.

The bundled `research-egress-broker.py` is the explicitly approved constrained
exception to the Bash-first rule. Python 3's standard library provides
the TLS, HTTP, DNS, cookie, HTML, JSON, XML, hashing, and stdio MCP
primitives needed for deterministic transport enforcement without a
runtime dependency graph. Bash remains authoritative for planning,
policy-path trust, lifecycle, failure mapping, artifact finalization,
and cleanup. Do not add PowerShell parity or another broker runtime.

The review target is always untrusted evidence. Never execute target
code, install target dependencies, inspect a selected local working
tree, weaken anonymous clone isolation, or grant the child review
session write or shell access.

## Fedora 44 toolchain

Install the required packages:

```bash
sudo dnf install -y \
  bash \
  findutils \
  gawk \
  git \
  nodejs24 \
  nodejs24-npm \
  python3 \
  tar \
  curl
```

Install GitHub Copilot CLI using an official method:

```bash
curl -fsSL https://gh.io/copilot-install | bash
```

Or:

```bash
npm install -g @github/copilot
```

Install Claude Code (validated with 2.1.292) using an official method:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

Verify the toolchain:

```bash
git --version
bash --version
node --version
npm --version
python3 --version
curl --version
copilot --version
claude --version
```

Git 2.41 or newer, Python 3, and curl are required for runner execution.
Authenticate from a clean directory outside every Git worktree:

```bash
mkdir -p "$HOME/rhyolite-work"
cd "$HOME/rhyolite-work"
copilot login
claude auth login
```

## Plugin discovery and launch

From the repository root:

```bash
copilot --plugin-dir ./plugins/rhyolite plugin list
claude plugin validate ./plugins/rhyolite
```

Use the repository-root launcher, adding `--harness claude` for Claude Code:

```bash
./rhyolite --repo https://github.com/owner/repository
./rhyolite --harness claude --repo https://github.com/owner/repository
```

The root wrapper remains delegation-only. The packaged implementation is
`plugins/rhyolite/bin/rhyolite`.

## Reasoning policy

- Use maximum available reasoning effort by default for every
  development task in this repository.
- This repository-wide policy persists across sessions. Carry it into
  every development handoff or continuation note.
- Downgrade only mechanical or fully scoped work, and only to high
  reasoning effort.
- Keep analytical or open-ended work at maximum effort. Never use none,
  minimal, low, or medium effort for repository development.
- Use a current frontier reasoning model; do not silently downgrade.

Supported launcher and child review invocations pass
`--reasoning-effort max` and `--context long_context`.

## Validation

Run the narrowest relevant check first:

| Change | Minimum validation |
| --- | --- |
| One Bash file | `bash -n <file>` |
| Research broker/policy | `python3 tests/test-research-egress-broker.py` |
| Terminal UI validator | `node tests/validate-tui-runtime.mjs --self-check` |
| Plugin/runtime behavior | `bash ./tests/validate-plugin.sh` |
| Public-release tooling | `bash ./tools/public-release/test-public-release.sh` |
| Marketplace installation | `bash ./tests/test-install.sh` |
| Text changes | `git diff --check` |
| Plugin discovery | `copilot --plugin-dir ./plugins/rhyolite plugin list` and `claude plugin validate ./plugins/rhyolite` |

The authoritative release validation command is:

```bash
bash ./tests/validate-all.sh
```

The fail-fast aggregate runs `tests/validate-harness-contract.sh` before the
legacy `tests/validate-plugin.sh` stage. The harness contract validator also
runs the Claude Code adapter section, `tests/harness-contract-claude.sh`. Run it locally on Fedora Linux 44.
There is no hosted CI requirement.

The plugin validator includes focused Bash helper regressions for shared
launcher-state resolution, canonical report/dossier extraction, and streaming
sanitization. Installation tests verify complete package contents, Git-free
local marketplaces, synthetic prior-version manual updates, and isolated
failure behavior; they do not replace the published-repository release smoke
checks.

## Architecture contracts

Changes to these surfaces normally move together:

- `VERSION`, `plugins/rhyolite/plugin.json`,
  `plugins/rhyolite/.claude-plugin/plugin.json`,
  `.github/plugin/marketplace.json`, `.claude-plugin/marketplace.json`, and
  `CHANGELOG.md` for releases.
- `AGENTS.md`, tool-specific bootstrap pointers, `DEVELOPERS.md`, and
  contributor checklists when the canonical development contract changes.
- `plugins/rhyolite/lib/harness/common.sh`, the selected adapter,
  `run-parallel-reviews.sh`, `tests/validate-harness-contract.sh`,
  `tests/harness-contract-claude.sh` for the Claude Code adapter,
  `docs/HARNESS-ARCHITECTURE.md`, and
  `docs/ADDING-A-HARNESS.md` for harness contract changes.
- `branding/banner.txt`, `scripts/show-welcome-panel.sh`, the embedded
  prompt-native panels in both orchestrators, `claude/hooks.json`,
  `tests/validate-tui-runtime.mjs`, and `tests/validate-plugin.sh` for
  onboarding changes.
- `bin/rhyolite`, `scripts/launcher-preferences.sh`, the guided setup
  instructions, and launcher smoke tests for startup preferences.
- `skills/readonly-repository-review/review-prompt.txt`,
  `research-prompt.txt`, `research-policy.json`,
  `research-event-integers.json`,
  `scripts/research-egress-broker.py`,
  `scripts/launch-research-egress-broker.sh`,
  `scripts/run-parallel-reviews.sh`, the Copilot and Claude Code worker
  agents, and validation for research/prompt/runner behavior.
- `skills/readonly-repository-review/SKILL.md`, both harness agent copies, and
  return-contract validation whenever `RHYOLITE_AGENT_SELF_CHECK_V2` or a
  main-report, security-pass, research-dossier, repair-JSON, or guided-summary
  self-check changes. Shared and harness-specific copies must not diverge.
- `scripts/review-output.sh` and validation for artifact rendering and
  sanitization.
- `tests/test-research-egress-broker.py` for offline URL, DNS, TLS,
  redirect, cookie, body-retention, provider, budget, and stdio MCP
  protocol coverage. Production code may use constructor-level injected
  collaborators in tests, but no runtime argument may disable the
  immutable safety floor.
- `tools/public-release/` and its Bash test for export or publication
  policy changes.

Repository-only validator agents must never be packaged under
`plugins/rhyolite/agents/`.

GitHub Copilot CLI and Claude Code are the production harnesses. The no-op
adapter belongs only under `tests/fixtures` and may be loaded only through
test-owned fixed fixture wiring. It must never be added to the production
registry, plugin assets, launcher choices, marketplace metadata, or public
support claims. Follow [docs/ADDING-A-HARNESS.md](docs/ADDING-A-HARNESS.md)
for Contract-v7 work and any future adapter.
[docs/CLAUDE-HARNESS-EVIDENCE.md](docs/CLAUDE-HARNESS-EVIDENCE.md) records the
probes and real runs behind the Claude Code adapter's capability values.

`bash tests/test-report-repair.sh` covers the report-only confidence edit
protocol and deterministic Markdown-table normalization. The aggregate gate
also runs it. Keep the strict report validator
unchanged; repair replies are exact edit descriptors, not replacement reports.
The runner owns the sole bounded attempt, canonical promotion, interruption,
cleanup, and synchronized repair artifacts/state.

Harness child output is structured, never terminal-rendered text. Copilot
CLI print mode renders text stdout as Markdown for a terminal: it wraps at
the terminal width, re-indents and renumbers lists, inserts blank lines, and
emits OSC 8 hyperlink escapes even under `--no-color`, so a raw text reply
can never byte-match what the model wrote. Every Copilot child runs with
`--output-format json`, and `harness_normalize_worker_output` turns the JSONL
event stream into a readable narrative plus the exact final
`assistant.message` while rejecting any recorded model or `reasoning_effort`
other than the approved plan and any recorded subagent event. The mocked
validators emit the same event
shapes. Before changing an adapter's output assumptions, re-verify the
real CLI with a cheap live probe, for example
`copilot -p 'Reply with exactly: 1. one' --model gpt-5-mini --no-color
--stream off --silent --output-format json --available-tools ''`, and
compare the `assistant.message` `content` with the text-mode stdout; the
mocked validators cannot detect a CLI rendering change on their own.

No Rhyolite worker receives a subagent tool. A live probe with an isolated
`COPILOT_HOME` whose `settings.json` pinned `subagents.agents.explore.model`
showed that a `task` call's `model` argument still wins
(`subagent.started` records `taskModelSource: "task_argument"` and
`modelSelectionSource: "explicit_override"`), so the review worker's
available tools are exactly `view,glob,rg,skill` and the worker performs the
dedicated security pass itself. Re-run that probe before ever offering
`task`, `list_agents`, or `read_agent` to a worker again, and only if the
CLI gains a configuration that rejects the override.

`harness_detect_worker_violation` is the live counterpart of the normalizer.
The runner's `wait_for_monitored_worker` calls it every
`RHYOLITE_WORKER_WATCH_INTERVAL_SECONDS` loop iterations (five, counted per
one-second sleep rather than by wall clock, so the mocked frozen `date` in
the validators still exercises it); the adapter scans only the complete
lines appended since the runner-owned cursor and returns
`RHYOLITE_HARNESS_WORKER_VIOLATION_STATUS` on the first recorded model,
effort, or subagent outside the approved plan. The runner then terminates
the child's process tree and records the `harness_detect_worker_violation`
stage; `tests/validate-harness-contract.sh` proves the whole path with a
mock that emits a `subagent.started` event and then blocks.

Scope 1 must remain transport-free: no research worker, MCP config,
broker process, cookie jar, or research/network artifact. Scope 2/3 must
complete dedicated research first, bind the broker acceptance proof to the raw
final assistant reply before sanitization, and pass only the validated
sanitized dossier and summary to the main worker. Keep the exact five-tool MCP
contract stable unless the prompt, broker, runner, agents, tests, and
documentation are intentionally versioned together.

`research-event-integers.json` is the shared producer/consumer inventory for
every exact JSON integer emitted in the broker event ledger, including nested
and optional fields. The broker rejects an undeclared integer before writing
an event, and the runner applies the same inventory plus event-specific
relationships and bounds. Accepted dossier-validation events record only
`ClaimEntryCount` values from `0` through `100`. Rejected events record the
observed count before acceptance enforcement; it may be `null` when no claim
section was processed or an exact integer through `209715`, the maximum
possible under the 2 MiB candidate bound and the shortest recognized claim
entry line. The observed rejected count is diagnostic history, not an accepted
claim allowance.

## Release checks

Before release:

1. Synchronize `VERSION`, both `plugin.json` manifests, both
   `marketplace.json` registries, and `CHANGELOG.md`.
2. Run `git diff --check`.
3. Run `node tests/validate-tui-runtime.mjs --self-check`.
4. Run `bash ./tests/validate-all.sh`.
5. Run `bash ./tools/public-release/test-public-release.sh`.
6. Run `bash ./tests/test-install.sh`.
7. Verify plugin discovery with Copilot CLI and `claude plugin validate`.
8. Export and preflight the approved source ref.
9. Create the matching stable tag from the approved public commit.

## Deferred work

- Additional platform support may be reconsidered later through a new
  explicit project decision.
- Private repository support remains deferred pending an approved
  least-privilege credential and audit design.
