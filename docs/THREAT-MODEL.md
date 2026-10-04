# Threat model

## Assets

- The reviewer's workstation and files.
- The reviewer's GitHub and Copilot identity.
- Source code outside the target checkout.
- Accuracy and integrity of generated reports.
- People and projects discussed in provenance findings about agentically
  generated code.

## Untrusted inputs

- Repository files and Git objects.
- Repository instruction, agent, prompt, and skill files.
- Source comments, strings, generated files, and documentation.
- Issues, pull requests, release notes, and commit messages.
- Public web pages, mailing-list posts, social media, and search
  results.
- Broker-normalized HTTP bodies, redirect targets, TLS certificates,
  response headers, cookies, anonymous GitHub search results, and fixed-provider
  general-web-search results.
- Repository URLs supplied to the runner.
- User-selected trusted research policy files and advanced provider/cookie
  settings.
- User-local launcher fleet/model/reasoning/context preference files.
- User-selected output workspace paths and generated artifact paths.

## Primary threats

1. Prompt injection causes the reviewer to execute repository
   instructions.
2. Repository code or hooks execute on the reviewer's machine.
3. A malicious URL invokes an unsafe Git transport or command-line
   option.
4. The agent modifies the target or unrelated files.
5. Public searches disclose private repository information.
6. Broad MCP or shell permissions allow mutation or credential access.
7. Generated reports make unsupported security or provenance claims.
8. Excessive repository count or concurrency consumes unexpected AI
   credits.
9. A writable artifact path overlaps the repository through traversal,
   casing, or a symbolic link.
10. Untrusted report content executes when the local HTML report is
    opened.
11. Parent allow-all mode leaks into an untrusted child review session.
12. Automatic temporary-directory access exposes unrelated local files.
13. A direct session resume omits the original review restrictions.
14. Repository hooks or project skills execute before prompt defenses
    apply.
15. Markdown transcripts trigger outbound image or link requests when
    rendered.
16. A public-looking hostname resolves to a loopback, private,
    link-local, or otherwise non-public address, or changes resolution
    between validation and clone.
17. Git obtains repository credentials from helpers, `_netrc`/`.netrc`,
    inherited auth variables, a proxy, an automatic or cross-origin redirect,
    or a client certificate.
18. A local path is accepted as a review source and triggers filesystem,
    Git metadata, DNS, or network access before the public-source
    contract rejects it.
19. The onboarding hook inspects credentials, mutates local state, or
    hijacks unrelated sessions before the user invokes the review agent.
20. A tampered or mismatched launcher preference silently changes fleet
    mode or model, leaks a selected source, or bypasses review approval.
21. An explicit `--yolo` launch broadens the outer Copilot orchestrator
    to all permissions for that launch. Its allow-all state also makes the
    runner open the local HTML report index without confirmation unless
    that behavior is disabled.
22. The retired launcher `--autopilot` spelling is mistaken for an initial
    request, or an in-session plan/autopilot transition replays the plaque,
    presents a misleading model-change notice, continues the guided review
    outside interactive mode, or prevents a stop request from terminating the
    runner process tree.
23. A research URL or redirect reaches loopback, private, link-local,
    reserved, or rebinding-controlled infrastructure.
24. Research transport inherits authentication, proxies, netrc, browser
    cookies, client certificates, or caller-supplied headers.
25. Server-issued cookies broaden scope, persist across repositories/runs, or
    expose raw tracking identifiers to a model/report.
26. Unsupported bodies or active HTML become executable, rendered, indexed,
    or model-visible.
27. A missing/broken MCP tool, zero-success research phase, malformed dossier,
    or orphaned broker process is mistaken for completed live research.
28. A custom policy/provider path selects target-derived configuration,
    arbitrary executables, remote MCP endpoints, configurable search endpoints,
    credentials, TLS bypass, or a weaker transport floor.
29. A report conflates direct model/effort/harness attribution with heuristic
    model identification, presents a heuristic as verified attribution,
    identifies a person rather than repository assets, assigns High heuristic
    confidence, or infers human generation from absent evidence.
30. Prompt injection, reviewer-directed instructions, poisoned source/docs/
    commit/ref metadata, poisoned datasets or benchmarks, encoded instructions,
    tool-call bait, resource-exhaustion tarpits, or tracking sensors manipulate
    review behavior or conclusions.
31. Trusted Markdown/HTML navigation accidentally promotes arbitrary report
    text or unsafe URLs into active markup, leaks credentials/referrers, or
    causes rendering-time network access.

## Controls

- Anonymous public HTTPS Git URLs on syntactically valid public DNS hosts
  only.
- User-facing orchestration starts from a clean non-Git directory, never
  from inside the target checkout.
