# Claude Code harness: implementation handoff

Status (2026-10-08): Phases 0-4 are complete and released in Rhyolite 0.8.0;
`main` and the annotated tag `v0.8.0` point to `1fbd538`. The feature branch
was merged and deleted. "Handoff (2026-10-08)" at the end of this file lists
the open follow-ups; `docs/CLAUDE-HARNESS-EVIDENCE.md` holds the probe and
real-run evidence.

Development reasoning policy (from AGENTS.md, carried into this handoff): use a
current frontier reasoning model at maximum available reasoning effort and the
largest supported context for every task in this plan; downgrade only
mechanical, fully scoped steps, and only to high. Read AGENTS.md,
docs/ADDING-A-HARNESS.md and docs/HARNESS-ARCHITECTURE.md before starting.

# Claude Code harness for Rhyolite: architecture and development plan

Execution model: this plan is written for Claude Opus 5.5 at maximum effort,
working on a new feature branch. The first iteration must *run*; polish comes
later. Every phase ends with the mandatory gate `bash ./tests/validate-all.sh`.

## Context

Rhyolite's `repo-review` runs its write-disabled review worker through a
harness adapter (Contract v4, `plugins/rhyolite/lib/harness/`). Production is
Copilot-only. The goal is a second production harness, `claude`, that drives
Claude Code CLI (`claude`, installed here as 2.1.292) and approaches parity
with the Copilot experience: the same launcher, guided setup, plan approval,
runner, artifacts and safety boundary, with Claude Code as both the outer
interactive session and the isolated worker.

This branch is the explicit project decision that `docs/ADDING-A-HARNESS.md`
("Non-negotiable preconditions", item 1) requires. The playbook's rules still
apply: no dynamic discovery, no fallback to Copilot, capabilities are evidence,
registration is the last enablement step of Phase 1, scope 2/3 fails closed
until Phase 3 proves the research contract.

### User decisions (confirmed)

- Plugin layout: **single dual-harness root** `plugins/rhyolite/`. Claude gets
  `.claude-plugin/plugin.json` plus `claude/{agents,commands,hooks.json}`;
  skills, scripts, lib, bin and branding stay shared. Copilot's
  `agents/`, `commands/`, `extensions/` move under `copilot/` only if probe P8
  shows Claude auto-loads the default directories.
- Default Claude model: **`claude-opus-5-5`**, guided alternate
  `claude-fable-5-1`, effort `max`.
- Phase order: adapter core -> outer experience -> research (Contract v5) ->
  docs/validators/release.

### Facts established during planning

- The runner calls the adapter only for the main worker and the report-repair
  child. The scope 2/3 research worker is runner-owned and hard-coded to
  Copilot (`run-parallel-reviews.sh:2248-2258`, `:5472-5555`), including a
  duplicate runtime-home helper that reads the Copilot adapter's globals.
- The transcript file (`<result>/session.md`) exists only because Copilot
  writes it via `--share`. The runner treats it as optional; it sanitizes it
  after `harness_persist_agent_state` (runtime home still present) and before
  `harness_extract_final_report`. The repair flow has no adapter hook between
  child exit and extraction.
- The runner execs `harness_cli_name` from its own cwd; Copilot gets its cwd
  from `-C`. Claude Code has no `-C`, but GNU `env` 9.10 on Fedora 44 supports
  `-C/--chdir`, and the runner applies the adapter's env array through `env`.
- The launcher (`plugins/rhyolite/bin/rhyolite`) hard-codes `command -v
  copilot`, the outer `copilot` argv, fleet pickers and `copilot-logs`; it
  does not use `harness_cli_name`, `harness_require_cli` or
  `harness_capability fleet`.
