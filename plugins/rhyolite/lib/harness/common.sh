#!/usr/bin/env bash

RHYOLITE_HARNESS_CONTRACT_VERSION=2
RHYOLITE_HARNESS_ERROR_DETAIL=''
RHYOLITE_HARNESS_LAST_STATUS=0
RHYOLITE_HARNESS_LOADED_ID=''
RHYOLITE_HARNESS_LOADED_PATH=''
RHYOLITE_HARNESS_REQUIRED_FUNCTIONS=(
    harness_id
    harness_display_name
    harness_cli_name
    harness_require_cli
    harness_capability
    harness_default_model
    harness_validate_model_id
    harness_model_choices
    harness_max_reasoning_effort
    harness_auth_secret_env_vars
    harness_login_remediation
    harness_provider_summary
    harness_resume_policy
    harness_prepare_run
    harness_prepare_worker_home
    harness_worker_argv
    harness_worker_env
    harness_render_request
    harness_extract_final_report
    harness_verify_isolation
    harness_persist_agent_state
    harness_sanitize_runtime_home
    harness_allow_all_detected
)

rhyolite_harness_set_error() {
    RHYOLITE_HARNESS_ERROR_DETAIL="$1"
    return 1
}

rhyolite_harness_valid_id() {
    [[ "$1" =~ ^[a-z][a-z0-9-]{0,31}$ ]]
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
        final_message_file; do
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
