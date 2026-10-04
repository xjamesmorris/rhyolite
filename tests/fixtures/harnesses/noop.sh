#!/usr/bin/env bash

NOOP_RUNTIME_HOME=''
NOOP_WORKER_DIRECTORY=''

noop_fixture_require_success() {
    local function_name="$1"

    if [[ "${RHYOLITE_NOOP_FAIL_FUNCTION:-}" == "${function_name}" ]]; then
        rhyolite_harness_set_error \
            "Development-only no-op fixture injected failure in ${function_name}."
        return 1
    fi
}

noop_fixture_resolve_worker() {
    local worker_path

    worker_path="$(command -v noop-worker || true)"
    if [[ -z "${worker_path}" || ! -x "${worker_path}" ]]; then
        rhyolite_harness_set_error \
            'The development-only noop-worker fixture is required.'
        return 1
    fi
    NOOP_WORKER_DIRECTORY="$(
        cd -- "$(dirname -- "${worker_path}")" && pwd
    )"
}

harness_id() {
    noop_fixture_require_success harness_id || return 1
    printf '%s\n' 'noop'
}

harness_display_name() {
    noop_fixture_require_success harness_display_name || return 1
    printf '%s\n' 'Development No-op Fixture'
}

harness_cli_name() {
    noop_fixture_require_success harness_cli_name || return 1
    printf '%s\n' 'noop-worker'
}

harness_require_cli() {
    noop_fixture_require_success harness_require_cli || return 1
    noop_fixture_resolve_worker
}

harness_capability() {
    noop_fixture_require_success harness_capability || return 1
    case "$1" in
        shell_denial|final_message_file)
            printf '%s\n' 'yes'
            ;;
        fleet|structured_questions|subagents|builtin_security_specialist|builtin_research_specialist|web_research)
            printf '%s\n' 'no'
            ;;
        *)
            printf '%s\n' 'unverified'
            ;;
    esac
}

harness_default_model() {
    noop_fixture_require_success harness_default_model || return 1
    printf '%s\n' 'noop-fixture-model'
}

harness_list_models() {
    noop_fixture_require_success harness_list_models || return 1
    printf '%s\n' 'noop-fixture-model'
}

harness_validate_model_id() {
    noop_fixture_require_success harness_validate_model_id || return 1
    [[ "$1" == 'noop-fixture-model' ]]
}

harness_model_choices() {
    noop_fixture_require_success harness_model_choices || return 1
    printf '%s\n' \
        'Development no-op fixture (diagnostic only) - noop-fixture-model'
}

harness_max_reasoning_effort() {
    noop_fixture_require_success harness_max_reasoning_effort || return 1
    harness_validate_model_id "$1" || return 1
    printf '%s\n' 'max'
}

harness_reasoning_effort_choices() {
    noop_fixture_require_success harness_reasoning_effort_choices || return 1
    printf '%s\n' 'Maximum reasoning (diagnostic only) - max'
}

harness_validate_reasoning_effort() {
    noop_fixture_require_success harness_validate_reasoning_effort || return 1
    [[ "$1" == max ]]
}

harness_default_context_tier() {
    noop_fixture_require_success harness_default_context_tier || return 1
    printf '%s\n' 'long_context'
}

harness_context_choices() {
    noop_fixture_require_success harness_context_choices || return 1
    printf '%s\n' 'Long context (diagnostic only) - long_context'
}

harness_validate_context_tier() {
    noop_fixture_require_success harness_validate_context_tier || return 1
    [[ "$1" == long_context ]]
}

harness_auth_secret_env_vars() {
    noop_fixture_require_success harness_auth_secret_env_vars || return 1
    return 0
}

harness_login_remediation() {
    noop_fixture_require_success harness_login_remediation || return 1
    printf '%s\n' \
        'This development-only no-op fixture requires no authentication and must never be used for a real review.'
}

harness_provider_summary() {
    noop_fixture_require_success harness_provider_summary || return 1
    printf '%s\n' \
        '{"Id":"fixture-noop","Host":"fixture.invalid","ForwardedEnvVarNames":[]}'
}

harness_resume_policy() {
    noop_fixture_require_success harness_resume_policy || return 1
    printf '%s\n' \
        'Do not resume this development-only no-op fixture; rerun the focused harness contract validator.'
}

harness_prepare_run() {
    noop_fixture_require_success harness_prepare_run || return 1
    if [[ -z "${NOOP_WORKER_DIRECTORY}" ]]; then
        noop_fixture_resolve_worker || return 1
    fi
}

harness_prepare_worker_home() {
    local runtime_home="$1"
    local reasoning_effort="$2"
    local context_tier="$3"

    noop_fixture_require_success harness_prepare_worker_home || return 1
    [[ "${reasoning_effort}" == max && "${context_tier}" == long_context ]] ||
        return 1
    [[ -d "${runtime_home}" ]] || {
        rhyolite_harness_set_error \
            'The no-op fixture runtime home was not created by the runner.'
        return 1
    }
    chmod 700 -- "${runtime_home}" || {
        rhyolite_harness_set_error \
            'Could not restrict the no-op fixture runtime home.'
        return 1
    }
    printf '%s\n' '{"Fixture":"noop","Purpose":"contract-proof"}' \
        > "${runtime_home}/fixture-runtime.json" || {
        rhyolite_harness_set_error \
            'Could not write the no-op fixture runtime marker.'
        return 1
    }
    chmod 600 -- "${runtime_home}/fixture-runtime.json" || {
        rhyolite_harness_set_error \
            'Could not restrict the no-op fixture runtime marker.'
        return 1
    }
    NOOP_RUNTIME_HOME="${runtime_home}"
}

