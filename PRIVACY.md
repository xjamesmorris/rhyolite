# Privacy guidance

## Release scope

Version `0.8.1` reviews anonymously readable public HTTPS Git
repositories.

Do not use this version with:

- Private or non-public repositories.
- Customer data.
- Credentials or secrets.
- Personal or sensitive data that is not already intentionally public.

## Public research

Public research is disabled by default. Scope 2/3 uses a dedicated
write-disabled research worker and bundled local stdio broker; the main
review worker has no direct network tool. Research queries must use
public project terminology and must not contain private code, internal
project names, internal URLs, credentials, or non-public personal
information.

The broker sends only fixed unauthenticated GET/HEAD requests to
validated public HTTPS destinations. It does not import authentication,
proxy settings, netrc files, browser state, client certificates, or
preexisting cookies. Anonymous GitHub REST/search is enabled. Scope 2/3
defaults to the fixed anonymous `duckduckgo-html-v1` general-web-search
provider; advanced direct-runner use may select explicit `none`. Search terms
and public result requests are sent only through the approval-bound broker and
must contain public project terminology, not private data.

The web-search adapter has a fixed HTTPS endpoint and fixed headers. It accepts
no credentials, configurable endpoint, caller headers, request body, proxy,
browser state, challenge bypass, or fallback provider. It returns only bounded
normalized public result URLs, titles, and summaries after redirect unwrapping,
public-HTTPS revalidation, and deduplication.

Guided scope 2/3 setup explicitly asks whether research cookie replay is
off or uses a fresh per-repository ephemeral jar. Off is recommended
and the default. In either mode, raw Set-Cookie values are retained
locally in a private per-repository ledger for transport analysis. They
are never supplied to a model or rendered report. When replay is
enabled, only bounded exact-host Secure cookies are eligible; the jar
starts empty, is isolated to one repository/run, and is destroyed after
the research phase.

The research-source assessment records public URLs, source categories,
check dates, freshness, ownership, and access failures. It never
authenticates to or bypasses inaccessible resources. Inaccessible
citations and retrieval priorities are persisted in the report so users
can decide whether to obtain and provide copies through an independently
approved path.

Evidence-based provenance review for agentically generated code is
separately disabled by default. When enabled, it must:

- Use public, verifiable evidence.
- Avoid inferring intent or misconduct from style, sparse activity, or
  similarity alone.
- Keep direct model, effort, and harness attribution direct-evidence-only.
- Limit heuristic model candidates to repository assets, never people; label
  them as non-attribution, cite path/commit/public evidence, preserve
  counterevidence and alternatives, and never assign High confidence.
- Present alternative explanations and missing evidence.
- Receive human review before distribution.

## Claims, reputation, and community assessments

Every scope assesses claims and reputation integrity and community health.
These assessments evaluate claims, artifacts, and aggregate public signals,
never a person's character, intent, motive, or misconduct. Named individuals
quoted in endorsements or testimonials are not researched or characterized;
reports cite only the path, line, and attributed role and say "no public
record located" when no independent record is found. Engagement and
contributor data appear only as counts and date distributions; individual
stargazer, fork, watcher, follower, and commenter accounts are never listed.
Scope 1 uses only the snapshot and wrapper Git metadata. Scope 2/3 research
may fetch anonymous public GitHub REST metadata, such as repository,
contributor, release, issue, pull request, and community-profile records,
through the existing broker `fetch_public_url` tool within the existing
request budgets. Human review is required before any such conclusion is
shared externally.

## Local onboarding hook

Installing the plugin registers a local, display-only `sessionStart`
hook, a display-only `userPromptSubmitted` command hook, and bundled
welcome helpers. Hook changes load when a new Copilot CLI session
starts. The outer session first receives one plain version/start line.
When extension mode is enabled, the extension emits the same plain
guidance immediately; it does not render the plaque.
The command hook recognizes only the trusted Rhyolite start marker or
start command, emits the plaque, and neither modifies nor stores the
prompt. The helpers perform no network access, Git commands, writes, or
environment/auth inspection beyond explicit terminal color signals
`NO_COLOR`, `COPILOT_NO_COLOR`, `FORCE_COLOR`, and `TERM`.

The large colored plaque appears only after `/rhyolite:start`, the
compatible `/rhyolite:repo-review`, or the `/repo-review` shorthand.
The agent does not repeat it and continues into setup in the same turn.
The prompt-native plain panel remains available for exact `help`. Exact
no-leading-slash `help`, `status`, and `explain scopes` setup phrases
operate on the agent's collected answers only; `/rhyolite:status`
reports the same command state plus elapsed time, task/subagent state,
run state, and output location when available.

