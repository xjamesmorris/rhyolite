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
- Contributes local, display-only outer-session hooks. `sessionStart`
  emits one plain version/start line for ordinary loads or the
  exactly-once launcher plaque. The `userPromptSubmitted` command hook
  emits a plaque only for exact manual review-start commands and ignores
  internal resumes, marker-bearing continuations, launcher prompts, and
  unrelated text. Neither hook performs network access, Git commands,
  writes, prompt mutation, or environment/auth inspection.
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
- Removes direct `web_fetch` and broad URL approval from every child.
- For scopes 2/3, launches a dedicated research worker before the main
  reviewer with exactly five local broker tools. The main reviewer receives
  only a validated read-only sanitized dossier and network summary.
- Starts one bundled local stdio broker per repository through an ephemeral
  mode-0600 MCP configuration and a minimal `env -i` launcher. The launcher
  does not inherit proxy, netrc, GitHub, Copilot, SSH-agent, browser-cookie,
  client-certificate, or model-provider credentials.
- Restricts broker transport to GET/HEAD over HTTPS on approved TLS ports,
  rejects URL userinfo and IP literals, resolves every initial/redirect host,
  requires every DNS answer to be globally routable, connects to a pinned
  address, and verifies TLS/SNI/hostname against the original host.
- Revalidates and bounds redirects; applies fixed safe headers, per-host
  pacing, request/concurrency/time/header/body/normalized-output limits, and
  never accepts model-supplied headers or request bodies.
- Implements general web search only through the closed in-code, fixed-endpoint
  anonymous `duckduckgo-html-v1` adapter. It unwraps provider redirect URLs,
  revalidates every result through the public-HTTPS floor, deduplicates and
  bounds URL/title/summary output, returns structured provider failures, and
  never configures credentials, caller headers, request bodies, proxies,
  challenge bypass, or fallback providers. Explicit `none` remains fail-closed.
- Keeps TLS verification mandatory. After verification failure, a second
  metadata-only diagnostic handshake may fingerprint and describe the
  presented leaf certificate, but sends no HTTP request and never converts the
  failed retrieval into success.
- Supports normalized HTML, text, JSON, XML, RSS, and Atom evidence. Active
  HTML elements are stripped. Unsupported or binary bodies are retained only
  as private content-addressed `.bin` evidence and are never rendered, parsed,
  indexed, linked individually, or exposed to a model. Because normalization
  can omit active-resource details, sensor detection from external pages is
  explicitly limited; Rhyolite does not activate resource URLs merely to test
  tracking behavior.
- Keeps research cookie replay off by default. Optional replay uses a fresh
  empty per-repository/per-run jar and only bounded exact-host Secure cookies.
  Wider Domain cookies and insecure/oversized/expired cookies are rejected.
  No jar is imported or reused.
- Retains raw Set-Cookie values in a private mode-0600 ledger in either cookie
  mode. Sanitized model/report surfaces contain only names, attributes, value
  hashes, rejection reasons, and aggregate observations.
- Validates the broker capability record, exact tool list, policy digest,
  request ledger, at least one successful public response, canonical research
  dossier, and broker/MCP/runtime cleanup before the main worker starts.
- Fails closed with distinct `ResearchCapabilityFailed` and `ResearchFailed`
  states when the transport/tool contract is unavailable, the phase has no
  successful public response, the dossier is malformed, or cleanup is unsafe.
- Supplies a bounded, sanitized, exact-commit collection of Git metadata from
  the trusted wrapper. The collection and wrapping are trusted; ref names,
  paths, author and committer names, commit subjects, selected sanitized
  commit trailer values, and other metadata content remain attacker-controlled
  untrusted evidence. The history is limited to the latest 100 commits and
  excludes email addresses and full commit bodies. Each logical field is
  sanitized before its rendered-line bound is applied; the 64 KiB aggregate
  keeps whole newest-first commit records and emits an inert marker when older
  records are omitted.
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
- Keeps canonical report bodies inert in Markdown and HTML. Only exact
  allowlisted report headings become trusted generated TOCs/anchors.
- Generates external-reference links only from the already-sanitized canonical
  report and only after conservative syntax validation. Non-HTTPS URLs,
  userinfo, IP literals, localhost/internal suffixes, malformed escapes,
  controls/whitespace, unsafe delimiters, and credential-like query
  keys/values remain inert. Rendering performs no DNS or network access and
  emits no remote images, scripts, or styles.
- Applies a restrictive CSP and no-referrer policy. Generated external HTML
  links use `noopener noreferrer nofollow external` and
  `referrerpolicy="no-referrer"`.
- Wraps transcripts and handoff values as inert Markdown code text.
- Fails closed unless every report contains the exact all-scope
  `AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT` contract. Scope 3 also
  requires the exact `GENERATED-CODE PROVENANCE ASSESSMENT`, its required
  fields, and a bounded generation verdict.
- Restricts direct model, effort, and harness provenance attribution to
  directly bound commit-specific attestations, transcripts, provenance
  records, or explicit disclosures. Heuristic model candidates are separate,
  explicitly non-attributive, limited to repository assets rather than people,
  preferably family-level, and require path/commit/public evidence,
  counterevidence, alternatives, and `Not applicable`, `Low`, or `Medium`
  confidence, never `High`. Configuration files, style, quality, verbosity,
  test density, bulk commits, and generic fingerprints alone are not proof, and
  absent evidence never proves human generation.
- Performs network activity only for user-requested anonymous clones and,
  when enabled, the approval-bound local research broker.
- Does not perform background network requests or telemetry uploads.

The custom agent delegates every review to the bundled runner, including
a single repository, so child review sessions retain the command-line
permission boundary. Users still approve the wrapper command and
writable output location unless they intentionally use allow-all/YOLO
mode. The onboarding hook is display-only and does not auto-select a
source, output path, scope, or any unrelated session workflow.

The Rhyolite launcher rejects the retired `--autopilot` option with exit
code `2` and explicitly starts Copilot in interactive mode. Switching the
outer session to plan or autopilot during setup or execution is unsupported;
the approved worker model remains explicit and plan-bound. Exact `stop` or
`cancel` requests terminate the tracked runner process tree and preserve
truthful `Interrupted` artifacts.

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

Research policy/provider selection is an advanced trusted runner surface, not
a guided picker. Policy schema 1 accepts only the bundled `local-broker`,
direct HTTPS adapter, anonymous GitHub adapter, fixed anonymous
`duckduckgo-html-v1` adapter, and explicit `none`. A custom policy is reduced
to an effective digest and cannot enable plaintext, private destinations,
authentication, arbitrary executables or remote MCPs, TLS bypass, imported
cookies, proxies, configurable endpoints, or cross-run state.

## Reporting a vulnerability

Report suspected vulnerabilities through
[GitHub private vulnerability reporting](https://github.com/xjamesmorris/rhyolite/security/advisories/new).
Do not open a public issue containing credentials, non-public repository
content, or working exploit details.

Before public release, configure branch protection and required status
checks, make the repository public, and enable GitHub private
vulnerability reporting before announcing availability.
