#!/usr/bin/env bash

COPILOT_AUTH_BRIDGE_INITIALIZED=0
COPILOT_AUTH_BRIDGE_HAS_PLAINTEXT=0
COPILOT_AUTH_BRIDGE_JSON='{}'
COPILOT_RUNTIME_HOME=''

copilot_require_array_destination() {
    if [[ ! "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        rhyolite_harness_set_error \
            'The Copilot harness array destination is invalid.'
        return 1
    fi
}

copilot_validate_protected_auth_csv() {
    local protected_names="$1"
    local expected_names
    local variable_name
    local -a expected_name_list=()

    mapfile -t expected_name_list < <(copilot_forwarded_env_var_names)
    expected_names="$(
        IFS=,
        printf '%s' "${expected_name_list[*]}"
    )"
    [[ "${protected_names}" == "${expected_names}" ]] || {
        rhyolite_harness_set_error \
            'The Copilot protected authentication-variable list is invalid.'
        return 1
    }
    for variable_name in "${expected_name_list[@]}"; do
        [[ "${variable_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
            rhyolite_harness_set_error \
                'The Copilot protected authentication-variable list is invalid.'
            return 1
        }
    done
}

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
    local phase="${5:-review}"

    {
        printf '{\n'
        if ((store_token_plaintext)); then
            printf '  "storeTokenPlaintext": true,\n'
        fi
        case "${phase}" in
            review)
                # Rhyolite workers receive no subagent tool, so these profiles
                # are defense in depth for any subagent the harness itself
                # might create: a `task` argument can override them, which is
                # why the runner also fails closed on every recorded subagent.
                cat <<EOF
  "disableAllHooks": true,
  "memory": false,
  "continueOnAutoMode": false,
  "ide": {
    "autoConnect": false
  },
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
                ;;
            report-repair)
                cat <<'EOF'
  "disableAllHooks": true,
  "memory": false,
  "continueOnAutoMode": false,
  "ide": {
    "autoConnect": false
  }
}
EOF
                ;;
            *)
                return 1
                ;;
        esac
    } > "${settings_path}"
}

copilot_extract_latest_assistant_reply() {
    local transcript="$1"
    local mode="${2:-main}"
    local strict=0

    case "${mode}" in
        main) ;;
        repair) strict=1 ;;
        *)
            rhyolite_harness_set_error 'Unsupported Copilot reply extraction mode.'
            return 1
            ;;
    esac
    awk -v strict="${strict}" '
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
            for (i = start; strict && i <= NR; i++) {
                marker = lines[i]
                sub(/^[[:space:]]+/, "", marker)
                sub(/[[:space:]]+$/, "", marker)
                if (marker == "### User" ||
                    marker == "### Tool" ||
                    marker == "### System" ||
                    marker == "### Info" ||
                    marker == "### Copilot" ||
                    marker ~ /^### (Tool[[:space:]]+)?`[^`]+`([[:space:]].*)?$/ ||
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
            if (strict && last >= start &&
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

copilot_populate_worker_environment() {
    local destination_name="$1"
    local runtime_home="$2"

    copilot_require_array_destination "${destination_name}" || return 1
    local -n output_environment="${destination_name}"

    output_environment=(
        -u COPILOT_ALLOW_ALL
        -u COPILOT_SKILLS_DIRS
        -u COPILOT_CUSTOM_INSTRUCTIONS_DIRS
        -u COPILOT_DYNAMIC_RETRIEVAL_SKILLS
        -u COPILOT_EMBEDDING_ONLY_SKILLS
        "COPILOT_HOME=${runtime_home}"
    )
}

copilot_write_pure_report_repair_descriptor() {
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
        fleet|structured_questions|builtin_research_specialist|web_research|shell_denial)
            printf '%s\n' 'yes'
            ;;
        # Re-invoking a non-interactive JSON worker with the same
        # --session-id and runtime home, without --name, resumes that
        # session with its full context (verified live with Copilot CLI
        # 1.0.98-2).
        worker_continuation)
            printf '%s\n' 'yes'
            ;;
        # Copilot CLI lets a `task` call override every configured subagent
        # model (verified live: `modelSelectionSource: "explicit_override"`),
        # so no subagent can be bound to the approved model. Rhyolite workers
        # therefore receive no subagent tools and perform the security pass
        # themselves, exactly like the Claude Code worker.
        subagents|builtin_security_specialist|final_message_file)
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
    help_output="$(
        PAGER=cat \
        COPILOT_PAGER=cat \
        GH_PAGER=cat \
        GIT_PAGER=cat \
        EDITOR=cat \
        VISUAL=cat \
        MANPAGER=cat \
        TERM=dumb \
        NO_COLOR=1 \
        copilot help config 2>/dev/null
    )" || {
        rhyolite_harness_set_error \
            'Copilot did not return its offline model catalog.'
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
            'Copilot returned an empty offline model catalog.'
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
    # Copilot's auto selector picks and substitutes models, so it is never an
    # exact model even if a future catalog lists it.
    if [[ "${requested_model}" =~ ^[Aa][Uu][Tt][Oo]$ ]]; then
        rhyolite_harness_set_error \
            "Model '${requested_model}' lets Copilot choose a model automatically; select an exact model ID."
        return 1
    fi
    if ! available_models="$(harness_list_models)"; then
        rhyolite_harness_set_error \
            'Copilot model-catalog discovery failed during model validation.'
        return 1
    fi
    while IFS= read -r available_model; do
        [[ "${available_model}" == "${requested_model}" ]] && return 0
    done <<< "${available_models}"
    # Copilot rejects an unavailable explicit model in non-interactive
    # workers without substitution, so a safe unlisted ID is opt-in eligible.
    rhyolite_harness_set_error \
        "Model '${requested_model}' is not in Copilot's offline model catalog."
    return "${RHYOLITE_HARNESS_MODEL_UNLISTED_STATUS:-1}"
}