- Launcher bootstrap performs syntax-only public-HTTPS canonicalization
  without DNS, Git, authentication, or target inspection and preserves a
  selected terminal `.git` endpoint. The runner independently repeats
  canonicalization and anonymous public-access preflight before clone.
- Exact URL parsing before invoking Git.
- DNS answers are classified before clone; any non-public address rejects
  the source. Approved IPv4/IPv6 addresses are pinned, explicit proxies and
  automatic curl/Git redirects are disabled, and the original validated
  origin and all-public pins are reused for every discovery request and later
  Git `ls-remote`, clone, and fetch.
- During execution only, the trusted runner may manually process at most three
  HTTP 301 smart-Git discovery hops. Every target must retain the original
  HTTPS origin, compared as normalized DNS host plus effective numeric port;
  host comparison is case-insensitive, implicit port 443 equals explicit port
  443, and a changed host, port, or subdomain is cross-origin. Every other
  3xx, downgrade, credential, IP/local/reserved/private destination, unsafe
  encoding, query, fragment, or path, loop, and hop exhaustion is rejected
  before following.
- The selected canonical URL, including a terminal `.git` endpoint, remains
  the source identity in the plan, approval, persisted state, and preferences.
  A final same-origin effective endpoint is internal execution transport state
  only.
- Plan-only remains syntax-only and offline, with no curl, DNS, Git transport,
  harness-runtime, or authentication dependency. curl is trusted-runner-only
  Git preflight machinery and grants no child web permissions; scope 1 remains
  research-off.
- Git 2.41 or newer is required.
- Hooks, submodules, LFS smudging, global Git config, and prompts
  disabled.
- Inherited Git environment variables are removed; only an explicit safe
  Git environment is restored, preventing alternate objects or discovery
  bypasses.
- Separate clone and artifact directory per repository.
- Read-only `.git`-free source snapshots under clean, non-Git session
  roots.
- Snapshot creation neutralizes archive-specific `export-ignore` and
  `export-subst` attributes so tracked content is neither omitted nor
  rewritten.
- Unique user-only temporary Copilot runtime homes with
  `disableAllHooks` enabled, plus separate sanitized persisted homes.
- A local plugin `sessionStart` hook emits one plain version/start line
  for ordinary loads or the exactly-once launcher plaque. A display-only
  `userPromptSubmitted` command hook emits a plaque only for exact manual
  review-start commands and ignores internal resumes, marker-bearing
  continuations, launcher prompts, and unrelated text. Neither hook
  performs network access, Git commands, writes, prompt mutation, or
  environment/auth inspection.
- Native fleet mode and the outer model, reasoning effort, and context tier
  are selected before Copilot starts. The trusted launcher setup block
  contains only canonical source URLs plus constrained
  fleet/model/reasoning/context/remember fields; sources
  remain untrusted data rather than prompt instructions.
- `--yolo` is disabled by default and is an ephemeral per-launch
  outer-orchestrator switch. It opts the outer Copilot orchestrator into all
  permissions but is not persisted in launcher context, copied into the
  trusted launcher setup block, or remembered as a preference. The runner
  reads allow-all state only to decide whether to open the local HTML report
  index automatically; `--no-open-html` disables that behavior.
- The launcher has an explicit retired-option parser branch for
  `--autopilot`; it renders `RHYOLITE ERROR` and exits `2` before Copilot
  starts. It passes `--mode interactive` explicitly. Rhyolite does not support
  plan/autopilot mode during guided setup or execution, and mode-related UI
  notices do not change the approval-bound worker model.
- Launcher startup emits the plaque once from `sessionStart`; the prompt hook
  matches only exact manual review-start commands and ignores internal
  resumes, marker-bearing continuations, and unrelated prompts.
- Exact `stop` and `cancel` intents use targeted execution cancellation. The
  Bash runner propagates INT/TERM/HUP through tracked repository, timeout,
  Copilot worker, and broker processes, then records `Interrupted` state and
  artifacts.
- Per-repository fleet/model/reasoning/context preferences are keyed by a
  SHA-256 hash of the selected canonical public URL, including its terminal
  `.git` endpoint when present, stored under user-only launcher state, and
  parsed against a versioned fixed schema. Missing, mixed, malformed, or
  mismatched preferences are ignored rather than silently applied.
- Preferences are written atomically only after effective-plan approval.
  Fleet mode, model, and remember state are included in `ApprovalHash`;
  preferences never grant source access or bypass runner validation.
- Launcher context and logs do not persist the selected source or
  arbitrary initial request.
- Local-only custom-agent discovery prevents organization/enterprise
  agents from becoming model-invocable in untrusted reviews.
- Child sessions can use environment tokens, system credential stores,
  GitHub CLI fallback, BYOK, or a narrow temporary bridge of Copilot
  login metadata and configured plaintext-token fields.
- Heuristic credential probes do not block cloning. The active outer
  session is the initial authentication check, and the actual child
  invocation determines whether its supported authentication path works.
