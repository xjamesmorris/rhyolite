# Claude Code harness evidence

This contributor-facing record holds the probe evidence behind the `claude`
harness adapter, as [ADDING-A-HARNESS.md](ADDING-A-HARNESS.md) requires. It
complements the implementation plan in
[CLAUDE-HARNESS-PLAN.md](CLAUDE-HARNESS-PLAN.md).

Development reasoning policy (from AGENTS.md): use a current frontier
reasoning model at maximum available reasoning effort and the largest
supported context for every task in this work; downgrade only mechanical,
fully scoped steps, and only to high.

## Environment

- Fedora Linux 44, GNU coreutils `env` 9.10 (`-C`/`--chdir` present).
- Claude Code 2.1.292, GitHub Copilot CLI 1.0.93.
- Probes ran on 2026-10-07 in scratch directories outside every Git
  worktree. Unless a row says otherwise they used the operator's normal Claude
  Code login. P1/P2 copy the operator's credentials file, so they ran only
  on the operator's explicit request; the probe prints no secret values.

## Probe results

| Probe | Result | Consequence |
| --- | --- | --- |
| P1 copied credentials in a fresh `CLAUDE_CONFIG_DIR` | Operator-approved run on 2026-10-07: a copy of the login in a fresh 0700 `CLAUDE_CONFIG_DIR` authenticated `claude -p --restricted --tools ""` (exit 0, `OK` from `claude-opus-5-5`). No onboarding file is needed; Claude Code writes its own `.claude.json` (including `oauthAccount`), `sessions/`, and `backups/`. With an empty `CLAUDE_CONFIG_DIR`, `claude -p` exits 1 with `Not logged in · Please run /login` on stdout. | The file bridge is the default when no environment authentication is set; `.claude.json` stays in the runtime home, is deleted by cleanup, and is never persisted. |
| P2 refresh-token rotation | Same run: neither the copied nor the original credentials file changed, and the original login still worked afterwards. The run did not cross access-token expiry, so rotation during a long review remains unproven. | Residual risk documented; exporting `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`) or `ANTHROPIC_API_KEY` skips the file bridge entirely. |
| P3 model availability | Unknown ID: exit 1, stdout `There's an issue with the selected model (<id>). It may not exist or you may not have access to it. Run --model to pick a different model.`, stderr includes `[claude-code:unrecognized_model] {"model":"<id>","query_source":"sdk"}`; JSON envelope `is_error: true`, `api_error_status: 404`. No substitution without `--fallback-model`. All six catalog IDs answered on this account. | Runner pattern keys on the stderr marker, not model-influenced stdout. |
| P3a Fable safeguard fallback | `claude-fable-5-1` and `claude-fable-5` answered `Reply with exactly OK` (tools disabled) through `claude-opus-4-8`. The transcript records `system`/`model_refusal_fallback` ("Fable 5.1's safeguards flagged this message... Switched to Opus 4.8", category `[cyber]`) followed by an assistant turn whose `message.model` is `claude-opus-4-8`; the JSON envelope lists both models in `modelUsage` with `safety_stops: 2`. A tool-enabled Fable run on a toy snapshot completed without fallback. | The adapter treats any non-approved assistant model, `model_refusal_fallback`, or `advisorModel` as a substituted review and fails closed. It does not attempt to change the safeguard. Fable remains selectable but is a poor default for security reviews. |
| R1 real scope-1 run (Opus 5.5) | Operator-approved run on 2026-10-07 against `https://github.com/xjamesmorris/rhyolite-test-1` at `a91e8de960a3`: preflight, clone, snapshot, and the isolated worker ran as designed (only `Read`/`Glob` calls; every turn `claude-opus-5-5` at `max`). After the worker read an intentionally insecure `src/snmp_legacy.c`, Opus 5.5 safeguards first stopped one response (`informational`: "continuing once with that noted") and later emitted `model_refusal_fallback` ("Opus 5 is answering instead", `[cyber]`); the remaining six turns, including the final report, came from `claude-opus-5`. The run ended `ReviewFailed` at `harness claude harness_verify_isolation` after 16.5 minutes. The runtime home and credential copy were removed; the output held no credential keys or email addresses; persisted state was exactly `settings.json` plus the filtered session record. | Substitution detection is necessary for Opus 5.5 too, not only Fable. Security-relevant targets can make an Opus 5.5 review fail closed; choosing a model is an operator decision (see Open items). |
| R2 real scope-1 run (Opus 5) | Operator-approved rerun on 2026-10-07 with `--model claude-opus-5`, same repository and commit: `Completed` in about 17 minutes; strict validation passed with `ReportRepair` `NotNeeded`; 1665-line canonical report with every scope-1 section in order; 63 assistant turns, all `claude-opus-5` at `max`; tools used: `Read`, `Glob`, `Grep` only; no safeguard events. State schema 6 recorded `Harness: claude`, provider `anthropic-claude-code`, model, effort, context, and the Claude resume policy. Runtime home and credential copy removed; no credential keys or email addresses in the output; persisted state exactly `settings.json` plus the filtered session record. | Phase 1 exit criterion met. |
| R4 staged scope-2 run (Opus 5) | Operator-approved run on 2026-10-07 from a staged copy with `web_research=yes`, `--model claude-opus-5`, effort `max`, same repository and commit. The research phase `Completed` in about 18 minutes through the local broker (49 broker calls: 37 `fetch_public_url`, 6 `search_public_github`, 4 `search_public_web`, plus `research_capabilities` and `research_network_summary`; 1890-line dossier; research transcript verified). The review worker's final reply reached Claude Code's per-response output limit (`stop_reason: max_tokens` at 64000 output tokens after 145071 characters of report). Claude Code then added a meta user message ("Output token limit hit. Resume directly ...") and the model finished the report in a second response with a new message ID. `-p` printed only that last 2217-character response, and the transcript fallback joined only replies that shared a message ID, so the run ended `ReviewFailed` with "Final report header or end marker was not found." | Workers now set `CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000`, which Claude Code 2.1.292 caps at the model's own maximum. The transcript renderer also joins a reply that was resumed after the limit into one `### Claude` block, before a notice that names the separator inserted at each joint. Re-rendering R4's persisted session gives a 145350-byte report that passes the scope-2 report contract. A fresh staged scope-2 run is still required. |
| P4 tool denial | Worker vector on a toy snapshot: tools reported as exactly `Read`, `Glob`, `Grep`; write, shell, skill, and subagent attempts impossible; `permission_denials` empty because the tools were absent; no file written. | `shell_denial=yes`. |
| P5 instruction injection | Canaries in `source/CLAUDE.md`, `source/sub/CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md`, `.claude/rules/*.md`, `AGENTS.md`, `.claude/skills/*`, and a `.claude/settings.json` hook. Plain `claude -p` loads the nested `CLAUDE.md` files. `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` alone blocks all of them. `claudeMdExcludes` without `**/AGENTS.md` falls back to loading `AGENTS.md`; with `**/AGENTS.md` it blocks all of them. `--restricted` alone also blocked nested loading. The hook did not run. | The worker keeps all three layers; `claudeMdExcludes` includes `**/AGENTS.md`. |
| P6 transcript | `CLAUDE_CONFIG_DIR/projects/<slug>/<session-id>.jsonl`, where `<slug>` is the working directory with every non-alphanumeric character replaced by `-`. Assistant lines carry `message.model`, `effort`, `perTurnEffort`, `advisorModel`, `isSidechain`; one JSONL line per content block, several lines can share one `message.id`. Attachments include `session_context` (account email) and `credential_org`. | Rendered into `session.md`; private attachments are not persisted; model and effort are verified per turn. |
| P7 JSON envelope | Fields include `type`, `subtype`, `is_error`, `result`, `session_id`, `modelUsage`, `permission_denials`, `terminal_reason`, `api_error_status`, `safety_stops`. | Repair reply comes from `result` only when `modelUsage` lists only the approved model. |
| P8 plugin layout | `.claude-plugin/plugin.json` with `agents: ["./claude/agents/..."]` and `commands: "./claude/commands/"` replaces the default `agents/` and `commands/` directories, so Copilot `*.agent.md` files and commands do not load. `--agent rhyolite:repo-review-worker` works in `-p`. An unknown `--agent` exits 1 (`--agent '<name>' not found`), with no fallback. `agents` must be an array of `.md` paths. Copilot keeps reading the root `plugin.json`. `claude plugin details` does not count custom-path agents. | No move under `copilot/` is needed. |
| P9 appended skill | `--append-system-prompt-file` with the 56 KB `SKILL.md` works in `-p`; the recorded system prompt contains the agent prompt and the skill. The default Claude Code system prompt still precedes them. | Worker receives the skill without the `Skill` tool. |
| P10 AskUserQuestion | Claude Code's tool contract allows 1-4 questions with 2-4 options and always adds a free-text "Other" answer. | Phase 2 pickers never add `Other`. |
| P11 hook display | Hook stdout `{"systemMessage": "..."}` is recorded as `hook_system_message` and is not sent to the model; SessionStart stdin has `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `source`; UserPromptSubmit adds `prompt_id`, `permission_mode`, `prompt`. ANSI escapes survive in the message. | Phase 2 plaque uses `systemMessage`. |
| P12 `env --chdir` | Present. | Worker and repair environments start with `-C <dir>`. |

### Settings validity

In print mode Claude Code silently ignores a whole settings source that fails
schema validation. A settings document with `"disableAllHooks":"yes-please"`
lost its `permissions.deny` rules and the model read a denied file. The
adapter's exact review and repair documents (including `effortLevel: "max"`)
were accepted. The adapter therefore builds settings only from fixed
literals and a validated effort token, and the tool boundary is also enforced
by `--tools` and `--disallowedTools`, which do not depend on settings.

The runtime home's `settings.json` is ignored under `--restricted` (it is a
user settings source), so the worker and repair argv pass the same document
inline through `--settings`; the runner also builds the worker argv before it
creates the runtime home.

## Capability decisions

| Capability | Value | Evidence or reason | Gate and negative test |
| --- | --- | --- | --- |
| `shell_denial` | `yes` | P4 | Golden argv/settings; mock run inventory. |
| `structured_questions` | `yes` | P10 | Phase 2 orchestrator. |
| `fleet` | `no` | No process-level fleet mode. | Launcher rejects native fleet (Phase 2). |
| `subagents` | `no` | `Agent` is removed and denied; sidechain turns fail verification. | `subagent` transcript case. |
| `builtin_security_specialist` | `no` | No bundled specialist; the worker agent performs a dedicated security pass. | Worker agent text. |
| `builtin_research_specialist` | `no` | Research is runner-owned and Copilot-only until Contract v5. | Scope 2/3 rejected before broker activity. |
| `web_research` | `no` | Same. | `scope-2`/`scope-3` pre-activity cases. |
| `final_message_file` | `no` | Final text comes from stdout, then the rendered transcript. | Extraction cases. |

## Model, effort, context, authentication

- Offline catalog (adapter-owned, verified available on 2026-10-07):
  `claude-opus-5-5`, `claude-fable-5-1`, `claude-sonnet-5-5`,
  `claude-fable-5`, `claude-opus-5`, `claude-sonnet-5`. Default
  `claude-opus-5-5`; guided alternate `claude-opus-5` (operator decision after
  P3a and R1; substitution stays fail-closed).
- Aliases `opus`, `sonnet`, `haiku`, `fable`, `default`, `auto`, `best`, and
  `opusplan` are rejected; safe `claude-*` IDs outside the catalog return the
  unlisted status; other IDs are rejected.
- Every catalog model reported a 1M-token context window. An ID unknown to
  the Claude Code catalog is held to 200k tokens by Claude Code auto-compact,
  so `long_context` is guaranteed only for catalog models.
- Effort: `max` default; `xhigh` and `high` selectable; verified per turn.
- Provider summary: `{"Id":"anthropic-claude-code","Host":"managed-provider",...}`.
  The host is a summary, not `api.anthropic.com`, because inherited Claude
  Code provider settings (Bedrock, Vertex, Foundry, a base URL) choose the
  endpoint.
- Authentication: inherited environment or cloud-provider authentication
  takes precedence; otherwise an ephemeral copy of
  `${CLAUDE_CONFIG_DIR:-~/.claude}/.credentials.json` (regular, non-symlink)
  is placed in the runtime home and deleted first during cleanup.

## Vectors

The focused validator section `tests/harness-contract-claude.sh` holds the
golden worker argv, worker environment, report-repair argv, and repair
environment, and checks them again through the real runner with a mock
`claude`. Runtime-home inventory at launch is exactly `settings.json` (0600)
plus `.credentials.json` (0600) when the bridge applies; persisted state is
exactly `agent-state/claude-home/settings.json` and the filtered
`projects/<slug>/<session-id>.jsonl`.

Every worker environment (review, research, and report repair) sets
`CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000`, overriding any value inherited from
the caller. Claude Code reads the value through a bounded parser: values above
the model's upper limit are capped, and invalid values fall back to the
default.

When a reply still reaches the limit, Claude Code asks the model to resume.
The renderer joins the segments only when all of the following hold:

- The cut text record has `stop_reason: max_tokens`.
- A meta user message that starts with `Output token limit hit.` follows it.
- The next main-thread text comes from a new message ID.

At each joint, the renderer inserts nothing when either side already has
whitespace. It inserts a line break when the resumed segment opens with a
section heading, delimiter, field label, list item, or table row. Otherwise,
it inserts a single space. These rules are needed because a resumed response
cannot begin with the whitespace that the cut removed. The raw records stay
in the persisted session JSONL. Strict report validation still runs on the
joined report. A resume prompt that gets no answer is rendered as a Claude
Code notice.

## Contract v5 research seam

The dedicated research worker now runs through four adapter functions plus
the `research` runtime-home phase:

| Function | Copilot | Claude Code |
| --- | --- | --- |
| `harness_write_research_mcp_config PATH LAUNCHER ARGS_ARRAY TOOLS_JSON` | `type: local`, `tools`, `timeout: 120000` (unchanged shape) | `type: stdio`, command and args only |
| `harness_research_worker_argv DEST ROOT PLUGIN NAME ID MODEL EFFORT CONTEXT AUTH_CSV MCP_CONFIG BROKER_TOOLS_CSV TRANSCRIPT` | the pre-v5 runner vector, byte for byte | `--mcp-config <path> --strict-mcp-config --tools Read,Glob,Grep --allowedTools mcp__rhyolite-research__<tool>,... --agent rhyolite:repo-research-worker --append-system-prompt-file .../research-source-assessment/SKILL.md` plus the review restrictions |
| `harness_research_worker_env DEST` | review clearing vector with the research home | review clearing vector with the research home plus `MCP_TOOL_TIMEOUT=120000` |
| `harness_finalize_research_session HOME RAW_OUTPUT` | explicit success (`--share` already wrote the transcript) | renders the research JSONL into `research-session.md`, fails on substitution, effort change, or subagent turns, or on a dossier without a session record |

The runner keeps request rendering, broker lifecycle, timeouts, dossier
extraction, validation, cleanup, and artifacts, and now gates scope 2/3 on
`web_research == yes` instead of the harness ID. The no-op fixture implements
the four functions as fail-closed stubs.

Claude Code keeps `web_research=no` and `builtin_research_specialist=no`. A
staged test copy with `web_research=yes` proves the runner reaches the Claude
Code research worker with the exact MCP configuration and grant, then fails
closed (`ResearchCapabilityFailed`) with the research home and MCP
configuration removed. Flipping the production capability requires one real
broker-backed scope-2 run (operator step) and review of its dossier, network
summary, and research transcript.

## Open items

- P2 under a long run that crosses access-token expiry.
- One real scope-1 review through `rhyolite --harness claude` (Phase 2 exit
  criterion).
- One real staged scope-2 run that completes before `web_research` can
  become `yes`. In R4 the research phase completed, but the review failed at
  the output token limit (now addressed). The run must be repeated.
