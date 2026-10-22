#!/usr/bin/env bash

CODEX_PROVIDER_METADATA_LOADED=0
CODEX_PROVIDER_ID=''
CODEX_PROVIDER_SUMMARY_ID=''
CODEX_PROVIDER_HOST=''
CODEX_PROVIDER_BASE_URL=''
CODEX_PROVIDER_ENV_KEY=''
CODEX_SOURCE_CONFIG=''
CODEX_RUNTIME_HOME=''
CODEX_REVIEW_RUNTIME_HOME=''
CODEX_HOME_PHASE=''
CODEX_SESSION_ROOT=''
CODEX_LOGICAL_SESSION_ID=''
CODEX_NATIVE_THREAD_ID=''
CODEX_TRANSCRIPT_PATH=''
CODEX_APPROVED_MODEL=''
CODEX_APPROVED_EFFORT=''
CODEX_CONTEXT_TIER=''
CODEX_TRANSCRIPT_STATUS=''
CODEX_REVIEW_FINAL_MESSAGE=''
CODEX_REPAIR_WORKDIR=''
CODEX_REPAIR_FINAL_MESSAGE=''
CODEX_RESEARCH_SESSION_ROOT=''
CODEX_RESEARCH_LOGICAL_SESSION_ID=''
CODEX_RESEARCH_TRANSCRIPT_PATH=''
CODEX_RESEARCH_MODEL=''
CODEX_RESEARCH_EFFORT=''
CODEX_RESEARCH_CONTEXT_TIER=''
CODEX_RESEARCH_FINAL_MESSAGE=''
CODEX_RESEARCH_CONFIG_PATH=''
CODEX_RESEARCH_BROKER_LAUNCHER=''
CODEX_RESEARCH_TOOLS_JSON=''
declare -a CODEX_RESEARCH_BROKER_ARGUMENTS=()

codex_require_array_destination() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
        rhyolite_harness_set_error \
            'The Codex harness array destination is invalid.'
        return 1
    }
}

codex_valid_safe_identifier() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]
}

