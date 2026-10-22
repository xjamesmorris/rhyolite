#!/usr/bin/env bash

set -euo pipefail
umask 077

plugin_root=''
working_directory=''
session_directory=''
model=''
reasoning_effort=''
context_tier=''
initial_output=''
declare -a repositories=()

fail_controller() {
    printf 'Codex guided review controller failed: %s\n' "$1" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --plugin-root)
            [[ $# -ge 2 && -z "${plugin_root}" ]] || fail_controller arguments
            plugin_root="$2"
            shift 2
            ;;
        --working-directory)
            [[ $# -ge 2 && -z "${working_directory}" ]] || fail_controller arguments
            working_directory="$2"
            shift 2
            ;;
        --session-directory)
            [[ $# -ge 2 && -z "${session_directory}" ]] || fail_controller arguments
            session_directory="$2"
            shift 2
            ;;
        --model)
            [[ $# -ge 2 && -z "${model}" ]] || fail_controller arguments
            model="$2"
            shift 2
            ;;
        --reasoning-effort)
            [[ $# -ge 2 && -z "${reasoning_effort}" ]] || fail_controller arguments
            reasoning_effort="$2"
            shift 2
            ;;
        --context)
            [[ $# -ge 2 && -z "${context_tier}" ]] || fail_controller arguments
            context_tier="$2"
            shift 2
            ;;
        --output-root)
            [[ $# -ge 2 && -z "${initial_output}" ]] || fail_controller arguments
            initial_output="$2"
            shift 2
            ;;
        --repo)
            [[ $# -ge 2 && -n "$2" ]] || fail_controller arguments
            repositories+=("$2")
            shift 2
            ;;
        *)
            fail_controller arguments
            ;;
    esac
done

[[ "${plugin_root}" == /* && -d "${plugin_root}" && ! -L "${plugin_root}" &&
    "${working_directory}" == /* && -d "${working_directory}" &&
    ! -L "${working_directory}" &&
    "${session_directory}" == /* && -d "${session_directory}" &&
    ! -L "${session_directory}" &&
    "${model}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ &&
    "${reasoning_effort}" =~ ^[a-z]{1,32}$ &&
    ${#repositories[@]} -gt 0 ]] || fail_controller validation

stage_helper="${plugin_root}/scripts/run-codex-guided-stage.sh"
runner="${plugin_root}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh"
[[ -x "${stage_helper}" && -x "${runner}" ]] || fail_controller assets

current_output="${initial_output:-NOT SELECTED}"
current_scope='NOT SELECTED'
current_lookback='NOT SELECTED'
current_cookies='NOT SELECTED'
setup_sequence=0
approval_sequence=0

read_setup_result() {
    local path="$1"
    local output=''

    output="$(
        python3 -I - "${path}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
for key in (
    "Action", "OutputRoot", "Scope",
    "ProvenanceLookbackMonths", "ResearchCookies",
):
    item = value[key]
    print("NULL" if item is None else item)
PY
    )" || return 1
    mapfile -t setup_values <<< "${output}"
    ((${#setup_values[@]} == 5)) || return 1
}

read_approval_result() {
    local path="$1"
    local expected_hash="$2"
    local output=''

    output="$(
        python3 -I - "${path}" "${expected_hash}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
if value["ApprovalHash"] != sys.argv[2]:
    raise SystemExit(1)
print(value["Action"])
PY
    )" || return 1
    approval_action="${output}"
}

print_scope_explanation() {
    printf '%s\n' \
        'Scope 1 covers source, history, architecture, quality, and a dedicated security pass with the lowest AI-credit use and only anonymous Git network access.' \
        'Scope 2 adds public prior-art/community research, public network requests, and materially higher resource use.' \
        'Scope 3 adds whole-repository provenance evidence gathering, uses the most model/subagent/network resources, and requires human review before sharing.' \
        'All timing ranges are rough and can increase substantially for large repositories or broad topics.'
}

print_run_status() {
    local run_folder="$1"
    local state_path="${run_folder}/state.json"

    if [[ -f "${state_path}" && ! -L "${state_path}" ]]; then
        python3 -I - "${state_path}" <<'PY' || true
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        value = json.load(stream)
except (OSError, ValueError):
    raise SystemExit(1)
print("RHYOLITE STATUS")
print(f"Run: {value.get('RunId', 'UNKNOWN')}")
print(f"Status: {value.get('Status', 'UNKNOWN')}")
repositories = value.get("Repositories")
if isinstance(repositories, list):
    counts = {}
    for repository in repositories:
        if isinstance(repository, dict):
            status = str(repository.get("Status", "UNKNOWN"))
            counts[status] = counts.get(status, 0) + 1
    if counts:
        print("Repositories: " + ", ".join(
            f"{key}={counts[key]}" for key in sorted(counts)
        ))
print(f"Output: {value.get('Paths', {}).get('WritableOutput', sys.argv[1][:-11])}")
PY
        return
    fi
    printf 'RHYOLITE STATUS\nStatus: STARTING\nOutput: %s\n' "${run_folder}"
}

while true; do
    setup_sequence=$((setup_sequence + 1))
    setup_input="${session_directory}/codex-setup-${setup_sequence}.txt"
    setup_result="${session_directory}/codex-setup-${setup_sequence}.json"
    rm -f -- "${setup_result}"
    {
        printf '%s\n' 'RHYOLITE_CODEX_SETUP_INPUT_V1'
        printf 'CurrentDirectoryOutput=%s/rhyolite-output/repo-review\n' \
            "${working_directory%/}"
        printf 'HomeDirectoryOutput=%s/rhyolite-output/repo-review\n' \
            "${HOME%/}"
        printf 'CurrentOutput=%s\n' "${current_output}"
        printf 'CurrentScope=%s\n' "${current_scope}"
        printf 'CurrentProvenanceLookbackMonths=%s\n' "${current_lookback}"
        printf 'CurrentResearchCookies=%s\n' "${current_cookies}"
        printf '%s\n' 'END_RHYOLITE_CODEX_SETUP_INPUT_V1'
    } > "${setup_input}"
    chmod 600 -- "${setup_input}"
    "${stage_helper}" \
        --stage setup \
        --plugin-root "${plugin_root}" \
        --working-directory "${working_directory}" \
        --input "${setup_input}" \
        --result "${setup_result}" \
        --model "${model}" \
        --reasoning-effort "${reasoning_effort}" \
        --context "${context_tier}" >/dev/null ||
        fail_controller setup
    read_setup_result "${setup_result}" || fail_controller setup-result
    [[ "${setup_values[0]}" != cancel ]] || exit 0
    [[ "${setup_values[0]}" == continue ]] || fail_controller setup-action
    current_output="${setup_values[1]}"
    current_scope="${setup_values[2]}"
    current_lookback="${setup_values[3]}"
    current_cookies="${setup_values[4]}"

    declare -a runner_arguments=(
        --harness codex
        --fleet-mode standard
        --model "${model}"
        --reasoning-effort "${reasoning_effort}"
        --context "${context_tier}"
        --output-root "${current_output}"
        --scope "${current_scope}"
        --remember-preferences
        --non-interactive
        --no-open-html
    )
    for repository in "${repositories[@]}"; do
        runner_arguments+=(--repo "${repository}")
    done
    if [[ "${current_scope}" == 3 ]]; then
        runner_arguments+=(--provenance-lookback-months "${current_lookback}")
    fi
    if [[ "${current_scope}" == 2 || "${current_scope}" == 3 ]]; then
        runner_arguments+=(--research-cookies "${current_cookies}")
    fi

    plan_path="${session_directory}/codex-plan-${setup_sequence}.json"
    plan_error="${session_directory}/codex-plan-${setup_sequence}.stderr"
    if ! /usr/bin/bash "${runner}" \
        "${runner_arguments[@]}" \
        --plan-only > "${plan_path}" 2> "${plan_error}"; then
        cat -- "${plan_error}" >&2
        fail_controller plan
    fi
    chmod 600 -- "${plan_path}" "${plan_error}"
    approval_hash="$(
        python3 -I - "${plan_path}" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
approval = value.get("ApprovalHash")
if not isinstance(approval, str) or not re.fullmatch(r"[0-9a-f]{64}", approval):
    raise SystemExit(1)
print(approval)
PY
    )" || fail_controller plan-hash
    printf '\nEFFECTIVE REVIEW PLAN\n'
    python3 -I - "${plan_path}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
print(json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True))
PY

    while true; do
        approval_sequence=$((approval_sequence + 1))
        approval_input="${session_directory}/codex-approval-${approval_sequence}.txt"
        approval_result="${session_directory}/codex-approval-${approval_sequence}.json"
        rm -f -- "${approval_result}"
        {
            printf '%s\n' 'RHYOLITE_CODEX_APPROVAL_INPUT_V1'
            printf 'ApprovalHash=%s\n' "${approval_hash}"
            printf 'Scope=%s\n' "${current_scope}"
            printf '%s\n' 'END_RHYOLITE_CODEX_APPROVAL_INPUT_V1'
        } > "${approval_input}"
        chmod 600 -- "${approval_input}"
        "${stage_helper}" \
            --stage approval \
            --plugin-root "${plugin_root}" \
            --working-directory "${working_directory}" \
            --input "${approval_input}" \
            --result "${approval_result}" \
            --model "${model}" \
            --reasoning-effort "${reasoning_effort}" \
            --context "${context_tier}" >/dev/null ||
            fail_controller approval
        read_approval_result "${approval_result}" "${approval_hash}" ||
            fail_controller approval-result
        case "${approval_action}" in
            run)
                execution_stdout="${session_directory}/codex-run.stdout"
                execution_stderr="${session_directory}/codex-run.stderr"
                : > "${execution_stdout}"
                : > "${execution_stderr}"
                active_run_folder=''
                stop_requested=0
                runner_pid=''
                controller_input=1
                stop_active_runner() {
                    local reason="$1"

                    ((stop_requested == 0)) || return 0
                    stop_requested=1
                    if [[ -n "${active_run_folder}" ]]; then
                        printf 'Stopping Rhyolite review (%s)...\n' "${reason}" >&2
                        /usr/bin/bash "${runner}" \
                            --harness codex \
                            --request-stop "${active_run_folder}" ||
                            true
                    elif [[ -n "${runner_pid}" ]] &&
                        kill -0 "${runner_pid}" 2>/dev/null; then
                        kill -TERM "${runner_pid}" 2>/dev/null || true
                    fi
                }
                trap 'stop_active_runner signal' INT TERM HUP
                if [[ -t 0 ]]; then
                    printf '%s\n' \
                        'Review started. Type exact stop or cancel to interrupt, or /rhyolite:status for current state.' >&2
                fi
                set +e
                /usr/bin/bash "${runner}" \
                    "${runner_arguments[@]}" \
                    --expected-plan-hash "${approval_hash}" \
                    > >(tee "${execution_stdout}") \
                    2> >(tee "${execution_stderr}" >&2) &
                runner_pid=$!
                while kill -0 "${runner_pid}" 2>/dev/null; do
                    if [[ -z "${active_run_folder}" ]]; then
                        active_run_folder="$(
                            sed -n \
                                's/^RHYOLITE PROGRESS | run | started | .* output //p' \
                                "${execution_stdout}" |
                                tail -n 1
                        )"
                    fi
                    if ((controller_input)); then
                        command=''
                        IFS= read -r -t 1 command
                        read_status=$?
                        if ((read_status == 0)); then
                            case "${command}" in
                                stop|cancel)
                                    stop_active_runner "${command}"
                                    ;;
                                /rhyolite:status)
                                    if [[ -n "${active_run_folder}" ]]; then
                                        print_run_status "${active_run_folder}"
                                    else
                                        printf '%s\n' \
                                            'RHYOLITE STATUS' \
                                            'Status: STARTING' \
                                            'Output: NOT AVAILABLE YET'
                                    fi
                                    ;;
                                '')
                                    ;;
                                *)
                                    printf '%s\n' \
                                        'During review execution, enter exact stop, cancel, or /rhyolite:status.' >&2
                                    ;;
                            esac
                        elif ((read_status == 1)); then
                            controller_input=0
                        fi
                    else
                        sleep 1
                    fi
                done
                wait "${runner_pid}"
                execution_status=$?
                set -e
                trap - INT TERM HUP
                if ((execution_status == 0)); then
                    exit 0
                fi
                if ((stop_requested)); then
                    printf '%s\n' 'Rhyolite review stopped.' >&2
                    exit 0
                fi
                if grep -Fq \
                    'approved plan changed; regenerate and reconfirm' \
                    "${execution_stderr}"; then
                    printf '%s\n' \
                        'The approved effective plan changed; regenerating it with the preserved setup.' >&2
                    break
                fi
                exit "${execution_status}"
                ;;
            edit)
                break
                ;;
            explain)
                print_scope_explanation
                continue
                ;;
            cancel)
                exit 0
                ;;
            *)
                fail_controller approval-action
                ;;
        esac
        break
    done
done
