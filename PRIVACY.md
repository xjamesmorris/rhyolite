# Privacy guidance

## Release scope

Version `0.4.1` reviews anonymously readable public HTTPS Git
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
preexisting cookies. Anonymous GitHub REST/search is enabled; the stable
general-web-search interface is provider-disabled by default in version
`0.4.1`.

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
- Present alternative explanations and missing evidence.
- Receive human review before distribution.

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
paths, and Copilot session names and IDs.

Scope 2/3 additionally creates a `research/` bundle. The sanitized
dossier, network summary, and event ledger contain public URLs, response
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

The plugin omits author email addresses by default. Users are
responsible for storing, sharing, and deleting reports according to
their own applicable data handling and retention requirements.
That responsibility includes deleting private research ledgers and
bodies when they are no longer needed; Rhyolite does not automatically
reuse or expire them.

HTML reports contain no scripts or remote assets and escape untrusted
content. Markdown reports, transcripts, and handoffs render untrusted
text as inert code rather than active links or images. Opening HTML uses
the operating system's local browser association and does not upload the
report.

No telemetry, report upload, background network requests, or reusable
cross-run research cookie store is implemented by this plugin.