codex_valid_session_id() {
    [[ "$1" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

codex_json_string() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '"%s"' "${value}"
}

codex_toml_string() {
    codex_json_string "$1"
}

codex_source_config_path() {
    local source_home="${CODEX_HOME:-${HOME}/.codex}"

    [[ "${source_home}" == /* && -d "${source_home}" &&
        ! -L "${source_home}" ]] || return 1
    printf '%s/config.toml\n' "${source_home%/}"
}

codex_load_provider_metadata() {
    local output=''
    local source_config
    local -a values=()

    ((CODEX_PROVIDER_METADATA_LOADED == 0)) || return 0
    source_config="$(codex_source_config_path)" || {
        rhyolite_harness_set_error \
            'The configured Codex home is unavailable or unsafe.'
        return 1
    }
    [[ -f "${source_config}" && ! -L "${source_config}" &&
        -r "${source_config}" ]] || {
        rhyolite_harness_set_error \
            'The Codex provider configuration is unavailable.'
        return 1
    }
    output="$(
        python3 -I - "${source_config}" <<'PY'
import re
import sys
import tomllib
import urllib.parse

path = sys.argv[1]
try:
    with open(path, "rb") as stream:
        config = tomllib.load(stream)
except (OSError, ValueError):
    raise SystemExit(1)

if not isinstance(config, dict) or config.get("profile"):
    raise SystemExit(1)
provider_id = config.get("model_provider")
providers = config.get("model_providers")
if (
    not isinstance(provider_id, str)
    or not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]{0,63}", provider_id)
    or not isinstance(providers, dict)
    or not isinstance(providers.get(provider_id), dict)
):
    raise SystemExit(1)
provider = providers[provider_id]
allowed = {"name", "base_url", "env_key", "wire_api"}
if set(provider) - allowed:
    raise SystemExit(1)
base_url = provider.get("base_url")
env_key = provider.get("env_key")
wire_api = provider.get("wire_api", "responses")
if (
    not isinstance(base_url, str)
    or not isinstance(env_key, str)
    or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", env_key)
    or wire_api != "responses"
    or any(ord(character) < 32 or ord(character) == 127 for character in base_url)
    or any(character in base_url for character in "\"\\")
):
    raise SystemExit(1)
try:
    parsed = urllib.parse.urlsplit(base_url)
    port = parsed.port or 443
except ValueError:
    raise SystemExit(1)
if (
    parsed.scheme.lower() != "https"
    or not parsed.hostname
    or parsed.username is not None
    or parsed.password is not None
    or parsed.query
    or parsed.fragment
    or port != 443
):
    raise SystemExit(1)
model = config.get("model")
if model is not None and model != "gpt-5.6-sol":
    raise SystemExit(1)
summary_id = "codex-" + provider_id.lower().replace("_", "-")
if not re.fullmatch(r"[a-z][a-z0-9-]{0,70}", summary_id):
    raise SystemExit(1)
for value in (
    provider_id,
    summary_id,
    parsed.hostname.lower(),
    base_url,
    env_key,
):
    print(value)
PY
    )" || {
        rhyolite_harness_set_error \
            'The Codex provider configuration uses an unsupported or unsafe form.'
        return 1
    }
    mapfile -t values <<< "${output}"
    ((${#values[@]} == 5)) || {
        rhyolite_harness_set_error \
            'The Codex provider configuration could not be normalized.'
        return 1
    }
    CODEX_PROVIDER_ID="${values[0]}"
    CODEX_PROVIDER_SUMMARY_ID="${values[1]}"
    CODEX_PROVIDER_HOST="${values[2]}"
    CODEX_PROVIDER_BASE_URL="${values[3]}"
    CODEX_PROVIDER_ENV_KEY="${values[4]}"
    CODEX_SOURCE_CONFIG="${source_config}"
    CODEX_PROVIDER_METADATA_LOADED=1
}

codex_context_window() {
    case "$1" in
        default) printf '%s\n' 272000 ;;
        long_context) printf '%s\n' 872000 ;;
        *) return 1 ;;
    esac
}

codex_usable_context_window() {
    case "$1" in
        default) printf '%s\n' 258400 ;;
        long_context) printf '%s\n' 828400 ;;
        *) return 1 ;;
    esac
}

codex_auto_compact_limit() {
    case "$1" in
        default) printf '%s\n' 244800 ;;
        long_context) printf '%s\n' 784800 ;;
        *) return 1 ;;
    esac
}

codex_write_model_catalog() {
    local destination="$1"

    cat > "${destination}" <<'JSON'
{
  "models": [
    {
      "slug": "gpt-5.6-sol",
      "display_name": "GPT-5.6-Sol",
      "description": "Rhyolite's exact shell-free Codex worker model.",
      "default_reasoning_level": "max",
      "supported_reasoning_levels": [
        {
          "effort": "high",
          "description": "High reasoning without delegation."
        },
        {
          "effort": "xhigh",
          "description": "Extra-high reasoning without delegation."
        },
        {
          "effort": "max",
          "description": "Maximum enforceable reasoning without delegation."
        }
      ],
      "shell_type": "disabled",
      "visibility": "list",
      "supported_in_api": true,
      "priority": 0,
      "model_messages": {
        "instructions_template": "Rhyolite supplies the complete trusted worker instructions through model_instructions_file."
      },
      "support_verbosity": false,
      "apply_patch_tool_type": null,
      "truncation_policy": {
        "mode": "bytes",
        "limit": 10000
      },
      "context_window": 272000,
      "max_context_window": 872000,
      "effective_context_window_percent": 95,
      "experimental_supported_tools": [],
      "input_modalities": [
        "text"
      ],
      "supports_search_tool": false,
      "supports_experimental_context": false,
      "supports_reasoning_effort_updates": false,
      "tool_mode": null,
      "multi_agent_version": null
    }
  ]
}
JSON
    chmod 600 -- "${destination}"
}

codex_write_runtime_config() {
    local destination="$1"
    local reasoning_effort="$2"
    local context_tier="$3"
    local context_window auto_compact
    local catalog_path="${destination%/*}/model-catalog.json"

    codex_load_provider_metadata || return 1
    context_window="$(codex_context_window "${context_tier}")" || return 1
    auto_compact="$(codex_auto_compact_limit "${context_tier}")" || return 1
    codex_write_model_catalog "${catalog_path}" || return 1
    {
        printf 'model_provider = %s\n' \
            "$(codex_toml_string "${CODEX_PROVIDER_ID}")"
        printf 'model_catalog_json = %s\n' \
            "$(codex_toml_string "${catalog_path}")"
        printf 'model_reasoning_effort = %s\n' \
            "$(codex_toml_string "${reasoning_effort}")"
        printf 'model_context_window = %s\n' "${context_window}"
        printf 'model_auto_compact_token_limit = %s\n' "${auto_compact}"
        printf '%s\n' \
            'approval_policy = "never"' \
            'sandbox_mode = "read-only"' \
            'web_search = "disabled"' \
            'project_doc_max_bytes = 0' \
            'suppress_unstable_features_warning = true' \
            '' \
            '[agents]' \
            'enabled = false' \
            '' \
            '[features]' \
            'shell_tool = false' \
            'unified_exec = false' \
            'apply_patch_freeform = false' \
            'js_repl = false' \
            'goals = false' \
            'view_image = false' \
            'multi_agent = false' \
            'multi_agent_v2 = false' \
            'plugins = false' \
            'plugin_hooks = false' \
            'search_tool = false' \
            'tool_search = false' \
            'skill_search = false' \
            'skip_host_skill_discovery = true' \
            'worktrees = false' \
            'daemon_auto_start = false' \
            'default_mode_request_user_input = false' \
            '' \
            '[skills]' \
            'include_instructions = false' \
            '' \
            '[skills.bundled]' \
            'enabled = false' \
            '' \
            '[plugins._default]' \
            'enabled = false' \
            '' \
            '[apps._default]' \
            'enabled = false' \
            '' \
            '[tools.update_plan]' \
            'enabled = false' \
            '' \
            '[tools.experimental_request_user_input]' \
            'enabled = false' \
            '' \
            '[analytics]' \
            'enabled = false' \
            '' \
            '[otel]' \
            'metrics_exporter = "none"' \
            ''
        printf '[model_providers.%s]\n' \
            "$(codex_toml_string "${CODEX_PROVIDER_ID}")"
        printf '%s\n' \
            'name = "Rhyolite configured Codex provider"'
        printf 'base_url = %s\n' \
            "$(codex_toml_string "${CODEX_PROVIDER_BASE_URL}")"
        printf '%s\n' \
            'wire_api = "responses"'
        printf 'env_key = %s\n' \
            "$(codex_toml_string "${CODEX_PROVIDER_ENV_KEY}")"
        printf '%s\n' \
            'requires_openai_auth = false' \
            'supports_websockets = false' \
            'request_max_retries = 0' \
            'stream_max_retries = 0'
    } > "${destination}" || return 1
    chmod 600 -- "${destination}"
}

codex_strip_frontmatter() {
    awk '
        NR == 1 && $0 == "---" { frontmatter = 1; next }
        frontmatter && $0 == "---" { frontmatter = 0; next }
        !frontmatter { print }
    ' "$1"
}

codex_write_instruction_bundle() {
    local destination="$1"
    local worker="$2"
    local skill="$3"

    if ! {
        printf '%s\n\n' '# Rhyolite trusted worker instructions'
        codex_strip_frontmatter "${worker}"
        printf '\n%s\n\n' '# Rhyolite shared review contract'
        codex_strip_frontmatter "${skill}"
    } > "${destination}"; then
        return 1
    fi
    chmod 600 -- "${destination}"
}

codex_populate_worker_environment() {
    local destination_name="$1"
    local working_directory="$2"
    local runtime_home="$3"

    codex_require_array_destination "${destination_name}" || return 1
    [[ "${working_directory}" == /* && -d "${working_directory}" &&
        ! -L "${working_directory}" &&
        "${runtime_home}" == /* && -d "${runtime_home}" &&
        ! -L "${runtime_home}" ]] || {
        rhyolite_harness_set_error \
            'The Codex worker environment paths are invalid.'
        return 1
    }
    local -n codex_environment_ref="${destination_name}"
    codex_environment_ref=(
        -C "${working_directory}"
        -u CODEX_HOME
        -u CODEX_THREAD_ID
        -u CODEX_SESSION_ID
        -u CODEX_REMOTE
        "HOME=${runtime_home}"
        "CODEX_HOME=${runtime_home}"
        "XDG_CONFIG_HOME=${runtime_home}"
        "XDG_CACHE_HOME=${runtime_home}"
        "XDG_STATE_HOME=${runtime_home}"
        "TMPDIR=${runtime_home}/tmp"
        NO_COLOR=1
        TERM=dumb
        RUST_LOG=off
    )
}

codex_write_server_config_record() {
    local config_path="$1"
    local server="$2"
    local launcher="$3"
    local arguments_name="$4"
    local tools_json="$5"
    local argument separator=''

    local -n codex_config_arguments_ref="${arguments_name}"
    {
        printf '{"Server":%s,"Command":%s,"Arguments":[' \
            "$(codex_json_string "${server}")" \
            "$(codex_json_string "${launcher}")"
        for argument in "${codex_config_arguments_ref[@]}"; do
            printf '%s%s' "${separator}" "$(codex_json_string "${argument}")"
            separator=','
        done
        printf '],"Tools":%s}\n' "${tools_json}"
    } > "${config_path}" &&
        chmod 600 -- "${config_path}"
}

codex_append_mcp_server() {
    local destination_name="$1"
    local server="$2"
    local launcher="$3"
    local arguments_name="$4"
    local tools_json="$5"
    local argument tool tools_csv=''
    local separator=''
    local arguments_toml='['
    local restore_stdin=0
    local owner_stat owner_fields owner_start_time
    local -a owner_values=()

    codex_require_array_destination "${destination_name}" || return 1
    codex_require_array_destination "${arguments_name}" || return 1
    [[ "${server}" =~ ^[a-z][a-z0-9_]{0,31}$ &&
        "${launcher}" == /* && -f "${launcher}" && ! -L "${launcher}" &&
        "${tools_json}" =~ ^\[\ *\"[a-z_]+\"(\ *,\ *\"[a-z_]+\")*\ *\]$ ]] || {
        rhyolite_harness_set_error \
            'The Codex MCP server configuration is invalid.'
        return 1
    }
    local -n codex_mcp_arguments_ref="${arguments_name}"
    local -n codex_mcp_destination_ref="${destination_name}"
    owner_stat="$(< "/proc/$$/stat")" || return 1
    owner_fields="${owner_stat##*) }"
    read -r -a owner_values <<< "${owner_fields}"
    ((${#owner_values[@]} > 19)) || return 1
    owner_start_time="${owner_values[19]}"
    [[ "${owner_start_time}" =~ ^[1-9][0-9]*$ ]] || return 1
    if ((${#codex_mcp_destination_ref[@]} > 0)) &&
        [[ "${codex_mcp_destination_ref[-1]}" == - ]]; then
        unset 'codex_mcp_destination_ref[-1]'
        restore_stdin=1
    fi
    for argument in "${codex_mcp_arguments_ref[@]}"; do
        [[ "${argument}" != *$'\n'* && "${argument}" != *$'\r'* ]] || return 1
        arguments_toml+="${separator}$(codex_toml_string "${argument}")"
        separator=','
    done
    arguments_toml+=']'
    tools_csv="${tools_json//[\[\]\"]/}"
    tools_csv="${tools_csv// /}"
    codex_mcp_destination_ref+=(
        -c "mcp_servers.${server}.command=$(codex_toml_string "${launcher}")"
        -c "mcp_servers.${server}.args=${arguments_toml}"
        -c "mcp_servers.${server}.enabled=true"
        -c "mcp_servers.${server}.required=true"
        -c "mcp_servers.${server}.enabled_tools=${tools_json}"
        -c "mcp_servers.${server}.env={RHYOLITE_BROKER_OWNER_PID=\"$$\",RHYOLITE_BROKER_OWNER_START_TIME=\"${owner_start_time}\"}"
        -c "mcp_servers.${server}.env_vars=[]"
        -c "mcp_servers.${server}.startup_timeout_sec=15"
        -c "mcp_servers.${server}.tool_timeout_sec=120"
    )
    while IFS= read -r tool; do
        [[ "${tool}" =~ ^[a-z_]+$ ]] || return 1
        codex_mcp_destination_ref+=(
            -c "mcp_servers.${server}.tools.${tool}.approval_mode=\"approve\""
        )
    done < <(printf '%s\n' "${tools_csv//,/$'\n'}")
    ((restore_stdin == 0)) || codex_mcp_destination_ref+=(-)
}

codex_extract_latest_assistant_reply() {
    local transcript="$1"

    awk '
        { lines[NR] = $0 }
        END {
            start = 0
            for (i = 1; i <= NR; i++) {
                marker = lines[i]
                sub(/^[[:space:]]+/, "", marker)
                sub(/[[:space:]]+$/, "", marker)
                if (marker == "### Codex") {
                    start = i + 1
                }
            }
            if (start == 0) exit 42
            for (i = start; i <= NR; i++) print lines[i]
        }
    ' "${transcript}"
}

codex_write_pure_report_repair_descriptor() {
    local source_path="$1"
    local destination_path="$2"

    awk '
        /^[[:space:]]*$/ { next }
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

codex_verify_session_record() {
    local runtime_home="$1"
    local transcript_output="$2"
    local filtered_output="$3"
    local approved_model="$4"
    local approved_effort="$5"
    local context_tier="$6"
    local expected_context

    expected_context="$(codex_usable_context_window "${context_tier}")" || return 1
    python3 -I - \
        "${runtime_home}" \
        "${transcript_output}" \
        "${filtered_output}" \
        "${approved_model}" \
        "${approved_effort}" \
        "${expected_context}" <<'PY'
import json
import pathlib
import re
import sys

root, transcript_name, filtered_name, model, effort, context_text = sys.argv[1:7]
expected_context = int(context_text)
root = pathlib.Path(root)
paths = sorted((root / "sessions").glob("**/*.jsonl")) if (root / "sessions").is_dir() else []
if len(paths) != 1 or paths[0].is_symlink():
    print("missing" if not paths else "unreadable")
    print("")
    raise SystemExit(0)

status = "verified"
thread_id = ""
turn_contexts = 0
contexts = set()
filtered = []
blocks = []


def escalate(candidate):
    global status
    priorities = {
        "verified": 0, "context-changed": 1, "effort-changed": 2,
        "substituted": 3, "subagent": 4, "unreadable": 5,
    }
    if priorities[candidate] > priorities[status]:
        status = candidate


def content_text(content):
    if not isinstance(content, list):
        return ""
    return "\n".join(
        str(item.get("text", ""))
        for item in content
        if isinstance(item, dict)
        and item.get("type") in {"text", "input_text", "output_text", "Text"}
    )


try:
    raw_lines = paths[0].read_bytes().split(b"\n")
except OSError:
    print("unreadable")
    print("")
    raise SystemExit(0)

for raw in raw_lines:
    if not raw.strip():
        continue
    try:
        record = json.loads(raw.decode("utf-8"))
    except (UnicodeError, ValueError):
        escalate("unreadable")
        continue
    if not isinstance(record, dict):
        continue
    record_type = record.get("type")
    payload = record.get("payload")
    if not isinstance(payload, dict):
        continue
    if record_type == "session_meta":
        candidate = payload.get("session_id") or payload.get("id")
        if isinstance(candidate, str) and re.fullmatch(
            r"[0-9A-Fa-f-]{36}", candidate
        ):
            thread_id = candidate
        filtered.append({
            "type": "session_meta",
            "payload": {
                "session_id": thread_id,
                "originator": payload.get("originator"),
                "cli_version": payload.get("cli_version"),
                "source": payload.get("source"),
            },
        })
    elif record_type == "turn_context":
        turn_contexts += 1
        used_model = payload.get("model")
        used_effort = payload.get("effort")
        collaboration = payload.get("collaboration_mode")
        if used_model != model:
            escalate("substituted")
        if used_effort != effort:
            escalate("effort-changed")
        if (
            payload.get("approval_policy") != "never"
            or not isinstance(payload.get("sandbox_policy"), dict)
            or payload["sandbox_policy"].get("type") != "read-only"
            or not isinstance(collaboration, dict)
            or collaboration.get("mode") != "default"
        ):
            escalate("unreadable")
        filtered.append({
            "type": "turn_context",
            "payload": {
                "model": used_model,
                "effort": used_effort,
                "approval_policy": payload.get("approval_policy"),
                "sandbox_policy": payload.get("sandbox_policy"),
                "collaboration_mode": collaboration,
            },
        })
    elif record_type == "event_msg":
        if payload.get("type") == "task_started":
            value = payload.get("model_context_window")
            if type(value) is int:
                contexts.add(value)
        item = payload.get("item")
        if payload.get("type") == "item_completed" and isinstance(item, dict):
            if str(item.get("type", "")).lower().startswith("collab"):
                escalate("subagent")
    elif record_type == "response_item" and payload.get("type") == "message":
        role = payload.get("role")
        text = content_text(payload.get("content"))
        if role == "assistant":
            blocks.append(("Codex", text))
        elif role == "user":
            blocks.append(("User", text))
        filtered.append({
            "type": "response_item",
            "payload": {
                "type": "message",
                "role": role,
                "phase": payload.get("phase"),
                "content": [{"type": "text", "text": text}],
            },
        })

if turn_contexts == 0 or not thread_id:
    escalate("unreadable")
if contexts != {expected_context}:
    escalate("context-changed")

try:
    pathlib.Path(filtered_name).write_text(
        "\n".join(json.dumps(record, ensure_ascii=False, separators=(",", ":"))
                  for record in filtered) + "\n",
        encoding="utf-8",
    )
    with pathlib.Path(transcript_name).open("w", encoding="utf-8", newline="\n") as stream:
        for label, text in blocks:
            stream.write(f"### {label}\n\n{text}\n\n")
except OSError:
    status = "unreadable"
print(status)
print(thread_id)
PY
}

harness_id() {
    printf '%s\n' 'codex'
}

harness_display_name() {
    printf '%s\n' 'OpenAI Codex CLI'
}

harness_cli_name() {
    printf '%s\n' 'codex'
}

harness_require_cli() {
    command -v codex >/dev/null 2>&1 || {
        rhyolite_harness_set_error 'codex is required.'
        return 1
    }
}

harness_capability() {
    case "$1" in
        shell_denial|structured_questions|web_research|builtin_research_specialist|final_message_file)
            printf '%s\n' 'yes'
            ;;
        fleet|subagents|builtin_security_specialist)
            printf '%s\n' 'no'
            ;;
        worker_continuation)
            printf '%s\n' 'unverified'
            ;;
        *)
            printf '%s\n' 'unverified'
            ;;
    esac
}

