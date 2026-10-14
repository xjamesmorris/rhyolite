#!/usr/bin/env bash

RHYOLITE_HARNESS_CONTRACT_VERSION=8
RHYOLITE_HARNESS_ERROR_DETAIL=''
RHYOLITE_HARNESS_LAST_STATUS=0
# harness_validate_model_id returns this status only for a safe model ID that
# is absent from the offline catalog and eligible for explicit operator opt-in.
RHYOLITE_HARNESS_MODEL_UNLISTED_STATUS=3
# harness_detect_worker_violation returns this status when the output a
# running worker has recorded so far already names a model, reasoning effort,
# or subagent other than the approved plan; the runner then terminates the
# worker instead of waiting for it to finish.
RHYOLITE_HARNESS_WORKER_VIOLATION_STATUS=4
# harness_worker_outcome writes one JSON object with exactly these keys so the
# runner can decide, deterministically, whether a worker invocation may be
# continued in the same session (transient model-service failure, or an
# automatic model fallback that was blocked before it produced any output).
RHYOLITE_HARNESS_OUTCOME_SCHEMA=1
RHYOLITE_HARNESS_OUTCOMES=(completed transient-failure fallback-blocked substituted failed unknown)
# Exact phase names accepted by harness_normalize_worker_output and
# harness_detect_worker_violation.
RHYOLITE_HARNESS_WORKER_PHASES=(review research report-repair)
RHYOLITE_HARNESS_LOADED_ID=''
RHYOLITE_HARNESS_LOADED_PATH=''
RHYOLITE_HARNESS_REQUIRED_FUNCTIONS=(
    harness_id
    harness_display_name
    harness_cli_name
    harness_require_cli
    harness_capability
    harness_default_model
    harness_list_models
    harness_validate_model_id
    harness_model_choices
    harness_max_reasoning_effort
    harness_reasoning_effort_choices
    harness_validate_reasoning_effort
    harness_default_context_tier
    harness_context_choices
    harness_validate_context_tier
    harness_auth_secret_env_vars
    harness_login_remediation
    harness_provider_summary
    harness_resume_policy
    harness_prepare_run
    harness_prepare_worker_home
    harness_worker_argv
    harness_worker_env
    harness_report_repair_argv
    harness_report_repair_env
    harness_write_research_mcp_config
    harness_research_worker_argv
    harness_research_worker_env
    harness_finalize_research_session
    harness_normalize_worker_output
    harness_detect_worker_violation
    harness_worker_outcome
    harness_worker_continuation_argv
    harness_render_request
    harness_extract_final_report
    harness_extract_report_repair
    harness_verify_isolation
    harness_persist_agent_state
    harness_sanitize_runtime_home
    harness_allow_all_detected
)

rhyolite_harness_list_registered() {
    printf '%s\n' copilot claude
}

rhyolite_harness_set_error() {
    RHYOLITE_HARNESS_ERROR_DETAIL="$1"
    return 1
}

rhyolite_harness_valid_id() {
    [[ "$1" =~ ^[a-z][a-z0-9-]{0,31}$ ]]
}

# Every adapter translates its CLI's raw worker stdout into a readable
# narrative plus the exact final assistant reply through
# harness_normalize_worker_output <phase> <raw_output> <approved_model>
# <approved_effort> <normalized_output> <final_reply_output>. These helpers
# validate the shared argument contract and implement the identity case for a
# CLI whose print mode writes the exact final reply to stdout.
rhyolite_harness_valid_worker_phase() {
    local candidate="$1"
    local phase

    for phase in "${RHYOLITE_HARNESS_WORKER_PHASES[@]}"; do
        [[ "${candidate}" != "${phase}" ]] || return 0
    done
    return 1
}

