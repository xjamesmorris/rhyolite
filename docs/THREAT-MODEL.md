# Threat model

## Assets

- The reviewer's workstation and files.
- The reviewer's GitHub and Copilot identity, and their Claude Code sign-in
  or API credentials.
- Source code outside the target checkout.
- Accuracy and integrity of generated reports.
- People and projects discussed in provenance findings about agentically
  generated code and in claims, reputation, community-health, prior-art, and
  code and architecture provenance conclusions.

## Untrusted inputs

- Repository files and Git objects.
- Repository instruction, agent, prompt, and skill files, including
  `CLAUDE.md`, `CLAUDE.local.md`, `AGENTS.md`, and `.claude/` rules, skills,
  settings, and hooks.
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
- User-local launcher model/reasoning/context preference files.
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
20. A tampered or mismatched launcher preference silently changes the
    model, leaks a selected source, or bypasses review approval.
21. An explicit `--yolo` launch broadens the outer Copilot orchestrator
    to all permissions for that launch, or allow-all state is incorrectly
    coupled to report opening instead of requiring explicit `--open-html`.
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
32. Claims, reputation, community, prior-art, or provenance assessments cause
    reputational harm through false positives, accusatory wording, research
    on people named in endorsements, or lists of individual accounts.
33. A harness's own safety mechanism silently answers with a model other than
    the approved one (for example, a Claude Code safeguard fallback), or a
    nested repository `CLAUDE.md`, rule, skill, setting, or hook loads into a
    Claude Code worker.
34. A Claude Code worker reply that reached the output token limit and was
    resumed is promoted as a partial or spliced report.

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
- The outer model, reasoning effort, and context tier
  are selected before Copilot starts. The trusted launcher setup block
  contains only canonical source URLs plus constrained
  model/reasoning/context/remember fields; sources
  remain untrusted data rather than prompt instructions.
- Before a Copilot session starts, the launcher checks that the account
  accepts the selected model, reasoning effort, and context with one
  non-interactive request: a fixed prompt, an empty working directory, an
  isolated mode-0700 runtime home with the same narrow authentication bridge
  as workers, no plugin, agent, custom instructions, built-in MCP, write, or
  shell access, and the adapter's normalizer verifying that exactly the
  selected model and effort answered. The home is removed afterwards. A
  rejected model or effort changes only through the user's explicit choice,
  never below high reasoning effort; without a terminal the launcher stops.
- `--yolo` is disabled by default and is an ephemeral per-launch
  outer-orchestrator switch. It opts the outer Copilot orchestrator into all
  permissions but is not persisted in launcher context, copied into the
  trusted launcher setup block, or remembered as a preference. The runner's
  default and guided open policy is `never`; it prints only the run output
  folder path and exits without a prompt or browser launch. Only explicit
  advanced direct-runner `--open-html` may open the index. `--no-open-html`
  remains a compatibility spelling, and `harness_allow_all_detected` is
  retained only as a harness contract compatibility signal, not an opening
  decision.
- The launcher has an explicit retired-option parser branch for
  `--autopilot`; it renders `RHYOLITE ERROR` and exits `2` before Copilot
  starts. It passes `--mode interactive` explicitly. Rhyolite does not support
  plan/autopilot mode during guided setup or execution, and mode-related UI
  notices do not change the approval-bound worker model.
- Launcher startup emits the plaque once from `sessionStart`; the prompt hook
  matches only exact manual review-start commands and ignores internal
  resumes, marker-bearing continuations, and unrelated prompts.
- Exact `stop` and `cancel` intents first run the runner's
  `--request-stop <run output folder>`, which sends TERM only to the runner
  recorded in that folder's user-only `.runner-process` file, after verifying
  the recorded process ID, kernel start time, owner, and runner command line,
  so a stale or altered record cannot signal another process; an optional
  `--harness` must match the run's planned harness. Targeted
  execution cancellation remains the fallback. The
  Bash runner propagates INT/TERM/HUP through tracked repository, timeout,
  Copilot worker, and broker processes, then records `Interrupted` state and
  artifacts. Workers start under util-linux `setpriv --pdeathsig TERM` when
  available, so a SIGKILL of the runner cannot leave a worker running with
  its credentials and network access after the run has stopped.
- Per-repository model/reasoning/context preferences are keyed by a
  SHA-256 hash of the selected canonical public URL, including its terminal
  `.git` endpoint when present, stored under user-only launcher state, and
  parsed against a versioned fixed schema. Missing, mixed, malformed, or
  mismatched preferences are ignored rather than silently applied.
