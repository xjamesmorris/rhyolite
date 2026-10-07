#!/usr/bin/env bash

CLAUDE_AUTH_BRIDGE_INITIALIZED=0
CLAUDE_AUTH_BRIDGE_SOURCE=''
CLAUDE_RUNTIME_HOME=''
CLAUDE_HOME_PHASE=''
CLAUDE_SESSION_ROOT=''
CLAUDE_SESSION_ID=''
CLAUDE_TRANSCRIPT_PATH=''
CLAUDE_APPROVED_MODEL=''
CLAUDE_APPROVED_EFFORT=''
CLAUDE_TRANSCRIPT_STATUS=''
CLAUDE_REPAIR_WORKDIR=''
CLAUDE_REPAIR_MODEL=''
CLAUDE_RESEARCH_SESSION_ROOT=''
CLAUDE_RESEARCH_SESSION_ID=''
CLAUDE_RESEARCH_TRANSCRIPT_PATH=''
CLAUDE_RESEARCH_MODEL=''
CLAUDE_RESEARCH_EFFORT=''

claude_require_array_destination() {
    if [[ ! "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        rhyolite_harness_set_error \
            'The Claude Code harness array destination is invalid.'
        return 1
    fi
}

claude_forwarded_env_var_names() {
    printf '%s\n' \
        ANTHROPIC_API_KEY \
        ANTHROPIC_AUTH_TOKEN \
        CLAUDE_CODE_OAUTH_TOKEN \
        ANTHROPIC_CUSTOM_HEADERS \
        AWS_ACCESS_KEY_ID \
        AWS_SECRET_ACCESS_KEY \
        AWS_SESSION_TOKEN \
        AWS_BEARER_TOKEN_BEDROCK \
        GOOGLE_APPLICATION_CREDENTIALS \
        ANTHROPIC_FOUNDRY_API_KEY
}

claude_validate_protected_auth_csv() {
    local protected_names="$1"
    local expected_names
    local -a expected_name_list=()

    mapfile -t expected_name_list < <(claude_forwarded_env_var_names)
    expected_names="$(
        IFS=,
        printf '%s' "${expected_name_list[*]}"
    )"
    [[ "${protected_names}" == "${expected_names}" ]] || {
        rhyolite_harness_set_error \
            'The Claude Code protected authentication-variable list is invalid.'
        return 1
    }
}

# Claude Code exposes no local model-catalog command. This adapter-owned
# offline catalog lists exact IDs verified with the pinned Claude Code release;
# an account may be able to use models that it omits.
claude_model_catalog() {
    printf '%s\n' \
        claude-opus-5-5 \
        claude-fable-5-1 \
        claude-sonnet-5-5 \
        claude-fable-5 \
        claude-opus-5 \
        claude-sonnet-5
}

claude_valid_safe_identifier() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]
}

claude_valid_session_id() {
    [[ "$1" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

claude_denied_review_tools() {
    printf '%s' \
        'Bash,Edit,Write,NotebookEdit,WebFetch,WebSearch,Agent,Skill,AskUserQuestion,TodoWrite,ToolSearch'
}

claude_denied_repair_tools() {
    printf '%s' \
        "Read,Glob,Grep,$(claude_denied_review_tools)"
}

# Print the compact settings JSON for one phase. Claude Code silently ignores
# a whole settings source that fails schema validation in print mode, so the
# document is built only from fixed literals and an already validated effort.
claude_settings_json() {
    local phase="$1"
    local reasoning_effort="$2"
    local denied_tools
    local denied_json=''
    local tool_name
    local separator=''

    case "${phase}" in
        review|research) denied_tools="$(claude_denied_review_tools)" ;;
        report-repair) denied_tools="$(claude_denied_repair_tools)" ;;
        *) return 1 ;;
    esac
    case "${reasoning_effort}" in
        high|xhigh|max) ;;
        *) return 1 ;;
    esac
    while IFS= read -r tool_name; do
        denied_json+="${separator}\"${tool_name}\""
        separator=','
    done < <(printf '%s\n' "${denied_tools//,/$'\n'}")

    printf '%s' \
        '{"disableAllHooks":true,"autoMemoryEnabled":false,' \
        '"includeCoAuthoredBy":false,' \
        '"claudeMdExcludes":["**/CLAUDE.md","**/CLAUDE.local.md","**/AGENTS.md","**/.claude/**"],'
    if [[ "${phase}" != report-repair ]]; then
        printf '"effortLevel":"%s",' "${reasoning_effort}"
    fi
    printf '"permissions":{"defaultMode":"dontAsk","additionalDirectories":[],"deny":[%s]}}' \
        "${denied_json}"
}

claude_write_settings() {
    local settings_path="$1"
    local phase="$2"
    local reasoning_effort="$3"
    local settings_json

    settings_json="$(
        claude_settings_json "${phase}" "${reasoning_effort}"
    )" || return 1
    printf '%s\n' "${settings_json}" > "${settings_path}"
}