harness_default_model() {
    printf '%s\n' 'gpt-5.6-sol'
}

harness_list_models() {
    printf '%s\n' 'gpt-5.6-sol'
}

harness_validate_model_id() {
    codex_valid_safe_identifier "$1" || {
        rhyolite_harness_set_error \
            'The model identifier contains unsupported characters.'
        return 1
    }
    [[ "$1" == gpt-5.6-sol ]] || {
        rhyolite_harness_set_error \
            "Model '$1' is not in Rhyolite's verified offline Codex model catalog."
        return 1
    }
}

harness_model_choices() {
    printf '%s\n' \
        'GPT-5.6 Sol (Recommended) - gpt-5.6-sol' \
        'List available model IDs'
}

harness_max_reasoning_effort() {
    [[ "$1" == gpt-5.6-sol ]] || return 1
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
                'Reasoning effort must be high, xhigh, or max. Codex ultra is excluded because it enables automatic task delegation.'
            return 1
            ;;
    esac
}

harness_default_context_tier() {
    printf '%s\n' 'long_context'
}

harness_context_choices() {
    printf '%s\n' \
        'Long context (Recommended, 872000 configured / 828400 usable) - long_context' \
        'Default context (272000 configured / 258400 usable) - default'
}

harness_validate_context_tier() {
    codex_context_window "$1" >/dev/null || {
        rhyolite_harness_set_error \
            'Context tier must be default or long_context.'
        return 1
    }
}

