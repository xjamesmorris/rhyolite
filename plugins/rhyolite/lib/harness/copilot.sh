#!/usr/bin/env bash

COPILOT_AUTH_BRIDGE_INITIALIZED=0
COPILOT_AUTH_BRIDGE_HAS_PLAINTEXT=0
COPILOT_AUTH_BRIDGE_JSON='{}'
COPILOT_RUNTIME_HOME=''

copilot_forwarded_env_var_names() {
    printf '%s\n' \
        COPILOT_GITHUB_TOKEN \
        GH_TOKEN \
        GITHUB_TOKEN \
        COPILOT_PROVIDER_API_KEY \
        COPILOT_PROVIDER_BEARER_TOKEN \
        ANTHROPIC_API_KEY \
        AZURE_OPENAI_API_KEY \
        OPENAI_API_KEY \
        CAPI_HMAC_KEY \
        COPILOT_HMAC_KEY \
        GITHUB_COPILOT_API_TOKEN
}

copilot_write_settings() {
    local settings_path="$1"
    local store_token_plaintext="$2"
    local reasoning_effort="$3"
    local context_tier="$4"

    {
        printf '{\n'
        if ((store_token_plaintext)); then
            printf '  "storeTokenPlaintext": true,\n'
        fi
        cat <<EOF
  "disableAllHooks": true,
  "customAgents": {
    "defaultLocalOnly": true
  },
  "subagents": {
    "agents": {
      "explore": {
        "model": "inherit",
        "effortLevel": "${reasoning_effort}",
        "contextTier": "${context_tier}"
      },
      "task": {
        "model": "inherit",
        "effortLevel": "${reasoning_effort}",
        "contextTier": "${context_tier}"
      },
      "code-review": {
        "model": "inherit",
        "effortLevel": "${reasoning_effort}",
        "contextTier": "${context_tier}"
      },
      "general-purpose": {
        "model": "inherit",
        "effortLevel": "${reasoning_effort}",
        "contextTier": "${context_tier}"
      },
      "research": {
        "model": "inherit",
        "effortLevel": "${reasoning_effort}",
        "contextTier": "${context_tier}"
      },
      "security-review": {
        "model": "inherit",
        "effortLevel": "${reasoning_effort}",
        "contextTier": "${context_tier}"
      },
      "rubber-duck": {
        "model": "inherit",
        "effortLevel": "${reasoning_effort}",
        "contextTier": "${context_tier}"
      }
    }
  }
}
EOF
    } > "${settings_path}"
}

harness_id() {
    printf '%s\n' 'copilot'
}

harness_display_name() {
    printf '%s\n' 'Copilot'
}

harness_cli_name() {
    printf '%s\n' 'copilot'
}

harness_require_cli() {
    if ! command -v copilot >/dev/null 2>&1; then
        rhyolite_harness_set_error 'copilot is required.'
        return 1
    fi
}