claude_populate_worker_environment() {
    local destination_name="$1"
    local working_directory="$2"
    local runtime_home="$3"

    claude_require_array_destination "${destination_name}" || return 1
    [[ "${working_directory}" == /* && -d "${working_directory}" &&
        ! -L "${working_directory}" ]] || {
        rhyolite_harness_set_error \
            'The Claude Code working directory is unavailable.'
        return 1
    }
    [[ "${runtime_home}" == /* && -d "${runtime_home}" &&
        ! -L "${runtime_home}" ]] || {
        rhyolite_harness_set_error \
            'The Claude Code runtime home is unavailable.'
        return 1
    }
    local -n claude_output_environment_ref="${destination_name}"

    claude_output_environment_ref=(
        -C "${working_directory}"
        -u CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD
        -u ANTHROPIC_MODEL
        -u CLAUDE_CODE_EFFORT_LEVEL
        -u MAX_THINKING_TOKENS
        -u CLAUDE_CODE_RESUME_INTERRUPTED_TURN
        -u CLAUDE_CODE_SIMPLE
        "CLAUDE_CONFIG_DIR=${runtime_home}"
        CLAUDE_CODE_DISABLE_CLAUDE_MDS=1
        DISABLE_AUTOUPDATER=1
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
        CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
        NO_COLOR=1
        # Claude Code caps this at the model's own output maximum, so a long
        # final report is not cut into separate responses at the default.
        CLAUDE_CODE_MAX_OUTPUT_TOKENS=128000
    )
}

# Render the private session JSONL as a readable transcript, write a filtered
# continuation copy, and verify that only the approved model and effort
# produced main-thread assistant turns. A reply that Claude Code stopped at
# its output token limit and asked the model to resume is rendered as one
# reply, preceded by a notice naming the separator inserted at each joint.
# Prints one status token: verified, substituted, effort-changed, subagent,
# or unreadable.
claude_render_session_transcript() {
    local session_jsonl="$1"
    local transcript_output="$2"
    local filtered_output="$3"
    local approved_model="$4"
    local approved_effort="$5"

    python3 -I - \
        "${session_jsonl}" \
        "${transcript_output}" \
        "${filtered_output}" \
        "${approved_model}" \
        "${approved_effort}" <<'PY'
import json
import re
import sys

source, transcript_path, filtered_path, model, effort = sys.argv[1:6]
TOOL_RESULT_LIMIT = 4000
RESUME_PROMPT = "Output token limit hit."
# A segment that opens with a section heading, delimiter, field label, list
# item, or table row begins its own report line; any other segment resumes
# the line where the previous response stopped.
LINE_START = re.compile(
    r"(?:={3,}|#{1,6}[ \t]|[-*+][ \t]|\d+[.)][ \t]|\||"
    r"[A-Z][A-Z0-9 ,&/()'-]*[A-Z0-9)]$|"
    r"[A-Z][A-Za-z0-9 /()'-]{0,60}:(?:[ \t]|$))"
)
JOINT_NAMES = {"": "none (whitespace already present)", "\n": "line break", " ": "space"}
KEEP_TYPES = {"user", "assistant", "system", "custom-title", "agent-name"}
status = "verified"
blocks = []


def indent(text):
    return "\n".join("    " + line for line in str(text).splitlines()) or "    "


def tool_result_text(content):
    if isinstance(content, str):
        return content
    parts = []
    if isinstance(content, list):
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                parts.append(str(item.get("text", "")))
            elif isinstance(item, dict):
                parts.append(f"[{item.get('type', 'unknown')} content omitted]")
    return "\n".join(parts)


def bounded(text):
    if len(text) <= TOOL_RESULT_LIMIT:
        return text
    omitted = len(text) - TOOL_RESULT_LIMIT
    return text[:TOOL_RESULT_LIMIT] + f"\n[tool result truncated: {omitted} characters omitted]"


def escalate(new_status):
    global status
    if status == "verified":
        status = new_status


def plain_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(
            str(item.get("text", "")) for item in content
            if isinstance(item, dict) and item.get("type") == "text"
        )
    return ""


def joint(previous, continuation):
    if (not previous or not continuation or previous[-1].isspace()
            or continuation[0].isspace()):
        return ""
    if LINE_START.match(continuation.split("\n", 1)[0]):
        return "\n"
    return " "


def stitch_notice(joints):
    resumes = len(joints)
    return indent(
        "Claude Code stopped this reply at its per-response output token "
        f"limit and asked the model to resume {resumes} "
        f"time{'' if resumes == 1 else 's'}; Rhyolite joined the "
        f"{resumes + 1} response segments in order. Separator inserted at "
        "each joint: " + ", ".join(JOINT_NAMES[item] for item in joints) + "."
    )


def flush_resume():
    global resume_notice
    if resume_notice is not None:
        blocks.append(("### Claude Code notice", indent(resume_notice)))
        resume_notice = None


kept_lines = []
last_text_message = None
cut_message = None
resume_notice = None
stitch = None
with open(source, encoding="utf-8", errors="strict") as stream:
    raw_lines = stream.readlines()
for index, raw_line in enumerate(raw_lines):
    if not raw_line.strip():
        continue
    try:
        record = json.loads(raw_line)
    except (ValueError, UnicodeError):
        # A worker stopped by the timeout can leave one partial final
        # record without its newline; every complete record must parse.
        if index == len(raw_lines) - 1 and not raw_line.endswith("\n"):
            continue
        escalate("unreadable")
        continue
    if not isinstance(record, dict):
        escalate("unreadable")
        continue
    record_type = record.get("type")
    if record_type in KEEP_TYPES:
        kept_lines.append(raw_line if raw_line.endswith("\n") else raw_line + "\n")
    if record.get("isSidechain") is True:
        escalate("subagent")
    if record_type == "system":
        flush_resume()
        if record.get("subtype") == "model_refusal_fallback":
            escalate("substituted")
        content = record.get("content")
        if content:
            blocks.append(("### Claude Code notice", indent(content)))
        last_text_message = None
        cut_message = None
        continue
    message = record.get("message")
    if not isinstance(message, dict):
        continue
    content = message.get("content")
    if record_type == "user":
        if (record.get("isMeta") and cut_message is not None and
                resume_notice is None and
                plain_text(content).startswith(RESUME_PROMPT)):
            resume_notice = plain_text(content)
            continue
        flush_resume()
        heading = "### Claude Code notice" if record.get("isMeta") else "### User"
        if isinstance(content, str):
            blocks.append((heading, indent(content)))
        elif isinstance(content, list):
            for item in content:
                if not isinstance(item, dict):
                    continue
                if item.get("type") == "tool_result":
                    blocks.append((
                        "### Tool result",
                        indent(bounded(tool_result_text(item.get("content")))),
                    ))
                elif item.get("type") == "text":
                    blocks.append((heading, indent(item.get("text", ""))))
        last_text_message = None
        cut_message = None
    elif record_type == "assistant":
        used_model = message.get("model")
        if used_model not in (model, "<synthetic>"):
            escalate("substituted")
        if record.get("advisorModel"):
            escalate("substituted")
        for effort_key in ("effort", "perTurnEffort"):
            used_effort = record.get(effort_key)
            if used_effort is not None and used_effort != effort:
                escalate("effort-changed")
        message_id = message.get("id")
        if not isinstance(content, list):
            continue
        for item in content:
            if not isinstance(item, dict):
                continue
            kind = item.get("type")
            if kind == "text":
                text = str(item.get("text", ""))
                if (resume_notice is not None and message_id != cut_message
                        and blocks and blocks[-1][0] == "### Claude"):
                    previous = blocks[-1][1]
                    separator = joint(previous, text)
                    blocks[-1] = ("### Claude", previous + separator + text)
                    if stitch is not None and stitch["block"] == len(blocks) - 1:
                        stitch["joints"].append(separator)
                    else:
                        blocks.insert(len(blocks) - 1, None)
                        stitch = {"block": len(blocks) - 1, "joints": [separator]}
                    blocks[stitch["block"] - 1] = (
                        "### Claude Code notice", stitch_notice(stitch["joints"])
                    )
                    resume_notice = None
                elif (last_text_message is not None and
                        last_text_message == message_id and blocks and
                        blocks[-1][0] == "### Claude"):
                    joined = blocks[-1][1]
                    if not joined.endswith("\n"):
                        joined += "\n"
                    blocks[-1] = ("### Claude", joined + text)
                else:
                    flush_resume()
                    blocks.append(("### Claude", text))
                last_text_message = message_id
                cut_message = (
                    message_id if message.get("stop_reason") == "max_tokens"
                    else None
                )
            elif kind == "tool_use":
                flush_resume()
                tool_input = json.dumps(
                    item.get("input", {}), ensure_ascii=False, sort_keys=True
                )
                blocks.append((
                    f"### Tool call: {item.get('name', 'unknown')}",
                    indent(tool_input),
                ))
                last_text_message = None
                cut_message = None
flush_resume()

with open(transcript_path, "w", encoding="utf-8") as stream:
    for heading, body in blocks:
        stream.write(f"{heading}\n\n{body}\n\n")
with open(filtered_path, "w", encoding="utf-8") as stream:
    stream.writelines(kept_lines)
print(status)
PY
}

# Select the latest assistant reply from a rendered, sanitized transcript.
# Main mode keeps the historical last-heading-through-EOF behavior so report
# subheadings survive; repair mode stops at the next transcript frame.
claude_extract_latest_assistant_reply() {
    local transcript="$1"
    local mode="${2:-main}"
    local strict=0

    case "${mode}" in
        main) ;;
        repair) strict=1 ;;
        *)
            rhyolite_harness_set_error \
                'Unsupported Claude Code reply extraction mode.'
            return 1
            ;;
    esac
    awk -v strict="${strict}" '
        function frame(value) {
            return value == "### User" ||
                value == "### Claude" ||
                value == "### Tool result" ||
                value == "### Claude Code notice" ||
                value ~ /^### Tool call: [^[:space:]]+$/
        }
        { lines[NR] = $0 }
        END {
            start = 0
            for (i = 1; i <= NR; i++) {
                if (lines[i] == "### Claude") {
                    start = i + 1
                }
            }
            if (start == 0) {
                exit 42
            }
            end = NR
            for (i = start; strict && i <= NR; i++) {
                if (frame(lines[i])) {
                    end = i - 1
                    break
                }
            }
            while (start <= end && lines[start] ~ /^[[:space:]]*$/) {
                start++
            }
            for (i = start; i <= end; i++) {
                print lines[i]
            }
        }
    ' "${transcript}"
}

claude_write_pure_report_repair_descriptor() {
    local source_path="$1"
    local destination_path="$2"

    awk '
        /^[[:space:]]*$/ {
            next
        }
        {
            count++
            if (count == 1) {
                candidate = $0
                sub(/^[[:space:]]+/, "", candidate)
                sub(/[[:space:]]+$/, "", candidate)
            }
        }
        END {
            if (count != 1 ||
                candidate !~ /^\{.*\}$/ ||
                index(candidate, "\"ProtocolVersion\"") == 0 ||
                index(candidate, "\"Section\"") == 0 ||
                index(candidate, "\"Field\"") == 0 ||
                index(candidate, "\"Confidence:\"") == 0 ||
                index(candidate, "\"Occurrence\"") == 0 ||
                index(candidate, "\"OriginalValueSha256\"") == 0 ||
                index(candidate, "\"ConservativeLevel\"") == 0) {
                exit 1
            }
            print candidate
        }
    ' "${source_path}" > "${destination_path}"
}

# Read the sanitized print-mode JSON envelope and write only its result text.
# The envelope must report success and usage by the approved model alone.
claude_write_report_repair_envelope_result() {
    local envelope_path="$1"
    local destination_path="$2"
    local approved_model="$3"

    python3 -I - "${envelope_path}" "${approved_model}" \
        > "${destination_path}" <<'PY'
import json
import sys

path, model = sys.argv[1:3]
try:
    with open(path, encoding="utf-8") as stream:
        text = stream.read()
    envelope = json.loads(text)
except (OSError, ValueError, UnicodeError):
    raise SystemExit(1)
if not isinstance(envelope, dict):
    raise SystemExit(1)
if envelope.get("type") != "result" or envelope.get("is_error") is not False:
    raise SystemExit(1)
if envelope.get("subtype") != "success":
    raise SystemExit(1)
usage = envelope.get("modelUsage")
if not isinstance(usage, dict) or set(usage) != {model}:
    raise SystemExit(1)
result = envelope.get("result")
if not isinstance(result, str):
    raise SystemExit(1)
sys.stdout.write(result.strip() + "\n")
PY
}

harness_id() {
    printf '%s\n' 'claude'
}

harness_display_name() {
    printf '%s\n' 'Claude Code'
}

harness_cli_name() {
    printf '%s\n' 'claude'
}

harness_require_cli() {
    if ! command -v claude >/dev/null 2>&1; then
        rhyolite_harness_set_error 'claude is required.'
        return 1
    fi
}

harness_capability() {
    case "$1" in
        shell_denial|structured_questions|web_research|builtin_research_specialist)
            printf '%s\n' 'yes'
            ;;
        fleet|subagents|builtin_security_specialist|final_message_file)
            printf '%s\n' 'no'
            ;;
        *)
            printf '%s\n' 'unverified'
            ;;
    esac
}

harness_default_model() {
    printf '%s\n' 'claude-opus-5-5'
}

harness_list_models() {
    claude_model_catalog
}

harness_validate_model_id() {
    local requested_model="$1"
    local available_model

    claude_valid_safe_identifier "${requested_model}" || {
        rhyolite_harness_set_error \
            'The model identifier contains unsupported characters.'
        return 1
    }
    # Claude Code aliases select whichever model the alias currently maps to,
    # so they are never exact model IDs.
    case "${requested_model,,}" in
        opus|sonnet|haiku|fable|default|auto|best|opusplan)
            rhyolite_harness_set_error \
                "Model '${requested_model}' is a Claude Code alias that selects a model automatically; select an exact model ID."
            return 1
            ;;
    esac
    while IFS= read -r available_model; do
        [[ "${available_model}" == "${requested_model}" ]] && return 0
    done < <(claude_model_catalog)
    if [[ "${requested_model}" =~ ^claude-[a-z0-9][a-z0-9.-]*$ ]]; then
        # Claude Code print mode rejects an unavailable explicit model with
        # exit status 1 and never substitutes without --fallback-model.
        rhyolite_harness_set_error \
            "Model '${requested_model}' is not in Rhyolite's offline Claude Code model catalog."
        return "${RHYOLITE_HARNESS_MODEL_UNLISTED_STATUS:-1}"
    fi
    rhyolite_harness_set_error \
        "Model '${requested_model}' is not a Claude model identifier."
    return 1
}

harness_model_choices() {
    printf '%s\n' \
        'Claude Opus 5.5 (Recommended) - claude-opus-5-5' \
        'Claude Opus 5 - claude-opus-5' \
        'List available model IDs'
}

harness_max_reasoning_effort() {
    claude_valid_safe_identifier "$1" || return 1
    printf '%s\n' 'max'
}

harness_reasoning_effort_choices() {
    printf '%s\n' \
        'Maximum reasoning (Recommended) - max' \
        'Extra-high reasoning - xhigh' \
        'High reasoning - high'
}

harness_validate_reasoning_effort() {
    case "$1" in
        high|xhigh|max) return 0 ;;
        *)
            rhyolite_harness_set_error \
                'Reasoning effort must be high, xhigh, or max.'
            return 1
            ;;
    esac
}

harness_default_context_tier() {
    printf '%s\n' 'long_context'
}

# Every catalog model runs with its native 1M-token context window, so the
# tier is approval-bound plan data and adds no Claude Code argument.
harness_context_choices() {
    printf '%s\n' \
        'Long context (Recommended) - long_context'
}

harness_validate_context_tier() {
    case "$1" in
        default|long_context) return 0 ;;
        *)
            rhyolite_harness_set_error \
                'Context tier must be default or long_context.'
            return 1
            ;;
    esac
}

harness_auth_secret_env_vars() {
    claude_forwarded_env_var_names
}

harness_login_remediation() {
    printf '%s' \
        'Review the sanitized errors and timeline. If they show Claude Code authentication failure, run claude auth login from a clean non-Git directory, or export CLAUDE_CODE_OAUTH_TOKEN from claude setup-token or ANTHROPIC_API_KEY, then retry.'
}

harness_provider_summary() {
    local variable_name
    local separator=''

    printf '%s' \
        '{"Id":"anthropic-claude-code","Host":"managed-provider","ForwardedEnvVarNames":['
    while IFS= read -r variable_name; do
        printf '%s"%s"' "${separator}" "${variable_name}"
        separator=','
    done < <(claude_forwarded_env_var_names)
    printf ']}\n'
}

harness_resume_policy() {
    printf '%s\n' \
        'Continue only through the trusted Rhyolite repo-review runner; do not invoke claude --resume directly.'
}

harness_prepare_run() {
    local source_config_dir
    local source_credentials
    local variable_name

    if ((CLAUDE_AUTH_BRIDGE_INITIALIZED)); then
        return 0
    fi

    CLAUDE_AUTH_BRIDGE_SOURCE=''
    # Environment or cloud-provider authentication takes precedence over the
    # credentials file in Claude Code, so no file bridge is copied for it.
    for variable_name in \
        ANTHROPIC_API_KEY \
        ANTHROPIC_AUTH_TOKEN \
        CLAUDE_CODE_OAUTH_TOKEN \
        CLAUDE_CODE_USE_BEDROCK \
        CLAUDE_CODE_USE_VERTEX \
        CLAUDE_CODE_USE_FOUNDRY; do
        if [[ -n "${!variable_name-}" ]]; then
            CLAUDE_AUTH_BRIDGE_INITIALIZED=1
            printf '%s\n' \
                'Claude Code authentication will be verified by the first isolated review session using the current environment or configured provider.'
            return 0
        fi
    done

    source_config_dir="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
    source_credentials="${source_config_dir%/}/.credentials.json"
    if [[ "${source_credentials}" == /* &&
        -f "${source_credentials}" &&
        ! -L "${source_credentials}" &&
        -r "${source_credentials}" ]]; then
        CLAUDE_AUTH_BRIDGE_SOURCE="${source_credentials}"
    fi
    CLAUDE_AUTH_BRIDGE_INITIALIZED=1
    printf '%s\n' \
        'Claude Code authentication will be verified by the first isolated review session using the current environment, configured provider, or an ephemeral copy of the local Claude Code login.'
}

harness_prepare_worker_home() {
    local runtime_home="$1"
    local reasoning_effort="$2"
    local context_tier="$3"
    local phase="${4:-review}"

    case "${phase}" in
        review|report-repair|research) ;;
        *)
            rhyolite_harness_set_error \
                'The Claude Code runtime-home phase is unsupported.'
            return 1
            ;;
    esac
    harness_validate_reasoning_effort "${reasoning_effort}" || return 1
    harness_validate_context_tier "${context_tier}" || return 1
    [[ "${runtime_home}" == /* && -d "${runtime_home}" &&
        ! -L "${runtime_home}" ]] || {
        rhyolite_harness_set_error \
            'The temporary Claude Code runtime home is unavailable.'
        return 1
    }

    CLAUDE_RUNTIME_HOME="${runtime_home}"
    CLAUDE_HOME_PHASE="${phase}"
    chmod 700 -- "${runtime_home}" || {
        rhyolite_harness_set_error \
            'Could not restrict the temporary Claude Code runtime home.'
        return 1
    }
    if ! claude_write_settings \
        "${runtime_home}/settings.json" \
        "${phase}" \
        "${reasoning_effort}"; then
        rhyolite_harness_set_error \
            'Could not write temporary Claude Code settings.'
        return 1
    fi
    chmod 600 -- "${runtime_home}/settings.json" || {
        rhyolite_harness_set_error \
            'Could not restrict temporary Claude Code settings.'
        return 1
    }

    if [[ -n "${CLAUDE_AUTH_BRIDGE_SOURCE}" ]]; then
        if [[ ! -f "${CLAUDE_AUTH_BRIDGE_SOURCE}" ||
            -L "${CLAUDE_AUTH_BRIDGE_SOURCE}" ]] ||
            ! cp -- "${CLAUDE_AUTH_BRIDGE_SOURCE}" \
                "${runtime_home}/.credentials.json" 2>/dev/null; then
            rm -f -- "${runtime_home}/.credentials.json"
            rhyolite_harness_set_error \
                'Could not copy the temporary Claude Code authentication bridge.'
            return 1
        fi
        chmod 600 -- "${runtime_home}/.credentials.json" || {
            rm -f -- "${runtime_home}/.credentials.json"
            rhyolite_harness_set_error \
                'Could not restrict the temporary Claude Code authentication bridge.'
            return 1
        }
    fi
}

harness_worker_argv() {
    local destination_name="$1"
    local session_root="$2"
    local plugin_root="$3"
    local session_name="$4"
    local session_id="$5"
    local model="$6"
    local reasoning_effort="$7"
    local context_tier="$8"
    local authentication_variables="$9"
    local available_tools="${10}"
    local transcript_path="${11}"
    local enable_public_research="${12}"
    local settings_json

    claude_require_array_destination "${destination_name}" || return 1
    [[ "${session_root}" == /* && -d "${session_root}" &&
        ! -L "${session_root}" ]] || {
        rhyolite_harness_set_error \
            'The Claude Code session root is unavailable.'
        return 1
    }
    [[ "${plugin_root}" == /* &&
        -f "${plugin_root}/.claude-plugin/plugin.json" &&
        -f "${plugin_root}/claude/agents/repo-review-worker.md" &&
        -f "${plugin_root}/skills/readonly-repository-review/SKILL.md" ]] || {
        rhyolite_harness_set_error \
            'The Claude Code plugin worker assets are unavailable.'
        return 1
    }
    claude_valid_safe_identifier "${session_name}" || {
        rhyolite_harness_set_error \
            'The Claude Code session name is invalid.'
        return 1
    }
    claude_valid_session_id "${session_id}" || {
        rhyolite_harness_set_error \
            'The Claude Code session identifier is invalid.'
        return 1
    }
    claude_valid_safe_identifier "${model}" || {
        rhyolite_harness_set_error \
            'The Claude Code model identifier is invalid.'
        return 1
    }
    harness_validate_reasoning_effort "${reasoning_effort}" || return 1
    harness_validate_context_tier "${context_tier}" || return 1
    claude_validate_protected_auth_csv \
        "${authentication_variables}" || return 1
    [[ "${transcript_path}" == /* ]] || {
        rhyolite_harness_set_error \
            'The Claude Code transcript path is invalid.'
        return 1
    }
    # Claude Code tool names are adapter-owned, and public research is a
    # separate dedicated-worker phase, so neither runner value is forwarded.
    : "${available_tools}" "${enable_public_research}"
    settings_json="$(claude_settings_json review "${reasoning_effort}")" || {
        rhyolite_harness_set_error \
            'Could not build Claude Code worker settings.'
        return 1
    }

    CLAUDE_SESSION_ROOT="${session_root}"
    CLAUDE_SESSION_ID="${session_id}"
    CLAUDE_TRANSCRIPT_PATH="${transcript_path}"
    CLAUDE_APPROVED_MODEL="${model}"
    CLAUDE_APPROVED_EFFORT="${reasoning_effort}"
    CLAUDE_TRANSCRIPT_STATUS=''
    local -n claude_output_arguments_ref="${destination_name}"
    claude_output_arguments_ref=(
        -p
        --model "${model}"
        --effort "${reasoning_effort}"
        --session-id "${session_id}"
        --name "${session_name}"
        --output-format text
        --permission-mode dontAsk
        --permission-prompts none
        --restricted
        --settings "${settings_json}"
        --strict-mcp-config
        --tools Read,Glob,Grep
        --disallowedTools "$(claude_denied_review_tools)"
        --disable-slash-commands
        --plugin-dir "${plugin_root}"
        --agent rhyolite:repo-review-worker
        --append-system-prompt-file
        "${plugin_root}/skills/readonly-repository-review/SKILL.md"
    )
}

harness_worker_env() {
    claude_populate_worker_environment \
        "$1" "${CLAUDE_SESSION_ROOT}" "${CLAUDE_RUNTIME_HOME}"
}

harness_report_repair_argv() {
    local destination_name="$1"
    local trusted_workdir="$2"
    local session_name="$3"
    local session_id="$4"
    local model="$5"
    local reasoning_effort="$6"
    local context_tier="$7"
    local authentication_variables="$8"
    local transcript_path="$9"
    local first_workdir_entry
    local settings_json

    claude_require_array_destination "${destination_name}" || return 1
    [[ "${trusted_workdir}" == /* && -d "${trusted_workdir}" &&
        ! -L "${trusted_workdir}" ]] || {
        rhyolite_harness_set_error \
            'The Claude Code report-repair working directory is unavailable.'
        return 1
    }
    if ! first_workdir_entry="$(
        find "${trusted_workdir}" -mindepth 1 -print -quit 2>/dev/null
    )"; then
        rhyolite_harness_set_error \
            'The Claude Code report-repair working directory could not be verified.'
        return 1
    fi
    [[ -z "${first_workdir_entry}" ]] || {
        rhyolite_harness_set_error \
            'The Claude Code report-repair working directory is not empty.'
        return 1
    }
    claude_valid_safe_identifier "${session_name}" || {
        rhyolite_harness_set_error \
            'The Claude Code report-repair session name is invalid.'
        return 1
    }
    claude_valid_session_id "${session_id}" || {
        rhyolite_harness_set_error \
            'The Claude Code report-repair session identifier is invalid.'
        return 1
    }
    claude_valid_safe_identifier "${model}" || {
        rhyolite_harness_set_error \
            'The Claude Code report-repair model identifier is invalid.'
        return 1
    }
    harness_validate_reasoning_effort "${reasoning_effort}" || return 1
    harness_validate_context_tier "${context_tier}" || return 1
    claude_validate_protected_auth_csv \
        "${authentication_variables}" || return 1
    [[ "${transcript_path}" == /* ]] || {
        rhyolite_harness_set_error \
            'The Claude Code report-repair transcript path is invalid.'
        return 1
    }
    settings_json="$(
        claude_settings_json report-repair "${reasoning_effort}"
    )" || {
        rhyolite_harness_set_error \
            'Could not build Claude Code report-repair settings.'
        return 1
    }

    CLAUDE_REPAIR_WORKDIR="${trusted_workdir}"
    CLAUDE_REPAIR_MODEL="${model}"
    local -n claude_output_arguments_ref="${destination_name}"
    claude_output_arguments_ref=(
        -p
        --model "${model}"
        --effort "${reasoning_effort}"
        --session-id "${session_id}"
        --name "${session_name}"
        --output-format json
        --permission-mode dontAsk
        --permission-prompts none
        --restricted
        --settings "${settings_json}"
        --strict-mcp-config
        --tools ''
        --disallowedTools "$(claude_denied_repair_tools)"
        --disable-slash-commands
        --no-session-persistence
    )
}

harness_report_repair_env() {
    local destination_name="$1"
    local runtime_home="$2"

    claude_require_array_destination "${destination_name}" || return 1
    [[ -d "${runtime_home}" && ! -L "${runtime_home}" ]] || {
        rhyolite_harness_set_error \
            'The Claude Code report-repair runtime home is unavailable.'
        return 1
    }
    [[ -n "${CLAUDE_REPAIR_WORKDIR}" ]] || {
        rhyolite_harness_set_error \
            'The Claude Code report-repair working directory was not prepared.'
        return 1
    }
    claude_populate_worker_environment \
        "${destination_name}" "${CLAUDE_REPAIR_WORKDIR}" "${runtime_home}"
}

claude_json_string() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '"%s"' "${value}"
}

# Claude Code names an MCP tool mcp__<server>__<tool>; the research worker may
# call only the five broker tools of the one strict local server.
claude_research_allowed_tools() {
    local broker_tools="$1"
    local tool_name
    local separator=''

    while IFS= read -r tool_name; do
        printf '%smcp__rhyolite-research__%s' "${separator}" "${tool_name}"
        separator=','
    done < <(printf '%s\n' "${broker_tools//,/$'\n'}")
}

harness_write_research_mcp_config() {
    local config_path="$1"
    local broker_launcher="$2"
    local arguments_name="$3"
    local tools_json="$4"
    local argument
    local separator=''

    claude_require_array_destination "${arguments_name}" || return 1
    local -n claude_research_broker_arguments_ref="${arguments_name}"
    [[ "${config_path}" == /* && "${broker_launcher}" == /* ]] || {
        rhyolite_harness_set_error \
            'The Claude Code research MCP configuration paths are invalid.'
        return 1
    }
    [[ "${tools_json}" =~ ^\[\ *\"[a-z_]+\"(\ *,\ *\"[a-z_]+\")*\ *\]$ ]] || {
        rhyolite_harness_set_error \
            'The Claude Code research broker tool list is invalid.'
        return 1
    }
    if ! {
        printf '{\n  "mcpServers": {\n    "rhyolite-research": {\n'
        printf '      "type": "stdio",\n'
        printf '      "command": %s,\n' "$(claude_json_string "${broker_launcher}")"
        printf '      "args": [\n'
        for argument in "${claude_research_broker_arguments_ref[@]}"; do
            printf '%s        %s' "${separator}" "$(claude_json_string "${argument}")"
            separator=$',\n'
        done
        printf '\n      ]\n'
        printf '    }\n  }\n}\n'
    } > "${config_path}" || ! chmod 600 -- "${config_path}"; then
        rhyolite_harness_set_error \
            'Could not write the Claude Code research MCP configuration.'
        return 1
    fi
}

harness_research_worker_argv() {
    local destination_name="$1"
    local session_root="$2"
    local plugin_root="$3"
    local session_name="$4"
    local session_id="$5"
    local model="$6"
    local reasoning_effort="$7"
    local context_tier="$8"
    local authentication_variables="$9"
    local mcp_config_path="${10}"
    local broker_tools="${11}"
    local transcript_path="${12}"
    local settings_json

    claude_require_array_destination "${destination_name}" || return 1
    [[ "${session_root}" == /* && -d "${session_root}" &&
        ! -L "${session_root}" ]] || {
        rhyolite_harness_set_error \
            'The Claude Code research session root is unavailable.'
        return 1
    }
    [[ "${plugin_root}" == /* &&
        -f "${plugin_root}/.claude-plugin/plugin.json" &&
        -f "${plugin_root}/claude/agents/repo-research-worker.md" &&
        -f "${plugin_root}/skills/research-source-assessment/SKILL.md" ]] || {
        rhyolite_harness_set_error \
            'The Claude Code research worker assets are unavailable.'
        return 1
    }
    claude_valid_safe_identifier "${session_name}" || {
        rhyolite_harness_set_error \
            'The Claude Code research session name is invalid.'
        return 1
    }
    claude_valid_session_id "${session_id}" || {
        rhyolite_harness_set_error \
            'The Claude Code research session identifier is invalid.'
        return 1
    }
    claude_valid_safe_identifier "${model}" || {
        rhyolite_harness_set_error \
            'The Claude Code research model identifier is invalid.'
        return 1
    }
    harness_validate_reasoning_effort "${reasoning_effort}" || return 1
    harness_validate_context_tier "${context_tier}" || return 1
    claude_validate_protected_auth_csv \
        "${authentication_variables}" || return 1
    [[ "${broker_tools}" =~ ^[a-z_]+(,[a-z_]+)*$ ]] || {
        rhyolite_harness_set_error \
            'The Claude Code research broker tool list is invalid.'
        return 1
    }
    [[ "${mcp_config_path}" == /* && -f "${mcp_config_path}" &&
        ! -L "${mcp_config_path}" && "${transcript_path}" == /* ]] || {
        rhyolite_harness_set_error \
            'The Claude Code research worker paths are invalid.'
        return 1
    }
    settings_json="$(claude_settings_json research "${reasoning_effort}")" || {
        rhyolite_harness_set_error \
            'Could not build Claude Code research settings.'
        return 1
    }

    CLAUDE_RESEARCH_SESSION_ROOT="${session_root}"
    CLAUDE_RESEARCH_SESSION_ID="${session_id}"
    CLAUDE_RESEARCH_TRANSCRIPT_PATH="${transcript_path}"
    CLAUDE_RESEARCH_MODEL="${model}"
    CLAUDE_RESEARCH_EFFORT="${reasoning_effort}"
    local -n claude_output_arguments_ref="${destination_name}"
    claude_output_arguments_ref=(
        -p
        --model "${model}"
        --effort "${reasoning_effort}"
        --session-id "${session_id}"
        --name "${session_name}"
        --output-format text
        --permission-mode dontAsk
        --permission-prompts none
        --restricted
        --settings "${settings_json}"
        --mcp-config "${mcp_config_path}"
        --strict-mcp-config
        --tools Read,Glob,Grep
        --allowedTools "$(claude_research_allowed_tools "${broker_tools}")"
        --disallowedTools "$(claude_denied_review_tools)"
        --disable-slash-commands
        --plugin-dir "${plugin_root}"
        --agent rhyolite:repo-research-worker
        --append-system-prompt-file
        "${plugin_root}/skills/research-source-assessment/SKILL.md"
    )
}

harness_research_worker_env() {
    local destination_name="$1"

    [[ "${CLAUDE_HOME_PHASE}" == research ]] || {
        rhyolite_harness_set_error \
            'The Claude Code research runtime home was not prepared.'
        return 1
    }
    claude_populate_worker_environment \
        "${destination_name}" \
        "${CLAUDE_RESEARCH_SESSION_ROOT}" \
        "${CLAUDE_RUNTIME_HOME}" || return 1
    local -n claude_output_environment_ref="${destination_name}"
    claude_output_environment_ref+=(MCP_TOOL_TIMEOUT=120000)
}

# Export the research session as a rendered transcript before the runtime
# home is removed, and fail the phase when its record shows another model,
# another effort, or a subagent, or when a dossier arrives without a record.
harness_finalize_research_session() {
    local runtime_home="$1"
    local raw_output="$2"
    local session_jsonl=''
    local candidate
    local candidate_count=0
    local status
    local discarded_path="${runtime_home}/rhyolite-research-filtered.jsonl"

    if claude_valid_session_id "${CLAUDE_RESEARCH_SESSION_ID}" &&
        [[ -d "${runtime_home}/projects" && ! -L "${runtime_home}/projects" ]]; then
        while IFS= read -r -d '' candidate; do
            session_jsonl="${candidate}"
            candidate_count=$((candidate_count + 1))
        done < <(
            find "${runtime_home}/projects" -mindepth 2 -maxdepth 2 \
                -type f -name "${CLAUDE_RESEARCH_SESSION_ID}.jsonl" -print0
        )
    fi
    if ((candidate_count == 0)); then
        if [[ -f "${raw_output}" ]] &&
            grep -Fq 'REPOSITORY RESEARCH DOSSIER' "${raw_output}"; then
            rhyolite_harness_set_error \
                'Claude Code returned a research dossier without its session transcript, so the approved model and effort could not be verified.'
            return 1
        fi
        return 0
    fi
    if ((candidate_count != 1)); then
        rhyolite_harness_set_error \
            'Claude Code wrote more than one transcript for the research session.'
        return 1
    fi
    if ! status="$(
        claude_render_session_transcript \
            "${session_jsonl}" \
            "${CLAUDE_RESEARCH_TRANSCRIPT_PATH}" \
            "${discarded_path}" \
            "${CLAUDE_RESEARCH_MODEL}" \
            "${CLAUDE_RESEARCH_EFFORT}" 2>/dev/null
    )"; then
        rm -f -- "${discarded_path}"
        rhyolite_harness_set_error \
            'Could not read the Claude Code research session transcript.'
        return 1
    fi
    rm -f -- "${discarded_path}"
    chmod 600 -- "${CLAUDE_RESEARCH_TRANSCRIPT_PATH}" 2>/dev/null || true
    case "${status}" in
        verified)
            return 0
            ;;
        substituted)
            rhyolite_harness_set_error \
                'Claude Code answered the research phase with a model other than the approved model; Rhyolite does not accept substituted research.'
            ;;
        effort-changed)
            rhyolite_harness_set_error \
                'Claude Code recorded a research reasoning effort other than the approved effort.'
            ;;
        subagent)
            rhyolite_harness_set_error \
                'Claude Code recorded a subagent turn in the research phase although subagents are disabled.'
            ;;
        *)
            rhyolite_harness_set_error \
                'The Claude Code research session transcript was unreadable.'
            ;;
    esac
    return 1
}

harness_render_request() {
    local template_path="$1"
    local request_path="$2"
    local repository="$3"
    local review_path="$4"
    local commit="$5"
    local review_date="$6"
    local prior_art_start_date="$7"
    local enable_provenance_research="$8"
    local provenance_lookback_months="$9"
    local provenance_start_date="${10}"
    local scope_name="${11}"
    local output_directory="${12}"
    local repository_metadata="${13}"
    local public_research_instructions="${14}"
    local provenance_instructions="${15}"
    local research_dossier_path="${16}"
    local research_network_summary_path="${17}"
    local research_transport_instructions="${18}"
    local template_line

    while IFS= read -r template_line || [[ -n "${template_line}" ]]; do
        case "${template_line}" in
            'Repository URL: {{REPOSITORY_URL}}')
                printf 'Repository URL: %s\n' "${repository}"
                ;;
            'Read-only source snapshot: {{REPOSITORY_PATH}}')
                printf 'Read-only source snapshot: %s\n' "${review_path}"
                ;;
            'Exact commit to review: {{COMMIT}}')
                printf 'Exact commit to review: %s\n' "${commit}"
                ;;
            'Review date: {{REVIEW_DATE}}')
                printf 'Review date: %s\n' "${review_date}"
                ;;
            'Recent-prior-art window: {{PRIOR_ART_START_DATE}} through {{REVIEW_DATE}}')
                printf 'Recent-prior-art window: %s through %s\n' \
                    "${prior_art_start_date}" "${review_date}"
                ;;
            'Provenance lookback months: {{PROVENANCE_LOOKBACK_MONTHS}}')
                if ((enable_provenance_research)); then
                    printf 'Provenance lookback months: %s\n' \
                        "${provenance_lookback_months}"
                else
                    printf 'Provenance lookback months: disabled\n'
                fi
                ;;
            'Provenance start date: {{PROVENANCE_START_DATE}}')
                if ((enable_provenance_research)); then
                    printf 'Provenance start date: %s\n' \
                        "${provenance_start_date}"
                else
                    printf 'Provenance start date: disabled\n'
                fi
                ;;
            'Selected scope: {{SCOPE_NAME}}')
                printf 'Selected scope: %s\n' "${scope_name}"
                ;;
            'Trusted wrapper artifact directory: {{OUTPUT_DIRECTORY}}')
                printf 'Trusted wrapper artifact directory: %s\n' \
                    "${output_directory}"
                ;;
            '{{REPOSITORY_METADATA}}')
                printf '%s\n' "${repository_metadata}"
                ;;
            '{{PUBLIC_RESEARCH_INSTRUCTIONS}}')
                printf '%s\n' "${public_research_instructions}"
                ;;
            '{{PROVENANCE_INSTRUCTIONS}}')
                printf '%s\n' "${provenance_instructions}"
                ;;
            '{{RESEARCH_DOSSIER_PATH}}')
                printf '%s\n' "${research_dossier_path}"
                ;;
            '{{RESEARCH_NETWORK_SUMMARY_PATH}}')
                printf '%s\n' "${research_network_summary_path}"
                ;;
            '{{RESEARCH_TRANSPORT_INSTRUCTIONS}}')
                printf '%s\n' "${research_transport_instructions}"
                ;;
            *)
                printf '%s\n' "${template_line}"
                ;;
        esac
    done < "${template_path}" > "${request_path}"
}

harness_extract_final_report() {
    local timeline="$1"
    local transcript="$2"
    local final_message="$3"
    local report="$4"
    local extraction_status=0

    : "${timeline}"
    if ! claude_extract_latest_assistant_reply \
        "${transcript}" > "${final_message}"; then
        rm -f -- "${final_message}"
        return 42
    fi

    extract_report "${final_message}" "${report}" || extraction_status=$?
    rm -f -- "${final_message}"
    return "${extraction_status}"
}

harness_extract_report_repair() {
    local timeline="$1"
    local transcript="$2"
    local reply_output="$3"
    local envelope_result="${reply_output}.envelope.$$"
    local assistant_candidate="${reply_output}.assistant.$$"

    rm -f -- "${reply_output}" "${envelope_result}" "${assistant_candidate}"
    if [[ -f "${timeline}" && -n "${CLAUDE_REPAIR_MODEL}" ]] &&
        claude_write_report_repair_envelope_result \
            "${timeline}" "${envelope_result}" "${CLAUDE_REPAIR_MODEL}" &&
        claude_write_pure_report_repair_descriptor \
            "${envelope_result}" "${reply_output}"; then
        rm -f -- "${envelope_result}"
        return 0
    fi
    rm -f -- "${reply_output}" "${envelope_result}"

    if [[ -f "${transcript}" ]] &&
        claude_extract_latest_assistant_reply \
            "${transcript}" repair > "${assistant_candidate}"; then
        if claude_write_pure_report_repair_descriptor \
            "${assistant_candidate}" "${reply_output}"; then
            rm -f -- "${assistant_candidate}"
            return 0
        fi
    fi
    rm -f -- "${reply_output}" "${assistant_candidate}"
    rhyolite_harness_set_error \
        'Claude Code report repair did not return a supported confidence-edit descriptor from the approved model.'
    return 42
}

harness_verify_isolation() {
    local timeline="$1"

    if [[ -n "${CLAUDE_RUNTIME_HOME}" && -e "${CLAUDE_RUNTIME_HOME}" ]] &&
        [[ -e "${CLAUDE_RUNTIME_HOME}/source" ||
            -e "${CLAUDE_RUNTIME_HOME}/.git" ]]; then
        rhyolite_harness_set_error \
            'The Claude Code runtime home contained source or Git data.'
        return 1
    fi
    if [[ -n "${CLAUDE_RUNTIME_HOME}" && -f "${timeline}" ]] &&
        grep -Fq -- "${CLAUDE_RUNTIME_HOME}" "${timeline}"; then
        rhyolite_harness_set_error \
            'Claude Code output disclosed its temporary runtime home.'
        return 1
    fi
    [[ "${CLAUDE_HOME_PHASE}" == review ]] || return 0
    case "${CLAUDE_TRANSCRIPT_STATUS}" in
        verified)
            return 0
            ;;
        missing)
            # Without a session record there is nothing to verify only when
            # no report was produced; the runner then reports the real
            # worker failure. A report without its record fails closed.
            if [[ -f "${timeline}" ]] &&
                grep -Eiq 'REPOSITORY.*REVIEW.*REPORT' "${timeline}"; then
                rhyolite_harness_set_error \
                    'Claude Code returned a report without its session transcript, so the approved model and effort could not be verified.'
                return 1
            fi
            return 0
            ;;
        substituted)
            rhyolite_harness_set_error \
                'Claude Code answered with a model other than the approved model; Rhyolite does not accept a substituted review.'
            ;;
        effort-changed)
            rhyolite_harness_set_error \
                'Claude Code recorded a reasoning effort other than the approved effort; Rhyolite does not accept a downgraded review.'
            ;;
        subagent)
            rhyolite_harness_set_error \
                'Claude Code recorded a subagent turn although subagents are disabled for the review worker.'
            ;;
        *)
            rhyolite_harness_set_error \
                'The Claude Code session transcript was unreadable, so the approved model and effort could not be verified.'
            ;;
    esac
    return 1
}

harness_persist_agent_state() {
    local runtime_home="$1"
    local agent_state_directory="$2"
    local reasoning_effort="$3"
    local context_tier="$4"
    local claude_home_path="${agent_state_directory}/claude-home"
    local session_jsonl=''
    local candidate
    local candidate_count=0
    local project_name
    local persisted_project
    local filtered_path
    local rendered_path

    : "${context_tier}"
    CLAUDE_TRANSCRIPT_STATUS='missing'
    mkdir -p -- "${claude_home_path}" || {
        rhyolite_harness_set_error \
            'Could not create the persisted Claude Code state directory.'
        return 1
    }
    chmod 700 -- "${claude_home_path}" || {
        rhyolite_harness_set_error \
            'Could not restrict the persisted Claude Code state directory.'
        return 1
    }
    if ! claude_write_settings \
        "${claude_home_path}/settings.json" review "${reasoning_effort}"; then
        rhyolite_harness_set_error \
            'Could not write persisted Claude Code settings.'
        return 1
    fi
    chmod 600 -- "${claude_home_path}/settings.json" || {
        rhyolite_harness_set_error \
            'Could not restrict persisted Claude Code settings.'
        return 1
    }

    if claude_valid_session_id "${CLAUDE_SESSION_ID}" &&
        [[ -d "${runtime_home}/projects" && ! -L "${runtime_home}/projects" ]]; then
        while IFS= read -r -d '' candidate; do
            session_jsonl="${candidate}"
            candidate_count=$((candidate_count + 1))
        done < <(
            find "${runtime_home}/projects" -mindepth 2 -maxdepth 2 \
                -type f -name "${CLAUDE_SESSION_ID}.jsonl" -print0
        )
    fi
    if ((candidate_count == 0)); then
        return 0
    fi
    if ((candidate_count != 1)); then
        CLAUDE_TRANSCRIPT_STATUS='unreadable'
        rhyolite_harness_set_error \
            'Claude Code wrote more than one transcript for the review session.'
        return 1
    fi
    if ! declare -F sanitize_review_text >/dev/null 2>&1; then
        CLAUDE_TRANSCRIPT_STATUS='unreadable'
        rhyolite_harness_set_error \
            'The runner transcript sanitizer is unavailable.'
        return 1
    fi

    project_name="$(basename -- "$(dirname -- "${session_jsonl}")")"
    [[ "${project_name}" =~ ^[A-Za-z0-9._-]{1,255}$ ]] || {
        CLAUDE_TRANSCRIPT_STATUS='unreadable'
        rhyolite_harness_set_error \
            'Claude Code used an unsupported transcript project directory.'
        return 1
    }
    persisted_project="${claude_home_path}/projects/${project_name}"
    filtered_path="${runtime_home}/rhyolite-filtered-session.jsonl"
    rendered_path="${runtime_home}/rhyolite-rendered-session.md"
    if ! CLAUDE_TRANSCRIPT_STATUS="$(
        claude_render_session_transcript \
            "${session_jsonl}" \
            "${rendered_path}" \
            "${filtered_path}" \
            "${CLAUDE_APPROVED_MODEL}" \
            "${CLAUDE_APPROVED_EFFORT}" 2>/dev/null
    )"; then
        CLAUDE_TRANSCRIPT_STATUS='unreadable'
        rm -f -- "${filtered_path}" "${rendered_path}"
        rhyolite_harness_set_error \
            'Could not read the Claude Code session transcript.'
        return 1
    fi
    case "${CLAUDE_TRANSCRIPT_STATUS}" in
        verified|substituted|effort-changed|subagent|unreadable) ;;
        *) CLAUDE_TRANSCRIPT_STATUS='unreadable' ;;
    esac

    if ! {
        mkdir -p -- "${persisted_project}" &&
        sanitize_review_text < "${filtered_path}" \
            > "${persisted_project}/${CLAUDE_SESSION_ID}.jsonl" &&
        cp -- "${rendered_path}" "${CLAUDE_TRANSCRIPT_PATH}" &&
        chmod 600 -- "${CLAUDE_TRANSCRIPT_PATH}"
    }; then
        rm -f -- "${filtered_path}" "${rendered_path}"
        rhyolite_harness_set_error \
            'Could not persist the allowlisted Claude Code session transcript.'
        return 1
    fi
    rm -f -- "${filtered_path}" "${rendered_path}"
    find "${claude_home_path}" -type d -exec chmod 700 -- {} + || {
        rhyolite_harness_set_error \
            'Could not restrict persisted Claude Code state directories.'
        return 1
    }
    find "${claude_home_path}" -type f -exec chmod 600 -- {} + || {
        rhyolite_harness_set_error \
            'Could not restrict persisted Claude Code state files.'
        return 1
    }
}

harness_sanitize_runtime_home() {
    local runtime_home="$1"
    local attempt

    [[ -n "${runtime_home}" && -e "${runtime_home}" ]] || return 0
    if [[ -f "${runtime_home}/.credentials.json" ]]; then
        if ! rm -f -- "${runtime_home}/.credentials.json"; then
            printf '%s\n' '{}' \
                > "${runtime_home}/.credentials.json" 2>/dev/null || true
            chmod 600 -- "${runtime_home}/.credentials.json" 2>/dev/null || true
        fi
    fi

    for attempt in 1 2 3; do
        rm -rf -- "${runtime_home}" 2>/dev/null || true
        [[ ! -e "${runtime_home}" ]] && return 0
        sleep 1
    done
    rhyolite_harness_set_error \
        "Could not remove the temporary Claude Code runtime home after three attempts: ${runtime_home}"
    return 1
}

# Claude Code has no inherited allow-all signal comparable to
# COPILOT_ALLOW_ALL; the child always receives an explicit permission mode.
harness_allow_all_detected() {
    return 1
}