rhyolite_harness_validate_normalize_arguments() {
    local phase="$1"
    local raw_output="$2"
    local approved_model="$3"
    local approved_effort="$4"
    local normalized_output="$5"
    local final_reply_output="$6"

    rhyolite_harness_valid_worker_phase "${phase}" || {
        rhyolite_harness_set_error \
            'The worker output normalization phase is unsupported.'
        return 1
    }
    [[ "${approved_model}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ &&
        "${approved_effort}" =~ ^[a-z]{1,32}$ ]] || {
        rhyolite_harness_set_error \
            'The approved model or reasoning effort for worker output normalization is invalid.'
        return 1
    }
    [[ "${raw_output}" == /* && -f "${raw_output}" && ! -L "${raw_output}" &&
        "${normalized_output}" == /* && ! -e "${normalized_output}" &&
        ! -L "${normalized_output}" &&
        "${final_reply_output}" == /* && ! -e "${final_reply_output}" &&
        ! -L "${final_reply_output}" &&
        "${normalized_output}" != "${final_reply_output}" &&
        "${raw_output}" != "${normalized_output}" &&
        "${raw_output}" != "${final_reply_output}" ]] || {
        rhyolite_harness_set_error \
            'The worker output normalization paths are invalid.'
        return 1
    }
}

rhyolite_harness_normalize_worker_output_identity() {
    local raw_output="$2"
    local normalized_output="$5"
    local final_reply_output="$6"

    rhyolite_harness_validate_normalize_arguments "$@" || return 1
    if ! (
        umask 077
        cat -- "${raw_output}" > "${normalized_output}" &&
            cat -- "${raw_output}" > "${final_reply_output}" &&
            chmod 600 -- "${normalized_output}" "${final_reply_output}"
    ); then
        rm -f -- "${normalized_output}" "${final_reply_output}"
        rhyolite_harness_set_error \
            'Could not preserve the exact worker reply during output normalization.'
        return 1
    fi
}

# While a worker is still running, the runner periodically asks the adapter
# through harness_detect_worker_violation <phase> <raw_output> <approved_model>
# <approved_effort> <cursor_path> whether the output recorded so far already
# shows a model, reasoning effort, or subagent other than the approved plan.
# The adapter scans only the complete lines appended since the offset saved in
# the runner-owned cursor file, returns 0 when nothing is recorded yet, returns
# RHYOLITE_HARNESS_WORKER_VIOLATION_STATUS with a sanitized detail on the first
# violation, and returns 1 for any other failure, which the runner treats as a
# monitor warning; the post-exit normalization remains authoritative.
rhyolite_harness_validate_violation_arguments() {
    local phase="$1"
    local raw_output="$2"
    local approved_model="$3"
    local approved_effort="$4"
    local cursor_path="$5"

    rhyolite_harness_valid_worker_phase "${phase}" || {
        rhyolite_harness_set_error \
            'The worker output violation-detection phase is unsupported.'
        return 1
    }
    [[ "${approved_model}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ &&
        "${approved_effort}" =~ ^[a-z]{1,32}$ ]] || {
        rhyolite_harness_set_error \
            'The approved model or reasoning effort for worker violation detection is invalid.'
        return 1
    }
    [[ "${raw_output}" == /* && ! -L "${raw_output}" &&
        "${cursor_path}" == /* && ! -L "${cursor_path}" &&
        "${cursor_path}" != "${raw_output}" &&
        -d "${cursor_path%/*}" && ! -L "${cursor_path%/*}" ]] || {
        rhyolite_harness_set_error \
            'The worker violation-detection paths are invalid.'
        return 1
    }
}

# Shared implementation for an adapter whose CLI records no model, effort, or
# subagent evidence while the worker runs. It validates the contract arguments
# and reports nothing, so enforcement happens once the worker exits.
rhyolite_harness_detect_worker_violation_none() {
    rhyolite_harness_validate_violation_arguments "$@" || return 1
    return 0
}

# After every worker invocation the runner asks the adapter through
# harness_worker_outcome <phase> <raw_output> <runtime_home> <session_id>
# <approved_model> <approved_effort> <outcome_output> to classify what
# happened. The adapter
# writes one JSON object; rhyolite_harness_validate_outcome_json checks it
# before the runner uses any value, so adapter output stays data.
rhyolite_harness_validate_outcome_arguments() {
    local phase="$1"
    local raw_output="$2"
    local runtime_home="$3"
    local session_id="$4"
    local approved_model="$5"
    local approved_effort="$6"
    local outcome_output="$7"

    rhyolite_harness_valid_worker_phase "${phase}" || {
        rhyolite_harness_set_error \
            'The worker outcome phase is unsupported.'
        return 1
    }
    [[ "${approved_model}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ &&
        "${approved_effort}" =~ ^[a-z]{1,32}$ &&
        "${session_id}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || {
        rhyolite_harness_set_error \
            'The approved model, effort, or session identifier for the worker outcome is invalid.'
        return 1
    }
    [[ "${raw_output}" == /* && -f "${raw_output}" && ! -L "${raw_output}" &&
        "${runtime_home}" == /* && ! -L "${runtime_home}" &&
        "${outcome_output}" == /* && ! -e "${outcome_output}" &&
        ! -L "${outcome_output}" &&
        "${outcome_output}" != "${raw_output}" ]] || {
        rhyolite_harness_set_error \
            'The worker outcome paths are invalid.'
        return 1
    }
}

# Shared implementation for an adapter whose CLI records no structured
# outcome evidence: the runner then never continues the session.
rhyolite_harness_worker_outcome_unknown() {
    local phase="$1"
    local outcome_output="$7"

    rhyolite_harness_validate_outcome_arguments "$@" || return 1
    (
        umask 077
        printf '{"Schema":1,"Phase":"%s","Outcome":"unknown","Retryable":false,"ExitCode":null,"SessionErrors":[],"ModelCallFailures":0,"TurnRetries":0,"OutputLimitHits":0,"OutputTokenLimit":null,"FinalReplyAtOutputLimit":false,"FallbackModel":""}\n' \
            "${phase}" > "${outcome_output}"
    ) || {
        rhyolite_harness_set_error 'Could not write the worker outcome.'
        return 1
    }
}

# Strictly validate an adapter-written worker outcome before the runner uses
# it. Prints the validated outcome token on success.
rhyolite_harness_validate_outcome_json() {
    local outcome_path="$1"
    local expected_phase="$2"

    [[ -f "${outcome_path}" && ! -L "${outcome_path}" ]] || return 1
    python3 - "${outcome_path}" "${expected_phase}" <<'PY'
import json
import re
import sys

path, phase = sys.argv[1:3]
keys = {
    "Schema", "Phase", "Outcome", "Retryable", "ExitCode", "SessionErrors",
    "ModelCallFailures", "TurnRetries", "OutputLimitHits", "OutputTokenLimit",
    "FinalReplyAtOutputLimit", "FallbackModel",
}
outcomes = {
    "completed", "transient-failure", "fallback-blocked", "substituted",
    "failed", "unknown",
}
try:
    with open(path, encoding="utf-8") as stream:
        data = json.load(stream)
except (OSError, UnicodeError, ValueError):
    raise SystemExit(1)


def count(value):
    return type(value) is int and 0 <= value <= 1000000


if (
    not isinstance(data, dict)
    or set(data) != keys
    or data["Schema"] != 1
    or data["Phase"] != phase
    or data["Outcome"] not in outcomes
    or type(data["Retryable"]) is not bool
    or data["Retryable"] != (data["Outcome"] in ("transient-failure", "fallback-blocked"))
    or not (data["ExitCode"] is None or (type(data["ExitCode"]) is int and -1 <= data["ExitCode"] <= 255))
    or not isinstance(data["SessionErrors"], list)
    or len(data["SessionErrors"]) > 5
    or any(
        not isinstance(item, str)
        or not 0 < len(item) <= 400
        or re.search(r"[\x00-\x1f\x7f]", item)
        for item in data["SessionErrors"]
    )
    or not all(count(data[key]) for key in ("ModelCallFailures", "TurnRetries", "OutputLimitHits"))
    or not (data["OutputTokenLimit"] is None or count(data["OutputTokenLimit"]))
    or type(data["FinalReplyAtOutputLimit"]) is not bool
    or not isinstance(data["FallbackModel"], str)
    or not re.fullmatch(r"(?:[A-Za-z0-9][A-Za-z0-9._:-]{0,127})?", data["FallbackModel"])
    or (data["Outcome"] == "fallback-blocked") != bool(data["FallbackModel"])
):
    raise SystemExit(1)
print(data["Outcome"])
PY
}

rhyolite_harness_capture() {
    local output_variable="$1"
    local function_name="$2"
    local captured_output
    shift 2

    RHYOLITE_HARNESS_ERROR_DETAIL=''
    if [[ ! "${output_variable}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
        [[ ! "${function_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
        ! declare -F "${function_name}" >/dev/null 2>&1; then
        RHYOLITE_HARNESS_ERROR_DETAIL="Harness adapter call '${function_name}' is unavailable or invalid."
        return 1
    fi
    if ! captured_output="$("${function_name}" "$@" 2>/dev/null)"; then
        RHYOLITE_HARNESS_ERROR_DETAIL="Harness adapter function '${function_name}' failed."
        return 1
    fi
    printf -v "${output_variable}" '%s' "${captured_output}"
}

rhyolite_harness_invoke() {
    local function_name="$1"
    local function_status=0
    shift

    RHYOLITE_HARNESS_ERROR_DETAIL=''
    RHYOLITE_HARNESS_LAST_STATUS=0
    if [[ ! "${function_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] ||
        ! declare -F "${function_name}" >/dev/null 2>&1; then
        RHYOLITE_HARNESS_ERROR_DETAIL="Harness adapter call '${function_name}' is unavailable or invalid."
        RHYOLITE_HARNESS_LAST_STATUS=1
        return 1
    fi
    "${function_name}" "$@" || function_status=$?
    RHYOLITE_HARNESS_LAST_STATUS="${function_status}"
    if ((function_status == 0)); then
        return 0
    fi
    if [[ -z "${RHYOLITE_HARNESS_ERROR_DETAIL}" ]]; then
        RHYOLITE_HARNESS_ERROR_DETAIL="Harness adapter function '${function_name}' failed."
    fi
    return 1
}

rhyolite_harness_resolve() {
    local explicit_harness="${1-}"
    local selected_harness

    RHYOLITE_HARNESS_ERROR_DETAIL=''
    if [[ -n "${explicit_harness}" ]]; then
        selected_harness="${explicit_harness}"
    elif [[ ${RHYOLITE_HARNESS+x} ]]; then
        selected_harness="${RHYOLITE_HARNESS}"
    else
        selected_harness='copilot'
    fi

    if ! rhyolite_harness_valid_id "${selected_harness}"; then
        rhyolite_harness_set_error \
            'The selected harness identifier is empty or contains unsupported characters.'
        return 1
    fi

    printf '%s\n' "${selected_harness}"
}

rhyolite_harness_validate_context() {
    local selected_harness="$1"
    local launcher_harness

    RHYOLITE_HARNESS_ERROR_DETAIL=''
    if ! rhyolite_harness_valid_id "${selected_harness}"; then
        rhyolite_harness_set_error \
            'The selected harness identifier is empty or contains unsupported characters.'
        return 1
    fi
    if [[ ! ${RHYOLITE_LAUNCHER_HARNESS+x} ]]; then
        return 0
    fi

    launcher_harness="${RHYOLITE_LAUNCHER_HARNESS}"
    if ! rhyolite_harness_valid_id "${launcher_harness}"; then
        rhyolite_harness_set_error \
            'The launcher harness marker is empty or contains unsupported characters.'
        return 1
    fi
    if [[ "${launcher_harness}" != "${selected_harness}" ]]; then
        rhyolite_harness_set_error \
            "Launcher harness '${launcher_harness}' does not match selected harness '${selected_harness}'."
        return 1
    fi
}

rhyolite_harness_registry_lookup() {
    local output_variable="$1"
    local plugin_root="$2"
    local selected_harness="$3"

    if [[ ! "${output_variable}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        rhyolite_harness_set_error \
            'The harness registry output variable is invalid.'
        return 1
    fi

    case "${selected_harness}" in
        copilot)
            printf -v "${output_variable}" '%s' \
                "${plugin_root%/}/lib/harness/copilot.sh"
            ;;
        claude)
            printf -v "${output_variable}" '%s' \
                "${plugin_root%/}/lib/harness/claude.sh"
            ;;
        *)
            rhyolite_harness_set_error \
                "Harness '${selected_harness}' is not supported by this Rhyolite installation."
            return 1
            ;;
    esac
}

rhyolite_harness_load() {
    local plugin_root="$1"
    local selected_harness="$2"
    local adapter_path
    local required_function
    local loaded_id
    local capability
    local capability_result

    RHYOLITE_HARNESS_ERROR_DETAIL=''
    RHYOLITE_HARNESS_LOADED_ID=''
    RHYOLITE_HARNESS_LOADED_PATH=''
    rhyolite_harness_validate_context "${selected_harness}" || return 1

    rhyolite_harness_registry_lookup \
        adapter_path "${plugin_root}" "${selected_harness}" || return 1

    if [[ ! -f "${adapter_path}" || ! -r "${adapter_path}" ]]; then
        rhyolite_harness_set_error \
            "Harness adapter '${selected_harness}' is missing or unreadable."
        return 1
    fi

    for required_function in "${RHYOLITE_HARNESS_REQUIRED_FUNCTIONS[@]}"; do
        unset -f "${required_function}" 2>/dev/null || true
    done

    # Adapter paths are selected only by the fixed mapping above.
    if ! source "${adapter_path}" >/dev/null 2>&1; then
        rhyolite_harness_set_error \
            "Harness adapter '${selected_harness}' could not be sourced."
        return 1
    fi

    for required_function in "${RHYOLITE_HARNESS_REQUIRED_FUNCTIONS[@]}"; do
        if ! declare -F "${required_function}" >/dev/null 2>&1; then
            rhyolite_harness_set_error \
                "Harness adapter '${selected_harness}' is incomplete: missing ${required_function}."
            return 1
        fi
    done

    if ! rhyolite_harness_capture loaded_id harness_id; then
        rhyolite_harness_set_error \
            "Harness adapter '${selected_harness}' could not report its identifier."
        return 1
    fi
    if [[ "${loaded_id}" != "${selected_harness}" ]]; then
        rhyolite_harness_set_error \
            "Harness adapter '${selected_harness}' reported identifier '${loaded_id}'."
        return 1
    fi

    for capability in \
        fleet \
        structured_questions \
        subagents \
        builtin_security_specialist \
        builtin_research_specialist \
        web_research \
        shell_denial \
        final_message_file \
        worker_continuation; do
        if ! rhyolite_harness_capture \
            capability_result harness_capability "${capability}"; then
            rhyolite_harness_set_error \
                "Harness adapter '${selected_harness}' could not report capability '${capability}'."
            return 1
        fi
        case "${capability_result}" in
            yes|no|unverified) ;;
            *)
                rhyolite_harness_set_error \
                    "Harness adapter '${selected_harness}' returned an invalid capability result for '${capability}'."
                return 1
                ;;
        esac
    done

    RHYOLITE_HARNESS_LOADED_ID="${selected_harness}"
    RHYOLITE_HARNESS_LOADED_PATH="${adapter_path}"
}