- The runtime authentication bridge is never placed in the reviewed
  checkout or persisted artifact home. Only allowlisted session-state/
  session-store files and sanitized configuration are retained. Cleanup
  removes or sanitizes the managed auth configuration before retrying
  runtime-home deletion; a persistent operating-system cleanup failure
  marks the review failed and reports the remaining user-only path.
- Canonical, symlink-aware clone/output roots that must be disjoint.
- Repository custom instructions disabled in child sessions.
- Custom agent tools exclude editing.
- Runner denies write and shell tools globally, removes direct Git tools,
  and supplies a bounded, sanitized, exact-commit collection of Git metadata
  from the trusted wrapper. Collection and wrapping are trusted; ref names,
  paths, author and committer names, commit subjects, selected sanitized
  commit trailer values, and all other metadata content remain
  attacker-controlled untrusted evidence. Only the latest 100 commits are
  represented; email addresses and full commit bodies are omitted. Logical
  fields are sanitized before line bounds, and the 64 KiB aggregate retains
  whole newest-first commit records with an inert marker for omitted older
  records.
- Scope 1 creates no broker process, MCP config, cookie jar, or research log.
- Scope 2/3 launches a dedicated research worker before the main reviewer.
  The research worker receives snapshot reads/searches and exactly
  `research_capabilities`, `fetch_public_url`, `search_public_github`,
  `search_public_web`, and `research_network_summary`. The main reviewer
  receives only a validated read-only dossier and sanitized network summary.
- Direct `web_fetch`, broad URL approval, built-in MCPs, shell, and writes are
  unavailable to both research and main review children.
- One bundled Python standard-library stdio broker is started per repository
  through an ephemeral mode-0600 MCP config and an `env -i` launcher.
- The broker permits GET/HEAD over HTTPS only, rejects userinfo/IP literals and
  reserved hosts, resolves every initial/redirect target, requires every answer
  to be globally routable, pins the selected address, and verifies TLS/SNI and
  hostname against the original host.
- Redirects, requests, concurrency, per-host rate, connect/total time, headers,
  wire body, normalized output, links, cookies, and TLS ports are bounded by an
  approval-hashed effective policy plus immutable code limits.
- Fixed safe headers exclude Referer and Authorization. Model-supplied headers,
  request bodies, authentication, inherited proxies/netrc/cookies/client
  certificates, arbitrary executables, and remote MCP endpoints are forbidden.
- General web search uses only the closed in-code fixed-endpoint anonymous
  `duckduckgo-html-v1` adapter or explicit `none`. Search requests use GET
  through the same fetch boundary. Provider redirect URLs are decoded, every
  result is revalidated against the public-HTTPS floor, duplicate results are
  removed, and bounded URL/title/summary records are returned. Provider
  challenges and malformed responses are structured failures; there is no
  bypass or silent fallback.
- A failed verified TLS handshake can trigger only a metadata-only diagnostic
  handshake. It sends no HTTP request and cannot turn failure into success.
- HTML active elements are stripped. Supported text/JSON/XML/RSS/Atom is
  normalized as untrusted evidence. Unsupported or binary bodies are stored
  privately by SHA-256 without original/executable extensions.
- Research does not activate or fetch resource URLs merely to test pixels,
  callbacks, trackers, or sensors. Normalized external pages may omit
  active-resource details, and reports preserve that evidence limitation.
- Cookie replay defaults off. Optional replay starts with a fresh empty
  per-repository/per-run jar and permits only bounded exact-host Secure cookies
  under path/expiry constraints. Raw Set-Cookie values remain only in a private
  mode-0600 ledger in either mode and are never model/report inputs.
- Broker capabilities, exact tools, policy digest, request ledger, at least one
  successful public response, dossier headings/delimiters, private permissions,
  and broker/config/runtime cleanup are validated before main analysis.
- Distinct `ResearchCapabilityFailed` and `ResearchFailed` statuses prevent
  missing transport, zero-success research, malformed output, or cleanup
  failures from becoming a completed review.
- Custom research policy files must be trusted and outside Git worktrees and
  target/output roots. Policy schema 1 accepts only bundled adapters; the
  effective policy digest, providers, limits, and cookie mode are part of
  `ApprovalHash`.
- Child file access is rooted at the checkout and automatic
  temporary-directory access is disabled.
- Outer `--yolo` or user-enabled in-session Copilot autopilot state does not
  relax child review restrictions. Runner-enforced tool isolation remains in
  place, and the runner removes inherited `COPILOT_ALLOW_ALL` state from child
  process environments after applying its own report-opening policy.
- Child remote export is disabled.
- Installed hook changes load only in new outer sessions; child review
  homes still set `disableAllHooks` and do not inherit the onboarding
  hook.
