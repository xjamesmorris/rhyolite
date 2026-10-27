#!/usr/bin/env bash

set -euo pipefail
umask 077

stage=''
plugin_root=''
working_directory=''
input_path=''
result_path=''
model=''
reasoning_effort=''
context_tier=''

fail_stage() {
    printf 'Codex guided stage failed: %s\n' "$1" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --stage)
            [[ $# -ge 2 && -z "${stage}" ]] || fail_stage arguments
            stage="$2"
            shift 2
            ;;
        --plugin-root)
            [[ $# -ge 2 && -z "${plugin_root}" ]] || fail_stage arguments
            plugin_root="$2"
            shift 2
            ;;
        --working-directory)
            [[ $# -ge 2 && -z "${working_directory}" ]] || fail_stage arguments
            working_directory="$2"
            shift 2
            ;;
        --input)
            [[ $# -ge 2 && -z "${input_path}" ]] || fail_stage arguments
            input_path="$2"
            shift 2
            ;;
        --result)
            [[ $# -ge 2 && -z "${result_path}" ]] || fail_stage arguments
            result_path="$2"
            shift 2
            ;;
        --model)
            [[ $# -ge 2 && -z "${model}" ]] || fail_stage arguments
            model="$2"
            shift 2
            ;;
        --reasoning-effort)
            [[ $# -ge 2 && -z "${reasoning_effort}" ]] || fail_stage arguments
            reasoning_effort="$2"
            shift 2
            ;;
        --context)
            [[ $# -ge 2 && -z "${context_tier}" ]] || fail_stage arguments
            context_tier="$2"
            shift 2
            ;;
        *)
            fail_stage arguments
            ;;
    esac
done

case "${stage}" in setup|approval) ;; *) fail_stage stage ;; esac
[[ "${plugin_root}" == /* && -d "${plugin_root}" && ! -L "${plugin_root}" &&
    "${working_directory}" == /* && -d "${working_directory}" &&
    ! -L "${working_directory}" &&
    "${input_path}" == /* && -f "${input_path}" && ! -L "${input_path}" &&
    "${result_path}" == /* && ! -e "${result_path}" &&
    "${model}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ &&
    "${reasoning_effort}" =~ ^[a-z]{1,32}$ ]] || fail_stage validation
# The native questions need the user's terminal: input on stdin and the
# Codex UI on stderr, because stdout is reserved for the result path.
[[ -t 0 && -t 2 ]] || fail_stage terminal
# Workers run with TERM=dumb; only this interactive session keeps a usable
# terminal type.
stage_terminal_type="${TERM-}"
case "${stage_terminal_type}" in
    '' | dumb | unknown) stage_terminal_type='xterm-256color' ;;
esac
[[ "${stage_terminal_type}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]{0,63}$ ]] ||
    stage_terminal_type='xterm-256color'

common="${plugin_root}/lib/harness/common.sh"
adapter="${plugin_root}/lib/harness/codex.sh"
manifest="${plugin_root}/.codex-plugin/plugin.json"
skills="${plugin_root}/codex/skills"
for required in "${common}" "${adapter}" "${manifest}" "${skills}"; do
    [[ -e "${required}" && ! -L "${required}" ]] || fail_stage assets
done

source "${common}"
source "${adapter}"
harness_validate_model_id "${model}" || fail_stage model
harness_validate_reasoning_effort "${reasoning_effort}" || fail_stage effort
harness_validate_context_tier "${context_tier}" || fail_stage context
harness_prepare_run >/dev/null || fail_stage authentication
codex_bin="$(command -v codex)" || fail_stage cli
[[ "$("${codex_bin}" --version)" == 'codex-cli 0.163.0' ]] ||
    fail_stage version

stage_root="$(mktemp -d "${TMPDIR:-/tmp}/rhyolite-codex-guided.XXXXXXXX")"
runtime_home="${stage_root}/codex-home"
marketplace="${stage_root}/marketplace"
marketplace_plugin="${marketplace}/plugins/rhyolite"
cleanup_stage() {
    local status=$?
    trap - EXIT INT TERM HUP
    if [[ -n "${runtime_home-}" && -e "${runtime_home}" ]]; then
        harness_sanitize_runtime_home "${runtime_home}" >/dev/null 2>&1 || true
    fi
    if [[ -d "${stage_root}" && ! -L "${stage_root}" ]]; then
        chmod -R u+rwX -- "${stage_root}" 2>/dev/null || true
        rm -rf -- "${stage_root}" 2>/dev/null || true
    fi
    exit "${status}"
}
trap cleanup_stage EXIT INT TERM HUP
mkdir -p -- \
    "${runtime_home}" \
    "${marketplace}/.agents/plugins" \
    "${marketplace_plugin}"
chmod 700 -- "${stage_root}" "${runtime_home}" "${marketplace}" \
    "${marketplace}/.agents" "${marketplace}/.agents/plugins" \
    "${marketplace}/plugins" "${marketplace_plugin}"
harness_prepare_worker_home \
    "${runtime_home}" "${reasoning_effort}" "${context_tier}" review ||
    fail_stage runtime
cp -a -- "${plugin_root}/.codex-plugin" "${marketplace_plugin}/"
cp -a -- "${plugin_root}/codex" "${marketplace_plugin}/"
cat > "${marketplace}/.agents/plugins/marketplace.json" <<'JSON'
{
  "name": "rhyolite-guided",
  "plugins": [
    {
      "name": "rhyolite",
      "source": {
        "source": "local",
        "path": "./plugins/rhyolite"
      }
    }
  ]
}
JSON
chmod 600 -- "${marketplace}/.agents/plugins/marketplace.json"

mkdir -p -- "${runtime_home}/tmp"
chmod 700 -- "${runtime_home}/tmp"
declare -a stage_environment=()
codex_populate_worker_environment \
    stage_environment "${working_directory}" "${runtime_home}"
env "${stage_environment[@]}" \
    "${codex_bin}" plugin marketplace add \
    -c features.plugins=true \
    -c 'plugins._default.enabled=true' \
    "${marketplace}" --json \
    > "${stage_root}/marketplace-add.json" ||
    fail_stage marketplace
env "${stage_environment[@]}" \
    "${codex_bin}" plugin add \
    -c features.plugins=true \
    -c 'plugins._default.enabled=true' \
    rhyolite@rhyolite-guided --json \
    > "${stage_root}/plugin-add.json" ||
    fail_stage plugin
chmod 600 -- "${stage_root}/marketplace-add.json" "${stage_root}/plugin-add.json"

case "${stage}" in
    setup) skill='rhyolite:repo-review-setup' ;;
    approval) skill='rhyolite:repo-review-approval' ;;
esac
prompt="$(
    printf '$%s\n' "${skill}"
    cat -- "${input_path}"
)"
printf '%s\n' \
    'Complete the native Rhyolite questions. After the one-line JSON result appears, press Ctrl-D to return to the launcher.' >&2
set +e
# Keep the native UI on the terminal when the controller discards result stdout.
env "${stage_environment[@]}" "TERM=${stage_terminal_type}" \
    "${codex_bin}" \
    --no-daemon \
    --no-alt-screen \
    --strict-config \
    -c features.plugins=true \
    -c features.default_mode_request_user_input=true \
    -c tools.experimental_request_user_input.enabled=true \
    -c skills.include_instructions=true \
    -c features.worktrees=false \
    -c features.daemon_auto_start=false \
    -c 'plugins._default.enabled=false' \
    -c 'plugins."rhyolite@rhyolite-guided".enabled=true' \
    --sandbox read-only \
    --ask-for-approval never \
    --cd "${working_directory}" \
    --model "${model}" \
    "${prompt}" >&2
codex_status=$?
set -e
((codex_status == 0)) || fail_stage session

expected_context="$(codex_usable_context_window "${context_tier}")" ||
    fail_stage context
python3 -I - \
    "${runtime_home}" \
    "${stage}" \
    "${model}" \
    "${reasoning_effort}" \
    "${expected_context}" \
    "${result_path}" <<'PY' || fail_stage result
import json
import os
import pathlib
import re
import sys

root, stage, model, effort, context_text, result_name = sys.argv[1:7]
expected_context = int(context_text)
paths = sorted((pathlib.Path(root) / "sessions").glob("**/*.jsonl"))
if len(paths) != 1 or paths[0].is_symlink():
    raise SystemExit(1)
final_messages = []
turns = 0
contexts = set()
for raw in paths[0].read_bytes().split(b"\n"):
    if not raw.strip():
        continue
    try:
        record = json.loads(raw.decode("utf-8"))
    except (UnicodeError, ValueError):
        raise SystemExit(1)
    if not isinstance(record, dict):
        continue
    payload = record.get("payload")
    if not isinstance(payload, dict):
        continue
    if record.get("type") == "turn_context":
        turns += 1
        collaboration = payload.get("collaboration_mode")
        if (
            payload.get("model") != model
            or payload.get("effort") != effort
            or payload.get("approval_policy") != "never"
            or payload.get("sandbox_policy", {}).get("type") != "read-only"
            or not isinstance(collaboration, dict)
            or collaboration.get("mode") != "default"
            or payload.get("multi_agent_version") != "disabled"
        ):
            raise SystemExit(1)
    elif record.get("type") == "event_msg":
        if payload.get("type") == "task_started":
            value = payload.get("model_context_window")
            if type(value) is int:
                contexts.add(value)
        item = payload.get("item")
        if payload.get("type") == "item_completed" and isinstance(item, dict):
            item_type = str(item.get("type", ""))
            if item_type not in {"UserMessage", "AgentMessage"}:
                raise SystemExit(1)
    elif record.get("type") == "response_item":
        payload_type = payload.get("type")
        if payload_type == "function_call":
            if payload.get("name") != "request_user_input":
                raise SystemExit(1)
        elif payload_type == "message" and payload.get("role") == "assistant":
            if payload.get("phase") == "final_answer":
                text = "\n".join(
                    str(item.get("text", ""))
                    for item in payload.get("content", [])
                    if isinstance(item, dict)
                    and item.get("type") in {"text", "output_text", "Text"}
                )
                final_messages.append(text)
if turns == 0 or contexts != {expected_context} or not final_messages:
    raise SystemExit(1)
try:
    value = json.loads(final_messages[-1])
except ValueError:
    raise SystemExit(1)
if stage == "setup":
    keys = {
        "Protocol", "Action", "OutputRoot", "Scope",
        "ProvenanceLookbackMonths", "ResearchCookies",
    }
    if not isinstance(value, dict) or set(value) != keys:
        raise SystemExit(1)
    if value["Protocol"] != "RHYOLITE_CODEX_SETUP_V1":
        raise SystemExit(1)
    if value["Action"] == "cancel":
        if any(value[key] is not None for key in keys - {"Protocol", "Action"}):
            raise SystemExit(1)
    elif value["Action"] == "continue":
        output = value["OutputRoot"]
        scope = value["Scope"]
        lookback = value["ProvenanceLookbackMonths"]
        cookies = value["ResearchCookies"]
        if (
            not isinstance(output, str)
            or not output.startswith("/")
            or len(output.encode("utf-8")) > 4096
            or re.search(r"[\x00-\x1f\x7f]", output)
            or type(scope) is not int
            or scope not in {1, 2, 3}
            or (scope == 3) != (type(lookback) is int and 1 <= lookback <= 60)
            or (scope != 3 and lookback is not None)
            or (scope in {2, 3} and cookies not in {"off", "ephemeral"})
            or (scope == 1 and cookies is not None)
        ):
            raise SystemExit(1)
    else:
        raise SystemExit(1)
else:
    if (
        not isinstance(value, dict)
        or set(value) != {"Protocol", "Action", "ApprovalHash"}
        or value["Protocol"] != "RHYOLITE_CODEX_APPROVAL_V1"
        or value["Action"] not in {"run", "edit", "explain", "cancel"}
        or not isinstance(value["ApprovalHash"], str)
        or not re.fullmatch(r"[0-9a-f]{64}", value["ApprovalHash"])
    ):
        raise SystemExit(1)
destination = pathlib.Path(result_name)
descriptor = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
    json.dump(value, stream, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    stream.write("\n")
PY

printf '%s\n' "${result_path}"
