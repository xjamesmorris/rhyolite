# Security policy

## Supported version

Only the latest tagged version is supported.

## Security boundary

The plugin treats cloned repositories, Git history, documentation,
issues, source comments, embedded prompts, and public web content as
hostile input.

The supported runner path:

- Accepts only anonymous public HTTPS repository URLs on public DNS
  hosts.
- Rejects embedded credentials, HTTP/SSH transports, IP literals, local
  or reserved hostnames, query strings, fragments, unsafe encodings, and
  control/whitespace characters.
- Resolves repository hosts before cloning, rejects any non-public IP
  answer, and pins the approved addresses through Git's
  `http.curloptResolve`; Git 2.41 or newer is required.
- Disables system and global Git configuration during clone and review.
- Scrubs inherited `GIT_*` discovery, object-store, replacement,
  template, and configuration variables before every wrapper Git
  operation.
- Disables Git hooks, submodules, Git LFS smudging, and interactive Git
  prompts.
- Contributes a local, display-only outer-session `sessionStart` hook
  that emits one plain version/start line after plugin load. A
  display-only `userPromptSubmitted` command hook recognizes only
  trusted Rhyolite start markers/commands and emits the plaque without
  modifying or storing the prompt. Neither hook performs network
  access, Git commands, writes, or environment/auth inspection.
- Runs clone/fetch in a process-local empty home, removes inherited Git,
  Copilot, GitHub, credential-manager, SSH-agent, `_netrc`/`.netrc`,
  and proxy inputs, clears credential helpers and HTTP headers, requires
  TLS verification, and disables redirects.
- Disables repository custom instructions for child Copilot sessions.
- Runs the child from a clean, non-Git session root against a read-only,
  `.git`-free archive snapshot.
- Overrides `export-ignore` and `export-subst` in the clone's
  highest-precedence local attributes while creating the snapshot, then
  restores the attributes.
- Uses isolated child Copilot homes with all hooks disabled, so worker
  sessions do not inherit the outer onboarding hook.
- Restricts custom-agent discovery to local built-in/plugin agents,
  excluding organization and enterprise agents from untrusted child
  sessions.
- Denies all write tools in child review sessions.
- Denies shell tools globally, including for nested specialist agents.
- Supplies bounded, sanitized Git metadata from the trusted wrapper.
- Pre-approves only checkout-contained file reads/searches and disables
  automatic access to the system temporary directory.
- Removes inherited `COPILOT_ALLOW_ALL` from child review processes.
- Disables remote export for child sessions.
- Marks supported inherited authentication variables as secret for child
  tools.
- Gives each child a unique user-only temporary Copilot home containing
  only login metadata and, when configured, plaintext token fields
  needed to use the normal keychain or headless authentication path.
- Persists only sanitized settings and allowlisted session-state/
  session-store files, never the bridged authentication configuration,
  and retries deletion of the temporary runtime home after normal
  completion, timeout, or failure. If the operating system still
  prevents deletion, the runner removes or sanitizes the managed auth
  configuration, marks the review failed, and reports the remaining
  user-only path.
- Treats the active outer session as the initial login check and lets
  the actual child invocation verify environment-token, system-keychain,
  GitHub CLI, BYOK, or bridged authentication. The plugin never launches
  login automatically.
- Does not build, test, compile, install, load, or execute target code.
- Uses the invoking user's Git and Copilot identity; there is no service
  token.
- Resolves links and traversal in clone/output roots, checks that they
  are physically disjoint, creates the roots, and verifies them again
  before use.
- Rejects a checkout workspace inside any Git worktree and atomically
  creates unpredictable run directories before rechecking their physical
  paths.
- Fails closed when checkout or output roots are inside worktrees, bare
  repositories, or Git metadata directories, or when Git isolation
  cannot be verified.
- Writes reports and state only from the trusted wrapper into the
  selected artifact workspace.
- Accepts only anonymously readable public HTTPS Git repository URLs and
  rejects local paths before any Git, DNS, or network access.
- Escapes all untrusted report and metadata content before writing HTML.
- Wraps transcripts and handoff values as inert Markdown code text.
- Performs network activity only for user-requested anonymous clones and,
  when enabled, public research.
- Does not perform background network requests or telemetry uploads.

The custom agent delegates every review to the bundled runner, including
a single repository, so child review sessions retain the command-line
permission boundary. Users still approve the wrapper command and
writable output location unless they intentionally use allow-all/YOLO
mode. The onboarding hook is display-only and does not auto-select a
source, output path, scope, or any unrelated session workflow.

The user-facing orchestrator must itself be started from a clean non-Git
directory. Starting Copilot inside an untrusted target can execute
repository hooks before any plugin instruction or worker isolation takes
effect.

Generated handoffs retain session IDs but do not advertise direct
`copilot --resume` commands, because a direct resume may not restore the
original restrictions.

Headless Linux can use supported environment variables, a local
provider, the GitHub CLI fallback, or Copilot's configured
plaintext-token mode. Plaintext tokens exist only in the temporary
runtime home and are not retained with review artifacts.

## Reporting a vulnerability

Report suspected vulnerabilities through
[GitHub private vulnerability reporting](https://github.com/xjamesmorris/rhyolite/security/advisories/new).
Do not open a public issue containing credentials, non-public repository
content, or working exploit details.

Before public release, configure branch protection and required status
checks, make the repository public, and enable GitHub private
vulnerability reporting before announcing availability.