- Preferences are written atomically only after effective-plan approval.
  The model and remember state are included in `ApprovalHash`;
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
- The optional `candidate` input on `research_network_summary` does not add a
  sixth capability or network path. It validates the complete dossier with a
  three-attempt same-session bound, persists a SHA-256 proof and byte count in
  the sanitized summary, and writes the exact accepted canonical bytes only to
  the broker's mode-0700 runtime root, which the runner consumes and destroys.
  The runner verifies the proof against those persisted bytes and against the
  exact final assistant message that the harness adapter extracts from the
  CLI's structured output, never from lossy terminal-rendered text. The
  persisted accepted candidate is the canonical dossier; a final reply that
  differs is recorded as a warning rather than discarding validated research.
  Verification happens before privacy sanitization, raw copies are deleted,
  and only the sanitized dossier persists. Missing, corrupted, or mismatched
  proof fails before the main reviewer can start; downstream dossier and event
  validation remains an independent defense-in-depth gate.
- Broker event integers are governed by one packaged producer/consumer
  inventory. The broker refuses undeclared integer leaves, while the runner
  requires exact JSON integers rather than booleans, strings, or floats and
  enforces field bounds and sequence/transport relationships. Accepted
  validation events are limited to 100 claims. Rejected validation events may
  preserve the pre-enforcement observed count through 209715, the bounded
  maximum under the 2 MiB candidate and shortest recognized entry line, so a
  rejected 101-claim attempt cannot invalidate a later corrected acceptance.
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
- The default per-session timeout is the same for every scope, so scope
  never shortens the core review or its dedicated security pass.
- Reports require exact source references and evidence/confidence
  separation.
- A malformed confidence field can trigger only the approval-bound, single
  report-repair attempt. Its fresh Copilot home and empty work directory have
  hooks, memory, custom instructions, IDE integration, skills, MCP, and
  model-visible tools disabled. Only the approved provider's model transport
  remains; no target, research, or arbitrary network access is granted.
  Its fresh `COPILOT_HOME` isolates model/session state without changing the
  analysis worker's authentication, provider/offline configuration, or trusted
  CLI cache/version resolution. Authentication stays in the environment or
  private bridge, never in process arguments.
- Markdown-table normalization is deterministic and runner-owned. It invokes
  no model or tool, converts only well-formed tables outside the
  field-validated assessment sections, refuses tables containing action-menu
  phrases, keeps every cell verbatim, and must pass the unchanged strict
  validator before promotion.
  The child sees sanitized report text and a fixed diagnostic/edit protocol,
  never snapshot files, private research evidence, credentials, or prior
  sessions. Its reply cannot replace report text: an exact descriptor is
  checked against the original value hash and conservative confidence level.
  Every other report byte is preserved, strict validation reruns, and failed
  cleanup or exhausted repair prevents canonical promotion.
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
- Every scope also requires exact `CLAIMS AND REPUTATION INTEGRITY ASSESSMENT`
  and `COMMUNITY HEALTH ASSESSMENT` sections; scope 1 derives them only from
  the snapshot and wrapper Git metadata. Scopes 2/3 add
  `PRIOR ART AND ORIGINALITY ASSESSMENT` and use the validated dossier's
  `COMMUNITY HEALTH EVIDENCE`, `CLAIM VERIFICATION EVIDENCE`, and
  `PRIOR ART AND LINEAGE EVIDENCE`. Scope 3 adds
  `CODE AND ARCHITECTURE PROVENANCE ASSESSMENT`, and the scope-3 generation
  assessment covers every tracked asset, including documentation and
  proposal material. Each section requires exact labeled fields, confidence,
  and evidence basis; out-of-scope headings are rejected. The confidence edit
  can target only a section that the approved scope requires, and missing,
  duplicated, or empty labels and tables still fail explicitly.
- Reputational-harm and false-positive mitigations: these assessments
  evaluate claims, artifacts, and aggregate public signals, never a person's
  character, intent, motive, or misconduct. They use neutral terms such as
  unsupported, not corroborated, indicator, and requires human review, never
  labeling a person or account fake or malicious; never research or
  characterize named individuals quoted in endorsements or testimonials;
  report engagement and contributor data only as counts and date
  distributions, never per-account lists; and treat supply-chain precursor
  indicators as risk indicators, never findings of intent. Every conclusion
  carries confidence and an evidence basis, strict validation enforces the
  required fields, and human review is required before external sharing.
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

