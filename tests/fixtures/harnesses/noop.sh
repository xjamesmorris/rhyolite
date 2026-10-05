#!/usr/bin/env bash

NOOP_RUNTIME_HOME=''
NOOP_WORKER_DIRECTORY=''

noop_fixture_require_array_destination() {
    if [[ ! "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        rhyolite_harness_set_error \
            'The development-only no-op fixture array destination is invalid.'
        return 1
    fi
}

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
    local phase="${4:-review}"

    noop_fixture_require_success harness_prepare_worker_home || return 1
    [[ "${reasoning_effort}" == max && "${context_tier}" == long_context ]] ||
        return 1
    case "${phase}" in
        review|report-repair) ;;
        *)
            rhyolite_harness_set_error \
                'The no-op fixture runtime-home phase is unsupported.'
            return 1
            ;;
    esac
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
    printf '{"Fixture":"noop","Purpose":"contract-proof","Phase":"%s"}\n' \
        "${phase}" \
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

    noop_fixture_require_success harness_report_repair_argv || return 1
    noop_fixture_require_array_destination "${destination_name}" || return 1
    local -n output_arguments="${destination_name}"

    [[ -z "${authentication_variables}" ]] || {
        rhyolite_harness_set_error \
            'The no-op fixture received an unexpected report-repair authentication allowlist.'
        return 1
    }
    [[ -d "${trusted_workdir}" && ! -L "${trusted_workdir}" ]] || {
        rhyolite_harness_set_error \
            'The no-op fixture report-repair working directory is unavailable.'
        return 1
    }
    if ! first_workdir_entry="$(
        find "${trusted_workdir}" -mindepth 1 -print -quit 2>/dev/null
    )"; then
        rhyolite_harness_set_error \
            'The no-op fixture report-repair working directory could not be verified.'
        return 1
    fi
    [[ -z "${first_workdir_entry}" ]] || {
        rhyolite_harness_set_error \
            'The no-op fixture report-repair working directory is not empty.'
        return 1
    }
    [[ -n "${session_name}" && -n "${session_id}" ]] || {
        rhyolite_harness_set_error \
            'The no-op fixture report-repair session identity is missing.'
        return 1
    }
    [[ "${model}" == noop-fixture-model &&
        "${reasoning_effort}" == max &&
        "${context_tier}" == long_context ]] || {
        rhyolite_harness_set_error \
            'The no-op fixture report-repair model settings are invalid.'
        return 1
    }
    [[ "${transcript_path}" == /* ]] || {
        rhyolite_harness_set_error \
            'The no-op fixture report-repair transcript path is invalid.'
        return 1
    }

    output_arguments=(
        --fixture-contract 4
        --fixture-mode report-repair
        --workdir "${trusted_workdir}"
        --session-name "${session_name}"
        --session-id "${session_id}"
        --model "${model}"
        --reasoning-effort "${reasoning_effort}"
        --context "${context_tier}"
        --transcript "${transcript_path}"
    )
}

harness_report_repair_env() {
    local destination_name="$1"
    local runtime_home="$2"
    local response_mode="${RHYOLITE_NOOP_REPAIR_RESPONSE_MODE:-stdout}"

    noop_fixture_require_success harness_report_repair_env || return 1
    noop_fixture_require_array_destination "${destination_name}" || return 1
    local -n output_environment="${destination_name}"

    [[ -n "${NOOP_WORKER_DIRECTORY}" ]] || {
        noop_fixture_resolve_worker || return 1
    }
    [[ -d "${runtime_home}" && ! -L "${runtime_home}" ]] || {
        rhyolite_harness_set_error \
            'The no-op fixture report-repair runtime home is unavailable.'
        return 1
    }
    case "${response_mode}" in
        stdout|transcript|missing|user-only|system-only|view-only|view-failed|task-completed|info-only) ;;
        *)
            rhyolite_harness_set_error \
                'The no-op fixture report-repair response mode is unsupported.'
            return 1
            ;;
    esac
    output_environment=(
        -i
        "PATH=${NOOP_WORKER_DIRECTORY}:/usr/bin:/bin"
        "HOME=${runtime_home}"
        "XDG_CONFIG_HOME=${runtime_home}"
        'LC_ALL=C'
        "NOOP_RUNTIME_HOME=${runtime_home}"
        "NOOP_CAPTURE_ROOT=${RHYOLITE_NOOP_CAPTURE_ROOT:-}"
        "NOOP_REPAIR_RESPONSE_MODE=${response_mode}"
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

noop_fixture_write_pure_report_repair_descriptor() {
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

noop_fixture_extract_latest_assistant_reply() {
    local transcript="$1"

    awk '
        { lines[NR] = $0 }
        END {
            start = 0
            for (i = 1; i <= NR; i++) {
                marker = lines[i]
                sub(/^[[:space:]]+/, "", marker)
                sub(/[[:space:]]+$/, "", marker)
                if (marker == "### Copilot") {
                    start = i + 1
                }
            }
            if (start == 0) {
                exit 42
            }

            end = NR
            for (i = start; i <= NR; i++) {
                marker = lines[i]
                sub(/^[[:space:]]+/, "", marker)
                sub(/[[:space:]]+$/, "", marker)
                if (marker == "### User" ||
                    marker == "### System" ||
                    marker == "### Info" ||
                    marker == "### Copilot" ||
                    marker ~ /^### `[^`]+`([[:space:]]+—[[:space:]]+.+)?$/ ||
                    marker ~ /^### task[[:space:]]+\([^()]+\)$/) {
                    end = i - 1
                    break
                }
            }

            last = end
            while (last >= start && lines[last] ~ /^[[:space:]]*$/) {
                last--
            }
            footer_marker = lines[last]
            sub(/^[[:space:]]+/, "", footer_marker)
            sub(/[[:space:]]+$/, "", footer_marker)
            if (last >= start &&
                footer_marker == "<sub>Generated by [GitHub Copilot CLI](https://github.com/features/copilot/cli)</sub>") {
                footer = last - 1
                while (footer >= start &&
                    lines[footer] ~ /^[[:space:]]*$/) {
                    footer--
                }
                if (footer >= start && lines[footer] == "---") {
                    end = footer - 1
                }
            }

            for (i = start; i <= end; i++) {
                print lines[i]
            }
        }
    ' "${transcript}"
}

harness_extract_report_repair() {
    local timeline="$1"
    local transcript="$2"
    local reply_output="$3"
    local assistant_candidate="${reply_output}.assistant.$$"

    noop_fixture_require_success harness_extract_report_repair || return 1
    rm -f -- "${reply_output}" "${assistant_candidate}"
    if [[ -f "${timeline}" ]] &&
        noop_fixture_write_pure_report_repair_descriptor \
            "${timeline}" "${reply_output}"; then
        return 0
    fi
    rm -f -- "${reply_output}"

    if [[ -f "${transcript}" ]] &&
        noop_fixture_extract_latest_assistant_reply \
            "${transcript}" > "${assistant_candidate}"; then
        if noop_fixture_write_pure_report_repair_descriptor \
            "${assistant_candidate}" "${reply_output}"; then
            rm -f -- "${assistant_candidate}"
            return 0
        fi
    fi
    rm -f -- "${reply_output}" "${assistant_candidate}"
    rhyolite_harness_set_error \
        'The no-op fixture report repair did not return a supported confidence-edit descriptor.'
    return 42
}

harness_verify_isolation() {
    local timeline="$1"

    noop_fixture_require_success harness_verify_isolation || return 1
    if ! grep -Fq \
        'NOOP FIXTURE: repository analysis intentionally skipped.' \
        "${timeline}" &&
        ! grep -Fq \
            'NOOP FIXTURE: repair reply is not present as pure standard output.' \
            "${timeline}" &&
        ! grep -Eq \
            '^[[:space:]]*\{"ProtocolVersion":1,"Section":.*"Field":"Confidence:".*"Occurrence":.*"OriginalValueSha256":.*"ConservativeLevel":.*\}[[:space:]]*$' \
            "${timeline}"; then
        rhyolite_harness_set_error \
            'The no-op fixture diagnostic marker was missing from sanitized output.'
        return 1
    fi
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