- Claude Code 2.1.292 facts (from `claude --help` and the binary):
  `-p`, `--model`, `--effort low|medium|high|xhigh|max`, `--session-id <uuid>`,
  `--name`, `--output-format text|json|stream-json`, `--permission-mode
  dontAsk`, `--permission-prompts none`, `--restricted` (removes Bash and other
  code-running tools and WebFetch, ignores user/project/local settings,
  confines file tools to cwd + `--add-dir`, refuses bypassPermissions),
  `--tools "Read,Glob,Grep"` / `--tools ""`, `--disallowedTools`,
  `--settings <file-or-json>` (still applied under `--restricted`),
  `--strict-mcp-config`, `--mcp-config`, `--plugin-dir`, `--agent
  <plugin>:<agent>`, `--disable-slash-commands`, `--append-system-prompt-file`,
  `--no-session-persistence`, `--fallback-model` (off by default; never pass),
  `--dangerously-skip-permissions`, `--bare` (skips CLAUDE.md/hooks but
  restricts auth to API key, so it is unusable for subscription users).
  `CLAUDE_CONFIG_DIR` relocates `.credentials.json`, `settings.json`,
  `projects/<cwd-slug>/<session-id>.jsonl`. Env switches present in the binary:
  `CLAUDE_CODE_DISABLE_CLAUDE_MDS`, `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD`,
  `DISABLE_AUTOUPDATER`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`; settings
  keys `claudeMdExcludes`, `disableAllHooks`, `autoMemoryEnabled`,
  `effortLevel`, `permissions.deny`. Print-mode JSON result subtypes include
  `error_during_execution`, `error_max_turns`, `error_max_budget_usd`.
  The session transcript JSONL format is documented as internal and
  version-dependent, so parsing must be defensive and fixture-tested.
- Injection surfaces specific to Claude Code: nested `CLAUDE.md` files load on
  demand from subdirectories of cwd (the snapshot is `cwd/source`), and
  `.claude/skills` under additional directories can load. Both must be closed
  by the worker argv/env/settings and proven by a negative test.

## Target architecture

### 1. Runner and seam (unchanged ownership)

The runner keeps source validation, anonymous clone, snapshot, plan approval,
timeouts, sanitization, report validation, repair policy and artifact schemas.
The Claude adapter translates only to the `claude` CLI. Plan schema stays 5
and state schema 6 for Phases 1-2. Phase 3 bumps the harness contract to 5
(new research functions) without changing plan/state schemas.

### 2. `plugins/rhyolite/lib/harness/claude.sh` (new, Contract v4 -> v5)

Mirror the structure of `copilot.sh` (helpers first, then every `harness_*`
function in the same order). Module globals, set only via
`rhyolite_harness_invoke` in the same shell: `CLAUDE_RUNTIME_HOME`,
`CLAUDE_SESSION_ROOT`, `CLAUDE_SESSION_ID`, `CLAUDE_TRANSCRIPT_PATH`,
`CLAUDE_REPAIR_WORKDIR`, `CLAUDE_AUTH_BRIDGE_SOURCE`, `CLAUDE_AUTH_BRIDGE_INITIALIZED`.

| Function | Claude behavior |
| --- | --- |
| `harness_id` / `harness_display_name` / `harness_cli_name` | `claude` / `Claude Code` / `claude` |
| `harness_require_cli` | `command -v claude` only |
| `harness_capability` | `shell_denial=yes`, `structured_questions=yes` (AskUserQuestion), `final_message_file=no`, `fleet=no`, `subagents=no`, `builtin_security_specialist=no`, `builtin_research_specialist=yes`, `web_research=yes` (flipped in Phase 3 after real run R5) |
| `harness_default_model` | `claude-opus-5-5` |
| `harness_list_models` | Adapter-owned offline catalog constant (ordered): `claude-opus-5-5`, `claude-fable-5-1`, `claude-sonnet-5-5`, `claude-fable-5`, `claude-opus-5`, `claude-sonnet-5`. Claude Code exposes no local catalog surface; document this interpretation in `docs/ADDING-A-HARNESS.md` (static catalog may omit models an account can use; unlisted path covers the rest). |
| `harness_validate_model_id` | Reject unsafe IDs and selector aliases `opus`, `sonnet`, `haiku`, `fable`, `default`, `auto` (case-insensitive) with status 1; exact catalog member -> 0; safe ID matching `^claude-[a-z0-9][a-z0-9.-]*$` -> status 3 (`RHYOLITE_HARNESS_MODEL_UNLISTED_STATUS`); anything else -> 1. `[1m]` suffixed IDs are unsafe under the runner grammar and stay rejected. |
| `harness_model_choices` | `Claude Opus 5.5 (Recommended) - claude-opus-5-5`, `Claude Fable 5.1 - claude-fable-5-1`, `List available model IDs` |
| `harness_max_reasoning_effort` | `max` for any safe model ID |
| `harness_reasoning_effort_choices` / `harness_validate_reasoning_effort` | same tokens as Copilot: `max`, `xhigh`, `high` |
| `harness_default_context_tier` / `harness_context_choices` / `harness_validate_context_tier` | `long_context` recommended and only guided choice; validator accepts `long_context` and `default`. Catalog models have native 1M context, so the tier adds no argv; document this. |
| `harness_auth_secret_env_vars` | ordered: `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_CUSTOM_HEADERS`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_BEARER_TOKEN_BEDROCK`, `GOOGLE_APPLICATION_CREDENTIALS`, `ANTHROPIC_FOUNDRY_API_KEY` |
| `harness_login_remediation` | "Run `claude auth login` from a clean non-Git directory (or export `CLAUDE_CODE_OAUTH_TOKEN` from `claude setup-token`, or `ANTHROPIC_API_KEY`), then retry." Never run login automatically. |
| `harness_provider_summary` | `{"Id":"anthropic-claude-code","Host":"api.anthropic.com","ForwardedEnvVarNames":[...same order...]}` |
| `harness_resume_policy` | "Continue only through the trusted Rhyolite repo-review runner; do not invoke `claude --resume` directly." |
| `harness_prepare_run` | Idempotent. Resolve `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json`; if it is a regular non-symlink file readable by the user, record its path as the bridge source (do not parse or load it); otherwise record empty (fail soft). Print one status sentence, no paths of secrets. Probe P1/P2 decide whether the file bridge is the default or env-token only (see Phase 0). |
| `harness_prepare_worker_home HOME EFFORT CTX [review\|report-repair\|research]` | `chmod 700`; copy the bridge file to `HOME/.credentials.json` (mode 600) when a source exists; write `HOME/settings.json` (mode 600) per phase (below); write `HOME/.claude.json` only if probe P1 shows onboarding state is needed (`{"hasCompletedOnboarding":true}`). Set `CLAUDE_RUNTIME_HOME`. |
| `harness_worker_argv` | ordered vector below; records `CLAUDE_SESSION_ROOT`, `CLAUDE_SESSION_ID`, `CLAUDE_TRANSCRIPT_PATH`; validates destination name, UUID, safe model, effort/context, auth CSV equality (reuse the `copilot_validate_protected_auth_csv` pattern) |
| `harness_worker_env` | env data array below (includes `-C <session_root>`) |
| `harness_report_repair_argv` / `harness_report_repair_env` | vectors below; same validations as Copilot (empty non-symlink workdir, UUID, absolute transcript path) |
| `harness_render_request` | copy the Copilot implementation verbatim into a shared helper (it is harness-neutral). Preferred: move `copilot_render_request_template` into `plugins/rhyolite/lib/harness/common.sh` as `rhyolite_harness_render_request_template` and have both adapters call it, with validator wording updated; acceptable fallback for I1: duplicate in `claude.sh`. |
| `harness_extract_final_report TIMELINE TRANSCRIPT FINAL REPORT` | `claude_extract_latest_assistant_text TRANSCRIPT main` (python3 stdlib: read JSONL lines defensively, keep the last line with `type=="assistant"` whose `message.content` has `text` blocks, concatenate text blocks in order, ignore lines that fail to parse) -> write to FINAL -> `extract_report FINAL REPORT` (runner-owned, `review-output.sh:159`). Return 42 when no assistant text exists; always remove FINAL. |
| `harness_extract_report_repair TIMELINE TRANSCRIPT REPLY` | 1) timeline is a `--output-format json` envelope: parse with python3, require `is_error` false and `result` present, then require `result` to be exactly one compact JSON object with the six descriptor keys (reuse the `copilot_write_pure_report_repair_descriptor` key check, factored into a shared helper or duplicated); 2) else latest assistant text from TRANSCRIPT if present; 3) else sanitized error, status 42, partial files removed. |
| `harness_verify_isolation TIMELINE` | assert `CLAUDE_RUNTIME_HOME` (if still present) contains no `source/`, no `.git`, and that the timeline does not contain a runtime-home path; otherwise return 0 explicitly. |
| `harness_persist_agent_state HOME DEST EFFORT CTX` | create `DEST/claude-home` (700); write sanitized `settings.json` (review-phase settings, 600); copy only `projects/**/<CLAUDE_SESSION_ID>.jsonl` under `DEST/claude-home/projects/` (600); **also export that JSONL to `CLAUDE_TRANSCRIPT_PATH`** so the runner's transcript sanitization, fallback extraction and `session.md` artifact work. Exclude `.credentials.json`, `.claude.json`, `history.jsonl`, caches, telemetry, shell snapshots, debug logs. |
| `harness_sanitize_runtime_home HOME` | delete `.credentials.json` first (overwrite with `{}` if unlink fails), then bounded `rm -rf` x3 with retries, idempotent, error if it still exists (copy Copilot's shape) |
| `harness_allow_all_detected` | return 1 always; Claude exposes no inherited allow-all signal and the child receives an explicit `--permission-mode`. Document. |

#### Main worker argv (golden vector, one argument per element)

```
-p
--model <model>
--effort <effort>
--session-id <session_id>
--name <session_name>
--output-format text
--permission-mode dontAsk
--permission-prompts none
--restricted
--settings <runtime_home>/settings.json
--strict-mcp-config
--tools Read,Glob,Grep
--disallowedTools Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch,Agent,Skill,AskUserQuestion,TodoWrite,ToolSearch
--disable-slash-commands
--plugin-dir <plugin_root>
--agent rhyolite:repo-review-worker
--append-system-prompt-file <plugin_root>/skills/readonly-repository-review/SKILL.md
```
Request arrives on stdin (the runner already redirects `request.txt`). Stdout
with `text` format is the final assistant text, so the runner's primary
`extract_report` on the timeline works unchanged; the JSONL transcript is the
fallback. `<transcript_path>` and `<available_tools>` are validated but not
forwarded (Claude has no `--share`; tool names are adapter-owned). Keep
`enable_public_research` ignored in Phase 1 exactly like Copilot.

#### Main worker env data array

```
-C <session_root>
-u CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD
-u ANTHROPIC_MODEL
-u CLAUDE_CODE_EFFORT_LEVEL
-u CLAUDE_CODE_RESUME_INTERRUPTED_TURN
-u CLAUDE_CODE_SIMPLE
CLAUDE_CONFIG_DIR=<runtime_home>
CLAUDE_CODE_DISABLE_CLAUDE_MDS=1
DISABLE_AUTOUPDATER=1
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
NO_COLOR=1
CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000
```
Not `env -i`: HOME, XDG, PATH and the approved auth variables stay inherited
(same semantics as Copilot). The `-C` entry needs `CLAUDE_SESSION_ROOT` from
`harness_worker_argv` (invoked earlier in the same shell; the runner order is
argv -> prepare home -> env).

#### Runtime-home `settings.json` (review phase)

```json
{"disableAllHooks":true,"autoMemoryEnabled":false,"includeCoAuthoredBy":false,
 "claudeMdExcludes":["**/CLAUDE.md","**/CLAUDE.local.md","**/.claude/**"],
 "effortLevel":"<effort>",
 "permissions":{"defaultMode":"dontAsk","additionalDirectories":[],
   "deny":["Bash","Edit","Write","NotebookEdit","WebFetch","WebSearch","Agent","Skill","AskUserQuestion","TodoWrite","ToolSearch"]}}
```
Report-repair phase: same minus `effortLevel`, with `deny` also covering
`Read`, `Glob`, `Grep`. Three independent layers deny tools: `--tools`
inventory, `--disallowedTools`, and `permissions.deny`.

#### Report-repair argv (separate golden vector)

```
-p
--model <model>
--effort <effort>
--session-id <session_id>
--name <session_name>
--output-format json
--permission-mode dontAsk
--permission-prompts none
--restricted
--settings <runtime_home>/settings.json
--strict-mcp-config
--tools ""
--disallowedTools Read,Glob,Grep,Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch,Agent,Skill,AskUserQuestion,TodoWrite,ToolSearch
--disable-slash-commands
--no-session-persistence
```
No `--plugin-dir`, `--agent`, `--mcp-config`, `--add-dir`, `--resume`,
`--continue`, `--fallback-model`, `--dangerously-skip-permissions`,
`--allowedTools`. Repair env = worker clearing semantics with
`-C <repair_workdir>` and `CLAUDE_CONFIG_DIR=<fresh repair home>`. The
descriptor is read from the JSON envelope's `result`; the repair transcript
artifact is not produced for Claude (documented; the runner already treats it
as optional).

#### Failure mapping

`errors_report_unavailable_model` (`run-parallel-reviews.sh:313`) gains a
Claude pattern captured by probe P3 so an unavailable approved model reports
the `model availability` stage. Exit code 1 with `is_error`/error subtypes is
otherwise handled by the runner's generic worker-failure path.

### 3. Outer experience (Phase 2)

Plugin layout (single root `plugins/rhyolite/`):

```
.claude-plugin/plugin.json        name rhyolite, version from VERSION, agents/commands/hooks custom paths
claude/agents/repo-review.md      orchestrator (tools: Read, Glob, Grep, Bash, AskUserQuestion; disallowedTools: Edit, Write, WebFetch, WebSearch)
claude/agents/repo-review-worker.md        (tools: Read, Glob, Grep; model: inherit)
claude/agents/repo-research-worker.md      (Phase 3; tools: Read, Glob, Grep, mcp__rhyolite-research__*)
claude/commands/{start,repo-review,status,version,help}.md
claude/hooks.json                 SessionStart + UserPromptSubmit -> scripts/show-welcome-panel.sh --claude-...
copilot/{agents,commands,extensions}   only if probe P8 requires the move; plugin.json paths updated
skills/, scripts/, lib/, bin/, branding/   shared
.claude-plugin/marketplace.json (repo root)   Claude marketplace entry pointing at plugins/rhyolite
```

- `scripts/show-welcome-panel.sh` gains Claude hook modes that read the
  Claude hook JSON on stdin and emit `{"systemMessage": ...}` (display) plus
  no `additionalContext`; the plaque trigger logic and marker handling stay
  shared. Probe P11 confirms the display field.
- `claude/agents/repo-review.md` is a Claude-native rewrite of
  `agents/repo-review.agent.md`: same intents (`help`, `status`, `explain
  scopes`, `stop`/`cancel`), same question order, same runner commands with
  `--harness claude`, AskUserQuestion pickers (up to 4 options per question,
  automatic free-text option, so never add `Other`), `Bash` only for the two
  runner invocations and `cat`-free reads via `Read`, stop handling by
  terminating the runner process (the runner propagates INT/TERM), the same
  `RHYOLITE EXECUTIVE SUMMARY` and single `Run output:` line. The fleet
  question is skipped because `fleet=no`. Keep the prompt-native help panel
  text identical to the Copilot agent so the existing sync validator pattern
  can be reused for the second file.
- Launcher `bin/rhyolite`: make CLI discovery, the fleet picker and the outer
  argv harness-aware through the adapter (`harness_cli_name`,
  `harness_require_cli`, `harness_capability fleet`, `harness_model_choices`).
  Keep the Copilot vector byte-identical. Claude vector (cwd set by `cd` to
  the clean launch dir before exec; log dir `claude-logs`):

```
claude
--plugin-dir <plugin_root>
--agent rhyolite:repo-review
--model <model>
--effort <effort>
--name rhyolite-<timestamp>
--strict-mcp-config
--settings {"permissions":{"allow":["Bash(bash <plugin_root>/skills/readonly-repository-review/scripts/run-parallel-reviews.sh *)"]}}
[--dangerously-skip-permissions]            # only with --yolo
<initial prompt block>                      # same RHYOLITE_START_COMMAND_V1 / RHYOLITE_LAUNCHER_SETUP_V1 text as -i today
```
  Exported markers stay identical (`RHYOLITE_LAUNCHER_HARNESS=claude`, etc.).
  Preferences already carry the harness (schema 3); the launcher must not
  reuse a Copilot preference for Claude (existing `mismatch` status covers it;
  add a test).
- Commands: Claude frontmatter (`description`, `allowed-tools`,
  `disable-model-invocation`), bodies reuse the Copilot text with
  `$ARGUMENTS`. The `/repo-review` shorthand is Copilot-extension-only; for
  Claude ship `/rhyolite:repo-review` only (document).

### 4. Research through the adapter (Phase 3, Contract v5)

Add to `common.sh` required list and bump `RHYOLITE_HARNESS_CONTRACT_VERSION=5`:

- `harness_research_tool_names` -> newline list of runtime tool names
  (Copilot `rhyolite-research-<tool>`, Claude `mcp__rhyolite-research__<tool>`).
- `harness_write_research_mcp_config PATH LAUNCHER ARGS_ARRAY_NAME TOOLS_JSON`
  -> harness-specific JSON (Copilot: `type local` + `tools` + `timeout`;
  Claude: `{"mcpServers":{"rhyolite-research":{"type":"stdio","command":...,"args":[...]}}}`).
- `harness_research_worker_argv DEST session_root plugin_root session_name session_id model effort context auth_csv mcp_config_path transcript_path`
  (Claude adds `--mcp-config <path> --strict-mcp-config --allowedTools
  mcp__rhyolite-research__research_capabilities,... --agent
  rhyolite:repo-research-worker --append-system-prompt-file
  <plugin_root>/skills/research-source-assessment/SKILL.md`).
- `harness_research_worker_env DEST`; `harness_prepare_worker_home` phase
  `research`; `harness_persist_agent_state` for the research session export.
- Runner: replace the `HARNESS != copilot` gate with `web_research == yes`;
  move `write_isolated_copilot_settings`, `initialize_runtime_copilot_home`,
  `sanitize_and_remove_runtime_copilot_home` and the inline research argv into
  `copilot.sh` behind the new functions, preserving the exact vectors that
  `tests/validate-plugin.sh` mock asserts; `extract_research_dossier` stays
  runner-owned (delimiter based, works on Claude stdout).
- No-op fixture implements the new functions as fail-closed stubs
  (`web_research=no`). Claude flips `web_research`,
  `builtin_research_specialist` to `yes` only with the end-to-end evidence.

## Phase 0: branch and probes (Opus, with network, ~half a day)

1. `git switch -c feature/claude-code-harness` from `main`.
2. Run probes in a scratch directory outside any Git worktree with a fresh
   `CLAUDE_CONFIG_DIR`. Record outcomes in `docs/CLAUDE-HARNESS-EVIDENCE.md`
   (new, contributor-facing) because the playbook requires evidence:
   - P1 auth/onboarding: copy `~/.claude/.credentials.json` into the fresh
     dir, run `claude -p --restricted --tools "" --output-format json "Reply OK"`.
     Expect no onboarding prompt and a result. If a `.claude.json` is needed,
     note the minimal content.
   - P2 refresh rotation: after P1, confirm the original credentials still
     work; if P1 rotated the refresh token and invalidated the original, make
     the bridge env-token-only (`CLAUDE_CODE_OAUTH_TOKEN`/`ANTHROPIC_API_KEY`)
     and update remediation text accordingly.
   - P3 model availability: `--model claude-bogus-9` and an alias; capture
     exit code and exact stdout/stderr wording for the runner pattern.
   - P4 tool denial: run the worker vector against a toy snapshot and ask the
     model to list its tools and to write a file; check
     `permission_denials` with `--output-format json` once, then `text`.
   - P5 nested CLAUDE.md: put a canary `source/CLAUDE.md` and
     `source/.claude/skills/x/SKILL.md`; prove neither is loaded with the env
     and settings above (try `CLAUDE_CODE_DISABLE_CLAUDE_MDS=1` and
     `claudeMdExcludes` separately, keep both).
   - P6 transcript: locate `projects/<slug>/<session-id>.jsonl`, record the
     slug rule and an assistant line shape; save a trimmed sample as a test
     fixture.
   - P7 json envelope fields (`result`, `is_error`, `subtype`, `session_id`).
   - P8 plugin: with `.claude-plugin/plugin.json` custom paths, does
     `claude --plugin-dir plugins/rhyolite` also load `agents/*.agent.md`?
     Does `--agent rhyolite:repo-review-worker` work in `-p`? Does
     `--disable-slash-commands` break anything the worker needs?
   - P9 `--append-system-prompt-file` accepted in `-p` with a 56 KB file.
   - P10 AskUserQuestion limits in an interactive session (options per
     question, free-text option) and `--agent` as main thread with a
     positional first prompt.
   - P11 hook display: which hook output shows text to the user without
     adding context (`systemMessage`), and the `UserPromptSubmit` stdin shape.
   - P12 `env --chdir` present (coreutils 9.10: yes).
3. Decide the open items from probe results and update this plan's vectors
   before coding.

## Phase 1: adapter core (scope 1 + report repair)

Files:
- `plugins/rhyolite/lib/harness/claude.sh` (new; model on `copilot.sh`).
- `plugins/rhyolite/lib/harness/common.sh`: registry case gains
  `claude) ... lib/harness/claude.sh`; `rhyolite_harness_list_registered`
  prints `copilot` and `claude`. Do this last in the phase.
- `plugins/rhyolite/skills/readonly-repository-review/scripts/run-parallel-reviews.sh`:
  usage text lists both harnesses; `errors_report_unavailable_model` gains
  the Claude pattern; no other runner change for scope 1.
- `plugins/rhyolite/claude/agents/repo-review-worker.md` (needed by the worker
  argv even before the outer experience lands) and the minimal
  `.claude-plugin/plugin.json` so `--plugin-dir` resolves the agent.
- `tests/validate-harness-contract.sh`: add a Claude section mirroring the
  Copilot one, using the same staging technique (copy plugin tree, append
  overrides, mock CLI in a temp bin):
  - mock `claude` that records argv/env, requires `CLAUDE_CONFIG_DIR`,
    writes `projects/<slug>/<session-id>.jsonl` (fixture lines from P6),
    prints the report on stdout; modes for incomplete stdout (transcript
    fallback), unsafe text, nonzero exit, unavailable model wording,
    repair json envelope valid/prose/missing;
  - golden worker argv/env and repair argv/env vectors, `cmp` over NUL;
  - identity, catalog, alias rejection, unlisted status 3 with and without
    `--allow-unlisted-model`, effort/context validators, auth list and
    provider summary equality, remediation, resume policy;
  - plan-only runs with no `claude` on PATH, approval-hash distinctness vs
    Copilot, cross-harness approval rejection in both directions;
  - runtime-home inventory and modes, bridge present/absent, persisted
    allowlist, transcript export, cleanup/trap/forced failure, injected
    failure at every function, nested-CLAUDE.md canary not in output,
    scope 2 rejected before broker activity;
  - update the existing assertions that expect `claude` to fail to load
    (`:270`, `:2405-2410`) to use `codex`/`bogus`/`noop`, and add a
    `claude` load-success case.
- `tests/validate-plugin.sh`: add `CLAUDE_HARNESS` to required files and
  `bash -n`; relax the CLAUDE.md pointer assertion (`:237-240`) in Phase 4
  only; keep every Copilot assertion green.
- `tests/test-install.sh`: add `lib/harness/claude.sh` to the required list.

Exit criteria: `bash ./tests/validate-harness-contract.sh` and
`bash ./tests/validate-all.sh` pass; one real scope-1 review runs end to end
with `bash plugins/rhyolite/skills/readonly-repository-review/scripts/run-parallel-reviews.sh --harness claude --repo <public url> ...` and produces a validated canonical report.

## Phase 2: outer experience

- `.claude-plugin/plugin.json`, `claude/agents/repo-review.md`,
  `claude/commands/*.md`, `claude/hooks.json`, hook modes in
  `scripts/show-welcome-panel.sh`, root `.claude-plugin/marketplace.json`.
- If P8 requires it: move Copilot `agents/`, `commands/`, `extensions/` to
  `copilot/...`, update `plugin.json`, `tests/validate-plugin.sh:361-365`,
  `tests/test-install.sh:87-88`, `tests/validate-tui-runtime.mjs` paths,
  AGENTS.md architecture map, README.
- `bin/rhyolite`: harness-aware discovery/argv/pickers as designed; help text
  lists both harnesses; `--fleet-mode native` rejected for Claude with a
  `RHYOLITE ERROR` (capability `no`).
- `scripts/launcher-preferences.sh`: no schema change; add mixed-harness
  tests.
- Tests: launcher golden vector for Claude in `validate-harness-contract.sh`
  (mock `claude` in PATH capturing argv), `validate-plugin.sh` assertions for
  the new manifest/agents/commands/hooks, `validate-tui-runtime.mjs` cases
  for the Claude hook output modes.

Exit criteria: `./rhyolite --harness claude --repo <url>` starts an
interactive Claude Code session that shows the plaque, runs guided setup with
pickers, approves a plan and completes a scope-1 review with the executive
summary.

## Phase 3: research (Contract v5)

As designed in section 4. Order: refactor Copilot research into `copilot.sh`
behind new functions with vectors preserved (validate-plugin mock must stay
green) -> no-op fixture stubs -> Claude implementation -> flip `web_research`
to `yes` -> end-to-end scope 2 run on Claude -> docs.

## Phase 4: docs, validators, release surfaces

- `AGENTS.md`, `CLAUDE.md` (now a contributor pointer that states Claude Code
  runtime support exists), `.github/copilot-instructions.md`, `README.md`
  (install for Claude: `claude --plugin-dir`, marketplace add), `DEVELOPERS.md`
  (Claude toolchain, `claude auth login`), `docs/HARNESS-ARCHITECTURE.md`
  (Claude baseline section, contract v5), `docs/ADDING-A-HARNESS.md` (static
  catalog interpretation, contract v5 functions, Claude evidence table),
  `docs/PLAN-OF-RECORD.md` (decision record), `docs/THREAT-MODEL.md`,
  `SECURITY.md`/`PRIVACY.md` (credential bridge statement), `SUPPORT.md`.
- Validators that assert Copilot-only wording (`tests/validate-plugin.sh`
  ~`:145`, `:237-240`, `:466`, `:479`, `:1107`, `:1433-1454`, `:1575`) are
  updated with the new wording, never deleted.
- Release: `VERSION`, `plugins/rhyolite/plugin.json`,
  `.github/plugin/marketplace.json`, `.claude-plugin/marketplace.json`,
  `CHANGELOG.md`; `bash tools/public-release/test-public-release.sh`;
  `bash tests/test-install.sh` (Copilot) plus a Claude install smoke check.

## Verification (every phase)

```bash
git diff --check
bash -n plugins/rhyolite/lib/harness/claude.sh
bash ./tests/validate-harness-contract.sh
bash ./tests/validate-all.sh
copilot --plugin-dir ./plugins/rhyolite plugin list      # Copilot discovery unchanged
claude --plugin-dir ./plugins/rhyolite -p --tools "" "Reply OK"   # Claude plugin loads (Phase 2+)
```
Real runs: scope 1 on a small public repository via the direct runner
(Phase 1), via the launcher (Phase 2), scope 2 (Phase 3). Keep the evidence
document updated with argv/env captures, runtime-home inventories, repair
vectors and negative results, as `docs/ADDING-A-HARNESS.md` "Evidence
required for completion" lists.

## Reuse pointers

- `plugins/rhyolite/lib/harness/copilot.sh`: `copilot_validate_protected_auth_csv`
  (:16), `copilot_write_settings` (:56), `copilot_populate_worker_environment`
  (:206), `copilot_write_pure_report_repair_descriptor` (:223),
  `harness_render_request` (:732), `harness_sanitize_runtime_home` (:957).
- `plugins/rhyolite/lib/harness/common.sh`: `rhyolite_harness_set_error`,
  `rhyolite_harness_capture`, `rhyolite_harness_invoke`, registry (:163).
- `review-output.sh`: `extract_report` (:159), `sanitize_review_text` (:43).
- `run-parallel-reviews.sh`: `new_session_id` (:4418, UUID),
  `errors_report_unavailable_model` (:313), worker launch (:5840-5935),
  repair launch (:3795-3900), research gate (:2233-2259), research launch
  (:5472-5555), MCP config writer (:4545).
- `tests/validate-harness-contract.sh`: staging and registry override
  (:3175-3233), mock CLI (:2790-2904), golden vectors (:745-803, :833-894),
  failure cases (:4373-4640), launcher cases (:4736-5194).
- `tests/fixtures/harnesses/noop.sh`: shape for fail-closed stubs.

## Risks and open items

- Auth bridge safety (P2) can change the default auth path; keep the env
  token path working regardless.
- Transcript JSONL is an internal format; keep parsing defensive, fixture
  based, and fall back to stdout-first extraction.
- `--restricted` and `--tools` semantics around `Agent`/`AskUserQuestion`
  (P4) decide whether `subagents` can later become `yes`.
- Validator wording churn in `tests/validate-plugin.sh` is large but
  mechanical; never weaken a negative test to make Claude pass.

## Progress (2026-10-07)

Development reasoning policy carries forward: maximum available reasoning
effort and the largest supported context for every task; downgrade only
mechanical, fully scoped steps, and only to high.

Done:

- Phase 0 probes, recorded in `docs/CLAUDE-HARNESS-EVIDENCE.md`, except the
  operator-run P1/P2 credential-bridge probes.
- Phase 1: `lib/harness/claude.sh`, registry entry and
  `rhyolite_harness_list_registered`, runner usage/model-availability/
  research-gate wording, `claude/agents/repo-review-worker.md`,
  `.claude-plugin/plugin.json`, and `tests/harness-contract-claude.sh`
  (sourced by `tests/validate-harness-contract.sh`). Test `ROOT` resolution is
  now physical (`cd -P`) so the gate passes from a symlinked checkout path.
- Phase 2: `claude/agents/repo-review.md`, `claude/commands/*.md`,
  `claude/hooks.json`, Claude hook modes in `scripts/show-welcome-panel.sh`,
  harness-aware `bin/rhyolite`, root `.claude-plugin/marketplace.json`, and
  `tests/test-install.sh` payload entries. Probe P8 showed no move under
  `copilot/` is needed.

Deviations from the plan above, each backed by probe evidence:

- Worker and repair settings are passed inline with `--settings <json>`:
  the runner builds argv before it creates the runtime home, and
  `--restricted` ignores the runtime home's own `settings.json`.
- `claudeMdExcludes` adds `**/AGENTS.md`; the worker env also unsets
  `MAX_THINKING_TOKENS`.
- Provider host is `managed-provider`, not `api.anthropic.com`, because
  inherited Claude Code provider settings choose the endpoint.
- The guided context picker offers only `long_context`; the runtime
  confirmation has no context option (AskUserQuestion needs 2-4 options).
- `session.md` is a rendered transcript (not raw JSONL); persisted state keeps
  a filtered, sanitized JSONL without private attachments.
- The adapter fails closed (`harness_verify_isolation`) when the session
  record shows another model (Fable safeguard fallback to Opus 4.8 observed),
  a changed effort, an advisor model, or a subagent turn, or when a report
  arrives without its session record.
- The outer launcher session adds `--permission-mode default` and `--`
  before the initial prompt; `--yolo` maps to
  `--dangerously-skip-permissions`. No `claude-logs` directory is created.
- The orchestrator locates the runner through Claude Code's
  `${CLAUDE_PLUGIN_ROOT}` substitution in agent text (verified), runs the
  review as a background Bash task, and stops it with `TaskStop`.
- Claude Code hook plaques use the same ANSI gradient as Copilot (operator
  confirmed colour renders). Claude Code renders a SessionStart
  `systemMessage` after the first visible prompt and runs full-screen, so the
  launcher passes the trusted setup block with `--append-system-prompt` and
  the visible first prompt is only `RHYOLITE_START_COMMAND_V1` plus the
  begin line; the orchestrator accepts the block only from its system prompt.
- Operator launcher run found a transient anonymous refusal of the
  blob-filtered clone's checkout fetch (Git reports it as
  `unable to get password from user`). The shared runner now retries that
  checkout twice (`reset --hard HEAD`, anonymous, pinned DNS, 5 s and 10 s)
  and explains an authentication challenge plainly; Copilot shares the fix.
