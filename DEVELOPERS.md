# Developer guide

This guide covers local development of the Rhyolite GitHub Copilot CLI
plugin. Start with Fedora 44 below; additional environment sections can
be added independently as their commands and validation coverage are
verified.

See also [README.md](README.md), [CONTRIBUTING.md](CONTRIBUTING.md),
[docs/PUBLISHING.md](docs/PUBLISHING.md), [SECURITY.md](SECURITY.md), and
[SUPPORT.md](SUPPORT.md).

## Development model

Rhyolite is source-loaded by GitHub Copilot CLI. There is no compile,
bundle, or package build step. Development consists of editing plugin
metadata, Markdown agent/skill contracts, JavaScript, Bash, and
PowerShell, then running the repository validators.

The review target is always untrusted evidence. Do not run Copilot
orchestration inside a target repository, execute target code, install
target dependencies, or weaken the anonymous-clone and read-only
snapshot boundary.

## Toolchain

| Tool | Requirement | Used for |
| --- | --- | --- |
| Git | 2.41 or newer | Anonymous accessibility preflight, exact-commit verification, and DNS-pinned clone enforcement |
| Bash | Bash-compatible scripts; preserve macOS Bash 3.2 syntax | Linux/macOS launchers, helpers, runners, and validation |
| PowerShell | PowerShell 7 | Windows-equivalent launchers, helpers, runners, and validation |
| Node.js | 22 or newer recommended | Shared validators, extensions, public-release tooling, and npm-based Copilot CLI installation |
| Python | Python 3 | Public-DNS checks in the Bash review runner |
| GitHub Copilot CLI | Current supported release | Source-loaded plugin discovery and review sessions |
| curl | Current distribution package | Tool installation and setup retrieval |
| GitHub CLI | Optional | Maintainer GitHub operations; not required by the plugin |

## Fedora 44 setup

Fedora 44 provides current Git, Bash, Python, and versioned Node.js 24
packages. Install the base development tools:

```bash
sudo dnf install -y \
  git \
  bash \
  python3 \
  nodejs24 \
  nodejs24-npm \
  curl
```