harness_auth_secret_env_vars() {
    codex_load_provider_metadata || return 1
    printf '%s\n' "${CODEX_PROVIDER_ENV_KEY}"
}

harness_login_remediation() {
    codex_load_provider_metadata || return 1
    printf 'Export %s in the shell that launches Rhyolite, verify the configured Codex provider without printing the value, and retry.' \
        "${CODEX_PROVIDER_ENV_KEY}"
}

harness_provider_summary() {
    codex_load_provider_metadata || return 1
    printf '{"Id":%s,"Host":%s,"ForwardedEnvVarNames":[%s]}\n' \
        "$(codex_json_string "${CODEX_PROVIDER_SUMMARY_ID}")" \
        "$(codex_json_string "${CODEX_PROVIDER_HOST}")" \
        "$(codex_json_string "${CODEX_PROVIDER_ENV_KEY}")"
}

harness_resume_policy() {
    printf '%s\n' \
        'Continue only through the trusted Rhyolite repo-review runner; do not invoke codex exec resume directly.'
}

harness_prepare_run() {
    codex_load_provider_metadata || return 1
    [[ -n "${!CODEX_PROVIDER_ENV_KEY-}" ]] || {
        rhyolite_harness_set_error \
            "The configured Codex provider environment variable ${CODEX_PROVIDER_ENV_KEY} is not set."
        return 1
    }
    printf '%s\n' \
        'Codex authentication will be verified by the first isolated worker through the configured environment-variable provider.'
}