- `/rhyolite:status` and exact `help` blocks now include `Harness:` for both
  harnesses.
- Operator launcher run R3 (`claude-opus-5`, `high`) failed strict validation:
  six assessment `Confidence:` values used `<Level> for ...`. Operator chose a
  shared runner fix: the approval-bound `DeterministicNormalizations` list is
  now `["markdown-table-rows","confidence-level-delimiters"]`; the new
  model-free step inserts ` - ` after a single level directly followed by
  words in field-validated assessment sections (every word kept; compound
  levels and `<Level> confidence` stay for the bounded edit), chains after
  table normalization, and records `ConfidenceNormalization` and
  `ConfidenceFieldsNormalized` in `ReportRepair`. Applied to R3's candidate it
  changed four lines and passed strict validation. The Claude Code worker
  prompt also states the single-level rule.
- Test-harness gap fixed for every harness: the contract validator's shared
  runner `python3` mock answered every `python3 - A B` call as the DNS
  resolver, which silently skipped strict report validation in runner seam
  tests. It now mocks DNS only for host/port arguments; the Copilot mock
  worker emits a complete canonical scope-1 report; a placeholder-report run
  must fail with `Final report contract validation failed`.
- Staged scope-2 run R4 (`claude-opus-5`, `max`, evidence file): research
  completed. The review's final reply reached Claude Code's 64000-token output
  limit, and Claude Code had the model finish it in a second response that
  `-p` printed alone. Workers now set `CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000`,
  which Claude Code caps at the model maximum. The transcript renderer joins
  a reply resumed after the limit into one block, before a notice that names
  each separator it inserted.

