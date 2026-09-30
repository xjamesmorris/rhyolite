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
- Repository URLs supplied to the runner.
- User-local launcher fleet/model preference files.
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
    inherited auth variables, a proxy, a redirect, or a client
    certificate.
18. A local path is accepted as a review source and triggers filesystem,
    Git metadata, DNS, or network access before the public-source
    contract rejects it.
19. The onboarding hook inspects credentials, mutates local state, or
    hijacks unrelated sessions before the user invokes the review agent.
20. A tampered or mismatched launcher preference silently changes fleet
    mode or model, leaks a selected source, or bypasses review approval.

## Controls

- Anonymous public HTTPS Git URLs on syntactically valid public DNS hosts
  only.
- User-facing orchestration starts from a clean non-Git directory, never
  from inside the target checkout.
- Launcher bootstrap performs syntax-only public-HTTPS canonicalization
  without DNS, Git, authentication, or target inspection. The runner
  independently repeats canonicalization and anonymous public-access
  preflight before clone.
- Exact URL parsing before invoking Git.
- DNS answers are classified before clone; any non-public address rejects
  the source. Approved IPv4/IPv6 addresses are pinned with
  `http.curloptResolve`, and redirects and explicit proxies are disabled
  to prevent rebinding or proxy-side re-resolution. Git 2.41 or newer is
  required.
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
- A local plugin `sessionStart` hook emits one plain version/start line.
  A display-only `userPromptSubmitted` command hook recognizes only
  trusted Rhyolite start markers/commands and emits the plaque without
  modifying or persisting the prompt. Neither hook performs network
  access, Git commands, writes, or environment/auth inspection.
- Native fleet mode and the outer model are selected before Copilot
  starts. The trusted launcher setup block contains only canonical
  source URLs plus constrained fleet/model/remember fields; sources
  remain untrusted data rather than prompt instructions.
- Per-repository fleet/model preferences are keyed by a SHA-256 hash of
  the canonical public URL, stored under user-only launcher state, and
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
  and supplies bounded Git metadata from the trusted wrapper.
- Child file access is rooted at the checkout and automatic
  temporary-directory access is disabled.
- Child processes remove inherited `COPILOT_ALLOW_ALL`.
- Child remote export is disabled.
- Installed hook changes load only in new outer sessions; child review
  homes still set `disableAllHooks` and do not inherit the onboarding
  hook.
- Only the trusted runner writes artifact files.
- The web-fetch tool is unavailable unless public research is explicitly
  enabled.
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
- Text artifacts strip terminal control sequences and redact email
  addresses.
- Markdown uses a fidelity-first indented code block.
- Transcripts and handoff values also use inert Markdown code text.
- HTML escapes all report and metadata content, has no scripts or remote
  assets, and applies a restrictive content security policy.
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
- `--allow-all-urls` is used only after explicit public-research opt-in
  because comprehensive research cannot be represented by a stable domain
  allowlist.
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