harness_worker_argv() {
    local -n output_arguments="$1"
    local session_name="$4"
    local session_id="$5"
    local model="$6"
    local reasoning_effort="$7"
    local context_tier="$8"
    local authentication_variables="$9"
    local transcript_path="${11}"

    noop_fixture_require_success harness_worker_argv || return 1
    [[ -z "${authentication_variables}" ]] || {
        rhyolite_harness_set_error \
            'The no-op fixture received an unexpected authentication allowlist.'
        return 1
    }
    output_arguments=(
        --fixture-contract 2
        --session-name "${session_name}"
        --session-id "${session_id}"
        --model "${model}"
        --reasoning-effort "${reasoning_effort}"
        --context "${context_tier}"
        --transcript "${transcript_path}"
    )
}

harness_worker_env() {
    local -n output_environment="$1"

    noop_fixture_require_success harness_worker_env || return 1
    [[ -n "${NOOP_RUNTIME_HOME}" && -n "${NOOP_WORKER_DIRECTORY}" ]] || {
        rhyolite_harness_set_error \
            'The no-op fixture runtime environment is incomplete.'
        return 1
    }
    output_environment=(
        -i
        "PATH=${NOOP_WORKER_DIRECTORY}:/usr/bin:/bin"
        "HOME=${NOOP_RUNTIME_HOME}"
        "XDG_CONFIG_HOME=${NOOP_RUNTIME_HOME}"
        'LC_ALL=C'
        "NOOP_RUNTIME_HOME=${NOOP_RUNTIME_HOME}"
        "NOOP_CAPTURE_ROOT=${RHYOLITE_NOOP_CAPTURE_ROOT:-}"
    )
}

harness_render_request() {
    local request_path="$2"

    noop_fixture_require_success harness_render_request || return 1
    cat > "${request_path}" <<'EOF'
RHYOLITE DEVELOPMENT-ONLY NO-OP HARNESS REQUEST

This fixture intentionally receives no repository URL, snapshot path, commit,
metadata, research evidence, credentials, or useful analysis instructions.
It must ignore repository contents and emit only its deterministic diagnostic
canonical report.
EOF
}

harness_extract_final_report() {
    local transcript="$2"
    local final_message="$3"
    local report="$4"
    local extraction_status=0

    noop_fixture_require_success harness_extract_final_report || return 1
    if ! awk '
        $0 == "### NOOP FIXTURE FINAL RESPONSE" {
            capture = 1
            found = 1
            next
        }
        $0 == "### END NOOP FIXTURE FINAL RESPONSE" {
            capture = 0
            finished = 1
            exit
        }
        capture {
            print
        }
        END {
            if (!found || !finished) {
                exit 42
            }
        }
    ' "${transcript}" > "${final_message}"; then
        rm -f -- "${final_message}"
        rhyolite_harness_set_error \
            'The no-op fixture transcript did not contain its diagnostic final response.'
        return 42
    fi

    extract_report "${final_message}" "${report}" || extraction_status=$?
    rm -f -- "${final_message}"
    return "${extraction_status}"
}

harness_verify_isolation() {
    local timeline="$1"

    noop_fixture_require_success harness_verify_isolation || return 1
    grep -Fq \
        'NOOP FIXTURE: repository analysis intentionally skipped.' \
        "${timeline}" || {
        rhyolite_harness_set_error \
            'The no-op fixture diagnostic marker was missing from sanitized output.'
        return 1
    }
    if [[ -n "${RHYOLITE_NOOP_FORBIDDEN_TEXT:-}" ]] &&
        grep -Fq -- "${RHYOLITE_NOOP_FORBIDDEN_TEXT}" "${timeline}"; then
        rhyolite_harness_set_error \
            'The no-op fixture exposed forbidden repository content.'
        return 1
    fi
}

harness_persist_agent_state() {
    local agent_state_directory="$2"
    local reasoning_effort="$3"
    local context_tier="$4"

    noop_fixture_require_success harness_persist_agent_state || return 1
    [[ "${reasoning_effort}" == max && "${context_tier}" == long_context ]] ||
        return 1
    if [[ -d "${agent_state_directory}" ]] &&
        [[ -n "$(find "${agent_state_directory}" -mindepth 1 -print -quit)" ]]; then
        rhyolite_harness_set_error \
            'The no-op fixture refuses to persist pre-existing agent state.'
        return 1
    fi
}

harness_sanitize_runtime_home() {
    local runtime_home="$1"
    local attempt

    noop_fixture_require_success harness_sanitize_runtime_home || return 1
    [[ -n "${runtime_home}" && -e "${runtime_home}" ]] || return 0
    for attempt in 1 2 3; do
        rm -rf -- "${runtime_home}" 2>/dev/null || true
        [[ ! -e "${runtime_home}" ]] && return 0
        sleep 1
    done
    rhyolite_harness_set_error \
        "Could not remove the no-op fixture runtime home after three attempts: ${runtime_home}"
    return 1
}

harness_allow_all_detected() {
    noop_fixture_require_success harness_allow_all_detected || return 1
    return 1
}