- Phase 3: Contract v5 (`RHYOLITE_HARNESS_CONTRACT_VERSION=5`) adds
  `harness_write_research_mcp_config`, `harness_research_worker_argv`,
  `harness_research_worker_env`, and `harness_finalize_research_session`
  plus the `research` home phase. The runner's Copilot-only research helpers
  moved into `copilot.sh` with the argv pinned by a golden vector; the scope
  2/3 gate is now capability-based. Claude Code implements research with a
  stdio MCP config, `--allowedTools mcp__rhyolite-research__*`, and
  `claude/agents/repo-research-worker.md`. It kept `web_research=no`
  until real run R5.
  Deviation: no `harness_research_tool_names`; runtime tool names stay
  adapter-owned and the runner passes the broker tool list.

Operator decisions (2026-10-07, after real run R1 in the evidence file):

- Keep fail-closed: any assistant turn from a non-approved model fails the
  review; no approval-bound fallback model.
- Keep `claude-opus-5-5` as the default.
- Replace the guided alternate `claude-fable-5-1` with `claude-opus-5`
  (Fable stays in the offline catalog for explicit selection).

Next:

1. Done: P1/P2 probe and a real direct-runner scope-1 review (R2 in the
   evidence file). Done: a real review through `rhyolite --harness claude`
   (guided scope-2 run R6).