harness_capability() {
    case "$1" in
        fleet|structured_questions|subagents|builtin_security_specialist|builtin_research_specialist|web_research|shell_denial)
            printf '%s\n' 'yes'
            ;;
        final_message_file)
            printf '%s\n' 'no'
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
    local help_output
    local model
    local found=0
    local -A seen=()

    command -v copilot >/dev/null 2>&1 || {
        rhyolite_harness_set_error 'copilot is required to list available models.'
        return 1
    }
    help_output="$(copilot help config 2>/dev/null)" || {
        rhyolite_harness_set_error \
            'Copilot did not return its available model catalog.'
        return 1
    }
    while IFS= read -r model; do
        [[ "${model}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || {
            rhyolite_harness_set_error \
                'Copilot returned an unsafe model identifier.'
            return 1
        }
        [[ -z "${seen[${model}]+x}" ]] || continue
        seen["${model}"]=1
        printf '%s\n' "${model}"
        found=1
    done < <(
        printf '%s\n' "${help_output}" |
            awk '
                /^[[:space:]]*`model`:/ {
                    in_model = 1
                    next
                }
                in_model &&
                    /^[[:space:]]*-[[:space:]]*"[^"]+"[[:space:]]*$/ {
                    value = $0
                    sub(/^[[:space:]]*-[[:space:]]*"/, "", value)
                    sub(/"[[:space:]]*$/, "", value)
                    print value
                    next
                }
                in_model && /^[[:space:]]*`[^`]+`:/ {
                    exit
                }
            '
    )
    ((found)) || {
        rhyolite_harness_set_error \
            'Copilot returned an empty available model catalog.'
        return 1
    }
}

harness_validate_model_id() {
    local requested_model="$1"
    local available_models
    local available_model

    [[ "${requested_model}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || {
        rhyolite_harness_set_error \
            'The model identifier contains unsupported characters.'
        return 1
    }
    if ! available_models="$(harness_list_models)"; then
        rhyolite_harness_set_error \
            'Copilot model-catalog discovery failed during model validation.'
        return 1
    fi
    while IFS= read -r available_model; do
        [[ "${available_model}" == "${requested_model}" ]] && return 0
    done <<< "${available_models}"
    rhyolite_harness_set_error \
        "Model '${requested_model}' is not in Copilot's available model catalog."
}

harness_model_choices() {
    printf '%s\n' \
        'GPT-5.6 Sol (Recommended) - gpt-5.6-sol' \
        'Claude Fable 5 - claude-fable-5' \
        'List available model IDs'
}

harness_max_reasoning_effort() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || return 1
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

harness_context_choices() {
    printf '%s\n' \
        'Long context (Recommended) - long_context' \
        'Default context - default'
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
    copilot_forwarded_env_var_names
}

harness_login_remediation() {
    printf '%s' \
        'Review the sanitized errors and timeline. If they show Copilot authentication failure, run copilot login from a clean non-Git directory, then retry.'
}

harness_provider_summary() {
    local variable_name
    local separator=''

    printf '%s' \
        '{"Id":"github-copilot","Host":"managed-provider","ForwardedEnvVarNames":['
    while IFS= read -r variable_name; do
        printf '%s"%s"' "${separator}" "${variable_name}"
        separator=','
    done < <(copilot_forwarded_env_var_names)
    printf ']}\n'
}

harness_resume_policy() {
    printf '%s\n' \
        'Continue only through the trusted Rhyolite repo-review runner; do not invoke copilot --resume directly.'
}

harness_prepare_run() {
    local source_copilot_home
    local copilot_auth_bridge_output
    local -a copilot_auth_bridge

    if ((COPILOT_AUTH_BRIDGE_INITIALIZED)); then
        return 0
    fi

    source_copilot_home="${COPILOT_HOME:-${HOME}/.copilot}"
    if ! copilot_auth_bridge_output="$(
        python3 - "${source_copilot_home}/config.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
bridge = {}
if path.is_file():
    try:
        text = "\n".join(
            line for line in path.read_text(encoding="utf-8").splitlines()
            if not line.lstrip().startswith("//")
        )
        config = json.loads(text)
        if not isinstance(config, dict):
            config = {}
        for name in (
            "lastLoggedInUser",
            "loggedInUsers",
            "copilotTokens",
            "last_logged_in_user",
            "logged_in_users",
            "copilot_tokens",
        ):
            if name in config:
                bridge[name] = config[name]
    except (OSError, UnicodeError, json.JSONDecodeError, TypeError):
        bridge = {}

has_plaintext_tokens = any(
    isinstance(bridge.get(name), dict) and bridge[name]
    for name in ("copilotTokens", "copilot_tokens")
)
print("1" if has_plaintext_tokens else "0")
print(json.dumps(bridge, separators=(",", ":")))
PY
    )"; then
        rhyolite_harness_set_error \
            'Could not prepare the temporary Copilot authentication bridge.'
        return 1
    fi
    mapfile -t copilot_auth_bridge <<< "${copilot_auth_bridge_output}"
    if [[ "${copilot_auth_bridge[0]-}" != 0 &&
        "${copilot_auth_bridge[0]-}" != 1 ]] ||
        [[ -z "${copilot_auth_bridge[1]-}" ]]; then
        rhyolite_harness_set_error \
            'The temporary Copilot authentication bridge was malformed.'
        return 1
    fi
    COPILOT_AUTH_BRIDGE_HAS_PLAINTEXT="${copilot_auth_bridge[0]:-0}"
    COPILOT_AUTH_BRIDGE_JSON="${copilot_auth_bridge[1]:-}"
    [[ -n "${COPILOT_AUTH_BRIDGE_JSON}" ]] ||
        COPILOT_AUTH_BRIDGE_JSON='{}'
    COPILOT_AUTH_BRIDGE_INITIALIZED=1
    printf '%s\n' \
        'Copilot authentication will be verified by the first isolated review session using the current environment, system credential store, GitHub CLI fallback, configured provider, or an ephemeral local auth bridge.'
}

harness_prepare_worker_home() {
    local runtime_home="$1"
    local reasoning_effort="$2"
    local context_tier="$3"

    COPILOT_RUNTIME_HOME="${runtime_home}"
    chmod 700 -- "${runtime_home}" || {
        rhyolite_harness_set_error \
            'Could not restrict the temporary Copilot runtime home.'
        return 1
    }

    if ! copilot_write_settings \
        "${runtime_home}/settings.json" \
        "${COPILOT_AUTH_BRIDGE_HAS_PLAINTEXT}" \
        "${reasoning_effort}" \
        "${context_tier}"; then
        rhyolite_harness_set_error \
            'Could not write temporary Copilot settings.'
        return 1
    fi
    if ! {
        printf '%s\n' \
            '// User settings belong in settings.json.' \
            '// This file is managed automatically.'
        printf '%s\n' "${COPILOT_AUTH_BRIDGE_JSON}"
    } > "${runtime_home}/config.json"; then
        rhyolite_harness_set_error \
            'Could not write the temporary Copilot authentication bridge.'
        return 1
    fi
    chmod 600 -- \
        "${runtime_home}/settings.json" \
        "${runtime_home}/config.json" || {
        rhyolite_harness_set_error \
            'Could not restrict temporary Copilot configuration files.'
        return 1
    }
}

harness_worker_argv() {
    local -n output_arguments="$1"
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

    output_arguments=(
        -C "${session_root}"
        --plugin-dir "${plugin_root}"
        --name "${session_name}"
        --session-id "${session_id}"
        --agent rhyolite:repo-review-worker
        --model "${model}"
        --reasoning-effort "${reasoning_effort}"
        --context "${context_tier}"
        --no-ask-user
        --no-color
        --no-custom-instructions
        --disable-builtin-mcps
        --disallow-temp-dir
        --no-remote-export
        --secret-env-vars "${authentication_variables}"
        --available-tools "${available_tools}"
        --allow-tool read
        --deny-tool write
        --deny-tool shell
        --stream off
        --share "${transcript_path}"
        --silent
    )
    : "${enable_public_research}"
}

harness_worker_env() {
    local -n output_environment="$1"

    output_environment=(
        -u COPILOT_ALLOW_ALL
        -u COPILOT_SKILLS_DIRS
        -u COPILOT_CUSTOM_INSTRUCTIONS_DIRS
        -u COPILOT_DYNAMIC_RETRIEVAL_SKILLS
        -u COPILOT_EMBEDDING_ONLY_SKILLS
        "COPILOT_HOME=${COPILOT_RUNTIME_HOME}"
    )
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
    if ! awk '
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
            for (i = start; i <= NR; i++) {
                print lines[i]
            }
        }
    ' "${transcript}" > "${final_message}"; then
        rm -f -- "${final_message}"
        return 42
    fi

    extract_report "${final_message}" "${report}" || extraction_status=$?
    rm -f -- "${final_message}"
    return "${extraction_status}"
}

harness_verify_isolation() {
    return 0
}

harness_persist_agent_state() {
    local runtime_home="$1"
    local agent_state_directory="$2"
    local reasoning_effort="$3"
    local context_tier="$4"
    local copilot_home_path="${agent_state_directory}/copilot-home"
    local state_entry
    local source_entry
    local destination_entry
    local state_file
    local relative_state_file
    local destination_state_file

    mkdir -p -- "${copilot_home_path}" || {
        rhyolite_harness_set_error \
            'Could not create the persisted Copilot state directory.'
        return 1
    }
    chmod 700 -- "${copilot_home_path}" || {
        rhyolite_harness_set_error \
            'Could not restrict the persisted Copilot state directory.'
        return 1
    }
    if ! copilot_write_settings \
        "${copilot_home_path}/settings.json" \
        0 \
        "${reasoning_effort}" \
        "${context_tier}"; then
        rhyolite_harness_set_error \
            'Could not write persisted Copilot settings.'
        return 1
    fi
    if ! cat > "${copilot_home_path}/config.json" <<'EOF'
// User settings belong in settings.json.
// This file is managed automatically.
{}
EOF
    then
        rhyolite_harness_set_error \
            'Could not write the sanitized persisted Copilot configuration.'
        return 1
    fi
    chmod 600 -- \
        "${copilot_home_path}/settings.json" \
        "${copilot_home_path}/config.json" || {
        rhyolite_harness_set_error \
            'Could not restrict persisted Copilot configuration files.'
        return 1
    }

    for state_entry in session-state session-store; do
        source_entry="${runtime_home}/${state_entry}"
        [[ -d "${source_entry}" ]] || continue
        destination_entry="${copilot_home_path}/${state_entry}"
        mkdir -p -- "${destination_entry}" || {
            rhyolite_harness_set_error \
                'Could not create a persisted Copilot session-state directory.'
            return 1
        }
        while IFS= read -r -d '' state_file; do
            relative_state_file="${state_file#"${source_entry}/"}"
            destination_state_file="${destination_entry}/${relative_state_file}"
            mkdir -p -- "$(dirname -- "${destination_state_file}")" || {
                rhyolite_harness_set_error \
                    'Could not create a persisted Copilot state path.'
                return 1
            }
            cp -- "${state_file}" "${destination_state_file}" || {
                rhyolite_harness_set_error \
                    'Could not persist an allowlisted Copilot state file.'
                return 1
            }
        done < <(find "${source_entry}" -type f -print0)
    done
    find "${copilot_home_path}" -type d -exec chmod 700 -- {} + || {
        rhyolite_harness_set_error \
            'Could not restrict persisted Copilot state directories.'
        return 1
    }
    find "${copilot_home_path}" -type f -exec chmod 600 -- {} + || {
        rhyolite_harness_set_error \
            'Could not restrict persisted Copilot state files.'
        return 1
    }
}

harness_sanitize_runtime_home() {
    local runtime_home="$1"
    local attempt

    [[ -n "${runtime_home}" && -e "${runtime_home}" ]] || return 0
    if [[ -f "${runtime_home}/config.json" ]]; then
        if ! rm -f -- "${runtime_home}/config.json"; then
            {
                printf '%s\n' \
                    '// User settings belong in settings.json.' \
                    '// This file is managed automatically.' \
                    '{}'
            } > "${runtime_home}/config.json" 2>/dev/null || true
            chmod 600 -- "${runtime_home}/config.json" 2>/dev/null || true
        fi
    fi

    for attempt in 1 2 3; do
        rm -rf -- "${runtime_home}" 2>/dev/null || true
        [[ ! -e "${runtime_home}" ]] && return 0
        sleep 1
    done
    rhyolite_harness_set_error \
        "Could not remove the temporary Copilot runtime home after three attempts: ${runtime_home}"
    return 1
}

harness_allow_all_detected() {
    local allow_all="${COPILOT_ALLOW_ALL:-false}"

    allow_all="${allow_all,,}"
    [[ "${allow_all}" == "true" || "${allow_all}" == "1" ||
        "${allow_all}" == "yes" ]]
}