The UI validator is repository-only development tooling under
`.github/agents/`; it is not packaged with or invoked by installed
Rhyolite sessions. Isolated review-worker homes still set
`disableAllHooks`, so worker sessions do not inherit the onboarding
hook.

## Output and retention

Reports, rendered requests, transcripts, timelines, state, and handoff
files are written to a user-selected local artifact workspace outside the
reviewed repository. They may contain public usernames, public
statements, source excerpts, vulnerability analysis, local filesystem
paths, and Copilot or Claude Code session names and IDs.

Scope 2/3 additionally creates a `research/` bundle. The sanitized
dossier remains canonical plain text; Rhyolite does not create Markdown or
HTML dossier variants. The dossier, network summary, and event ledger contain
public URLs, response
metadata, cookie names/attributes/value hashes, TLS certificate
metadata, rate-limit information, access failures, and ownership-aware
anomaly summaries. `research/network/private/` is mode 0700; its files
are mode 0600. `cookies.jsonl` contains raw Set-Cookie values.
Unsupported or binary response bodies are retained as content-addressed
`.bin` files with a private manifest.

Those private artifacts may contain tracking identifiers, personal data
already published by a server, copyrighted material, misleading
content, or hostile bytes. They are local, inert, unindexed, not
individually linked from HTML, and never exposed to a model by Rhyolite.

Rhyolite currently accepts only anonymously readable public HTTPS Git
repository URLs as review sources. Local repository paths are rejected
before any `.git` inspection, origin/`HEAD` resolution, DNS lookup, or
network access.

The per-repository `agent-state/` directory contains a sanitized Copilot
home. It can contain allowlisted session-state and session-store files
needed for handoff. Treat it with the same retention and access controls
as the reports.

During execution, the runner creates a separate user-only temporary
Copilot home. It copies only login metadata and, when present,
configured plaintext token fields needed by the child session. That
temporary authentication bridge is not copied into `agent-state/`; the
runner removes or sanitizes its managed auth configuration and retries
deleting the runtime home after normal completion, timeout, or failure.
If the operating system prevents deletion, the review is marked failed
and the remaining user-only path is reported. Persisted settings disable
hooks and the persisted managed configuration is empty. Supported
authentication environment variables are marked secret for child tools.

With `--harness claude`, `agent-state/claude-home/` contains the worker's
`settings.json` and a filtered, redacted session record. Attachments such as
the account email and organization ID are dropped, and `session.md` is a
rendered transcript of that record. When no supported Claude Code
authentication variable is set, the runner copies Claude Code's
`.credentials.json` into the user-only temporary runtime home for the worker
and deletes it with that home; the copy is never written to `agent-state/`.
Exporting `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` avoids the copy.

The plugin omits author email addresses by default. Users are
responsible for storing, sharing, and deleting reports according to
their own applicable data handling and retention requirements.
That responsibility includes deleting private research ledgers and
bodies when they are no longer needed; Rhyolite does not automatically
reuse or expire them.

HTML reports contain no scripts or remote assets and escape untrusted
content. Markdown and HTML report bodies remain inert; only exact allowlisted
headings become trusted generated navigation. Each report also has a trusted
generated external-reference block built from conservatively validated HTTPS
URLs extracted from the already-sanitized canonical report. URLs with
userinfo, IP literals, localhost/internal suffixes, controls/whitespace,
malformed escapes, unsafe delimiters, or credential-like query data remain
inert. Rendering performs no DNS or network access. HTML uses a restrictive
CSP and no-referrer policy, and external links suppress referrer data.

Opening a local HTML report uses the operating system's browser association
and does not itself upload the report. Following a generated external
reference is an explicit user navigation and can contact that public site;
Rhyolite does not prefetch it. Transcripts and handoffs continue to render
untrusted text as inert code rather than active links or images.

## Model providers

Review content, including source excerpts, Git metadata, research dossiers,
and prompts, is processed by the selected harness's model provider: GitHub
Copilot for `--harness copilot`, and Anthropic or the provider configured for
Claude Code for `--harness claude`. Claude Code workers run with nonessential
traffic and auto-update disabled; the outer Claude Code session uses the
user's own Claude Code settings.

No telemetry, report upload, background network requests, or reusable
cross-run research cookie store is implemented by this plugin.