2. Done: guided alternate is now `claude-opus-5`.
3. Done: staged real scope-2 run R5 completed (after R4 hit the output
   token limit), and the operator approved the flip. `web_research` and
   `builtin_research_specialist` are now `yes` for Claude Code. The guided
   orchestrator offers scopes 2 and 3 with the provenance-lookback and
   research-cookie questions. Real guided scope-2 run R6 (fedithread)
   completed.
4. Done: Phase 4 docs and validators. Support claims now cover GitHub
   Copilot CLI and Claude Code in `AGENTS.md`, `CLAUDE.md`,
   `.github/copilot-instructions.md`, the PR template and bug form, README,
   DEVELOPERS, SECURITY, PRIVACY, SUPPORT, PUBLISHING, PLAN-OF-RECORD, and the
   threat model. `HARNESS-ARCHITECTURE.md` and `ADDING-A-HARNESS.md` document
   Contract v5 and the Claude Code baseline. CHANGELOG `Unreleased` lists the
   Claude Code harness. `tests/validate-plugin.sh` pins the new wording and
   rejects stale Copilot-only claims. `tests/test-install.sh` validates both
   Claude Code manifests and installs the plugin from the local Claude Code
   marketplace into an isolated configuration.
5. Done: released as 0.8.0 (see the handoff below).