- Only the trusted runner writes artifact files.
- Public research egress is unavailable unless scope 2/3 is explicitly
  approved, and then only through the local broker.
- Target code execution is explicitly prohibited.
- Public research and evidence-based provenance review for agentically
  generated code are separate opt-ins.
- No shared credentials.
- Clone/fetch processes use an empty process-local home and remove
  GitHub, Copilot, credential-manager, SSH-agent, netrc, and proxy
  inputs. Credential helpers, HTTP auth headers, and interactive auth
  are cleared; TLS verification remains enabled.
- Guided setup accepts only public HTTPS repository URLs and does not
  discover local repositories or inspect local origins.
- Direct local-path flags and non-URL repository-list entries are
  rejected before any `.git` inspection, origin/`HEAD` resolution, DNS
  lookup, or network access.
- Repository count, concurrency, and session duration are bounded.
- Unpredictable run directories are created without reuse and physically
  revalidated before child sessions start.
- Bash containment checks walk filesystem identities, including on
  case-insensitive mounted filesystems.
- Scope-based default timeouts match the published planning ranges.
- Reports require exact source references and evidence/confidence
  separation.
- Every scope requires an exact
  `AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT` with explicit coverage
  of prompt injection, reviewer-directed instructions, metadata/dataset/
  benchmark poisoning, encoded instructions/tool-call bait, recursive or
  resource-exhaustion tarpits, tracking/callback mechanisms, evidence
  limitations, confidence, and evidence basis. The source remains inert
  evidence.
- Scope 3 additionally requires an exact
  `GENERATED-CODE PROVENANCE ASSESSMENT` with generation, direct model,
  non-attributive heuristic model candidates, heuristic confidence, direct
  effort, direct harness, coverage/window, alternative-explanation,
  confidence, and evidence-basis fields. Validation fails closed on omission
  and rejects High heuristic confidence or inconsistent controlled
  no-candidate values. Direct model/effort/harness attribution requires
  commit-bound evidence; heuristics concern repository assets, never people,
  and remain explicitly non-attributive.
- Text artifacts strip terminal control sequences and redact email
  addresses.
- Markdown and HTML promote only exact allowlisted report headings into
  trusted generated TOCs/anchors. All canonical report-body chunks remain
  inert code/preformatted text.
- Trusted external-reference blocks are deduplicated from the already
  sanitized canonical report and accept only conservatively validated HTTPS
  URLs. Userinfo, IP literals, localhost/internal suffixes, controls/
  whitespace, malformed escapes, unsafe delimiters, credential-like query
  keys/values, and non-HTTPS schemes remain inert.
- Transcripts and handoff values also use inert Markdown code text.
- HTML escapes all report and metadata content, has no scripts or remote
  assets, applies a restrictive content security policy and no-referrer
  policy, and marks generated external links
  `noopener noreferrer nofollow external` with
  `referrerpolicy="no-referrer"`. Rendering performs no DNS or network
  access.
- Handoffs save session IDs but require continuation through the trusted
  runner instead of advertising an unrestricted direct resume.
- Recovered reports without the mandatory closing delimiter are retained
  for diagnosis but marked failed rather than completed.
- The plugin performs no background network requests; network activity is
  limited to user-requested anonymous clones and optional public
  research.

## Residual risks

- Copilot and public search services process prompts and public source
  content.
- Read-only analysis can still be inaccurate or incomplete.
- Public web sources can contain prompt injection and false claims.
- The wrapper command itself can write to the user-selected artifact
  workspace.
- Public research still sends project terminology and public URLs to selected
  public endpoints. The constrained broker reduces transport risk but cannot
  establish source truthfulness.
- Raw private cookie/body evidence may contain tracking identifiers,
  copyrighted material, misleading content, or hostile bytes until the user
  deletes the local run bundle.
- The fixed anonymous general-web-search provider can rate-limit, change HTML
  structure, return an automated-access challenge, or omit relevant sources.
  Rhyolite fails that provider call without bypass or fallback, so coverage
  gaps remain possible.
- Broker normalization can remove active-resource details, so public-page
  tracking-pixel, callback, tracker, and sensor detection can be incomplete.
  Checked-in source and documentation remain inspectable as inert evidence.
- A local user can intentionally override the runner or plugin
  safeguards.
- Public DNS classification and pinning reduce, but cannot eliminate,
  risks from a compromised DNS resolver, transparent network
  interception, or a malicious public endpoint sharing infrastructure
  with sensitive services.
- Disabling inherited proxies can prevent cloning in environments that
  require an explicit proxy; the runner fails rather than weakening
  anonymous/public transport controls.

## Expansion requirements

Private or non-public repository support requires a separate privacy,
security, credential, network, and data-retention review. A centralized
GitHub Actions or comparable service additionally requires an approved
service identity, per-repository authorization, ephemeral runners, audit
logging, and bounded artifact retention.