Install PowerShell 7 from the upstream
[PowerShell releases](https://github.com/PowerShell/PowerShell/releases/latest)
using the package or portable archive that matches the host architecture.
Verify the downloaded artifact before installation and ensure `pwsh` is
available on `PATH`.

Install GitHub Copilot CLI using one of its documented methods. The
installer script defaults to a user-local prefix for non-root users:

```bash
curl -fsSL https://gh.io/copilot-install | bash
```

Alternatively, Node.js 22 or newer supports the npm package:

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
pwsh --version
copilot --version
```

Confirm Git is at least 2.41 and Node.js is at least 22. Authenticate
from a clean directory that is not inside any Git worktree:

```bash
mkdir -p "$HOME/rhyolite-work"
cd "$HOME/rhyolite-work"
copilot login
```

## Other environments

### macOS

The Unix launcher and Bash helpers must remain compatible with the
system Bash 3.2 and BSD userland. Do not introduce associative arrays,
`mapfile`, namerefs, `${value,,}`, `readlink -f`, GNU `realpath`, or
other Bash 4+/GNU-only behavior.

Homebrew can provide Git, Node.js, Python, PowerShell, and Copilot CLI:

```bash
brew install git node python
brew install --cask powershell copilot-cli
```

Run both the Bash and PowerShell validators on macOS. A newer installed
Bash may be used interactively, but launcher changes must still satisfy
the Bash 3.2 compatibility contract.

### Windows

Use PowerShell 7, Git, Node.js 22 or newer, Python 3, and Copilot CLI.
Copilot CLI can be installed with:

```powershell
winget install GitHub.Copilot
```

Run the PowerShell validator and installation test natively. Run the
Bash validator in a Linux environment when changing shared Bash/
PowerShell behavior; do not treat Git Bash as proof of Linux or macOS
runtime compatibility.

### Adding another environment

Add a separate subsection with:

1. Authoritative package sources and copyable installation commands.
2. Exact version verification commands.
3. Shell, path, encoding, and terminal limitations.
4. Which validation commands run natively and which require CI.

Do not claim support until the platform-native validator passes.

## Checkout and plugin discovery

From the repository root, verify that Copilot CLI can discover the
development plugin:

```bash
copilot --plugin-dir ./plugins/rhyolite plugin list
```

The recommended development entrypoint is the repository-root checkout
wrapper:

```bash
./rhyolite -- \
  "Review https://github.com/owner/repository"
```

It resolves the checkout's physical path and forwards every argument
unchanged to the canonical packaged launcher at
`./plugins/rhyolite/bin/rhyolite`, which remains the direct packaged
path for release/debug coverage. Keep the wrapper delegation-only so the
canonical launcher's trusted immediate-start environment reaches the
helper path unchanged, including suppression of the ordinary plugin load
line when setup begins at launch.

On Windows:

```powershell
pwsh .\plugins\rhyolite\bin\rhyolite.ps1 -- `
  "Review https://github.com/owner/repository"
```

The checkout wrapper delegates into the packaged launcher, and the
launchers resolve the plugin checkout, select `rhyolite:repo-review`,
and move orchestration to a clean directory outside every Git worktree.
`/rhyolite:start` remains an in-session compatibility path, not the
preferred development launcher.

## Architecture contracts

Changes to these surfaces normally move together:

- `VERSION`, `plugins/rhyolite/plugin.json`,
  `.github/plugin/marketplace.json`, and `CHANGELOG.md` for releases.
- `branding/banner.txt`, both welcome-panel helpers, the embedded
  prompt-native panel in `repo-review.agent.md`, and both validators for
  onboarding changes, including the right-aligned subordinate
  `v<version>` line immediately below the wordmark and
  metadata-aware documentation/support text.
- `run-parallel-reviews.sh` and `run-parallel-reviews.ps1` for runner
  behavior or policy.
- `show-welcome-panel.sh` and `Show-WelcomePanel.ps1` for onboarding
  rendering.
- `review-output.sh` and `ReviewOutput.psm1` for artifact rendering and
  sanitization, including matching email/credential redaction.
- `review-prompt.txt`, both template renderers, and both validators when
  adding or changing a prompt placeholder.
- `commands/start.md`, `commands/repo-review.md`, the extension handoff,
  and `tests/validate-tui-runtime.mjs` for startup routing.
- `.github/agents/rhyolite-ui-validator.agent.md` for finite
  `ask_user` picker validation only.
- `.github/agents/rhyolite-tui-runtime-validator.agent.md` and
  `tests/validate-tui-runtime.mjs` for ANSI, width, no-color, screenshot,
  version-line alignment/gradient placement, and command-handoff
  validation.
- `tools/public-release/` and its tests for export or publication-policy
  changes.

Repository-only development validators must never be copied into
`plugins/rhyolite/agents/`.

## Validation matrix

Run the narrowest applicable check first, then the platform validators
covering the changed behavior.

| Change | Minimum validation |
| --- | --- |
| One Bash file | `bash -n <file>` |
| Terminal UI validator | `node tests/validate-tui-runtime.mjs --self-check` |
| Bash/plugin behavior | `bash ./tests/validate-plugin.sh` |
| PowerShell/plugin behavior | `pwsh ./tests/validate-plugin.ps1` |
| Marketplace installation | `pwsh ./tests/test-install.ps1` |
| Installed agent invocation | `pwsh ./tests/test-install.ps1 -RunAgentSmoke` |
| Public-release tooling | `bash ./tools/public-release/test-public-release.sh` |
| Any text changes | `git diff --check` |

There is no separate lint command. The full validators cover JSON
metadata, exact prompt and policy text, launcher smoke tests, Bash and
PowerShell syntax, mocked runner behavior, artifact schemas, UTF-8
without a BOM, and LF line endings.

Run both full validators whenever both shells are available. The agent
smoke test invokes Copilot and therefore requires valid authentication;
the ordinary installation test does not perform that invocation.

## Change-specific checks

### Plaque and onboarding

Keep the logo within the validator's terminal-width bound, preserve the
solid full/half-block treatment, color only the logo, and keep
onboarding copy in the terminal default foreground. The half-block
contours provide extra vertical resolution without relying on font-
specific shade or braille glyphs. Check both TrueColor and `NO_COLOR`
output through the full validators and the shared Node validator.

### Launchers and command handoff

Keep launchers outside Git worktrees, preserve paths containing spaces,
strip control characters from the initial request, never persist that
request in launcher context, and never add `--allow-all`. Startup
commands must explicitly avoid routing through `skill(start)`.
Launcher and extension failures must retain the safe underlying stage,
detail, and exit/RPC status in a `RHYOLITE ERROR` block. Before the
public owner is resolved, tests must prove that these surfaces use local
support/contribution guidance and never emit placeholder URLs.

### Runner failure experience

Runner failures remain fail-closed but must be explanatory. Keep
repository state status and exit codes truthful, preserve sanitized
`errors.txt` and timeline detail, and render terminal summaries for
anonymous preflight, clone, commit, snapshot, worker, timeout,
incomplete-report, and cleanup stages. Failure fixtures must include
control, email, and credential sentinels so both platform validators
prove detail retention and safe redaction.

### Picker UI

Finite choices use `ask_user`, contain no numeric prefixes, omit an
explicit `Other`, preserve existing answers, and follow the exact choice
order guarded by validation.

### Review runners

Preserve the fail-closed anonymous-access preflight, anonymous public
HTTPS clone, exact commit pin, read-only `.git`-free snapshot, isolated
Copilot home, approval hash, and fail-closed path separation. Never
test a runner by executing code from a selected target repository.

### Public-release files

Run the public-release test in addition to both plugin validators.
Preflight publication against an exported tree, not the development
checkout. Follow [docs/PUBLISHING.md](docs/PUBLISHING.md).

## Deferred work

- [ ] Private repository support remains deferred; do not imply current
  support or implement authentication before approved least-privilege
  credential handling, secret isolation/redaction, auditability, and UX
  design are in place.

## Troubleshooting

### `pwsh` is missing

Install an upstream PowerShell 7 package or portable archive as shown
above. Confirm the executable is on `PATH` with `pwsh --version`.

### Node.js is missing or too old

Install Fedora's `nodejs24` and `nodejs24-npm` packages. Copilot CLI's
npm installation requires Node.js 22 or newer.

### Copilot does not discover Rhyolite

Run from the repository root:

```bash
copilot --plugin-dir ./plugins/rhyolite plugin list
```

Check that `plugins/rhyolite/plugin.json` is readable and start a new
Copilot session after changing plugin commands, agents, hooks, or
extensions.

### `/rhyolite:start` becomes `skill(start)`

Prefer `./rhyolite`, which delegates to
`plugins/rhyolite/bin/rhyolite`, preselects the correct agent, and
submits the trusted start marker. For an existing session, reload the
current plugin checkout and use `/rhyolite:start`; do not manually
invoke a skill named `start`.

### Line-ending or encoding failures

Repository text files must use LF line endings and UTF-8 without a BOM.
Do not let PowerShell or an editor silently introduce CRLF or a BOM.
Run `git diff --check` and the platform validators.

### Workspace safety rejects the current directory

This is a safety gate. Restart through `./rhyolite` (or the canonical
packaged launcher) or start Copilot with `-C` pointing to a clean
directory outside every Git worktree. Guided setup does not discover
local repositories or inspect local origins. Do not bypass the check.

## Releases

For a release:

1. Synchronize `VERSION`, `plugins/rhyolite/plugin.json`,
   `.github/plugin/marketplace.json`, and `CHANGELOG.md`.
2. Run both full validators, installation tests, public-release tests,
   and `git diff --check`.
3. Export and preflight the approved source ref.
4. Create the matching stable `vX.Y.Z` tag from the approved public
   repository commit only.

The complete release process and mandatory publication gates are in
[docs/PUBLISHING.md](docs/PUBLISHING.md).