## Handoff (2026-10-08)

Release 0.8.0:

- `chore: prepare 0.8.0 release` synchronized `VERSION`, both plugin
  manifests, both marketplace registries, the version commands, the
  orchestrator panels, the extension, `SKILL.md`, `PRIVACY.md`, and the
  CHANGELOG heading `0.8.0 - 2026-10-08`. The Claude Code contract tests read
  the version from `VERSION`.
- `main` had gained a README quickstart, a screenshot, and a sample scope 3
  review. A merge commit (`1fbd538`) brought them into the release candidate
  so `main` fast-forwarded; README conflicts kept main's layout and
  reapplied the Claude Code wording.
- On `1fbd538`: `bash ./tests/validate-all.sh`, `bash ./tests/test-install.sh`,
  `bash ./tools/public-release/test-public-release.sh`, and
  `tools/public-release/public-export.sh` with preflight (0 findings; the
  exported tree's own gate passed) all passed. Copilot CLI lists
  `rhyolite (v0.8.0)` and `claude plugin validate` passes for the plugin and
  the marketplace.
- `main` and `v0.8.0` were pushed to GitHub and verified to resolve to
  `1fbd538`. All five version surfaces in the tag read `0.8.0`.

Post-release smoke test (`docs/PUBLISHING.md` checklist step 9), run in
isolated homes against the release commit:

- Fresh install, Copilot CLI and Claude Code: the plugin lists v0.8.0; the
  installed payload is byte-identical to the `v0.8.0` tag's `plugins/rhyolite`
  with executables intact; `claude plugin validate` passes on the installed
  copy; the launcher, both load lines, and both review-start plaques report
  `v0.8.0 Beta`.
- Copilot CLI manual update: installing the real 0.7.0 release and running
  `plugin marketplace update` plus `plugin update` after moving the
  marketplace source to `v0.8.0` gave v0.8.0 with a byte-identical payload.
  Claude Code has no update path to test because 0.7.0 shipped no Claude Code
  plugin.
- Installs used local-path marketplaces cloned from the canonical checkout,
  not GitHub. The GitHub repository is private: anonymous `git ls-remote`
  asks for credentials and the anonymous API returns 404, and Copilot CLI
  treats `file://` sources as local paths. Copilot loads local-path
  marketplaces live from the source tree, so its update check proves the
  update commands accept 0.7.0 to 0.8.0, not a remote download.

Open follow-ups:

1. Repository visibility is an administrative decision. Until the repository
   is public, the README and `docs/PUBLISHING.md` `marketplace add` commands
   work only for accounts with access. After a visibility change, repeat the
   smoke test with `https://github.com/xjamesmorris/rhyolite` as the
   marketplace source for both CLIs, and complete the other pre-publication
   gates in `docs/PUBLISHING.md`.
2. Interactive checks of the installed plugin, in a new Copilot CLI session
   and a new Claude Code session: the `Rhyolite v0.8.0 Beta` load line, the
   large plaque after `/rhyolite:start`, and exact `help`, `status` (Claude
   Code shows `Harness: claude`), and `explain scopes`.
3. The unmerged `chore/update-recommended-models` branch (`fd7acdd`, cut from
   `d91fe6f` before the Claude Code work) makes GPT-6 Astra the Copilot
   default. It touches `bin/rhyolite`, `AGENTS.md`, README, both harness
   docs, the agents, prompts, and both validators, so it conflicts with 0.8.0.
   Rebase it onto `main` and keep the Claude Code defaults (`claude-opus-5-5`,
   alternate `claude-opus-5`) adapter-owned in `claude.sh`.
4. Evidence open items in `docs/CLAUDE-HARNESS-EVIDENCE.md`: a long run that
   crosses access-token expiry with the copied credentials; a guided review
   with the default `claude-opus-5-5` on a non-adversarial repository; and
   joining a mid-stream resume (`Your response above was cut off
   mid-stream`) that continues partial report text, which currently fails
   closed.
5. New work starts from `main`; there is no Claude Code feature branch.