harness_model_choices() {
    printf '%s\n' \
        'GPT-5.6 Sol (Recommended) - gpt-5.6-sol' \
        'Claude Opus 5.5 - claude-opus-5.5' \
        'Claude Fable 5.1 - claude-fable-5.1' \
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
    local phase="${4:-review}"

    case "${phase}" in
        review|report-repair|research) ;;
        *)
            rhyolite_harness_set_error \
                'The Copilot runtime-home phase is unsupported.'
            return 1
            ;;
    esac

    # The dedicated research worker uses the same isolated settings as the
    # review worker; only its argv grants the local broker tools.
    [[ "${phase}" != research ]] || phase=review
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
        "${context_tier}" \
        "${phase}"; then
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

harness_snapshot_transport() {
    rhyolite_harness_native_snapshot_transport
}

harness_configure_snapshot_transport() {
    rhyolite_harness_reject_snapshot_configuration
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
        --output-format json
        --share "${transcript_path}"
        --silent
    )
    : "${enable_public_research}"
}

harness_worker_env() {
    copilot_populate_worker_environment "$1" "${COPILOT_RUNTIME_HOME}"
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

    copilot_require_array_destination "${destination_name}" || return 1
    local -n output_arguments="${destination_name}"

    [[ -d "${trusted_workdir}" && ! -L "${trusted_workdir}" ]] || {
        rhyolite_harness_set_error \
            'The Copilot report-repair working directory is unavailable.'
        return 1
    }
    if ! first_workdir_entry="$(
        find "${trusted_workdir}" -mindepth 1 -print -quit 2>/dev/null
    )"; then
        rhyolite_harness_set_error \
            'The Copilot report-repair working directory could not be verified.'
        return 1
    fi
    [[ -z "${first_workdir_entry}" ]] || {
        rhyolite_harness_set_error \
            'The Copilot report-repair working directory is not empty.'
        return 1
    }
    [[ "${session_name}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || {
        rhyolite_harness_set_error \
            'The Copilot report-repair session name is invalid.'
        return 1
    }
    [[ "${session_id}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || {
        rhyolite_harness_set_error \
            'The Copilot report-repair session identifier is invalid.'
        return 1
    }
    [[ "${model}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]] || {
        rhyolite_harness_set_error \
            'The Copilot report-repair model identifier is invalid.'
        return 1
    }
    harness_validate_reasoning_effort "${reasoning_effort}" || return 1
    harness_validate_context_tier "${context_tier}" || return 1
    copilot_validate_protected_auth_csv \
        "${authentication_variables}" || return 1
    [[ "${transcript_path}" == /* ]] || {
        rhyolite_harness_set_error \
            'The Copilot report-repair transcript path is invalid.'
        return 1
    }

    output_arguments=(
        -C "${trusted_workdir}"
        --name "${session_name}"
        --session-id "${session_id}"
        --model "${model}"
        --reasoning-effort "${reasoning_effort}"
        --context "${context_tier}"
        --mode interactive
        --no-ask-user
        --no-color
        --no-custom-instructions
        --disable-builtin-mcps
        --disallow-temp-dir
        --no-remote-export
        --no-bash-env
        --no-auto-update
        --no-experimental
        --dynamic-retrieval skills=off
        --secret-env-vars "${authentication_variables}"
        --excluded-tools 'builtin:*' 'mcp:*' 'custom:*'
        --deny-tool read
        --deny-tool write
        --deny-tool shell
        --deny-tool url
        --stream off
        --output-format json
        --share "${transcript_path}"
        --silent
    )
}

harness_report_repair_env() {
    local destination_name="$1"
    local runtime_home="$2"

    copilot_require_array_destination "${destination_name}" || return 1
    [[ -d "${runtime_home}" && ! -L "${runtime_home}" ]] || {
        rhyolite_harness_set_error \
            'The Copilot report-repair runtime home is unavailable.'
        return 1
    }
    copilot_populate_worker_environment \
        "${destination_name}" "${runtime_home}"
}

copilot_json_string() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '"%s"' "${value}"
}

harness_write_research_mcp_config() {
    local config_path="$1"
    local broker_launcher="$2"
    local arguments_name="$3"
    local tools_json="$4"
    local argument
    local separator=''

    copilot_require_array_destination "${arguments_name}" || return 1
    local -n copilot_research_broker_arguments_ref="${arguments_name}"
    [[ "${config_path}" == /* && "${broker_launcher}" == /* ]] || {
        rhyolite_harness_set_error \
            'The Copilot research MCP configuration paths are invalid.'
        return 1
    }
    [[ "${tools_json}" =~ ^\[\ *\"[a-z_]+\"(\ *,\ *\"[a-z_]+\")*\ *\]$ ]] || {
        rhyolite_harness_set_error \
            'The Copilot research broker tool list is invalid.'
        return 1
    }
    if ! {
        printf '{\n  "mcpServers": {\n    "rhyolite-research": {\n'
        printf '      "type": "local",\n'
        printf '      "command": %s,\n' "$(copilot_json_string "${broker_launcher}")"
        printf '      "args": [\n'
        for argument in "${copilot_research_broker_arguments_ref[@]}"; do
            printf '%s        %s' "${separator}" "$(copilot_json_string "${argument}")"
            separator=$',\n'
        done
        printf '\n      ],\n'
        printf '      "tools": %s,\n' "${tools_json}"
        printf '      "timeout": 120000\n'
        printf '    }\n  }\n}\n'
    } > "${config_path}" || ! chmod 600 -- "${config_path}"; then
        rhyolite_harness_set_error \
            'Could not write the Copilot research MCP configuration.'
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
    local tool_name
    local runtime_tools=''
    local separator=''
    local -a allow_arguments=()

    copilot_require_array_destination "${destination_name}" || return 1
    [[ "${broker_tools}" =~ ^[a-z_]+(,[a-z_]+)*$ ]] || {
        rhyolite_harness_set_error \
            'The Copilot research broker tool list is invalid.'
        return 1
    }
    [[ "${mcp_config_path}" == /* && "${transcript_path}" == /* ]] || {
        rhyolite_harness_set_error \
            'The Copilot research worker paths are invalid.'
        return 1
    }
    while IFS= read -r tool_name; do
        runtime_tools+="${separator}rhyolite-research-${tool_name}"
        separator=','
        allow_arguments+=(--allow-tool "rhyolite-research(${tool_name})")
    done < <(printf '%s\n' "${broker_tools//,/$'\n'}")

    local -n output_arguments="${destination_name}"
    output_arguments=(
        -C "${session_root}"
        --plugin-dir "${plugin_root}"
        --name "${session_name}"
        --session-id "${session_id}"
        --agent rhyolite:repo-research-worker
        --model "${model}"
        --reasoning-effort "${reasoning_effort}"
        --context "${context_tier}"
        --no-ask-user
        --no-color
        --no-custom-instructions
        --disable-builtin-mcps
        --additional-mcp-config "@${mcp_config_path}"
        --disallow-temp-dir
        --no-remote-export
        --secret-env-vars "${authentication_variables}"
        --available-tools "view,glob,rg,skill,${runtime_tools}"
        --allow-tool read
        "${allow_arguments[@]}"
        --deny-tool write
        --deny-tool shell
        --stream off
        --output-format json
        --share "${transcript_path}"
        --silent
    )
}

harness_research_worker_env() {
    copilot_populate_worker_environment "$1" "${COPILOT_RUNTIME_HOME}"
}

# Copilot binds every non-interactive worker to the approved model through
# the CLI, and its structured JSONL output records the model and reasoning
# effort of every model call. harness_normalize_worker_output verifies them
# after the worker exits, so this hook has no separate session record to
# export.
harness_finalize_research_session() {
    return 0
}

# Copilot print mode renders text output as terminal Markdown: it wraps lines
# at the terminal width, re-indents and renumbers lists, inserts blank lines,
# and emits OSC 8 hyperlink escapes even with --no-color. Those bytes are not
# the assistant reply. Every Copilot child therefore runs with
# --output-format json, and this scanner reads the JSONL event stream in one
# of two modes with the same enforcement rules:
#   normalize  translate the complete stream into a readable narrative plus
#              the exact final assistant message;
#   watch      scan only the complete lines appended since the offset saved in
#              the cursor file while the worker is still running.
# Both modes verify that every recorded model call, tool call, usage
# checkpoint, and subagent metric used the approved model and effort, and both
# reject any subagent event because Rhyolite workers receive no subagent tool
# and Copilot CLI lets a `task` argument override every configured subagent
# model. It prints one status token followed by one sanitized detail line.
copilot_scan_structured_output() {
    local mode="$1"
    local raw_output="$2"
    local approved_model="$3"
    local approved_effort="$4"
    local normalized_output="${5:--}"
    local final_reply_output="${6:--}"
    local cursor_path="${7:--}"

    python3 - \
        "${mode}" \
        "${raw_output}" \
        "${approved_model}" \
        "${approved_effort}" \
        "${normalized_output}" \
        "${final_reply_output}" \
        "${cursor_path}" <<'PY'
import json
import pathlib
import re
import sys

mode = sys.argv[1]
raw_path = pathlib.Path(sys.argv[2])
approved_model = sys.argv[3]
approved_effort = sys.argv[4]
normalized_path = pathlib.Path(sys.argv[5]) if sys.argv[5] != "-" else None
reply_path = pathlib.Path(sys.argv[6]) if sys.argv[6] != "-" else None
cursor_path = pathlib.Path(sys.argv[7]) if sys.argv[7] != "-" else None
SAFE_TOKEN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")
SUBAGENT_EVENTS = (
    "subagent.started",
    "subagent.configured",
    "subagent.selected",
    "subagent.completed",
    "subagent.failed",
)


def safe_token(value):
    if isinstance(value, str) and SAFE_TOKEN.fullmatch(value):
        return value
    return "unrecognized"


def finish(status, detail=""):
    sys.stdout.write(f"{status}\n{detail}\n")
    raise SystemExit(0 if status == "ok" else 1)


if mode not in ("normalize", "watch"):
    finish("invalid", "The Copilot output scanner mode is unsupported.")

offset = 0
if mode == "watch":
    try:
        if cursor_path.is_file():
            offset = int(cursor_path.read_text(encoding="ascii").strip() or 0)
    except (OSError, ValueError, UnicodeError):
        offset = 0
    if offset < 0:
        offset = 0

try:
    if mode == "watch" and not raw_path.is_file():
        raw_bytes = b""
    else:
        with raw_path.open("rb") as stream:
            if offset:
                stream.seek(offset)
            raw_bytes = stream.read()
except OSError:
    finish("unreadable", "The Copilot worker output could not be read.")

narrative = []
passthrough = []
final_reply = None
event_count = 0
observed_models = []
content_models = []
observed_efforts = []
subagent_seen = None


def flush_passthrough():
    if passthrough:
        narrative.append("\n".join(passthrough))
        passthrough.clear()


def observe_model(value, content=False):
    if isinstance(value, str) and value:
        observed_models.append(value)
        if content:
            content_models.append(value)


def observe_effort(value):
    if isinstance(value, str) and value:
        observed_efforts.append(value)


def observe_metrics(metrics):
    if isinstance(metrics, dict):
        for model_id in metrics:
            observe_model(model_id)


def observe_agent_metrics(agent_metrics):
    if isinstance(agent_metrics, dict):
        entries = agent_metrics.values()
    elif isinstance(agent_metrics, list):
        entries = agent_metrics
    else:
        return
    for entry in entries:
        if isinstance(entry, dict):
            observe_metrics(entry.get("modelMetrics"))


def observe_subagent(data):
    global subagent_seen
    for key in ("model", "firstDispatchedModel", "explicitModelOverride"):
        observe_model(data.get(key))
    observe_effort(data.get("reasoningEffort"))
    if subagent_seen is None:
        name = data.get("agentName") or data.get("agentType") or "unknown"
        model = data.get("model") or data.get("explicitModelOverride") or ""
        subagent_seen = (safe_token(name), safe_token(model) if model else "")


consumed = 0
lines = raw_bytes.split(b"\n")
# In watch mode the split tail is either the empty string after a final
# newline or the line the writer is still producing; neither is consumed, so
# the cursor stops exactly after the last complete line.
if mode == "watch":
    lines = lines[:-1]
for raw_line in lines:
    consumed += len(raw_line) + 1
    line = raw_line.rstrip(b"\r")
    if not line.strip():
        continue
    event = None
    if line.lstrip()[:1] == b"{":
        try:
            event = json.loads(line.decode("utf-8"))
        except (UnicodeError, json.JSONDecodeError):
            event = None
    if not isinstance(event, dict) or not isinstance(event.get("type"), str):
        passthrough.append(line.decode("utf-8", "replace"))
        continue
    event_count += 1
    event_type = event["type"]
    data = event.get("data")
    if not isinstance(data, dict):
        data = {}
    if event_type == "assistant.message":
        observe_model(data.get("model"), content=True)
        content = data.get("content")
        if isinstance(content, str):
            final_reply = content
            if content.strip():
                flush_passthrough()
                narrative.append(content)
    elif event_type in ("tool.execution_start", "tool.execution_complete"):
        observe_model(data.get("model"), content=True)
    elif event_type == "model.call_final_result":
        observe_model(data.get("model"), content=data.get("result") == "success")
    elif event_type in ("model.call_start", "model.call_failure", "agent.interrupted"):
        # A call that started, failed, or was interrupted before its first
        # token is an attempt; it produced no output the worker could use.
        observe_model(data.get("model"))
    elif event_type in SUBAGENT_EVENTS:
        observe_subagent(data)
    elif event_type == "session.usage_checkpoint":
        for state in data.get("promptCacheBreakState") or []:
            if not isinstance(state, dict):
                continue
            models = state.get("models")
            if not isinstance(models, dict):
                continue
            for model_id, call in models.items():
                observe_model(model_id)
                if isinstance(call, dict):
                    observe_model(call.get("model"))
                    observe_effort(call.get("reasoning_effort"))
        snapshot = data.get("accountingSnapshot")
        if isinstance(snapshot, dict):
            observe_metrics(snapshot.get("modelMetrics"))
            observe_agent_metrics(snapshot.get("agentMetrics"))
        observe_agent_metrics(data.get("agentMetrics"))

if mode == "watch":
    try:
        cursor_path.write_text(f"{offset + consumed}\n", encoding="ascii")
        cursor_path.chmod(0o600)
    except OSError:
        finish("unwritable", "The Copilot worker output cursor could not be written.")

if subagent_seen is not None:
    name, model = subagent_seen
    finish("subagent", f"{name}:{model}" if model else name)
substituted = [model for model in content_models if model != approved_model]
if substituted:
    finish("substituted", safe_token(substituted[0]))
# Copilot CLI automatically retries a request on another model when the
# approved model refuses it. Any such attempt still fails closed; the worker
# outcome tells the runner whether it was blocked before producing output.
attempted = [model for model in observed_models if model != approved_model]
if attempted:
    finish("fallback", safe_token(attempted[0]))
changed = [effort for effort in observed_efforts if effort != approved_effort]
if changed:
    finish("effort-changed", safe_token(changed[0]))
if mode == "watch":
    finish("ok", "clean")

flush_passthrough()
normalized_text = "\n\n".join(block.rstrip("\n") for block in narrative)
if normalized_text:
    normalized_text += "\n"
reply_text = final_reply or ""
if reply_text and not reply_text.endswith("\n"):
    reply_text += "\n"


def exact_bytes(text):
    # JSON may carry lone surrogates that stand for undecodable bytes; round
    # them back to the original bytes so strict validation still sees them.
    try:
        return text.encode("utf-8", "surrogateescape")
    except UnicodeEncodeError:
        return text.encode("utf-8", "replace")


try:
    normalized_path.write_bytes(exact_bytes(normalized_text))
    reply_path.write_bytes(exact_bytes(reply_text))
except OSError:
    finish("unwritable", "The normalized Copilot worker output could not be written.")
finish("ok", "structured" if event_count else "unstructured")
PY
}

# Translate one scanner status into the sanitized, phase-specific failure
# detail shared by normalization and live violation detection.
copilot_set_scan_error() {
    local phase="$1"
    local status="$2"
    local detail="$3"
    local approved_model="$4"
    local approved_effort="$5"
    local subagent_name subagent_model

    case "${status}" in
        subagent)
            subagent_name="${detail%%:*}"
            subagent_model=''
            [[ "${detail}" != *:* ]] || subagent_model="${detail#*:}"
            if [[ -n "${subagent_model}" ]]; then
                rhyolite_harness_set_error \
                    "Copilot started subagent '${subagent_name}' with model '${subagent_model}' in the ${phase} phase although Rhyolite workers receive no subagent tool; Rhyolite does not accept output from an unapproved subagent."
            else
                rhyolite_harness_set_error \
                    "Copilot started subagent '${subagent_name}' in the ${phase} phase although Rhyolite workers receive no subagent tool; Rhyolite does not accept output from an unapproved subagent."
            fi
            ;;
        substituted)
            rhyolite_harness_set_error \
                "Copilot answered the ${phase} phase with model '${detail}' instead of the approved model '${approved_model}'; Rhyolite does not accept substituted output."
            ;;
        fallback)
            rhyolite_harness_set_error \
                "Copilot attempted an automatic fallback from the approved model '${approved_model}' to model '${detail}' in the ${phase} phase after a request to the approved model did not complete; no output from '${detail}' was recorded, and Rhyolite does not accept substituted output."
            ;;
        effort-changed)
            rhyolite_harness_set_error \
                "Copilot recorded reasoning effort '${detail}' in the ${phase} phase instead of the approved effort '${approved_effort}'; Rhyolite does not accept downgraded or substituted effort."
            ;;
        unreadable | unwritable)
            rhyolite_harness_set_error "${detail}"
            ;;
        *)
            rhyolite_harness_set_error \
                "The Copilot ${phase} worker output could not be normalized."
            ;;
    esac
    return 1
}

harness_normalize_worker_output() {
    local phase="$1"
    local raw_output="$2"
    local approved_model="$3"
    local approved_effort="$4"
    local normalized_output="$5"
    local final_reply_output="$6"
    local result status detail

    rhyolite_harness_validate_normalize_arguments "$@" || return 1
    result="$(
        umask 077
        copilot_scan_structured_output \
            normalize \
            "${raw_output}" \
            "${approved_model}" \
            "${approved_effort}" \
            "${normalized_output}" \
            "${final_reply_output}" 2>/dev/null
    )" || true
    status="${result%%$'\n'*}"
    detail=''
    if [[ "${result}" == *$'\n'* ]]; then
        detail="${result#*$'\n'}"
        detail="${detail%%$'\n'*}"
    fi
    if [[ "${status}" == ok ]] &&
        chmod 600 -- "${normalized_output}" "${final_reply_output}" 2>/dev/null; then
        return 0
    fi
    rm -f -- "${normalized_output}" "${final_reply_output}"
    copilot_set_scan_error \
        "${phase}" "${status}" "${detail}" \
        "${approved_model}" "${approved_effort}"
    return 1
}

# Live enforcement while a worker runs: scan the JSONL appended since the last
# call and report the first recorded model, effort, or subagent violation so
# the runner can terminate the worker immediately instead of after completion.
harness_detect_worker_violation() {
    local phase="$1"
    local raw_output="$2"
    local approved_model="$3"
    local approved_effort="$4"
    local cursor_path="$5"
    local result status detail

    rhyolite_harness_validate_violation_arguments "$@" || return 1
    result="$(
        umask 077
        copilot_scan_structured_output \
            watch \
            "${raw_output}" \
            "${approved_model}" \
            "${approved_effort}" \
            - - \
            "${cursor_path}" 2>/dev/null
    )" || true
    status="${result%%$'\n'*}"
    detail=''
    if [[ "${result}" == *$'\n'* ]]; then
        detail="${result#*$'\n'}"
        detail="${detail%%$'\n'*}"
    fi
    case "${status}" in
        ok)
            return 0
            ;;
        subagent | substituted | fallback | effort-changed)
            copilot_set_scan_error \
                "${phase}" "${status}" "${detail}" \
                "${approved_model}" "${approved_effort}"
            return "${RHYOLITE_HARNESS_WORKER_VIOLATION_STATUS}"
            ;;
        unreadable | unwritable)
            rhyolite_harness_set_error "${detail}"
            return 1
            ;;
        *)
            rhyolite_harness_set_error \
                "The Copilot ${phase} worker output could not be scanned for approved-plan violations."
            return 1
            ;;
    esac
}

# Classify one finished Copilot worker invocation for the runner. The raw
# JSONL stdout carries session errors, model-call failures, retries, the CLI
# exit code, and every model the invocation attempted; the persisted session
# events add per-response usage, which shows when a response reached the
# per-response output token limit. Copilot CLI silently re-requests a response
# that reaches that limit and emits only the last segment, so this is the only
# reliable evidence that a reply was cut.
copilot_scan_worker_outcome() {
    local phase="$1"
    local raw_output="$2"
    local session_events="$3"
    local approved_model="$4"
    local approved_effort="$5"
    local outcome_output="$6"

    python3 - \
        "${phase}" \
        "${raw_output}" \
        "${session_events}" \
        "${approved_model}" \
        "${approved_effort}" \
        "${outcome_output}" <<'PY'
import json
import pathlib
import re
import sys

phase, raw_name, events_name, approved_model, approved_effort, output_name = sys.argv[1:7]
SAFE_TOKEN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:-]{0,127}")
TRANSIENT = re.compile(
    r"Failed to get response from the AI model|ENOTFOUND|EAI_AGAIN|ETIMEDOUT|"
    r"ECONNRESET|ECONNREFUSED|EPIPE|unexpected EOF|timed out|server error|"
    r"Service Unavailable|Bad Gateway|Gateway Timeout|overloaded|"
    r"(?:status|HTTP|code)[^0-9A-Za-z]{0,3}(?:5[0-9][0-9]|429)(?![0-9])|"
    r"(?<![0-9])(?:5[0-9][0-9]|429) (?:internal|service|bad|gateway|too many)|"
    r"rate limit",
    re.IGNORECASE,
)
PERMANENT = re.compile(
    r"is not available|not supported for model|does not support reasoning effort|"
    r"unauthori[sz]ed|forbidden|(?<![0-9])40[13](?![0-9])|authentication|"
    r"not logged in|quota",
    re.IGNORECASE,
)
SUBAGENT_EVENTS = (
    "subagent.started",
    "subagent.configured",
    "subagent.selected",
    "subagent.completed",
    "subagent.failed",
)


def clean(text):
    text = re.sub(r"[\x00-\x1f\x7f]+", " ", str(text))
    text = re.sub(r"\s+", " ", text).strip()
    return text[:400]


exit_code = None
errors = []
call_failures = 0
failure_kinds = []
turn_retries = 0
observed = []
content = []
efforts = []
subagent = False
for raw_line in pathlib.Path(raw_name).read_bytes().split(b"\n"):
    line = raw_line.strip()
    if not line.startswith(b"{"):
        continue
    try:
        event = json.loads(line.decode("utf-8", "replace"))
    except ValueError:
        continue
    if not isinstance(event, dict):
        continue
    kind = event.get("type")
    data = event.get("data") if isinstance(event.get("data"), dict) else {}
    if kind == "result":
        code = event.get("exitCode")
        if type(code) is int and -1 <= code <= 255:
            exit_code = code
    elif kind == "session.error":
        message = clean(data.get("message", ""))
        if message and message not in errors and len(errors) < 5:
            errors.append(message)
    elif kind == "model.call_failure":
        call_failures += 1
        failure_kinds.append(str(data.get("failureKind", "")))
        if isinstance(data.get("model"), str):
            observed.append(data["model"])
    elif kind == "assistant.turn_retry":
        turn_retries += 1
    elif kind in ("model.call_start", "agent.interrupted"):
        if isinstance(data.get("model"), str):
            observed.append(data["model"])
    elif kind == "model.call_final_result":
        if isinstance(data.get("model"), str):
            observed.append(data["model"])
            if data.get("result") == "success":
                content.append(data["model"])
    elif kind in ("assistant.message", "tool.execution_start", "tool.execution_complete"):
        if isinstance(data.get("model"), str):
            observed.append(data["model"])
            content.append(data["model"])
    elif kind in SUBAGENT_EVENTS:
        subagent = True
    elif kind == "session.usage_checkpoint":
        for state in data.get("promptCacheBreakState") or []:
            models = state.get("models") if isinstance(state, dict) else None
            if isinstance(models, dict):
                for call in models.values():
                    if isinstance(call, dict) and isinstance(call.get("reasoning_effort"), str):
                        efforts.append(call["reasoning_effort"])

output_limit = None
limit_hits = 0
final_at_limit = False
events_path = pathlib.Path(events_name)
if events_path.is_file() and not events_path.is_symlink():
    for raw_line in events_path.read_bytes().split(b"\n"):
        if b'"session.usage_record"' not in raw_line:
            continue
        try:
            usage = json.loads(raw_line.decode("utf-8", "replace"))["data"]["usage"]
            produced = int(usage.get("outputTokens") or 0)
            maximum = int(usage.get("maxOutputTokens") or 0)
        except (ValueError, KeyError, TypeError, AttributeError):
            continue
        if maximum > 0:
            output_limit = min(maximum, 1000000)
            final_at_limit = produced >= maximum
            limit_hits += 1 if final_at_limit else 0

attempted = [model for model in observed if model != approved_model]
fallback = ""
if (
    subagent
    or any(model != approved_model for model in content)
    or any(effort != approved_effort for effort in efforts)
):
    outcome = "substituted"
elif attempted:
    outcome = "fallback-blocked"
    fallback = attempted[0] if SAFE_TOKEN.fullmatch(attempted[0]) else "unrecognized"
elif exit_code == 0:
    outcome = "completed"
elif any(TRANSIENT.search(item) and not PERMANENT.search(item) for item in errors) or (
    exit_code not in (None, 0)
    and not errors
    and failure_kinds
    and all(kind == "transport" for kind in failure_kinds)
):
    outcome = "transient-failure"
elif exit_code is not None:
    outcome = "failed"
else:
    outcome = "unknown"
record = {
    "Schema": 1,
    "Phase": phase,
    "Outcome": outcome,
    "Retryable": outcome in ("transient-failure", "fallback-blocked"),
    "ExitCode": exit_code,
    "SessionErrors": errors,
    "ModelCallFailures": min(call_failures, 1000000),
    "TurnRetries": min(turn_retries, 1000000),
    "OutputLimitHits": min(limit_hits, 1000000),
    "OutputTokenLimit": output_limit,
    "FinalReplyAtOutputLimit": final_at_limit,
    "FallbackModel": fallback,
}
pathlib.Path(output_name).write_text(json.dumps(record, sort_keys=True) + "\n", encoding="utf-8")
PY
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
    if ! (
        umask 077
        copilot_scan_worker_outcome \
            "${phase}" \
            "${raw_output}" \
            "${runtime_home}/session-state/${session_id}/events.jsonl" \
            "${approved_model}" \
            "${approved_effort}" \
            "${outcome_output}" 2>/dev/null
    ); then
        rm -f -- "${outcome_output}"
        rhyolite_harness_set_error \
            "The Copilot ${phase} worker outcome could not be classified."
        return 1
    fi
}

# Copilot CLI resumes an existing non-interactive session when it is invoked
# again with the same --session-id and runtime home, so a continuation reuses
# the exact approved worker argv without its --name pair; only the request on
# stdin changes. --name only labels a brand-new session, and Copilot CLI
# 1.0.98-2 rejects it when --session-id resolves to an existing session
# (verified live).
harness_worker_continuation_argv() {
    local destination_name="$1"
    local source_name="$2"
    local copilot_continuation_index=0
    local copilot_continuation_sessions=0
    local -a copilot_continuation_source_copy=()
    local -a copilot_continuation_result=()

    copilot_require_array_destination "${destination_name}" || return 1
    [[ "${source_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ &&
        "${source_name}" != "${destination_name}" &&
        "${source_name}" != copilot_continuation_* &&
        "${destination_name}" != copilot_continuation_* ]] || {
        rhyolite_harness_set_error \
            'The Copilot continuation source argv name is invalid.'
        return 1
    }
    local -n copilot_continuation_source_ref="${source_name}"
    local -n copilot_continuation_output_ref="${destination_name}"
    copilot_continuation_source_copy=("${copilot_continuation_source_ref[@]}")
    while ((copilot_continuation_index < ${#copilot_continuation_source_copy[@]})); do
        case "${copilot_continuation_source_copy[copilot_continuation_index]}" in
            --session-id)
                copilot_continuation_sessions=$((copilot_continuation_sessions + 1))
                [[ "${copilot_continuation_source_copy[copilot_continuation_index + 1]-}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || {
                    rhyolite_harness_set_error \
                        'The Copilot continuation session identifier is invalid.'
                    return 1
                }
                ;;
            --name)
                ((copilot_continuation_index + 1 < ${#copilot_continuation_source_copy[@]})) || {
                    rhyolite_harness_set_error \
                        'The Copilot continuation session name is missing.'
                    return 1
                }
                copilot_continuation_index=$((copilot_continuation_index + 2))
                continue
                ;;
            -n|--name=*)
                rhyolite_harness_set_error \
                    'The Copilot continuation argv names the session in an unsupported form.'
                return 1
                ;;
        esac
        copilot_continuation_result+=(
            "${copilot_continuation_source_copy[copilot_continuation_index]}"
        )
        copilot_continuation_index=$((copilot_continuation_index + 1))
    done
    ((copilot_continuation_sessions == 1)) || {
        rhyolite_harness_set_error \
            'The Copilot continuation argv must name exactly one session.'
        return 1
    }
    copilot_continuation_output_ref=("${copilot_continuation_result[@]}")
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
    if ! copilot_extract_latest_assistant_reply \
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
    local assistant_candidate="${reply_output}.assistant.$$"

    rm -f -- "${reply_output}" "${assistant_candidate}"
    if [[ -f "${timeline}" ]] &&
        copilot_write_pure_report_repair_descriptor \
            "${timeline}" "${reply_output}"; then
        return 0
    fi
    rm -f -- "${reply_output}"

    if [[ -f "${transcript}" ]] &&
        copilot_extract_latest_assistant_reply \
            "${transcript}" repair > "${assistant_candidate}"; then
        if copilot_write_pure_report_repair_descriptor \
            "${assistant_candidate}" "${reply_output}"; then
            rm -f -- "${assistant_candidate}"
            return 0
        fi
    fi
    rm -f -- "${reply_output}" "${assistant_candidate}"
    rhyolite_harness_set_error \
        'Copilot report repair did not return a supported confidence-edit descriptor.'
    return 42
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