harness_prepare_worker_home() {
    local runtime_home="$1"
    local reasoning_effort="$2"
    local context_tier="$3"
    local phase="${4:-review}"

    case "${phase}" in
        review|research|report-repair) ;;
        *)
            rhyolite_harness_set_error \
                'The Codex runtime-home phase is unsupported.'
            return 1
            ;;
    esac
    harness_validate_reasoning_effort "${reasoning_effort}" || return 1
    harness_validate_context_tier "${context_tier}" || return 1
    [[ "${runtime_home}" == /* && -d "${runtime_home}" &&
        ! -L "${runtime_home}" ]] || {
        rhyolite_harness_set_error \
            'The temporary Codex runtime home is unavailable.'
        return 1
    }
    chmod 700 -- "${runtime_home}" &&
        mkdir -p -- "${runtime_home}/tmp" &&
        chmod 700 -- "${runtime_home}/tmp" || {
        rhyolite_harness_set_error \
            'Could not restrict the temporary Codex runtime home.'
        return 1
    }
    codex_write_runtime_config \
        "${runtime_home}/config.toml" \
        "${reasoning_effort}" \
        "${context_tier}" || {
        rhyolite_harness_set_error \
            'Could not write the temporary Codex configuration.'
        return 1
    }
    CODEX_RUNTIME_HOME="${runtime_home}"
    CODEX_HOME_PHASE="${phase}"
    CODEX_CONTEXT_TIER="${context_tier}"
    [[ "${phase}" != review ]] || CODEX_REVIEW_RUNTIME_HOME="${runtime_home}"
}

harness_snapshot_transport() {
    printf '%s\n' 'local-stdio-mcp-snapshot-read-v1'
}

harness_configure_snapshot_transport() {
    local phase="$1"
    local argv_name="$2"
    local runtime_home="$3"
    local config_path="$4"
    local launcher="$5"
    local arguments_name="$6"
    local tools_json="$7"

    case "${phase}" in review|research) ;; *) return 1 ;; esac
    [[ "${runtime_home}" == "${CODEX_RUNTIME_HOME}" &&
        "${config_path}" == /* && ! -e "${config_path}" ]] || {
        rhyolite_harness_set_error \
            'The Codex snapshot configuration paths are invalid.'
        return 1
    }
    codex_write_server_config_record \
        "${config_path}" rhyolite_snapshot "${launcher}" \
        "${arguments_name}" "${tools_json}" &&
        codex_append_mcp_server \
            "${argv_name}" rhyolite_snapshot "${launcher}" \
            "${arguments_name}" "${tools_json}" || {
        rm -f -- "${config_path}"
        rhyolite_harness_set_error \
            'Could not configure the Codex snapshot MCP server.'
        return 1
    }
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
    local instruction_path

    codex_require_array_destination "${destination_name}" || return 1
    [[ "${session_root}" == /* && -d "${session_root}" && ! -L "${session_root}" &&
        "${plugin_root}" == /* &&
        -f "${plugin_root}/agents/repo-review-worker.agent.md" &&
        -f "${plugin_root}/skills/readonly-repository-review/SKILL.md" ]] || return 1
    codex_valid_safe_identifier "${session_name}" &&
        codex_valid_session_id "${session_id}" || return 1
    harness_validate_model_id "${model}" &&
        harness_validate_reasoning_effort "${reasoning_effort}" &&
        harness_validate_context_tier "${context_tier}" || return 1
    [[ "${authentication_variables}" == "${CODEX_PROVIDER_ENV_KEY}" &&
        "${transcript_path}" == /* ]] || return 1
    : "${available_tools}" "${enable_public_research}"
    instruction_path="${CODEX_RUNTIME_HOME}/review-worker-instructions.md"
    codex_write_instruction_bundle \
        "${instruction_path}" \
        "${plugin_root}/agents/repo-review-worker.agent.md" \
        "${plugin_root}/skills/readonly-repository-review/SKILL.md" || return 1
    CODEX_SESSION_ROOT="${session_root}"
    CODEX_LOGICAL_SESSION_ID="${session_id}"
    CODEX_TRANSCRIPT_PATH="${transcript_path}"
    CODEX_APPROVED_MODEL="${model}"
    CODEX_APPROVED_EFFORT="${reasoning_effort}"
    CODEX_CONTEXT_TIER="${context_tier}"
    CODEX_NATIVE_THREAD_ID=''
    CODEX_TRANSCRIPT_STATUS=''
    CODEX_REVIEW_FINAL_MESSAGE="${transcript_path}.codex-final"
    local -n codex_arguments_ref="${destination_name}"
    codex_arguments_ref=(
        --no-daemon
        exec
        --strict-config
        --ignore-rules
        -c "model_instructions_file=$(codex_toml_string "${instruction_path}")"
        --sandbox read-only
        --json
        --skip-git-repo-check
        --cd "${session_root}"
        --model "${model}"
        --output-last-message "${CODEX_REVIEW_FINAL_MESSAGE}"
        -
    )
}

harness_worker_env() {
    codex_populate_worker_environment \
        "$1" "${CODEX_SESSION_ROOT}" "${CODEX_RUNTIME_HOME}"
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
    local first_entry

    codex_require_array_destination "${destination_name}" || return 1
    [[ "${trusted_workdir}" == /* && -d "${trusted_workdir}" &&
        ! -L "${trusted_workdir}" ]] || return 1
    first_entry="$(find "${trusted_workdir}" -mindepth 1 -print -quit 2>/dev/null)" ||
        return 1
    [[ -z "${first_entry}" ]] || return 1
    codex_valid_safe_identifier "${session_name}" &&
        codex_valid_session_id "${session_id}" || return 1
    harness_validate_model_id "${model}" &&
        harness_validate_reasoning_effort "${reasoning_effort}" &&
        harness_validate_context_tier "${context_tier}" || return 1
    [[ "${authentication_variables}" == "${CODEX_PROVIDER_ENV_KEY}" &&
        "${transcript_path}" == /* ]] || return 1
    CODEX_REPAIR_WORKDIR="${trusted_workdir}"
    CODEX_REPAIR_FINAL_MESSAGE="${transcript_path}.codex-final"
    local -n codex_arguments_ref="${destination_name}"
    codex_arguments_ref=(
        --no-daemon
        exec
        --strict-config
        --ignore-rules
        --ephemeral
        --sandbox read-only
        --json
        --skip-git-repo-check
        --cd "${trusted_workdir}"
        --model "${model}"
        --output-last-message "${CODEX_REPAIR_FINAL_MESSAGE}"
        -
    )
}

harness_report_repair_env() {
    codex_populate_worker_environment \
        "$1" "${CODEX_REPAIR_WORKDIR}" "$2"
}

harness_write_research_mcp_config() {
    local config_path="$1"
    local broker_launcher="$2"
    local arguments_name="$3"
    local tools_json="$4"

    codex_require_array_destination "${arguments_name}" || return 1
    [[ "${config_path}" == /* && ! -e "${config_path}" ]] || return 1
    codex_write_server_config_record \
        "${config_path}" rhyolite_research "${broker_launcher}" \
        "${arguments_name}" "${tools_json}" || return 1
    local -n source_arguments="${arguments_name}"
    CODEX_RESEARCH_BROKER_ARGUMENTS=("${source_arguments[@]}")
    CODEX_RESEARCH_BROKER_LAUNCHER="${broker_launcher}"
    CODEX_RESEARCH_TOOLS_JSON="${tools_json}"
    CODEX_RESEARCH_CONFIG_PATH="${config_path}"
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
    local instruction_path tools_json

    codex_require_array_destination "${destination_name}" || return 1
    [[ "${session_root}" == /* && -d "${session_root}" && ! -L "${session_root}" &&
        "${plugin_root}" == /* &&
        -f "${plugin_root}/agents/repo-research-worker.agent.md" &&
        -f "${plugin_root}/skills/research-source-assessment/SKILL.md" ]] || return 1
    codex_valid_safe_identifier "${session_name}" &&
        codex_valid_session_id "${session_id}" || return 1
    harness_validate_model_id "${model}" &&
        harness_validate_reasoning_effort "${reasoning_effort}" &&
        harness_validate_context_tier "${context_tier}" || return 1
    [[ "${authentication_variables}" == "${CODEX_PROVIDER_ENV_KEY}" &&
        "${mcp_config_path}" == "${CODEX_RESEARCH_CONFIG_PATH}" &&
        -f "${mcp_config_path}" && ! -L "${mcp_config_path}" &&
        "${transcript_path}" == /* ]] || return 1
    tools_json="[\"${broker_tools//,/\", \"}\"]"
    [[ "${tools_json}" == "${CODEX_RESEARCH_TOOLS_JSON}" ]] || return 1
    instruction_path="${CODEX_RUNTIME_HOME}/research-worker-instructions.md"
    codex_write_instruction_bundle \
        "${instruction_path}" \
        "${plugin_root}/agents/repo-research-worker.agent.md" \
        "${plugin_root}/skills/research-source-assessment/SKILL.md" || return 1
    CODEX_RESEARCH_SESSION_ROOT="${session_root}"
    CODEX_RESEARCH_LOGICAL_SESSION_ID="${session_id}"
    CODEX_RESEARCH_TRANSCRIPT_PATH="${transcript_path}"
    CODEX_RESEARCH_MODEL="${model}"
    CODEX_RESEARCH_EFFORT="${reasoning_effort}"
    CODEX_RESEARCH_CONTEXT_TIER="${context_tier}"
    CODEX_RESEARCH_FINAL_MESSAGE="${transcript_path}.codex-final"
    local -n codex_arguments_ref="${destination_name}"
    codex_arguments_ref=(
        --no-daemon
        exec
        --strict-config
        --ignore-rules
        -c "model_instructions_file=$(codex_toml_string "${instruction_path}")"
        --sandbox read-only
        --json
        --skip-git-repo-check
        --cd "${session_root}"
        --model "${model}"
        --output-last-message "${CODEX_RESEARCH_FINAL_MESSAGE}"
        -
    )
    codex_append_mcp_server \
        "${destination_name}" rhyolite_research \
        "${CODEX_RESEARCH_BROKER_LAUNCHER}" \
        CODEX_RESEARCH_BROKER_ARGUMENTS \
        "${CODEX_RESEARCH_TOOLS_JSON}"
}

harness_research_worker_env() {
    codex_populate_worker_environment \
        "$1" "${CODEX_RESEARCH_SESSION_ROOT}" "${CODEX_RUNTIME_HOME}"
}

harness_finalize_research_session() {
    local runtime_home="$1"
    local raw_output="$2"
    local filtered="${runtime_home}/rhyolite-research-filtered.jsonl"
    local result status native_id

    result="$(
        codex_verify_session_record \
            "${runtime_home}" \
            "${CODEX_RESEARCH_TRANSCRIPT_PATH}" \
            "${filtered}" \
            "${CODEX_RESEARCH_MODEL}" \
            "${CODEX_RESEARCH_EFFORT}" \
            "${CODEX_RESEARCH_CONTEXT_TIER}"
    )" || return 1
    status="${result%%$'\n'*}"
    native_id="${result#*$'\n'}"
    rm -f -- "${filtered}"
    chmod 600 -- "${CODEX_RESEARCH_TRANSCRIPT_PATH}" 2>/dev/null || true
    case "${status}" in
        verified) return 0 ;;
        missing)
            if grep -Fq 'REPOSITORY RESEARCH DOSSIER' "${raw_output}" 2>/dev/null; then
                rhyolite_harness_set_error \
                    'Codex returned a research dossier without its private session record.'
                return 1
            fi
            return 0
            ;;
        substituted)
            rhyolite_harness_set_error \
                'Codex recorded a research model other than the approved model.'
            ;;
        effort-changed)
            rhyolite_harness_set_error \
                'Codex recorded a research reasoning effort other than the approved effort.'
            ;;
        context-changed)
            rhyolite_harness_set_error \
                'Codex recorded a research context window other than the approved tier.'
            ;;
        subagent)
            rhyolite_harness_set_error \
                'Codex recorded a research subagent although subagents are disabled.'
            ;;
        *)
            rhyolite_harness_set_error \
                'The Codex research session record was unreadable.'
            ;;
    esac
    : "${native_id}"
    return 1
}

codex_final_message_for_phase() {
    case "$1" in
        review) printf '%s\n' "${CODEX_REVIEW_FINAL_MESSAGE}" ;;
        research) printf '%s\n' "${CODEX_RESEARCH_FINAL_MESSAGE}" ;;
        report-repair) printf '%s\n' "${CODEX_REPAIR_FINAL_MESSAGE}" ;;
        *) return 1 ;;
    esac
}

harness_normalize_worker_output() {
    local phase="$1"
    local raw_output="$2"
    local approved_model="$3"
    local approved_effort="$4"
    local normalized_output="$5"
    local final_reply_output="$6"
    local final_message status

    rhyolite_harness_validate_normalize_arguments "$@" || return 1
    final_message="$(codex_final_message_for_phase "${phase}")" || return 1
    [[ -f "${final_message}" && ! -L "${final_message}" ]] || {
        rhyolite_harness_set_error \
            'Codex did not write its exact final-message artifact.'
        return 1
    }
    if [[ "${phase}" == review && "${CODEX_TRANSCRIPT_STATUS}" != verified ]]; then
        rhyolite_harness_set_error \
            'The Codex review session record did not verify the approved model, effort, context, and no-subagent boundary.'
        return 1
    fi
    status="$(
        python3 -I - \
            "${phase}" "${raw_output}" "${final_message}" \
            "${normalized_output}" "${final_reply_output}" <<'PY'
import json
import pathlib
import re
import sys

phase, raw_name, final_name, normalized_name, reply_name = sys.argv[1:6]
allowed_mcp = {
    "review": {
        ("rhyolite_snapshot", "snapshot_capabilities"),
        ("rhyolite_snapshot", "list_snapshot_paths"),
        ("rhyolite_snapshot", "read_snapshot_text"),
        ("rhyolite_snapshot", "search_snapshot_text"),
        ("codex", "list_mcp_resources"),
        ("codex", "list_mcp_resource_templates"),
        ("codex", "read_mcp_resource"),
    },
    "research": {
        ("rhyolite_snapshot", "snapshot_capabilities"),
        ("rhyolite_snapshot", "list_snapshot_paths"),
        ("rhyolite_snapshot", "read_snapshot_text"),
        ("rhyolite_snapshot", "search_snapshot_text"),
        ("rhyolite_research", "research_capabilities"),
        ("rhyolite_research", "fetch_public_url"),
        ("rhyolite_research", "search_public_github"),
        ("rhyolite_research", "search_public_web"),
        ("rhyolite_research", "research_network_summary"),
        ("codex", "list_mcp_resources"),
        ("codex", "list_mcp_resource_templates"),
        ("codex", "read_mcp_resource"),
    },
    "report-repair": set(),
}[phase]
try:
    raw = pathlib.Path(raw_name).read_text(encoding="utf-8")
    exact = pathlib.Path(final_name).read_text(encoding="utf-8")
except (OSError, UnicodeError):
    print("unreadable")
    raise SystemExit(0)
last_reply = None
threads = set()
status = "verified"
for line in raw.splitlines():
    if not line.strip():
        continue
    try:
        event = json.loads(line)
    except ValueError:
        status = "unreadable"
        break
    event_type = event.get("type")
    if event_type == "thread.started":
        candidate = event.get("thread_id")
        if isinstance(candidate, str):
            threads.add(candidate)
    elif event_type in {"turn.failed", "error"}:
        status = "failed"
    elif event_type in {"item.started", "item.updated", "item.completed"}:
        item = event.get("item")
        if not isinstance(item, dict):
            continue
        item_type = item.get("type")
        if item_type == "agent_message" and event_type == "item.completed":
            last_reply = item.get("text")
        elif item_type == "error":
            message = str(item.get("message", ""))
            if message.startswith("model rerouted: "):
                status = "substituted"
        elif item_type == "collab_tool_call":
            status = "subagent"
        elif item_type in {
            "command_execution", "file_change", "web_search", "todo_list"
        }:
            status = "forbidden-tool"
        elif item_type == "mcp_tool_call":
            if (item.get("server"), item.get("tool")) not in allowed_mcp:
                status = "forbidden-tool"
if len(threads) != 1 or last_reply is None or last_reply != exact:
    status = "unreadable" if status == "verified" else status
if status == "verified":
    pathlib.Path(normalized_name).write_text(raw, encoding="utf-8")
    pathlib.Path(reply_name).write_text(exact, encoding="utf-8")
print(status)
PY
    )" || return 1
    case "${status}" in
        verified)
            chmod 600 -- "${normalized_output}" "${final_reply_output}"
            return 0
            ;;
        substituted)
            rhyolite_harness_set_error \
                'Codex recorded a model reroute; Rhyolite does not accept substituted output.'
            ;;
        subagent)
            rhyolite_harness_set_error \
                'Codex recorded a collab/subagent tool call although subagents are disabled.'
            ;;
        forbidden-tool)
            rhyolite_harness_set_error \
                'Codex recorded a tool outside the approved phase inventory.'
            ;;
        failed)
            rhyolite_harness_set_error \
                'Codex recorded a failed worker turn.'
            ;;
        *)
            rhyolite_harness_set_error \
                'Codex structured output or exact final-message evidence was unreadable.'
            ;;
    esac
    rm -f -- "${normalized_output}" "${final_reply_output}"
    return 1
}

harness_detect_worker_violation() {
    local phase="$1"
    local raw_output="$2"
    local approved_model="$3"
    local approved_effort="$4"
    local cursor_path="$5"
    local result

    rhyolite_harness_validate_violation_arguments "$@" || return 1
    : "${approved_model}" "${approved_effort}"
    result="$(
        python3 -I - "${phase}" "${raw_output}" "${cursor_path}" <<'PY'
import json
import pathlib
import sys

phase, raw_name, cursor_name = sys.argv[1:4]
source = pathlib.Path(raw_name)
cursor = pathlib.Path(cursor_name)
offset = 0
try:
    if cursor.is_file():
        offset = max(0, int(cursor.read_text(encoding="ascii").strip() or 0))
    data = source.read_bytes() if source.is_file() else b""
except (OSError, ValueError, UnicodeError):
    print("error\nThe Codex worker output could not be monitored.")
    raise SystemExit(0)
tail = data[offset:]
lines = tail.split(b"\n")[:-1]
consumed = sum(len(line) + 1 for line in lines)
status = "clean"
detail = ""
for raw in lines:
    if not raw.strip():
        continue
    try:
        event = json.loads(raw.decode("utf-8"))
    except (UnicodeError, ValueError):
        continue
    if event.get("type") not in {"item.started", "item.updated", "item.completed"}:
        continue
    item = event.get("item")
    if not isinstance(item, dict):
        continue
    item_type = item.get("type")
    if item_type == "collab_tool_call":
        status, detail = "violation", "Codex recorded a collab/subagent tool call."
        break
    if item_type in {"command_execution", "file_change", "web_search", "todo_list"}:
        status, detail = "violation", "Codex recorded a tool outside the approved phase inventory."
        break
    if item_type == "error" and str(item.get("message", "")).startswith("model rerouted: "):
        status, detail = "violation", "Codex recorded an automatic model reroute."
        break
try:
    cursor.write_text(f"{offset + consumed}\n", encoding="ascii")
    cursor.chmod(0o600)
except OSError:
    status, detail = "error", "The Codex worker-output cursor could not be written."
print(status)
print(detail)
PY
    )" || return 1
    case "${result%%$'\n'*}" in
        clean) return 0 ;;
        violation)
            RHYOLITE_HARNESS_ERROR_DETAIL="${result#*$'\n'}"
            return "${RHYOLITE_HARNESS_WORKER_VIOLATION_STATUS}"
            ;;
        *)
            RHYOLITE_HARNESS_ERROR_DETAIL="${result#*$'\n'}"
            return 1
            ;;
    esac
}

harness_worker_outcome() {
    local phase="$1"
    local raw_output="$2"
    local runtime_home="$3"
    local session_id="$4"
    local approved_model="$5"
    local approved_effort="$6"
    local outcome_output="$7"

    rhyolite_harness_validate_outcome_arguments "$@" || return 1
    : "${runtime_home}" "${session_id}" "${approved_model}" "${approved_effort}"
    python3 -I - "${phase}" "${raw_output}" "${outcome_output}" <<'PY' || {
import json
import pathlib
import re
import sys

phase, raw_name, output_name = sys.argv[1:4]
transient = re.compile(
    r"429|rate limit|overloaded|timed out|timeout|connection|"
    r"ECONNRESET|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|5[0-9][0-9]",
    re.I,
)
errors = []
completed = False
agent_messages = 0
rerouted = ""
failed = False
for line in pathlib.Path(raw_name).read_text(encoding="utf-8").splitlines():
    if not line.strip():
        continue
    try:
        event = json.loads(line)
    except ValueError:
        continue
    event_type = event.get("type")
    if event_type == "turn.completed":
        completed = True
    elif event_type in {"turn.failed", "error"}:
        failed = True
        value = event.get("error") if isinstance(event.get("error"), dict) else event
        message = str(value.get("message", "turn failed"))
        if message and message not in errors and len(errors) < 5:
            errors.append(message[:400])
    elif event_type == "item.completed":
        item = event.get("item")
        if not isinstance(item, dict):
            continue
        if item.get("type") == "agent_message":
            agent_messages += 1
        if item.get("type") == "error":
            message = str(item.get("message", ""))
            if message.startswith("model rerouted: "):
                match = re.search(r" -> ([A-Za-z0-9._:-]+)", message)
                rerouted = match.group(1) if match else "unrecognized"
            elif message and message not in errors and len(errors) < 5:
                errors.append(message[:400])
if rerouted and agent_messages:
    outcome = "substituted"
elif rerouted:
    outcome = "fallback-blocked"
elif completed and agent_messages and not failed:
    outcome = "completed"
elif any(transient.search(error) for error in errors):
    outcome = "transient-failure"
elif failed or errors:
    outcome = "failed"
else:
    outcome = "unknown"
pathlib.Path(output_name).write_text(json.dumps({
    "Schema": 1,
    "Phase": phase,
    "Outcome": outcome,
    "Retryable": outcome in {"transient-failure", "fallback-blocked"},
    "ExitCode": None,
    "SessionErrors": errors,
    "ModelCallFailures": 1 if failed else 0,
    "TurnRetries": 0,
    "OutputLimitHits": 0,
    "OutputTokenLimit": None,
    "FinalReplyAtOutputLimit": False,
    "FallbackModel": rerouted if outcome == "fallback-blocked" else "",
}, sort_keys=True) + "\n", encoding="utf-8")
PY
        rm -f -- "${outcome_output}"
        rhyolite_harness_set_error \
            'The Codex worker outcome could not be classified.'
        return 1
    }
    chmod 600 -- "${outcome_output}"
}

harness_worker_continuation_argv() {
    local destination_name="$1"
    local source_name="$2"
    local index=0 inserted=0
    local -a source_copy=()
    local -a result=()

    codex_require_array_destination "${destination_name}" || return 1
    [[ "${source_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ &&
        "${source_name}" != "${destination_name}" &&
    "${source_name}" != codex_continuation_* &&
    "${destination_name}" != codex_continuation_* &&
        -n "${CODEX_NATIVE_THREAD_ID}" ]] || return 1
    local -n source_ref="${source_name}"
    local -n destination_ref="${destination_name}"
    source_copy=("${source_ref[@]}")
    while ((index < ${#source_copy[@]})); do
        if [[ "${source_copy[index]}" == --model ]] && ((inserted == 0)); then
            result+=(resume)
            inserted=1
        fi
        if [[ "${source_copy[index]}" == - ]] &&
            ((index == ${#source_copy[@]} - 1)); then
            result+=("${CODEX_NATIVE_THREAD_ID}" -)
            index=$((index + 1))
            continue
        fi
        case "${source_copy[index]}" in
            resume|--last|--all)
                return 1
                ;;
        esac
        result+=("${source_copy[index]}")
        index=$((index + 1))
    done
    ((inserted == 1)) || return 1
    destination_ref=("${result[@]}")
    CODEX_RUNTIME_HOME="${CODEX_REVIEW_RUNTIME_HOME}"
    CODEX_HOME_PHASE=review
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
    local line

    while IFS= read -r line || [[ -n "${line}" ]]; do
        case "${line}" in
            'Repository URL: {{REPOSITORY_URL}}')
                printf 'Repository URL: %s\n' "${repository}" ;;
            'Read-only source snapshot: {{REPOSITORY_PATH}}')
                printf 'Read-only source snapshot: %s\n' "${review_path}" ;;
            'Exact commit to review: {{COMMIT}}')
                printf 'Exact commit to review: %s\n' "${commit}" ;;
            'Review date: {{REVIEW_DATE}}')
                printf 'Review date: %s\n' "${review_date}" ;;
            'Recent-prior-art window: {{PRIOR_ART_START_DATE}} through {{REVIEW_DATE}}')
                printf 'Recent-prior-art window: %s through %s\n' \
                    "${prior_art_start_date}" "${review_date}" ;;
            'Provenance lookback months: {{PROVENANCE_LOOKBACK_MONTHS}}')
                if ((enable_provenance_research)); then
                    printf 'Provenance lookback months: %s\n' "${provenance_lookback_months}"
                else
                    printf '%s\n' 'Provenance lookback months: disabled'
                fi ;;
            'Provenance start date: {{PROVENANCE_START_DATE}}')
                if ((enable_provenance_research)); then
                    printf 'Provenance start date: %s\n' "${provenance_start_date}"
                else
                    printf '%s\n' 'Provenance start date: disabled'
                fi ;;
            'Selected scope: {{SCOPE_NAME}}')
                printf 'Selected scope: %s\n' "${scope_name}" ;;
            'Trusted wrapper artifact directory: {{OUTPUT_DIRECTORY}}')
                printf 'Trusted wrapper artifact directory: %s\n' "${output_directory}" ;;
            '{{REPOSITORY_METADATA}}') printf '%s\n' "${repository_metadata}" ;;
            '{{PUBLIC_RESEARCH_INSTRUCTIONS}}') printf '%s\n' "${public_research_instructions}" ;;
            '{{PROVENANCE_INSTRUCTIONS}}') printf '%s\n' "${provenance_instructions}" ;;
            '{{RESEARCH_DOSSIER_PATH}}') printf '%s\n' "${research_dossier_path}" ;;
            '{{RESEARCH_NETWORK_SUMMARY_PATH}}')
                printf '%s\n' "${research_network_summary_path}" ;;
            '{{RESEARCH_TRANSPORT_INSTRUCTIONS}}')
                printf '%s\n' "${research_transport_instructions}" ;;
            *) printf '%s\n' "${line}" ;;
        esac
    done < "${template_path}" > "${request_path}"
}

harness_extract_final_report() {
    local timeline="$1"
    local transcript="$2"
    local final_message="$3"
    local report="$4"
    local status=0

    : "${timeline}"
    codex_extract_latest_assistant_reply "${transcript}" > "${final_message}" ||
        return 42
    extract_report "${final_message}" "${report}" || status=$?
    rm -f -- "${final_message}"
    return "${status}"
}

harness_extract_report_repair() {
    local timeline="$1"
    local transcript="$2"
    local reply_output="$3"
    local candidate="${reply_output}.candidate.$$"

    rm -f -- "${reply_output}" "${candidate}"
    if codex_extract_latest_assistant_reply "${transcript}" > "${candidate}" &&
        codex_write_pure_report_repair_descriptor \
            "${candidate}" "${reply_output}"; then
        rm -f -- "${candidate}"
        return 0
    fi
    if codex_write_pure_report_repair_descriptor \
        "${timeline}" "${reply_output}"; then
        rm -f -- "${candidate}"
        return 0
    fi
    rm -f -- "${reply_output}" "${candidate}"
    rhyolite_harness_set_error \
        'Codex report repair did not return a supported confidence-edit descriptor.'
    return 42
}

harness_verify_isolation() {
    local timeline="$1"

    if [[ -n "${CODEX_RUNTIME_HOME}" && -e "${CODEX_RUNTIME_HOME}" ]] &&
        [[ -e "${CODEX_RUNTIME_HOME}/source" ||
            -e "${CODEX_RUNTIME_HOME}/.git" ]]; then
        rhyolite_harness_set_error \
            'The Codex runtime home contained source or Git data.'
        return 1
    fi
    if [[ -n "${CODEX_RUNTIME_HOME}" && -f "${timeline}" ]] &&
        grep -Fq -- "${CODEX_RUNTIME_HOME}" "${timeline}"; then
        rhyolite_harness_set_error \
            'Codex output disclosed its temporary runtime home.'
        return 1
    fi
    [[ "${CODEX_HOME_PHASE}" != review ||
        "${CODEX_TRANSCRIPT_STATUS}" == verified ]] || {
        rhyolite_harness_set_error \
            'The Codex review session record did not verify the approved execution identity.'
        return 1
    }
}

harness_persist_agent_state() {
    local runtime_home="$1"
    local agent_state_directory="$2"
    local reasoning_effort="$3"
    local context_tier="$4"
    local codex_state="${agent_state_directory}/codex-home"
    local filtered="${runtime_home}/rhyolite-filtered-session.jsonl"
    local rendered="${runtime_home}/rhyolite-rendered-session.md"
    local result status native_id

    result="$(
        codex_verify_session_record \
            "${runtime_home}" "${rendered}" "${filtered}" \
            "${CODEX_APPROVED_MODEL}" "${reasoning_effort}" "${context_tier}"
    )" || return 1
    status="${result%%$'\n'*}"
    native_id="${result#*$'\n'}"
    CODEX_TRANSCRIPT_STATUS="${status}"
    CODEX_NATIVE_THREAD_ID="${native_id}"
    [[ "${status}" != unreadable ]] || {
        rm -f -- "${filtered}" "${rendered}"
        return 1
    }
    mkdir -p -- "${codex_state}/sessions" &&
        chmod 700 -- "${codex_state}" "${codex_state}/sessions" || return 1
    if ! declare -F sanitize_review_text >/dev/null 2>&1; then
        rm -f -- "${filtered}" "${rendered}"
        return 1
    fi
    sanitize_review_text < "${filtered}" \
        > "${codex_state}/sessions/${native_id:-missing}.jsonl" &&
        sanitize_review_text < "${rendered}" > "${CODEX_TRANSCRIPT_PATH}" &&
        chmod 600 -- \
            "${codex_state}/sessions/${native_id:-missing}.jsonl" \
            "${CODEX_TRANSCRIPT_PATH}" || {
        rm -f -- "${filtered}" "${rendered}"
        return 1
    }
    rm -f -- "${filtered}" "${rendered}"
}

harness_sanitize_runtime_home() {
    local runtime_home="$1"
    local attempt

    [[ -n "${runtime_home}" && -e "${runtime_home}" ]] || return 0
    rm -f -- "${runtime_home}/config.toml" 2>/dev/null || true
    for attempt in 1 2 3; do
        rm -rf -- "${runtime_home}" 2>/dev/null || true
        [[ ! -e "${runtime_home}" ]] && return 0
        sleep 1
    done
    rhyolite_harness_set_error \
        "Could not remove the temporary Codex runtime home after three attempts: ${runtime_home}"
    return 1
}

harness_allow_all_detected() {
    return 1
}
