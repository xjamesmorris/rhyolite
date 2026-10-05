# Developer guide

Rhyolite is developed, validated, and released on **Fedora Linux 44**.
Other operating systems and Linux distributions are outside the current
validation matrix. See [docs/PLAN-OF-RECORD.md](docs/PLAN-OF-RECORD.md).
Read [AGENTS.md](AGENTS.md) first; it is the canonical repository-wide
development contract for human contributors and coding agents.

## Development model

Rhyolite is source-loaded by GitHub Copilot CLI. There is no compile or
package build step. Bash is the canonical implementation language for
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

Verify the toolchain:

```bash
git --version
bash --version
node --version
npm --version
python3 --version
curl --version
copilot --version
```

Git 2.41 or newer, Python 3, and curl are required for runner execution.
Authenticate from a clean directory outside every Git worktree:

```bash
mkdir -p "$HOME/rhyolite-work"
cd "$HOME/rhyolite-work"
copilot login
```

## Plugin discovery and launch

From the repository root:

```bash
copilot --plugin-dir ./plugins/rhyolite plugin list
```

Use the repository-root launcher:

```bash
./rhyolite --repo https://github.com/owner/repository
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
| Plugin discovery | `copilot --plugin-dir ./plugins/rhyolite plugin list` |

The authoritative release validation command is:

```bash
bash ./tests/validate-all.sh
```

The fail-fast aggregate runs `tests/validate-harness-contract.sh` before the
legacy `tests/validate-plugin.sh` stage. Run it locally on Fedora Linux 44.
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
  `.github/plugin/marketplace.json`, and `CHANGELOG.md` for releases.
- `AGENTS.md`, tool-specific bootstrap pointers, `DEVELOPERS.md`, and
  contributor checklists when the canonical development contract changes.
- `plugins/rhyolite/lib/harness/common.sh`, the selected adapter,
  `run-parallel-reviews.sh`, `tests/validate-harness-contract.sh`,
  `docs/HARNESS-ARCHITECTURE.md`, and
  `docs/ADDING-A-HARNESS.md` for harness contract changes.
- `branding/banner.txt`, `scripts/show-welcome-panel.sh`, the embedded
  prompt-native panel, `tests/validate-tui-runtime.mjs`, and
  `tests/validate-plugin.sh` for onboarding changes.
- `bin/rhyolite`, `scripts/launcher-preferences.sh`, the guided setup
  instructions, and launcher smoke tests for startup preferences.
- `skills/readonly-repository-review/review-prompt.txt`,
  `research-prompt.txt`, `research-policy.json`,
  `scripts/research-egress-broker.py`,
  `scripts/launch-research-egress-broker.sh`,
  `scripts/run-parallel-reviews.sh`, both worker agents, and validation
  for research/prompt/runner behavior.
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

GitHub Copilot is the only production harness. The no-op adapter belongs
only under `tests/fixtures` and may be loaded only through test-owned fixed
fixture wiring. It must never be added to the production registry, plugin
assets, launcher choices, marketplace metadata, or public support claims.
Follow [docs/ADDING-A-HARNESS.md](docs/ADDING-A-HARNESS.md) for Contract-v3
work and any future adapter.

Scope 1 must remain transport-free: no research worker, MCP config,
broker process, cookie jar, or research/network artifact. Scope 2/3 must
complete dedicated research first and pass only the validated sanitized
dossier and summary to the main worker. Keep the exact five-tool MCP
contract stable unless the prompt, broker, runner, agents, tests, and
documentation are intentionally versioned together.

## Release checks

Before release:

1. Synchronize `VERSION`, `plugin.json`, `marketplace.json`, and
   `CHANGELOG.md`.
2. Run `git diff --check`.
3. Run `node tests/validate-tui-runtime.mjs --self-check`.
4. Run `bash ./tests/validate-all.sh`.
5. Run `bash ./tools/public-release/test-public-release.sh`.
6. Run `bash ./tests/test-install.sh`.
7. Verify plugin discovery.
8. Export and preflight the approved source ref.
9. Create the matching stable tag from the approved public commit.

## Deferred work

- Additional platform support may be reconsidered later through a new
  explicit project decision.
- Private repository support remains deferred pending an approved
  least-privilege credential and audit design.
