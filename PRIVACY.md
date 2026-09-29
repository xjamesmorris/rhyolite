# Privacy guidance

## Release scope

Version `0.4.0` reviews anonymously readable public HTTPS Git
repositories.

Do not use this version with:

- Private or non-public repositories.
- Customer data.
- Credentials or secrets.
- Personal or sensitive data that is not already intentionally public.

## Public research

Public web research is disabled by default. When enabled, searches must
use public project terminology and must not contain private code,
internal project names, internal URLs, credentials, or non-public
personal information.

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

HTML reports contain no scripts or remote assets and escape untrusted
content. Markdown reports, transcripts, and handoffs render untrusted
text as inert code rather than active links or images. Opening HTML uses
the operating system's local browser association and does not upload the
report.

No telemetry, report upload, or background network requests are
implemented by this plugin.