- Claude Code workers run `--restricted` with only `Read`, `Glob`, and
  `Grep` (plus the five broker tools for research), with hooks, memory,
  slash commands, MCP discovery, and repository instruction files disabled
  by flags, settings, and environment. Rhyolite never passes
  `--fallback-model` and fails the review when the session record shows
  another model or effort, a safeguard handover, an advisor model, a
  subagent turn, or an unreadable record.
- Copilot workers receive only `view`, `glob`, `rg`, and `skill`. No
  Rhyolite worker on either harness receives a subagent tool: a live probe
  showed that a Copilot `task` call's `model` argument overrides every
  configured `subagents.agents.<name>.model` value, so a specialist could
  silently run on another model while the main session stayed on the
  approved one. The worker performs the dedicated security pass itself, the
  structured-output normalizer rejects any recorded subagent event, and
  worker prompts never invite the model to select, name, or request a model,
  effort, or context.
- While a review, research, or report-repair child runs, the runner polls
  the adapter every five seconds for recorded evidence of another model,
  effort, or a subagent and terminates the child's process tree on the first
  violation instead of accepting a completed session later. The post-exit
  checks still reject the same evidence, so live detection shortens the
  blast radius without widening what is accepted.
- Claude Code workers raise the per-response output limit to the model's
  maximum. When Claude Code still resumes a cut reply, the transcript
  renderer joins the segments only after an explicit `Output token limit
  hit.` resume prompt, discloses every inserted separator, and the joined
  report must still pass strict validation.
- The Claude Code credential bridge copies only `.credentials.json` into a
  mode-0700 runtime home when no supported authentication variable is set,
  and deletes it with that home.

### Same-session worker recovery

- Recovery continues only the review worker's own session and only when the
  adapter has verified `worker_continuation` live. A continuation reuses the
  exact approved argv less only its new-session name label (Claude Code
  resumes with `--resume` in place of `--session-id`), and the same
  environment, isolated runtime home, read-only tools, model, effort, and
  context; it receives no new tool, path, or network access, and live
  approved-plan enforcement applies to it. The adapter's post-exit
  verification runs again after every continuation, before its reply can be
  accepted.
- Continuation requests are fixed runner text plus validator diagnostics and
  section names; they never include repository content, research evidence,
  or private artifacts.
- The adapter's worker outcome is data. The runner validates it strictly and
  treats a malformed or missing outcome as `unknown`, which never continues
  a session. Substituted output, adapter-function failures, timeouts, and
  interruptions are never continued.
- Paged delivery accepts only sections that pass the strict contract program,
  never accepts invalid UTF-8, and promotes only an assembled report that
  passes unchanged strict finalization. Limits on retries, resubmission
  rounds, continuations, and the approved session timeout bound cost.
- Research is never continued. After the research worker's own transient
  model-service failure or blocked automatic fallback, the runner relaunches
  research at most once, as the approval-bound `ResearchRelaunchLimit`
  allows, with a fresh broker, runtime, session, cookie jar, and network
  log. The failed attempt's network log and sanitized artifacts move under
  `research/attempts/<n>/` with private evidence still mode 0700/0600, and
  no archived ledger is ever passed to a broker or reloaded. Timeouts,
  interruptions, substituted output, adapter or cleanup failures, and dossier
  or transport validation failures are never relaunched.
- The deterministic failure analysis reads only trusted artifacts in the
  repository output directory, redacts email addresses, writes mode-0600
  files, and never changes the run outcome.

## Residual risks

- Copilot, Claude Code's model provider, and public search services process
  prompts and public source content.
- Claude Code's session record format is internal and version-dependent.
  Rhyolite parses it defensively and fails closed on unreadable records, but
  a format change can stop reviews until the adapter is updated.
- If Claude Code rotates the refresh token inside the copied credentials
  file during a long review, the rotated token is discarded with the runtime
  home. Whether that can invalidate the user's original login is unproven.
  Exporting `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` avoids the
  copy.
- Read-only analysis can still be inaccurate or incomplete.
- Claims, reputation, community, prior-art, and provenance indicators can be
  false positives or miss context. They are advisory, never verdicts about
  people, and require human review before they are shared or acted on.
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
- A runner stopped with `SIGKILL` cannot remove its mode-0700 runtime homes
  under `TMPDIR`, and a launcher stopped that way during its model check
  cannot remove the mode-0700 `model-check-<n>` home in its private session
  directory under launcher state, so their ephemeral authentication bridge
  remains until the directory is deleted. Each owner holds a util-linux
  `flock` lock on its home, which every child that inherits it keeps, and
  the next runner or launcher start removes the current user's matching
  homes whose lock is free and whose whole tree is unchanged for 60 minutes.
  Without `flock`, nothing is locked or removed.
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
