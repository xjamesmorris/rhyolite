#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN_ROOT="${ROOT}/plugins/rhyolite"
HARNESS_COMMON="${PLUGIN_ROOT}/lib/harness/common.sh"
PREFERENCE_HELPER="${PLUGIN_ROOT}/scripts/launcher-preferences.sh"
RUNNER="${PLUGIN_ROOT}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh"
PROMPT="${PLUGIN_ROOT}/skills/readonly-repository-review/review-prompt.txt"
OUTPUT_HELPER="${PLUGIN_ROOT}/skills/readonly-repository-review/scripts/review-output.sh"
LAUNCHER="${PLUGIN_ROOT}/bin/rhyolite"
AGENT_ROOT="${PLUGIN_ROOT}/agents"
SKILL_ROOT="${PLUGIN_ROOT}/skills"

required_contract_functions=(
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

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local label="$3"

    [[ "${actual}" == "${expected}" ]] ||
        fail "${label}: expected '${expected}', got '${actual}'"
}

assert_contains() {
    local path="$1"
    local expected="$2"
    local label="$3"

    grep -Fq -- "${expected}" "${path}" ||
        fail "${label}: missing '${expected}'"
}

assert_not_contains() {
    local path="$1"
    local forbidden="$2"
    local label="$3"

    ! grep -Fq -- "${forbidden}" "${path}" ||
        fail "${label}: found forbidden '${forbidden}'"
}

assert_no_terminal_controls() {
    local path="$1"
    local label="$2"

    if LC_ALL=C grep -q $'[\001-\010\013-\037\177]' "${path}"; then
        fail "${label}: output contains terminal control characters"
    fi
}

fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/rhyolite-harness-contract.XXXXXXXX")"
cleanup() {
    chmod -R u+w -- "${fixture_root}" 2>/dev/null || true
    rm -rf -- "${fixture_root}"
}
trap cleanup EXIT

for path in \
    "${RUNNER}" \
    "${PROMPT}" \
    "${OUTPUT_HELPER}" \
    "${LAUNCHER}" \
    "${PREFERENCE_HELPER}"; do
    [[ -f "${path}" ]] || fail "Required production file is missing: ${path}"
done
[[ -f "${HARNESS_COMMON}" ]] ||
    fail "Harness common module is missing: ${HARNESS_COMMON}"
assert_not_contains \
    "${RUNNER}" \
    'validate-plugin.sh still locates these Copilot safeguards' \
    'Runner compatibility scaffolding'
assert_not_contains \
    "${AGENT_ROOT}/repo-review.agent.md" \
    'Legacy validator compatibility only' \
    'Agent compatibility scaffolding'
assert_not_contains \
    "${OUTPUT_HELPER}" \
    'extract_final_copilot_report' \
    'Output-helper compatibility wrapper'

resolve_harness() {
    local explicit="$1"
    local environment_mode="$2"
    local environment_value="${3-}"

    (
        case "${environment_mode}" in
            unset) unset RHYOLITE_HARNESS ;;
            set) export RHYOLITE_HARNESS="${environment_value}" ;;
            *) exit 97 ;;
        esac
        # shellcheck source=../plugins/rhyolite/lib/harness/common.sh
        source "${HARNESS_COMMON}"
        rhyolite_harness_resolve "${explicit}"
    )
}

assert_equal \
    'copilot' \
    "$(resolve_harness '' unset)" \
    'Default harness resolution'
assert_equal \
    'copilot' \
    "$(resolve_harness '' set copilot)" \
    'Environment harness resolution'
assert_equal \
    'copilot' \
    "$(resolve_harness copilot set bogus)" \
    'Explicit harness precedence'

for unsafe_id in \
    '../copilot' \
    'copilot/child' \
    'co pilot' \
    'co_pilot' \
    'Copilot' \
    '.copilot' \
    'copilot.' \
    'copilot-copilot-copilot-copilot-x' \
    $'copilot\nother' \
    $'copilot\033[31m'; do
    if resolve_harness "${unsafe_id}" unset >/dev/null 2>&1; then
        fail "Unsafe explicit harness ID was accepted: ${unsafe_id}"
    fi
    if resolve_harness '' set "${unsafe_id}" >/dev/null 2>&1; then
        fail "Unsafe RHYOLITE_HARNESS value was accepted: ${unsafe_id}"
    fi
done
if resolve_harness '' set '' >/dev/null 2>&1; then
    fail 'Empty RHYOLITE_HARNESS value was accepted.'
fi

# shellcheck source=../plugins/rhyolite/lib/harness/common.sh
unset RHYOLITE_HARNESS RHYOLITE_LAUNCHER_HARNESS
source "${HARNESS_COMMON}"
assert_equal '2' \
    "${RHYOLITE_HARNESS_CONTRACT_VERSION}" \
    'Harness contract version'
load_stdout="${fixture_root}/copilot-load.stdout"
rhyolite_harness_load "${PLUGIN_ROOT}" copilot > "${load_stdout}" ||
    fail 'Copilot harness adapter did not load.'
[[ ! -s "${load_stdout}" ]] ||
    fail 'Copilot harness adapter load wrote unexpected stdout.'
assert_equal \
    'copilot' \
    "${RHYOLITE_HARNESS_LOADED_ID}" \
    'Loaded harness ID'
assert_equal \
    "${PLUGIN_ROOT}/lib/harness/copilot.sh" \
    "${RHYOLITE_HARNESS_LOADED_PATH}" \
    'Loaded harness path'

for function_name in "${required_contract_functions[@]}"; do
    declare -F "${function_name}" >/dev/null ||
        fail "Copilot adapter is missing Contract-v2 function: ${function_name}"
done
[[ "${RHYOLITE_HARNESS_REQUIRED_FUNCTIONS[*]}" == \
    "${required_contract_functions[*]}" ]] ||
    fail 'Common loader and focused validator disagree on required functions.'

incomplete_plugin="${fixture_root}/incomplete-plugin"
mkdir -p -- "${incomplete_plugin}/lib/harness"
cp -- "${HARNESS_COMMON}" "${incomplete_plugin}/lib/harness/common.sh"
cat > "${incomplete_plugin}/lib/harness/copilot.sh" <<'INCOMPLETE_ADAPTER'
#!/usr/bin/env bash
harness_id() {
    printf 'copilot\n'
}
INCOMPLETE_ADAPTER
if bash -c '
    set -euo pipefail
    unset RHYOLITE_HARNESS RHYOLITE_LAUNCHER_HARNESS
    # shellcheck source=/dev/null
    source "$1"
    rhyolite_harness_load "$2" copilot
' bash \
    "${incomplete_plugin}/lib/harness/common.sh" \
    "${incomplete_plugin}" \
    >"${fixture_root}/incomplete.stdout" \
    2>"${fixture_root}/incomplete.stderr"; then
    fail 'Incomplete Copilot adapter unexpectedly loaded.'
fi

for unsupported_id in bogus codex claude; do
    if bash -c '
        set -euo pipefail
        unset RHYOLITE_HARNESS RHYOLITE_LAUNCHER_HARNESS
        # shellcheck source=/dev/null
        source "$1"
        rhyolite_harness_load "$2" "$3"
    ' bash \
        "${HARNESS_COMMON}" \
        "${PLUGIN_ROOT}" \
        "${unsupported_id}" \
        >"${fixture_root}/${unsupported_id}.stdout" \
        2>"${fixture_root}/${unsupported_id}.stderr"; then
        fail "Unsupported harness unexpectedly loaded: ${unsupported_id}"
    fi
done

assert_equal 'copilot' "$(harness_id)" 'Copilot harness ID'
assert_equal 'Copilot' \
    "$(harness_display_name)" \
    'Copilot display name'
assert_equal 'copilot' "$(harness_cli_name)" 'Copilot CLI name'
assert_equal 'gpt-5.6-sol' \
    "$(harness_default_model)" \
    'Copilot default model'
assert_equal 'max' \
    "$(harness_max_reasoning_effort gpt-5.6-sol)" \
    'Copilot default-model reasoning effort'
assert_equal 'max' \
    "$(harness_max_reasoning_effort claude-fable-5)" \
    'Copilot alternate-model reasoning effort'

mapfile -t model_choices < <(harness_model_choices)
[[ ${#model_choices[@]} -eq 2 &&
    "${model_choices[0]}" == \
        'GPT-5.6 Sol (Recommended) - gpt-5.6-sol' &&
    "${model_choices[1]}" == \
        'Claude Fable 5 - claude-fable-5' ]] ||
    fail 'Copilot model choices lost their exact text or order.'
for valid_model in gpt-5.6-sol claude-fable-5 gpt-6_sol model.1; do
    harness_validate_model_id "${valid_model}" ||
        fail "Copilot adapter rejected a safe model ID: ${valid_model}"
done
for invalid_model in '' '../model' 'model/name' 'model name' '-model'; do
    if harness_validate_model_id "${invalid_model}"; then
        fail "Copilot adapter accepted an unsafe model ID: ${invalid_model}"
    fi
done
if harness_max_reasoning_effort '../model' >/dev/null 2>&1; then
    fail 'Copilot maximum-effort resolution accepted an unsafe model ID.'
fi

declare -A expected_capabilities=(
    [fleet]=yes
    [structured_questions]=yes
    [subagents]=yes
    [builtin_security_specialist]=yes
    [builtin_research_specialist]=yes
    [web_research]=yes
    [shell_denial]=yes
    [final_message_file]=no
)
for capability in "${!expected_capabilities[@]}"; do
    capability_value="$(harness_capability "${capability}")"
    case "${capability_value}" in
        yes|no|unverified) ;;
        *)
            fail "Capability '${capability}' returned invalid value: ${capability_value}"
            ;;
    esac
    assert_equal \
        "${expected_capabilities[${capability}]}" \
        "${capability_value}" \
        "Copilot capability ${capability}"
done
assert_equal \
    'unverified' \
    "$(harness_capability future_unknown_capability)" \
    'Unknown capability state'

expected_auth_secret_env_vars=(
    COPILOT_GITHUB_TOKEN
    GH_TOKEN
    GITHUB_TOKEN
    COPILOT_PROVIDER_API_KEY
    COPILOT_PROVIDER_BEARER_TOKEN
    ANTHROPIC_API_KEY
    AZURE_OPENAI_API_KEY
    OPENAI_API_KEY
    CAPI_HMAC_KEY
    COPILOT_HMAC_KEY
    GITHUB_COPILOT_API_TOKEN
)
mapfile -t actual_auth_secret_env_vars < <(harness_auth_secret_env_vars)
[[ "${actual_auth_secret_env_vars[*]}" == \
    "${expected_auth_secret_env_vars[*]}" ]] ||
    fail 'Copilot protected authentication-variable contract changed.'

assert_equal \
    'Review the sanitized errors and timeline. If they show Copilot authentication failure, run copilot login from a clean non-Git directory, then retry.' \
    "$(harness_login_remediation)" \
    'Copilot login remediation'
provider_summary_path="${fixture_root}/provider-summary.json"
harness_provider_summary > "${provider_summary_path}"
python3 - \
    "${provider_summary_path}" \
    "${expected_auth_secret_env_vars[@]}" <<'PY'
import json
import pathlib
import sys

summary = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
if set(summary) != {"Id", "Host", "ForwardedEnvVarNames"}:
    raise SystemExit("Copilot provider summary keys are invalid")
if summary["Id"] != "github-copilot":
    raise SystemExit("Copilot provider summary ID changed")
if summary["Host"] != "managed-provider":
    raise SystemExit("Copilot provider host is not the safe managed summary")
if summary["ForwardedEnvVarNames"] != sys.argv[2:]:
    raise SystemExit("Copilot provider environment names changed")
PY
assert_equal \
    'Continue only through the trusted Rhyolite repo-review runner; do not invoke copilot --resume directly.' \
    "$(harness_resume_policy)" \
    'Copilot resume policy'

# shellcheck source=../plugins/rhyolite/scripts/launcher-preferences.sh
source "${PREFERENCE_HELPER}"

preference_contract_root="${fixture_root}/preference-contract"
preference_contract_repository='https://github.com/octocat/Hello-World'
rhyolite_write_preference \
    "${preference_contract_repository}" \
    copilot \
    native \
    gpt-5.6-sol \
    "${preference_contract_root}" ||
    fail 'Contract-v2 preference write failed.'
preference_contract_path="$(
    rhyolite_preference_path \
        "${preference_contract_repository}" \
        "${preference_contract_root}"
)"
python3 - "${preference_contract_path}" <<'PY'
import json
import pathlib
import sys

preference = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
if set(preference) != {
    "schemaVersion",
    "canonicalRepository",
    "harness",
    "fleetMode",
    "model",
    "updatedAt",
}:
    raise SystemExit("preference schema 2 keys are invalid")
if (
    preference["schemaVersion"] != 2
    or preference["harness"] != "copilot"
    or preference["fleetMode"] != "native"
    or preference["model"] != "gpt-5.6-sol"
):
    raise SystemExit("preference schema 2 values are invalid")
PY
rhyolite_read_preference \
    "${preference_contract_repository}" \
    copilot \
    "${preference_contract_root}" ||
    fail 'Contract-v2 preference read failed.'
[[ "${RHYOLITE_PREFERENCE_HARNESS}" == copilot &&
    "${RHYOLITE_PREFERENCE_FLEET_MODE}" == native &&
    "${RHYOLITE_PREFERENCE_MODEL}" == gpt-5.6-sol ]] ||
    fail 'Contract-v2 preference values did not round-trip.'
if rhyolite_read_preference \
    "${preference_contract_repository}" \
    codex \
    "${preference_contract_root}" ||
    [[ "${RHYOLITE_PREFERENCE_STATUS}" != mismatch ]]; then
    fail 'Harness-mismatched schema 2 preference was reused.'
fi

legacy_preference_repository='https://github.com/octocat/Spoon-Knife'
legacy_preference_path="$(
    rhyolite_preference_path \
        "${legacy_preference_repository}" \
        "${preference_contract_root}"
)"
cat > "${legacy_preference_path}" <<'EOF'
{
  "schemaVersion": 1,
  "canonicalRepository": "https://github.com/octocat/Spoon-Knife",
  "fleetMode": "standard",
  "model": "gpt-5.6-sol",
  "updatedAt": "2026-10-01T12:00:00Z"
}
EOF
chmod 600 -- "${legacy_preference_path}"
rhyolite_read_preference \
    "${legacy_preference_repository}" \
    copilot \
    "${preference_contract_root}" ||
    fail 'Legacy schema 1 Copilot preference was not accepted.'
[[ "${RHYOLITE_PREFERENCE_HARNESS}" == copilot ]] ||
    fail 'Legacy schema 1 preference was not interpreted as Copilot-only.'
if rhyolite_read_preference \
    "${legacy_preference_repository}" \
    codex \
    "${preference_contract_root}" ||
    [[ "${RHYOLITE_PREFERENCE_STATUS}" != mismatch ]]; then
    fail 'Legacy schema 1 preference was reused for a non-Copilot harness.'
fi

chmod 0770 -- "${preference_contract_root}/preferences"
if rhyolite_read_preference \
    "${preference_contract_repository}" \
    copilot \
    "${preference_contract_root}" ||
    [[ "${RHYOLITE_PREFERENCE_STATUS}" != invalid ]]; then
    fail 'Group-writable preference path was accepted.'
fi
chmod 0700 -- "${preference_contract_root}/preferences"

symlink_preference_root="${fixture_root}/preference-symlink-root"
symlink_preference_target="${fixture_root}/preference-symlink-target"
mkdir -p -- "${symlink_preference_root}" "${symlink_preference_target}"
chmod 0700 -- "${symlink_preference_root}" "${symlink_preference_target}"
ln -s -- "${symlink_preference_target}" \
    "${symlink_preference_root}/preferences"
symlink_preference_path="$(
    rhyolite_preference_path \
        "${preference_contract_repository}" \
        "${symlink_preference_root}"
)"
cp -- "${preference_contract_path}" \
    "${symlink_preference_target}/$(basename -- "${symlink_preference_path}")"
chmod 0600 -- \
    "${symlink_preference_target}/$(basename -- "${symlink_preference_path}")"
if rhyolite_read_preference \
    "${preference_contract_repository}" \
    copilot \
    "${symlink_preference_root}" ||
    [[ "${RHYOLITE_PREFERENCE_STATUS}" != invalid ]]; then
    fail 'Symlinked preference path component was accepted.'
fi

if [[ "$(id -u)" == 0 ]] && command -v chown >/dev/null 2>&1; then
    chown 65534 -- "${preference_contract_path}"
    if rhyolite_read_preference \
        "${preference_contract_repository}" \
        copilot \
        "${preference_contract_root}" ||
        [[ "${RHYOLITE_PREFERENCE_STATUS}" != invalid ]]; then
        fail 'Preference owned by another uid was accepted.'
    fi
    chown 0 -- "${preference_contract_path}"
    chmod 0600 -- "${preference_contract_path}"
fi

mock_cli_bin="${fixture_root}/mock-cli-bin"
mkdir -p -- "${mock_cli_bin}"
cat > "${mock_cli_bin}/copilot" <<'MOCK_COPILOT_CLI'
#!/usr/bin/env bash
exit 0
MOCK_COPILOT_CLI
chmod +x "${mock_cli_bin}/copilot"
require_cli_stdout="${fixture_root}/require-cli.stdout"
PATH="${mock_cli_bin}:/usr/bin:/bin" \
    harness_require_cli > "${require_cli_stdout}" ||
    fail 'Copilot adapter did not accept an available Copilot CLI.'
[[ ! -s "${require_cli_stdout}" ]] ||
    fail 'Successful Copilot CLI validation wrote unexpected stdout.'
missing_cli_stdout="${fixture_root}/missing-cli.stdout"
set +e
PATH="${fixture_root}/missing-cli" \
    harness_require_cli > "${missing_cli_stdout}" 2>/dev/null
missing_cli_status=$?
set -e
if ((missing_cli_status == 0)); then
    fail 'Copilot adapter accepted a missing Copilot CLI.'
fi
[[ ! -s "${missing_cli_stdout}" ]] ||
    fail 'Missing Copilot CLI validation wrote unexpected stdout.'
assert_equal \
    'copilot is required.' \
    "${RHYOLITE_HARNESS_ERROR_DETAIL}" \
    'Missing Copilot CLI detail'
RHYOLITE_HARNESS_ERROR_DETAIL=''

authentication_variables_csv="$(
    IFS=,
    printf '%s' "${expected_auth_secret_env_vars[*]}"
)"
base_available_tools='view,glob,rg,skill,task,list_agents,read_agent'
research_available_tools="${base_available_tools}"
worker_session_root="${fixture_root}/worker-session"
worker_transcript="${fixture_root}/worker-result/session.md"
worker_session_name='review-fixture-run'
worker_session_id='00000000-1111-2222-3333-444444444444'

write_worker_vector() {
    local selection_mode="$1"
    local enable_public_research="$2"
    local output_path="$3"

    (
        local selected_harness
        local explicit_harness=''
        local available_tools="${base_available_tools}"
        local -a worker_arguments=()

        unset RHYOLITE_LAUNCHER_HARNESS
        case "${selection_mode}" in
            default)
                unset RHYOLITE_HARNESS
                ;;
            explicit)
                export RHYOLITE_HARNESS=bogus
                explicit_harness='copilot'
                ;;
            *)
                exit 94
                ;;
        esac
        if ((enable_public_research)); then
            available_tools="${research_available_tools}"
        fi

        # shellcheck source=../plugins/rhyolite/lib/harness/common.sh
        source "${HARNESS_COMMON}"
        selected_harness="$(
            rhyolite_harness_resolve "${explicit_harness}"
        )"
        rhyolite_harness_load "${PLUGIN_ROOT}" "${selected_harness}"
        harness_worker_argv \
            worker_arguments \
            "${worker_session_root}" \
            "${PLUGIN_ROOT}" \
            "${worker_session_name}" \
            "${worker_session_id}" \
            gpt-5.6-sol \
            max \
            "${authentication_variables_csv}" \
            "${available_tools}" \
            "${worker_transcript}" \
            "${enable_public_research}"
        printf '%s\0' "${worker_arguments[@]}" > "${output_path}"
    )
}

worker_default_vector="${fixture_root}/worker-default.vector"
worker_explicit_vector="${fixture_root}/worker-explicit.vector"
worker_research_vector="${fixture_root}/worker-research.vector"
write_worker_vector default 0 "${worker_default_vector}"
write_worker_vector explicit 0 "${worker_explicit_vector}"
write_worker_vector explicit 1 "${worker_research_vector}"
cmp -s "${worker_default_vector}" "${worker_explicit_vector}" ||
    fail 'Default and explicit Copilot worker vectors differ.'

expected_worker_arguments=(
    -C "${worker_session_root}"
    --plugin-dir "${PLUGIN_ROOT}"
    --name "${worker_session_name}"
    --session-id "${worker_session_id}"
    --agent rhyolite:repo-review-worker
    --model gpt-5.6-sol
    --reasoning-effort max
    --context long_context
    --no-ask-user
    --no-color
    --no-custom-instructions
    --disable-builtin-mcps
    --disallow-temp-dir
    --no-remote-export
    --secret-env-vars "${authentication_variables_csv}"
    --available-tools "${base_available_tools}"
    --allow-tool read
    --deny-tool write
    --deny-tool shell
    --stream off
    --share "${worker_transcript}"
    --silent
)
expected_worker_vector="${fixture_root}/worker-expected.vector"
printf '%s\0' "${expected_worker_arguments[@]}" > "${expected_worker_vector}"
cmp -s "${expected_worker_vector}" "${worker_default_vector}" ||
    fail 'Copilot worker argv changed from the I1a baseline.'

expected_research_worker_arguments=(
    -C "${worker_session_root}"
    --plugin-dir "${PLUGIN_ROOT}"
    --name "${worker_session_name}"
    --session-id "${worker_session_id}"
    --agent rhyolite:repo-review-worker
    --model gpt-5.6-sol
    --reasoning-effort max
    --context long_context
    --no-ask-user
    --no-color
    --no-custom-instructions
    --disable-builtin-mcps
    --disallow-temp-dir
    --no-remote-export
    --secret-env-vars "${authentication_variables_csv}"
    --available-tools "${research_available_tools}"
    --allow-tool read
    --deny-tool write
    --deny-tool shell
    --stream off
    --share "${worker_transcript}"
    --silent
)
expected_research_worker_vector="${fixture_root}/worker-research-expected.vector"
printf '%s\0' \
    "${expected_research_worker_arguments[@]}" \
    > "${expected_research_worker_vector}"
cmp -s "${expected_research_worker_vector}" "${worker_research_vector}" ||
    fail 'Copilot main worker gained public-network access from the dedicated research phase.'

for worker_vector in \
    "${worker_default_vector}" \
    "${worker_explicit_vector}" \
    "${worker_research_vector}"; do
    mapfile -d '' -t captured_worker_arguments < "${worker_vector}"
    for captured_argument in "${captured_worker_arguments[@]}"; do
        [[ "${captured_argument}" != *'--harness'* ]] ||
            fail "Rhyolite forwarded --harness to a Copilot worker: ${worker_vector}"
    done
done

source_copilot_home="${fixture_root}/source-copilot-home"
runtime_home="${fixture_root}/runtime-copilot-home"
agent_state="${fixture_root}/agent-state"
mkdir -m 700 -- "${source_copilot_home}" "${runtime_home}"
cat > "${source_copilot_home}/config.json" <<'EOF'
{
  "lastLoggedInUser": "fixture-user",
  "copilotTokens": {
    "fixture-user": "bridge-secret"
  },
  "unrelatedSetting": "must-not-bridge"
}
EOF
chmod 600 -- "${source_copilot_home}/config.json"
COPILOT_HOME="${source_copilot_home}"
COPILOT_AUTH_BRIDGE_INITIALIZED=0
COPILOT_AUTH_BRIDGE_HAS_PLAINTEXT=0
COPILOT_AUTH_BRIDGE_JSON='{}'
prepare_run_output="${fixture_root}/prepare-run.stdout"
harness_prepare_run > "${prepare_run_output}" ||
    fail 'Copilot adapter could not prepare the authentication bridge.'
assert_contains \
    "${prepare_run_output}" \
    'Copilot authentication will be verified' \
    'Copilot run preparation'
cat > "${source_copilot_home}/config.json" <<'EOF'
{
  "lastLoggedInUser": "must-not-be-reread",
  "copilotTokens": {
    "must-not-be-reread": "replacement-secret"
  }
}
EOF
prepare_run_second_output="${fixture_root}/prepare-run-second.stdout"
harness_prepare_run > "${prepare_run_second_output}" ||
    fail 'Repeated Copilot run preparation unexpectedly failed.'
[[ ! -s "${prepare_run_second_output}" ]] ||
    fail 'Repeated Copilot run preparation was not silent.'
[[ "${COPILOT_AUTH_BRIDGE_JSON}" == *'"fixture-user"'* &&
    "${COPILOT_AUTH_BRIDGE_JSON}" != *'must-not-be-reread'* ]] ||
    fail 'Repeated Copilot run preparation reread mutable source config.'
harness_prepare_worker_home "${runtime_home}" ||
    fail 'Copilot adapter could not prepare the worker home.'
[[ "$(stat -c '%a' "${runtime_home}")" == 700 ]] ||
    fail 'Copilot runtime home is not mode 700.'
for private_file in \
    "${runtime_home}/settings.json" \
    "${runtime_home}/config.json"; do
    [[ "$(stat -c '%a' "${private_file}")" == 600 ]] ||
        fail "Copilot runtime file is not mode 600: ${private_file}"
done
assert_contains \
    "${runtime_home}/settings.json" \
    '"storeTokenPlaintext": true' \
    'Copilot plaintext-token bridge setting'
assert_contains \
    "${runtime_home}/settings.json" \
    '"disableAllHooks": true' \
    'Copilot hook isolation setting'
assert_contains \
    "${runtime_home}/settings.json" \
    '"defaultLocalOnly": true' \
    'Copilot local-only agent setting'
assert_contains \
    "${runtime_home}/config.json" \
    '"lastLoggedInUser":"fixture-user"' \
    'Copilot login metadata bridge'
assert_contains \
    "${runtime_home}/config.json" \
    '"copilotTokens":{"fixture-user":"bridge-secret"}' \
    'Copilot plaintext-token bridge'
assert_not_contains \
    "${runtime_home}/config.json" \
    'must-not-bridge' \
    'Copilot auth bridge allowlist'

metadata_copilot_home="${fixture_root}/metadata-copilot-home"
metadata_runtime_home="${fixture_root}/metadata-runtime-home"
mkdir -m 700 -- "${metadata_copilot_home}" "${metadata_runtime_home}"
cat > "${metadata_copilot_home}/config.json" <<'EOF'
{
  "lastLoggedInUser": "metadata-only-user",
  "unrelatedSetting": "must-not-bridge"
}
EOF
chmod 600 -- "${metadata_copilot_home}/config.json"
COPILOT_HOME="${metadata_copilot_home}"
COPILOT_AUTH_BRIDGE_INITIALIZED=0
COPILOT_AUTH_BRIDGE_HAS_PLAINTEXT=0
COPILOT_AUTH_BRIDGE_JSON='{}'
harness_prepare_run >/dev/null ||
    fail 'Copilot adapter could not prepare metadata-only authentication.'
harness_prepare_worker_home "${metadata_runtime_home}" ||
    fail 'Copilot adapter could not prepare a metadata-only worker home.'
assert_not_contains \
    "${metadata_runtime_home}/settings.json" \
    'storeTokenPlaintext' \
    'Copilot metadata-only settings'
assert_contains \
    "${metadata_runtime_home}/config.json" \
    '"lastLoggedInUser":"metadata-only-user"' \
    'Copilot metadata-only bridge'
harness_sanitize_runtime_home "${metadata_runtime_home}" ||
    fail 'Copilot adapter could not clean the metadata-only runtime home.'

assert_fail_soft_auth_config() {
    local name="$1"
    local fixture_mode="$2"
    local fixture_value="${3-}"
    local case_home="${fixture_root}/auth-fail-soft-${name}-home"
    local case_runtime="${fixture_root}/auth-fail-soft-${name}-runtime"
    local case_output="${fixture_root}/auth-fail-soft-${name}.stdout"
    local case_config="${case_home}/config.json"

    mkdir -m 700 -- "${case_home}" "${case_runtime}"
    case "${fixture_mode}" in
        text)
            printf '%s\n' "${fixture_value}" > "${case_config}"
            ;;
        invalid-utf8)
            printf '\377\376\375\n' > "${case_config}"
            ;;
        unreadable)
            printf '%s\n' "${fixture_value}" > "${case_config}"
            chmod 000 -- "${case_config}"
            ;;
        *)
            fail "Unknown fail-soft auth fixture mode: ${fixture_mode}"
            ;;
    esac

    COPILOT_HOME="${case_home}"
    COPILOT_AUTH_BRIDGE_INITIALIZED=0
    COPILOT_AUTH_BRIDGE_HAS_PLAINTEXT=0
    COPILOT_AUTH_BRIDGE_JSON='{}'
    harness_prepare_run > "${case_output}" ||
        fail "Copilot adapter rejected fail-soft auth fixture: ${name}"
    [[ "${COPILOT_AUTH_BRIDGE_INITIALIZED}" -eq 1 &&
        "${COPILOT_AUTH_BRIDGE_HAS_PLAINTEXT}" -eq 0 &&
        "${COPILOT_AUTH_BRIDGE_JSON}" == '{}' ]] ||
        fail "Copilot fail-soft auth state is invalid: ${name}"
    assert_contains \
        "${case_output}" \
        'Copilot authentication will be verified' \
        "Copilot fail-soft auth output ${name}"

    if [[ -e "${case_config}" ]]; then
        chmod 600 -- "${case_config}" 2>/dev/null || true
    fi
    harness_prepare_worker_home "${case_runtime}" ||
        fail "Copilot fail-soft worker home failed: ${name}"
    assert_not_contains \
        "${case_runtime}/settings.json" \
        'storeTokenPlaintext' \
        "Copilot fail-soft settings ${name}"
    assert_contains \
        "${case_runtime}/config.json" \
        '{}' \
        "Copilot fail-soft config ${name}"
    assert_not_contains \
        "${case_runtime}/config.json" \
        'must-not-cross' \
        "Copilot fail-soft bridge ${name}"
    harness_sanitize_runtime_home "${case_runtime}" ||
        fail "Copilot fail-soft cleanup failed: ${name}"
}

assert_fail_soft_auth_config null text 'null'
assert_fail_soft_auth_config array text '[]'
assert_fail_soft_auth_config string text '"not-an-object"'
assert_fail_soft_auth_config malformed text '{'
assert_fail_soft_auth_config invalid-utf8 invalid-utf8
assert_fail_soft_auth_config \
    unreadable \
    unreadable \
    '{"lastLoggedInUser":"must-not-cross"}'
unset COPILOT_HOME

declare -a worker_environment=()
COPILOT_RUNTIME_HOME="${runtime_home}"
harness_worker_env worker_environment
expected_worker_environment=(
    -u COPILOT_ALLOW_ALL
    -u COPILOT_SKILLS_DIRS
    -u COPILOT_CUSTOM_INSTRUCTIONS_DIRS
    -u COPILOT_DYNAMIC_RETRIEVAL_SKILLS
    -u COPILOT_EMBEDDING_ONLY_SKILLS
    "COPILOT_HOME=${runtime_home}"
)
worker_environment_vector="${fixture_root}/worker-environment.vector"
expected_worker_environment_vector="${fixture_root}/worker-environment-expected.vector"
printf '%s\0' "${worker_environment[@]}" > "${worker_environment_vector}"
printf '%s\0' \
    "${expected_worker_environment[@]}" \
    > "${expected_worker_environment_vector}"
cmp -s \
    "${expected_worker_environment_vector}" \
    "${worker_environment_vector}" ||
    fail 'Copilot worker environment changed from the I1a baseline.'

rendered_request="${fixture_root}/rendered-request.txt"
harness_render_request \
    "${PROMPT}" \
    "${rendered_request}" \
    'https://github.com/octocat/Hello-World' \
    "${worker_session_root}/source" \
    '7fd1a60b01f91b314f59955a4e4d4e80d8edf11d' \
    '2026-10-01' \
    '2026-04-01' \
    0 \
    '' \
    '' \
    '1 - Core repository review' \
    "${fixture_root}/worker-result" \
    'TRUSTED FIXTURE METADATA' \
    'PUBLIC RESEARCH DISABLED' \
    'PROVENANCE DISABLED' \
    'disabled' \
    'disabled' \
    'RESEARCH TRANSPORT DISABLED' ||
    fail 'Copilot adapter could not render the worker request.'
for expected_request_line in \
    'Repository URL: https://github.com/octocat/Hello-World' \
    "Read-only source snapshot: ${worker_session_root}/source" \
    'Exact commit to review: 7fd1a60b01f91b314f59955a4e4d4e80d8edf11d' \
    'Review date: 2026-10-01' \
    'Recent-prior-art window: 2026-04-01 through 2026-10-01' \
    'Provenance lookback months: disabled' \
    'Provenance start date: disabled' \
    'Selected scope: 1 - Core repository review' \
    'TRUSTED FIXTURE METADATA' \
    'PUBLIC RESEARCH DISABLED' \
    'PROVENANCE DISABLED' \
    'RESEARCH TRANSPORT DISABLED'; do
    assert_contains \
        "${rendered_request}" \
        "${expected_request_line}" \
        'Copilot request rendering'
done
assert_not_contains \
    "${rendered_request}" \
    '{{' \
    'Copilot request rendering'

mkdir -p -- \
    "${runtime_home}/session-state/mock-session" \
    "${runtime_home}/session-store" \
    "${runtime_home}/other-state"
printf '{"status":"saved"}\n' \
    > "${runtime_home}/session-state/mock-session/state.json"
printf 'mock-session-database\n' \
    > "${runtime_home}/session-store/sessions.db"
printf 'must-not-persist bridge-secret\n' \
    > "${runtime_home}/other-state/secret.txt"
harness_persist_agent_state "${runtime_home}" "${agent_state}" ||
    fail 'Copilot adapter could not persist allowlisted agent state.'
persisted_home="${agent_state}/copilot-home"
[[ -f "${persisted_home}/session-state/mock-session/state.json" &&
    -f "${persisted_home}/session-store/sessions.db" ]] ||
    fail 'Copilot adapter omitted allowlisted session state.'
[[ ! -e "${persisted_home}/other-state" ]] ||
    fail 'Copilot adapter persisted non-allowlisted runtime state.'
assert_not_contains \
    "${persisted_home}/settings.json" \
    'storeTokenPlaintext' \
    'Persisted Copilot settings'
assert_not_contains \
    "${persisted_home}/config.json" \
    'bridge-secret' \
    'Persisted Copilot config'
if grep -RFl -- 'bridge-secret' "${persisted_home}" >/dev/null; then
    fail 'Persisted Copilot state contains authentication bridge data.'
fi
while IFS= read -r persisted_path; do
    if [[ -d "${persisted_path}" ]]; then
        [[ "$(stat -c '%a' "${persisted_path}")" == 700 ]] ||
            fail "Persisted Copilot directory is not mode 700: ${persisted_path}"
    else
        [[ "$(stat -c '%a' "${persisted_path}")" == 600 ]] ||
            fail "Persisted Copilot file is not mode 600: ${persisted_path}"
    fi
done < <(find "${persisted_home}" -print)

# shellcheck source=../plugins/rhyolite/skills/readonly-repository-review/scripts/review-output.sh
source "${OUTPUT_HELPER}"
fallback_timeline="${fixture_root}/fallback-timeline.txt"
fallback_transcript="${fixture_root}/fallback-transcript.md"
fallback_final_message="${fixture_root}/fallback-final-message.txt"
fallback_report="${fixture_root}/fallback-report.txt"
cat > "${fallback_timeline}" <<'EOF'
================================================================================
REPOSITORY REVIEW REPORT
Truncated standard output.
EOF
cat > "${fallback_transcript}" <<'EOF'
# Copilot session

### User

Return the canonical report.

### Copilot

================================================================================
REPOSITORY REVIEW REPORT
Complete deterministic report recovered from the transcript.
================================================================================

---

<sub>Generated by GitHub Copilot CLI</sub>
EOF
harness_extract_final_report \
    "${fallback_timeline}" \
    "${fallback_transcript}" \
    "${fallback_final_message}" \
    "${fallback_report}" ||
    fail 'Copilot transcript report fallback failed.'
assert_contains \
    "${fallback_report}" \
    'Complete deterministic report recovered from the transcript.' \
    'Copilot transcript report fallback'
report_has_closing_delimiter "${fallback_report}" ||
    fail 'Copilot transcript fallback report lost its closing delimiter.'
[[ ! -e "${fallback_final_message}" ]] ||
    fail 'Copilot transcript fallback left a temporary final-message file.'

missing_section_transcript="${fixture_root}/missing-section-transcript.md"
missing_section_temp="${fixture_root}/missing-section-final-message.txt"
missing_section_report="${fixture_root}/missing-section-report.txt"
printf '# Transcript without a final Copilot section\n' \
    > "${missing_section_transcript}"
set +e
harness_extract_final_report \
    "${fallback_timeline}" \
    "${missing_section_transcript}" \
    "${missing_section_temp}" \
    "${missing_section_report}" >/dev/null
missing_section_status=$?
set -e
[[ "${missing_section_status}" -eq 42 ]] ||
    fail "Copilot missing-section extraction returned ${missing_section_status}, expected 42."
[[ ! -e "${missing_section_temp}" ]] ||
    fail 'Copilot missing-section extraction left its temporary file.'

isolation_fixture="${fixture_root}/copilot-events.txt"
printf 'Copilot adapter has no structured event isolation file.\n' \
    > "${isolation_fixture}"
isolation_before="$(sha256sum "${isolation_fixture}" | awk '{print $1}')"
harness_verify_isolation "${isolation_fixture}" ||
    fail 'Copilot isolation no-op unexpectedly failed.'
isolation_after="$(sha256sum "${isolation_fixture}" | awk '{print $1}')"
assert_equal \
    "${isolation_before}" \
    "${isolation_after}" \
    'Copilot isolation no-op'

for allow_all_value in true TRUE 1 yes YeS; do
    (
        COPILOT_ALLOW_ALL="${allow_all_value}"
        harness_allow_all_detected
    ) || fail "Copilot allow-all detection rejected: ${allow_all_value}"
done
for allow_all_value in false FALSE 0 no ''; do
    if (
        COPILOT_ALLOW_ALL="${allow_all_value}"
        harness_allow_all_detected
    ); then
        fail "Copilot allow-all detection accepted: ${allow_all_value}"
    fi
done
if (
    unset COPILOT_ALLOW_ALL
    harness_allow_all_detected
); then
    fail 'Copilot allow-all detection accepted an unset marker.'
fi

harness_sanitize_runtime_home "${runtime_home}" ||
    fail 'Copilot adapter could not remove the runtime home.'
[[ ! -e "${runtime_home}" ]] ||
    fail 'Copilot adapter left the runtime home after cleanup.'
harness_sanitize_runtime_home "${runtime_home}" ||
    fail 'Copilot runtime-home cleanup is not idempotent.'

for shim_root in "${AGENT_ROOT}" "${SKILL_ROOT}"; do
    while IFS= read -r shim_path; do
        if grep -F 'run-parallel-reviews.sh' "${shim_path}" |
            grep -Fvq -- '--harness copilot'; then
            fail "Runner shim omits explicit --harness copilot: ${shim_path}"
        fi
    done < <(
        find "${shim_root}" -type f -name '*.md' -print |
            LC_ALL=C sort |
            while IFS= read -r candidate; do
                grep -Fq 'run-parallel-reviews.sh' "${candidate}" &&
                    printf '%s\n' "${candidate}"
            done
    )
done

plan_workspace="${fixture_root}/plan-workspace"
plan_output="${fixture_root}/plan-output"
plan_default="${fixture_root}/plan-default.json"
plan_environment="${fixture_root}/plan-environment.json"
plan_explicit="${fixture_root}/plan-explicit.json"
plan_override="${fixture_root}/plan-override.json"
plan_stderr="${fixture_root}/plan.stderr"
plan_mock_bin="${fixture_root}/plan-mock-bin"
mkdir -p -- "${plan_mock_bin}"
cat > "${plan_mock_bin}/date" <<'MOCK_PLAN_DATE'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
    '-u +%Y-%m-%dT%H:%M:%SZ')
        printf '2026-10-01T12:00:00Z\n'
        ;;
    '+%Y-%m-%d')
        printf '2026-10-01\n'
        ;;
    *)
        exec /usr/bin/date "$@"
        ;;
esac
MOCK_PLAN_DATE
chmod +x "${plan_mock_bin}/date"
plan_arguments=(
    --repo https://github.com/octocat/Hello-World
    --scope 1
    --workspace-root "${plan_workspace}"
    --output-root "${plan_output}"
    --non-interactive
    --no-open-html
    --plan-only
)

for hash_fragment in \
    'PlanSchemaVersion=%s' \
    'Harness=%s' \
    'ReasoningEffort=%s' \
    'Provider=%s'; do
    assert_contains \
        "${RUNNER}" \
        "${hash_fragment}" \
        'Harness identity approval-hash material'
done

env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${plan_mock_bin}:${PATH}" \
    "${RUNNER}" "${plan_arguments[@]}" \
    >"${plan_default}" 2>"${plan_stderr}" ||
    fail 'Marker-unset default Copilot plan-only invocation failed.'
[[ ! -s "${plan_stderr}" ]] ||
    fail 'Default Copilot plan-only invocation wrote stderr.'

RHYOLITE_HARNESS=copilot \
    env -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${plan_mock_bin}:${PATH}" \
    "${RUNNER}" "${plan_arguments[@]}" \
    >"${plan_environment}" 2>"${plan_stderr}" ||
    fail 'Marker-unset RHYOLITE_HARNESS=copilot plan-only invocation failed.'
[[ ! -s "${plan_stderr}" ]] ||
    fail 'Environment-selected Copilot plan-only invocation wrote stderr.'

env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${plan_mock_bin}:${PATH}" \
    "${RUNNER}" --harness copilot "${plan_arguments[@]}" \
    >"${plan_explicit}" 2>"${plan_stderr}" ||
    fail 'Marker-unset explicit Copilot plan-only invocation failed.'
[[ ! -s "${plan_stderr}" ]] ||
    fail 'Explicit Copilot plan-only invocation wrote stderr.'

env \
    RHYOLITE_HARNESS=bogus \
    RHYOLITE_LAUNCHER_HARNESS=copilot \
    PATH="${plan_mock_bin}:${PATH}" \
    "${RUNNER}" --harness copilot "${plan_arguments[@]}" \
    >"${plan_override}" 2>"${plan_stderr}" ||
    fail 'Explicit Copilot did not override RHYOLITE_HARNESS within matching launcher context.'
[[ ! -s "${plan_stderr}" ]] ||
    fail 'Explicit-over-environment Copilot launcher-context plan wrote stderr.'

python3 - \
    "${plan_default}" \
    "${plan_environment}" \
    "${plan_explicit}" \
    "${plan_override}" <<'PY'
import json
import pathlib
import sys

plans = [json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
         for path in sys.argv[1:]]
for index, plan in enumerate(plans):
    if plan.get("SchemaVersion") != 4:
        raise SystemExit(f"plan {index} did not use harness-aware schema 4")
    if plan.get("Harness") != "copilot":
        raise SystemExit(f"plan {index} lost the selected harness")
    if plan.get("ReasoningEffort") != "max":
        raise SystemExit(f"plan {index} lost resolved reasoning effort")
    provider = plan.get("Provider")
    if not isinstance(provider, dict) or set(provider) != {
        "Id", "Host", "ForwardedEnvVarNames"
    }:
        raise SystemExit(f"plan {index} has invalid provider metadata")
    if (
        provider["Id"] != "github-copilot"
        or provider["Host"] != "managed-provider"
        or provider["ForwardedEnvVarNames"] != [
            "COPILOT_GITHUB_TOKEN",
            "GH_TOKEN",
            "GITHUB_TOKEN",
            "COPILOT_PROVIDER_API_KEY",
            "COPILOT_PROVIDER_BEARER_TOKEN",
            "ANTHROPIC_API_KEY",
            "AZURE_OPENAI_API_KEY",
            "OPENAI_API_KEY",
            "CAPI_HMAC_KEY",
            "COPILOT_HMAC_KEY",
            "GITHUB_COPILOT_API_TOKEN",
        ]
    ):
        raise SystemExit(f"plan {index} changed Copilot provider metadata")
    approval_hash = plan.get("ApprovalHash")
    if not isinstance(approval_hash, str) or len(approval_hash) != 64:
        raise SystemExit(f"plan {index} has an invalid ApprovalHash")
hashes = {plan["ApprovalHash"] for plan in plans}
if len(hashes) != 1:
    raise SystemExit("default, environment, explicit, and overriding Copilot plans changed ApprovalHash")
PY

copy_identity_fixture() {
    local name="$1"
    local fixture_plugin="${fixture_root}/${name}-identity-plugin"
    local fixture_skill="${fixture_plugin}/skills/readonly-repository-review"
    local fixture_scripts="${fixture_skill}/scripts"

    mkdir -p -- \
        "${fixture_plugin}/lib/harness" \
        "${fixture_plugin}/scripts" \
        "${fixture_scripts}"
    cp -- "${HARNESS_COMMON}" "${fixture_plugin}/lib/harness/common.sh"
    cp -- "${PLUGIN_ROOT}/lib/harness/copilot.sh" \
        "${fixture_plugin}/lib/harness/copilot.sh"
    cp -- "${PREFERENCE_HELPER}" \
        "${fixture_plugin}/scripts/launcher-preferences.sh"
    cp -- "${RUNNER}" "${fixture_scripts}/run-parallel-reviews.sh"
    cp -- "${OUTPUT_HELPER}" "${fixture_scripts}/review-output.sh"
    cp -- "${PROMPT}" "${fixture_skill}/review-prompt.txt"
    chmod +x "${fixture_scripts}/run-parallel-reviews.sh"
    printf '%s\n' "${fixture_plugin}"
}

provider_identity_plugin="$(copy_identity_fixture provider)"
cat >> "${provider_identity_plugin}/lib/harness/copilot.sh" <<'PROVIDER_IDENTITY_OVERRIDE'

harness_provider_summary() {
    printf '%s\n' '{"Id":"github-copilot","Host":"alternate-managed-provider","ForwardedEnvVarNames":["COPILOT_GITHUB_TOKEN","GH_TOKEN","GITHUB_TOKEN","COPILOT_PROVIDER_API_KEY","COPILOT_PROVIDER_BEARER_TOKEN","ANTHROPIC_API_KEY","AZURE_OPENAI_API_KEY","OPENAI_API_KEY","CAPI_HMAC_KEY","COPILOT_HMAC_KEY","GITHUB_COPILOT_API_TOKEN"]}'
}
PROVIDER_IDENTITY_OVERRIDE
provider_identity_plan="${fixture_root}/provider-identity-plan.json"
PATH="${plan_mock_bin}:${PATH}" \
    "${provider_identity_plugin}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh" \
    "${plan_arguments[@]}" > "${provider_identity_plan}" ||
    fail 'Provider-identity plan fixture failed.'

reasoning_identity_plugin="$(copy_identity_fixture reasoning)"
cat >> "${reasoning_identity_plugin}/lib/harness/copilot.sh" <<'REASONING_IDENTITY_OVERRIDE'

harness_max_reasoning_effort() {
    harness_validate_model_id "$1" || return 1
    printf '%s\n' 'high'
}
REASONING_IDENTITY_OVERRIDE
reasoning_identity_plan="${fixture_root}/reasoning-identity-plan.json"
PATH="${plan_mock_bin}:${PATH}" \
    "${reasoning_identity_plugin}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh" \
    "${plan_arguments[@]}" > "${reasoning_identity_plan}" ||
    fail 'Reasoning-identity plan fixture failed.'

python3 - \
    "${plan_default}" \
    "${provider_identity_plan}" \
    "${reasoning_identity_plan}" <<'PY'
import json
import pathlib
import sys

plans = [
    json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    for path in sys.argv[1:]
]
if len({plan["ApprovalHash"] for plan in plans}) != 3:
    raise SystemExit("provider or reasoning identity did not change ApprovalHash")
if plans[1]["Provider"]["Host"] != "alternate-managed-provider":
    raise SystemExit("provider identity fixture did not reach the plan")
if plans[2]["ReasoningEffort"] != "high":
    raise SystemExit("reasoning identity fixture did not reach the plan")
PY

legacy_identity_hash="$(
    python3 - "${plan_default}" <<'PY'
import json
import pathlib
import sys
print(json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))["ApprovalHash"])
PY
)"
identity_mismatch_stderr="${fixture_root}/identity-mismatch.stderr"
set +e
PATH="${plan_mock_bin}:${PATH}" \
    "${provider_identity_plugin}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh" \
    --repo https://github.com/octocat/Hello-World \
    --scope 1 \
    --workspace-root "${plan_workspace}" \
    --output-root "${plan_output}" \
    --non-interactive \
    --no-open-html \
    --expected-plan-hash "${legacy_identity_hash}" \
    >"${fixture_root}/identity-mismatch.stdout" \
    2>"${identity_mismatch_stderr}"
identity_mismatch_status=$?
set -e
((identity_mismatch_status == 2)) ||
    fail 'A plan hash from different provider identity authorized execution.'
assert_contains \
    "${identity_mismatch_stderr}" \
    'approved plan changed; regenerate and reconfirm' \
    'Identity-bound approval mismatch'

invalid_provider_plugin="$(copy_identity_fixture invalid-provider)"
cat >> "${invalid_provider_plugin}/lib/harness/copilot.sh" <<'INVALID_PROVIDER_OVERRIDE'

harness_provider_summary() {
    printf '%s\n' '{"Id":"github-copilot","Host":"managed-provider","ForwardedEnvVarNames":[],"Extra":"forbidden"}'
}
INVALID_PROVIDER_OVERRIDE
invalid_provider_stderr="${fixture_root}/invalid-provider.stderr"
set +e
PATH="${plan_mock_bin}:${PATH}" \
    "${invalid_provider_plugin}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh" \
    "${plan_arguments[@]}" >"${fixture_root}/invalid-provider.stdout" \
    2>"${invalid_provider_stderr}"
invalid_provider_status=$?
set -e
((invalid_provider_status == 2)) ||
    fail 'Provider summary with an extra key was accepted.'
assert_contains \
    "${invalid_provider_stderr}" \
    'Stage: harness copilot harness_provider_summary' \
    'Strict provider summary validation'
[[ ! -e "${plan_workspace}" && ! -e "${plan_output}" ]] ||
    fail 'Plan-only harness validation created workspace or output roots.'

guard_bin="${fixture_root}/guard-bin"
guard_log="${fixture_root}/guard-activity.log"
mkdir -p -- "${guard_bin}"
cat > "${guard_bin}/copilot" <<'GUARD_COPILOT'
#!/usr/bin/env bash
set -euo pipefail
printf 'copilot\n' >> "${RHYOLITE_GUARD_LOG:?}"
exit 96
GUARD_COPILOT
cat > "${guard_bin}/git" <<'GUARD_GIT'
#!/usr/bin/env bash
set -euo pipefail
printf 'git\n' >> "${RHYOLITE_GUARD_LOG:?}"
exit 95
GUARD_GIT
cat > "${guard_bin}/curl" <<'GUARD_CURL'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl\n' >> "${RHYOLITE_GUARD_LOG:?}"
exit 94
GUARD_CURL
cat > "${guard_bin}/python3" <<'GUARD_PYTHON'
#!/usr/bin/env bash
set -euo pipefail
printf 'python3\n' >> "${RHYOLITE_GUARD_LOG:?}"
exit 93
GUARD_PYTHON
chmod +x \
    "${guard_bin}/copilot" \
    "${guard_bin}/git" \
    "${guard_bin}/curl" \
    "${guard_bin}/python3"

assert_pre_activity_failure() {
    local name="$1"
    local expected_stage="$2"
    local selection_mode="$3"
    local selected_harness="$4"
    local marker_mode="$5"
    local marker_value="${6-}"
    local stdout_path="${fixture_root}/${name}.stdout"
    local stderr_path="${fixture_root}/${name}.stderr"
    local workspace_path="${fixture_root}/${name}-workspace"
    local output_path="${fixture_root}/${name}-output"
    local status
    local -a command_env=(env)
    local -a environment_assignments=()
    local -a harness_arguments=()

    case "${selection_mode}" in
        explicit)
            command_env+=(-u RHYOLITE_HARNESS)
            harness_arguments=(--harness "${selected_harness}")
            ;;
        environment)
            environment_assignments+=(
                "RHYOLITE_HARNESS=${selected_harness}"
            )
            ;;
        *)
            fail "Invalid harness selection mode: ${selection_mode}"
            ;;
    esac

    case "${marker_mode}" in
        unset) command_env+=(-u RHYOLITE_LAUNCHER_HARNESS) ;;
        set) command_env+=("RHYOLITE_LAUNCHER_HARNESS=${marker_value}") ;;
        *) fail "Invalid marker test mode: ${marker_mode}" ;;
    esac
    environment_assignments+=(
        RHYOLITE_GUARD_LOG="${guard_log}"
        PATH="${guard_bin}:/usr/bin:/bin"
    )
    command_env+=("${environment_assignments[@]}")

    rm -f -- "${guard_log}"
    set +e
    "${command_env[@]}" \
        "${RUNNER}" \
        "${harness_arguments[@]}" \
        --repo https://github.com/octocat/Hello-World \
        --scope 1 \
        --workspace-root "${workspace_path}" \
        --output-root "${output_path}" \
        --non-interactive \
        --no-open-html >"${stdout_path}" 2>"${stderr_path}"
    status=$?
    set -e

    ((status != 0)) ||
        fail "${name}: harness failure unexpectedly succeeded"
    assert_contains "${stderr_path}" "Stage: ${expected_stage}" "${name}"
    assert_no_terminal_controls "${stderr_path}" "${name}"
    assert_no_terminal_controls "${stdout_path}" "${name} stdout"
    assert_not_contains \
        "${stdout_path}" \
        'EFFECTIVE REVIEW PLAN' \
        "${name} stdout"
    [[ ! -e "${guard_log}" ]] ||
        fail "${name}: failure invoked downstream CLI, Git, or network activity"
    [[ ! -e "${workspace_path}" && ! -e "${output_path}" ]] ||
        fail "${name}: failure created workspace or output roots"
}

assert_pre_activity_failure \
    bogus-load \
    'harness bogus load' \
    explicit \
    bogus \
    unset
assert_pre_activity_failure \
    codex-load \
    'harness codex load' \
    explicit \
    codex \
    unset
assert_pre_activity_failure \
    claude-load \
    'harness claude load' \
    explicit \
    claude \
    unset
assert_pre_activity_failure \
    empty-environment-harness \
    'harness unresolved context' \
    environment \
    '' \
    unset
assert_pre_activity_failure \
    unsafe-environment-harness \
    'harness unresolved context' \
    environment \
    '../copilot' \
    unset
assert_pre_activity_failure \
    selected-copilot-marker-bogus \
    'harness copilot context' \
    explicit \
    copilot \
    set \
    bogus
assert_pre_activity_failure \
    selected-bogus-marker-copilot \
    'harness bogus context' \
    explicit \
    bogus \
    set \
    copilot
assert_pre_activity_failure \
    empty-launcher-marker \
    'harness copilot context' \
    explicit \
    copilot \
    set \
    ''
assert_pre_activity_failure \
    unsafe-launcher-marker \
    'harness copilot context' \
    explicit \
    copilot \
    set \
    '../copilot'

function_failure_plugin="${fixture_root}/function-failure-plugin"
function_failure_skill="${function_failure_plugin}/skills/readonly-repository-review"
function_failure_scripts="${function_failure_skill}/scripts"
mkdir -p -- \
    "${function_failure_plugin}/lib/harness" \
    "${function_failure_plugin}/scripts" \
    "${function_failure_scripts}"
cp -- "${HARNESS_COMMON}" \
    "${function_failure_plugin}/lib/harness/common.sh"
cp -- "${PLUGIN_ROOT}/lib/harness/copilot.sh" \
    "${function_failure_plugin}/lib/harness/copilot.sh"
cp -- "${PLUGIN_ROOT}/scripts/launcher-preferences.sh" \
    "${function_failure_plugin}/scripts/launcher-preferences.sh"
cp -- "${RUNNER}" \
    "${function_failure_scripts}/run-parallel-reviews.sh"
cp -- "${OUTPUT_HELPER}" \
    "${function_failure_scripts}/review-output.sh"
cp -- "${PROMPT}" "${function_failure_skill}/review-prompt.txt"
cat >> "${function_failure_plugin}/lib/harness/copilot.sh" <<'FAIL_REQUIRE_CLI'

harness_require_cli() {
    local credential_url
    local email_address
    local failure_detail

    printf '%s\n' 'function-secret fixture-user fixture-pass'
    printf '%s\n' 'unsafe adapter stderr' >&2
    credential_url="$(
        printf '%s%s%s' \
            'https://fixture-user:fixture-pass' \
            '@example' \
            '.com/path'
    )"
    email_address="$(printf '%s%s%s' 'fixture' '@example' '.com')"
    printf -v failure_detail '%s\n%s\n%s\n%s' \
        'Authorization: Bearer function-secret' \
        "${credential_url}" \
        "contact ${email_address}" \
        $'controls:\rbackspace:\bvertical-tab:\vform-feed:\fshift-out:\016delete:\177escape:\033[31m'
    rhyolite_harness_set_error "${failure_detail}"
    return 1
}
FAIL_REQUIRE_CLI
chmod +x "${function_failure_scripts}/run-parallel-reviews.sh"
function_failure_plan_stdout="${fixture_root}/function-failure-plan.stdout"
function_failure_plan_stderr="${fixture_root}/function-failure-plan.stderr"
function_failure_plan_workspace="${fixture_root}/function-failure-plan-workspace"
function_failure_plan_output="${fixture_root}/function-failure-plan-output"
env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    "${function_failure_scripts}/run-parallel-reviews.sh" \
    --harness copilot \
    --repo https://github.com/octocat/Hello-World \
    --scope 1 \
    --workspace-root "${function_failure_plan_workspace}" \
    --output-root "${function_failure_plan_output}" \
    --non-interactive \
    --no-open-html \
    --plan-only >"${function_failure_plan_stdout}" \
    2>"${function_failure_plan_stderr}" ||
    fail 'Plan-only mode incorrectly required the harness CLI.'
[[ ! -s "${function_failure_plan_stderr}" ]] ||
    fail 'Plan-only mode invoked the failing harness CLI check.'
assert_contains \
    "${function_failure_plan_stdout}" \
    '"SchemaVersion": 4' \
    'Plan-only mode without harness CLI'
[[ ! -e "${function_failure_plan_workspace}" &&
    ! -e "${function_failure_plan_output}" ]] ||
    fail 'Plan-only mode without a harness CLI created workspace or output roots.'

function_failure_stdout="${fixture_root}/function-failure.stdout"
function_failure_stderr="${fixture_root}/function-failure.stderr"
function_failure_workspace="${fixture_root}/function-failure-workspace"
function_failure_output="${fixture_root}/function-failure-output"
set +e
env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    "${function_failure_scripts}/run-parallel-reviews.sh" \
    --harness copilot \
    --repo https://github.com/octocat/Hello-World \
    --scope 1 \
    --workspace-root "${function_failure_workspace}" \
    --output-root "${function_failure_output}" \
    --non-interactive \
    --no-open-html >"${function_failure_stdout}" \
    2>"${function_failure_stderr}"
function_failure_status=$?
set -e
((function_failure_status != 0)) ||
    fail 'Adapter-function failure unexpectedly succeeded.'
assert_contains \
    "${function_failure_stderr}" \
    'Stage: harness copilot harness_require_cli' \
    'Adapter-function failure stage'
assert_no_terminal_controls \
    "${function_failure_stderr}" \
    'Adapter-function failure'
assert_contains \
    "${function_failure_stderr}" \
    'Details: Authorization: [credential omitted]' \
    'Adapter-function failure detail'
assert_contains \
    "${function_failure_stderr}" \
    '(exit code 2)' \
    'Adapter-function failure exit code'
assert_contains \
    "${function_failure_stderr}" \
    'Support: SUPPORT.md and local documentation' \
    'Adapter-function fallback support'
assert_contains \
    "${function_failure_stderr}" \
    'Contribute: CONTRIBUTING.md' \
    'Adapter-function fallback contribution'
function_fixture_email="$(printf '%s%s%s' 'fixture' '@example' '.com')"
for secret_fragment in \
    'function-secret' \
    'fixture-user' \
    'fixture-pass' \
    "${function_fixture_email}"; do
    assert_not_contains \
        "${function_failure_stderr}" \
        "${secret_fragment}" \
        'Adapter-function failure sanitization'
    assert_not_contains \
        "${function_failure_stdout}" \
        "${secret_fragment}" \
        'Adapter-function stdout sanitization'
done
assert_not_contains \
    "${function_failure_stdout}" \
    'EFFECTIVE REVIEW PLAN' \
    'Adapter-function failure stdout'
[[ ! -e "${function_failure_workspace}" &&
    ! -e "${function_failure_output}" ]] ||
    fail 'Adapter-function failure created workspace or output roots.'

runner_mock_bin="${fixture_root}/runner-mock-bin"
runner_tmp_root="${fixture_root}/runner-tmp"
runner_source_home="${fixture_root}/runner-source-home"
runner_capture_root="${fixture_root}/runner-captures"
mkdir -p -- \
    "${runner_mock_bin}" \
    "${runner_tmp_root}" \
    "${runner_source_home}" \
    "${runner_capture_root}"
printf '{}\n' > "${runner_source_home}/config.json"

cat > "${runner_mock_bin}/date" <<'MOCK_RUNNER_DATE'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
    '-u +%Y-%m-%dT%H:%M:%SZ')
        printf '2026-10-01T12:00:00Z\n'
        ;;
    '+%Y-%m-%d')
        printf '2026-10-01\n'
        ;;
    '+%Y%m%d-%H%M%S')
        printf '20261001-120000\n'
        ;;
    '+%s')
        printf '1790856000\n'
        ;;
    *)
        exec /usr/bin/date "$@"
        ;;
esac
MOCK_RUNNER_DATE

cat > "${runner_mock_bin}/python3" <<'MOCK_RUNNER_PYTHON'
#!/usr/bin/env bash
set -euo pipefail
if (($# == 2)) && [[ "${1-}" == "-" && "${2-}" == */config.json ]]; then
    exec /usr/bin/python3 "$@"
fi
if (($# == 3)) && [[ "${1-}" == "-" ]]; then
    printf '%s:%s:93.184.216.34\n' "$2" "$3"
    exit 0
fi
exec /usr/bin/python3 "$@"
MOCK_RUNNER_PYTHON

cat > "${runner_mock_bin}/git" <<'MOCK_RUNNER_GIT'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" == "--version" ]]; then
    printf 'git version 2.55.0\n'
    exit 0
fi

command_name=""
for argument in "$@"; do
    case "${argument}" in
        version|ls-remote|init|clone|cat-file|fetch|checkout|rev-parse|config|ls-files|ls-tree|for-each-ref|log|status|diff|archive)
            command_name="${argument}"
            break
            ;;
    esac
done

working_directory=""
previous=""
for argument in "$@"; do
    if [[ "${previous}" == "-C" ]]; then
        working_directory="${argument}"
    fi
    previous="${argument}"
done

case "${command_name}" in
    version)
        printf 'git version 2.55.0\n'
        ;;
    ls-remote)
        printf 'ref: refs/heads/main\tHEAD\n'
        printf '%s\tHEAD\n' \
            '7fd1a60b01f91b314f59955a4e4d4e80d8edf11d'
        ;;
    init)
        destination="${@: -1}"
        mkdir -p -- "${destination}/.git"
        ;;
    clone)
        destination="${@: -1}"
        mkdir -p -- "${destination}/.git"
        printf '# mock repository\n' > "${destination}/README.md"
        ;;
    fetch|cat-file|checkout|status|diff)
        ;;
    config)
        exit 1
        ;;
    rev-parse)
        if [[ " $* " == *" --git-path "* ]]; then
            printf '%s\n' '.git/info/attributes'
        elif [[ "${working_directory}" == *-preflight &&
            " $* " == *" FETCH_HEAD^{commit} "* ]]; then
            printf '%s\n' \
                '7fd1a60b01f91b314f59955a4e4d4e80d8edf11d'
        elif [[ "${working_directory}" == *-readonly ]]; then
            printf '%s\n' \
                '7fd1a60b01f91b314f59955a4e4d4e80d8edf11d'
        else
            printf '%s\n' \
                'fatal: not a git repository (or any parent directories): .git' \
                >&2
            exit 128
        fi
        ;;
    ls-files|ls-tree)
        printf '%s\n' 'README.md'
        ;;
    for-each-ref)
        printf '%s\t%s\n' \
            'refs/remotes/origin/main' \
            '7fd1a60b01f91b314f59955a4e4d4e80d8edf11d'
        ;;
    log)
        commit_subject='Fixture commit'
        if [[ "${RHYOLITE_MOCK_UNSAFE_TEXT:-0}" == 1 ]]; then
            credential_url="$(
                printf '%s%s%s' \
                    'https://metadata-user:metadata-pass' \
                    '@example' \
                    '.com/path'
            )"
            email_address="$(
                printf '%s%s%s' 'metadata' '@example' '.com'
            )"
            printf -v commit_subject '%s %s %s %s' \
                $'A\rB\bC\vD\fE\016F\177G\033[31mH' \
                'Authorization: Bearer metadata-secret' \
                "${credential_url}" \
                "${email_address}"
        fi
        printf '%s\t%s\t%s\t%s\n' \
            '7fd1a60b01f91b314f59955a4e4d4e80d8edf11d' \
            '2026-09-30T00:00:00+00:00' \
            'Fixture Author' \
            "${commit_subject}"
        ;;
    archive)
        output_path=""
        for argument in "$@"; do
            if [[ "${argument}" == --output=* ]]; then
                output_path="${argument#--output=}"
            fi
        done
        [[ -n "${working_directory}" && -n "${output_path}" ]] || exit 70
        /usr/bin/tar -cf "${output_path}" \
            -C "${working_directory}" README.md
        ;;
    *)
        printf 'Unexpected mock git invocation: %s\n' "$*" >&2
        exit 71
        ;;
esac
MOCK_RUNNER_GIT

cat > "${runner_mock_bin}/copilot" <<'MOCK_RUNNER_COPILOT'
#!/usr/bin/env bash
set -euo pipefail

: "${RHYOLITE_WORKER_CAPTURE:?}"
mkdir -p -- "${RHYOLITE_WORKER_CAPTURE}"
printf '%s\0' "$@" > "${RHYOLITE_WORKER_CAPTURE}/argv"
for variable_name in \
    COPILOT_ALLOW_ALL \
    COPILOT_SKILLS_DIRS \
    COPILOT_CUSTOM_INSTRUCTIONS_DIRS \
    COPILOT_DYNAMIC_RETRIEVAL_SKILLS \
    COPILOT_EMBEDDING_ONLY_SKILLS \
    COPILOT_HOME; do
    if [[ -v "${variable_name}" ]]; then
        printf '%s\0%s\0' \
            "${variable_name}" \
            "${!variable_name}" \
            >> "${RHYOLITE_WORKER_CAPTURE}/environment"
    else
        printf '%s\0%s\0' \
            "${variable_name}" \
            '<unset>' \
            >> "${RHYOLITE_WORKER_CAPTURE}/environment"
    fi
done
printf 'started\n' > "${RHYOLITE_WORKER_CAPTURE}/started"

share_path=""
working_directory=""
previous=""
for argument in "$@"; do
    if [[ "${previous}" == "--share" ]]; then
        share_path="${argument}"
    elif [[ "${previous}" == "-C" ]]; then
        working_directory="${argument}"
    fi
    previous="${argument}"
done
[[ -n "${share_path}" && -n "${working_directory}" ]] || exit 72
[[ -d "${working_directory}/source" &&
    ! -e "${working_directory}/.git" ]] || exit 73
[[ -f "${COPILOT_HOME}/settings.json" &&
    -f "${COPILOT_HOME}/config.json" ]] || exit 74

mkdir -p -- \
    "${COPILOT_HOME}/session-state/mock-session" \
    "${COPILOT_HOME}/session-store"
printf '{"status":"saved"}\n' \
    > "${COPILOT_HOME}/session-state/mock-session/state.json"
printf 'mock-session-database\n' \
    > "${COPILOT_HOME}/session-store/sessions.db"
cat >/dev/null

if [[ "${RHYOLITE_MOCK_UNSAFE_TEXT:-0}" == 1 ]]; then
    credential_url="$(
        printf '%s%s%s' \
            'https://worker-user:worker-pass' \
            '@example' \
            '.com/path'
    )"
    email_address="$(printf '%s%s%s' 'worker' '@example' '.com')"
    printf -v unsafe_text '%s %s %s %s' \
        $'A\rB\bC\vD\fE\016F\177G\033[31mH' \
        'Authorization: Bearer worker-secret' \
        "${credential_url}" \
        "${email_address}"
    {
        printf '# Mock Copilot session\n\n'
        printf '### Copilot\n\n'
        printf '%s\n' "${unsafe_text}"
    } > "${share_path}"
    printf '%s\n' "${unsafe_text}"
    printf '%s\n' "${unsafe_text}" >&2
    exit 17
fi

if [[ "${RHYOLITE_MOCK_INCOMPLETE:-0}" == 1 ]]; then
    cat > "${share_path}" <<'TRANSCRIPT'
# Mock Copilot session

### Copilot

================================================================================
REPOSITORY REVIEW REPORT
Complete report available only through transcript extraction.
================================================================================
TRANSCRIPT
    cat <<'REPORT'
================================================================================
REPOSITORY REVIEW REPORT
Incomplete standard output.
REPORT
    exit 0
fi

printf '# Mock Copilot session\n' > "${share_path}"
cat <<'REPORT'
================================================================================
REPOSITORY REVIEW REPORT
Mock deterministic repository review.
================================================================================
REPORT
MOCK_RUNNER_COPILOT

chmod +x \
    "${runner_mock_bin}/date" \
    "${runner_mock_bin}/python3" \
    "${runner_mock_bin}/git" \
    "${runner_mock_bin}/copilot"

contract_plan_hash() {
    node -e '
const fs = require("fs");
const plan = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
if (!/^[0-9a-f]{64}$/.test(plan.ApprovalHash)) process.exit(2);
process.stdout.write(plan.ApprovalHash);
' "$1"
}

contract_run_path() {
    sed -n 's/^Run output:[[:space:]]*//p' "$1" | tail -n 1
}

contract_assert_worker_contract() {
    local run_path="$1"
    local capture_path="$2"
    local public_research="$3"
    local normalized_path="$4"
    local state_path="${run_path}/github--octocat--hello-world/state.json"
    local available_tools="${base_available_tools}"
    local runtime_home
    local -a state_values=()
    local -a expected_arguments=()
    local -a actual_arguments=()
    local -a environment_fields=()
    local -a expected_environment_names=(
        COPILOT_ALLOW_ALL
        COPILOT_SKILLS_DIRS
        COPILOT_CUSTOM_INSTRUCTIONS_DIRS
        COPILOT_DYNAMIC_RETRIEVAL_SKILLS
        COPILOT_EMBEDDING_ONLY_SKILLS
        COPILOT_HOME
    )
    local expected_vector="${capture_path}/expected-argv"
    local index
    local argument

    [[ -f "${state_path}" ]] ||
        fail "Runner seam state is missing: ${state_path}"
    mapfile -d '' -t state_values < <(
        node - "${state_path}" <<'JS'
const fs = require("fs");
const state = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (state.SchemaVersion !== 5 ||
    state.Harness !== "copilot" ||
    state.ReasoningEffort !== "max" ||
    state.Provider?.Id !== "github-copilot" ||
    state.Provider?.Host !== "managed-provider" ||
    JSON.stringify(state.Provider?.ForwardedEnvVarNames) !== JSON.stringify([
      "COPILOT_GITHUB_TOKEN",
      "GH_TOKEN",
      "GITHUB_TOKEN",
      "COPILOT_PROVIDER_API_KEY",
      "COPILOT_PROVIDER_BEARER_TOKEN",
      "ANTHROPIC_API_KEY",
      "AZURE_OPENAI_API_KEY",
      "OPENAI_API_KEY",
      "CAPI_HMAC_KEY",
      "COPILOT_HMAC_KEY",
      "GITHUB_COPILOT_API_TOKEN",
    ]) ||
    state.Session.ResumePolicy !==
      "Continue only through the trusted Rhyolite repo-review runner; do not invoke copilot --resume directly.") {
  throw new Error("runner seam state lost harness contract-v2 identity");
}
for (const value of [
  state.Session.Name,
  state.Session.Id,
  state.Paths.ReadOnlyCheckout,
  state.Artifacts.Transcript,
]) {
  process.stdout.write(`${value}\0`);
}
JS
    )
    [[ ${#state_values[@]} -eq 4 ]] ||
        fail 'Runner seam state did not expose the expected dynamic fields.'
    if ((public_research)); then
        available_tools="${research_available_tools}"
    fi
    expected_arguments=(
        -C "$(dirname -- "${state_values[2]}")"
        --plugin-dir "${PLUGIN_ROOT}"
        --name "${state_values[0]}"
        --session-id "${state_values[1]}"
        --agent rhyolite:repo-review-worker
        --model gpt-5.6-sol
        --reasoning-effort max
        --context long_context
        --no-ask-user
        --no-color
        --no-custom-instructions
        --disable-builtin-mcps
        --disallow-temp-dir
        --no-remote-export
        --secret-env-vars "${authentication_variables_csv}"
        --available-tools "${available_tools}"
        --allow-tool read
        --deny-tool write
        --deny-tool shell
        --stream off
        --share "${state_values[3]}"
        --silent
    )
    printf '%s\0' "${expected_arguments[@]}" > "${expected_vector}"
    cmp -s "${expected_vector}" "${capture_path}/argv" ||
        fail 'Actual runner-to-adapter worker argv changed from the golden contract.'

    mapfile -d '' -t actual_arguments < "${capture_path}/argv"
    for argument in "${actual_arguments[@]}"; do
        [[ "${argument}" != --harness &&
            "${argument}" != --harness=* ]] ||
            fail 'Actual runner forwarded --harness to the worker.'
    done

    mapfile -d '' -t environment_fields < "${capture_path}/environment"
    [[ ${#environment_fields[@]} -eq 12 ]] ||
        fail 'Actual runner worker environment capture has the wrong shape.'
    for index in "${!expected_environment_names[@]}"; do
        [[ "${environment_fields[index * 2]}" == \
            "${expected_environment_names[index]}" ]] ||
            fail 'Actual runner worker environment changed variable order.'
        if ((index < 5)); then
            [[ "${environment_fields[index * 2 + 1]}" == '<unset>' ]] ||
                fail "Actual runner did not unset ${expected_environment_names[index]}."
        fi
    done
    runtime_home="${environment_fields[11]}"
    [[ "${runtime_home}" == \
        "${runner_tmp_root}/rhyolite-repo-review-copilot."* ]] ||
        fail 'Actual runner used an unexpected worker runtime-home path.'
    [[ ! -e "${runtime_home}" ]] ||
        fail 'Actual runner left its temporary worker runtime home.'

    : > "${normalized_path}"
    index=0
    while ((index < ${#actual_arguments[@]})); do
        argument="${actual_arguments[index]}"
        printf '%s\0' "${argument}" >> "${normalized_path}"
        case "${argument}" in
            -C|--name|--session-id|--share)
                index=$((index + 1))
                ((index < ${#actual_arguments[@]})) ||
                    fail "Actual worker argv is missing a value after ${argument}."
                printf '%s\0' "<${argument#--}-value>" \
                    >> "${normalized_path}"
                ;;
        esac
        index=$((index + 1))
    done
}

runner_plan_hash="$(contract_plan_hash "${plan_default}")"
runner_default_capture="${runner_capture_root}/default"
runner_explicit_capture="${runner_capture_root}/explicit"
runner_default_stdout="${fixture_root}/runner-default.stdout"
runner_default_stderr="${fixture_root}/runner-default.stderr"
runner_explicit_stdout="${fixture_root}/runner-explicit.stdout"
runner_explicit_stderr="${fixture_root}/runner-explicit.stderr"
mkdir -p -- "${runner_default_capture}" "${runner_explicit_capture}"

env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    COPILOT_HOME="${runner_source_home}" \
    RHYOLITE_WORKER_CAPTURE="${runner_default_capture}" \
    TMPDIR="${runner_tmp_root}" \
    PATH="${runner_mock_bin}:/usr/bin:/bin" \
    "${RUNNER}" \
    --repo https://github.com/octocat/Hello-World \
    --scope 1 \
    --workspace-root "${plan_workspace}" \
    --output-root "${plan_output}" \
    --expected-plan-hash "${runner_plan_hash}" \
    --non-interactive \
    --no-open-html >"${runner_default_stdout}" \
    2>"${runner_default_stderr}" ||
    fail 'Default-harness runner seam execution failed.'
[[ ! -s "${runner_default_stderr}" ]] ||
    fail 'Default-harness runner seam execution wrote stderr.'

env -u RHYOLITE_LAUNCHER_HARNESS \
    RHYOLITE_HARNESS=bogus \
    COPILOT_HOME="${runner_source_home}" \
    RHYOLITE_WORKER_CAPTURE="${runner_explicit_capture}" \
    TMPDIR="${runner_tmp_root}" \
    PATH="${runner_mock_bin}:/usr/bin:/bin" \
    "${RUNNER}" \
    --harness copilot \
    --repo https://github.com/octocat/Hello-World \
    --scope 1 \
    --workspace-root "${plan_workspace}" \
    --output-root "${plan_output}" \
    --expected-plan-hash "${runner_plan_hash}" \
    --non-interactive \
    --no-open-html >"${runner_explicit_stdout}" \
    2>"${runner_explicit_stderr}" ||
    fail 'Explicit-harness runner seam execution failed.'
[[ ! -s "${runner_explicit_stderr}" ]] ||
    fail 'Explicit-harness runner seam execution wrote stderr.'

runner_default_run="$(contract_run_path "${runner_default_stdout}")"
runner_explicit_run="$(contract_run_path "${runner_explicit_stdout}")"
[[ -d "${runner_default_run}" && -d "${runner_explicit_run}" ]] ||
    fail 'Runner seam executions did not create output bundles.'
runner_default_normalized="${fixture_root}/runner-default.normalized"
runner_explicit_normalized="${fixture_root}/runner-explicit.normalized"
contract_assert_worker_contract \
    "${runner_default_run}" \
    "${runner_default_capture}" \
    0 \
    "${runner_default_normalized}"
contract_assert_worker_contract \
    "${runner_explicit_run}" \
    "${runner_explicit_capture}" \
    0 \
    "${runner_explicit_normalized}"
cmp -s "${runner_default_normalized}" "${runner_explicit_normalized}" ||
    fail 'Default and explicit runner worker vectors differ after dynamic-field normalization.'

node - \
    "${plan_default}" \
    "${plan_explicit}" \
    "${runner_default_run}/review-plan.json" \
    "${runner_explicit_run}/review-plan.json" <<'JS'
const fs = require("fs");
const plans = process.argv.slice(2).map((planPath) =>
  JSON.parse(fs.readFileSync(planPath, "utf8")));
for (const [index, plan] of plans.entries()) {
  if (plan.SchemaVersion !== 4) {
    throw new Error(`runner seam plan ${index} changed schema`);
  }
  if (!/^[0-9a-f]{64}$/.test(plan.ApprovalHash)) {
    throw new Error(`runner seam plan ${index} has invalid hash`);
  }
  if (plan.Harness !== "copilot" ||
      plan.ReasoningEffort !== "max" ||
      plan.Provider?.Id !== "github-copilot" ||
      plan.Provider?.Host !== "managed-provider" ||
      !Array.isArray(plan.Provider?.ForwardedEnvVarNames)) {
    throw new Error(`runner seam plan ${index} lost harness identity`);
  }
}
if (new Set(plans.map((plan) => plan.ApprovalHash)).size !== 1) {
  throw new Error("runner seam default/explicit approval hashes differ");
}
JS

contract_copy_fixture_plugin() {
    local fixture_name="$1"
    local failure_function="$2"
    local fixture_plugin="${fixture_root}/${fixture_name}-plugin"
    local fixture_skill="${fixture_plugin}/skills/readonly-repository-review"
    local fixture_scripts="${fixture_skill}/scripts"

    mkdir -p -- \
        "${fixture_plugin}/lib/harness" \
        "${fixture_plugin}/scripts" \
        "${fixture_plugin}/branding" \
        "${fixture_scripts}"
    cp -- "${HARNESS_COMMON}" \
        "${fixture_plugin}/lib/harness/common.sh"
    cp -- "${PLUGIN_ROOT}/lib/harness/copilot.sh" \
        "${fixture_plugin}/lib/harness/copilot.sh"
    cp -- "${PLUGIN_ROOT}/scripts/launcher-preferences.sh" \
        "${fixture_plugin}/scripts/launcher-preferences.sh"
    cp -- "${PLUGIN_ROOT}/branding/welcome-metadata.json" \
        "${fixture_plugin}/branding/welcome-metadata.json"
    cp -- "${RUNNER}" "${fixture_scripts}/run-parallel-reviews.sh"
    cp -- "${OUTPUT_HELPER}" "${fixture_scripts}/review-output.sh"
    cp -- "${PROMPT}" "${fixture_skill}/review-prompt.txt"
    chmod +x "${fixture_scripts}/run-parallel-reviews.sh"

    cat >> "${fixture_plugin}/lib/harness/copilot.sh" <<'FIXTURE_FAILURE_HELPER'

fixture_adapter_failure() {
    local credential_url
    local email_address
    local failure_detail

    credential_url="$(
        printf '%s%s%s' \
            'https://runner-user:runner-pass' \
            '@example' \
            '.com/path'
    )"
    email_address="$(printf '%s%s%s' 'runner' '@example' '.com')"
    printf -v failure_detail '%s\n%s\n%s\n%s' \
        'Authorization: Bearer runner-secret' \
        "${credential_url}" \
        "contact ${email_address}" \
        $'controls:\rbackspace:\bvertical-tab:\vform-feed:\fshift-out:\016delete:\177escape:\033[31m'
    rhyolite_harness_set_error "${failure_detail}"
    return 1
}
FIXTURE_FAILURE_HELPER

    case "${failure_function}" in
        harness_require_cli|harness_prepare_run|harness_prepare_worker_home|harness_worker_env|harness_render_request|harness_verify_isolation|harness_persist_agent_state|harness_extract_final_report)
            cat >> "${fixture_plugin}/lib/harness/copilot.sh" <<EOF

${failure_function}() {
    fixture_adapter_failure
}
EOF
            ;;
        harness_worker_argv)
            cat >> "${fixture_plugin}/lib/harness/copilot.sh" <<'EOF'

harness_worker_argv() {
    fixture_adapter_failure
}
EOF
            ;;
        harness_allow_all_detected)
            cat >> "${fixture_plugin}/lib/harness/copilot.sh" <<'EOF'

harness_allow_all_detected() {
    printf 'called\n' > "${RHYOLITE_ALLOW_ALL_MARKER:?}"
    return 1
}
EOF
            ;;
        none) ;;
        *) fail "Unknown fixture failure function: ${failure_function}" ;;
    esac

    printf '%s\n' "${fixture_plugin}"
}

cleanup_mock_bin="${fixture_root}/cleanup-mock-bin"
mkdir -p -- "${cleanup_mock_bin}"
cat > "${cleanup_mock_bin}/rm" <<'MOCK_CLEANUP_RM'
#!/usr/bin/env bash
set -euo pipefail
for argument in "$@"; do
    if [[ "${argument}" == \
        "${RHYOLITE_CLEANUP_FAIL_ROOT:?}"/rhyolite-repo-review-copilot.* ]]; then
        relative="${argument#"${RHYOLITE_CLEANUP_FAIL_ROOT}/"}"
        if [[ "${relative}" != */* ]]; then
            exit 1
        fi
    fi
done
exec /usr/bin/rm "$@"
MOCK_CLEANUP_RM
cat > "${cleanup_mock_bin}/sleep" <<'MOCK_CLEANUP_SLEEP'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == 1 ]]; then
    exit 0
fi
exec /usr/bin/sleep "$@"
MOCK_CLEANUP_SLEEP
chmod +x "${cleanup_mock_bin}/rm" "${cleanup_mock_bin}/sleep"

contract_fixture_email="$(printf '%s%s%s' 'runner' '@example' '.com')"
contract_worker_email="$(printf '%s%s%s' 'worker' '@example' '.com')"
contract_metadata_email="$(printf '%s%s%s' 'metadata' '@example' '.com')"
contract_assert_sanitized_file() {
    local path="$1"
    local label="$2"
    local secret

    assert_no_terminal_controls "${path}" "${label}"
    for secret in \
        runner-secret \
        runner-user \
        runner-pass \
        "${contract_fixture_email}" \
        worker-secret \
        worker-user \
        worker-pass \
        "${contract_worker_email}" \
        metadata-secret \
        metadata-user \
        metadata-pass \
        "${contract_metadata_email}"; do
        assert_not_contains "${path}" "${secret}" "${label}"
    done
}

contract_assert_sanitized_tree() {
    local root_path="$1"
    local label="$2"
    local file_path

    while IFS= read -r -d '' file_path; do
        contract_assert_sanitized_file "${file_path}" "${label}"
    done < <(find "${root_path}" -type f -print0)
}

contract_run_failure_case() {
    local case_name="$1"
    local failure_function="$2"
    local expected_status="$3"
    local worker_started="$4"
    local expected_terminal_stage="$5"
    local fixture_plugin
    local fixture_runner
    local case_root="${fixture_root}/failure-${case_name}"
    local case_workspace="${case_root}/workspace"
    local case_output="${case_root}/output"
    local case_tmp="${case_root}/tmp"
    local case_capture="${case_root}/capture"
    local case_plan="${case_root}/plan.json"
    local case_plan_stderr="${case_root}/plan.stderr"
    local case_stdout="${case_root}/run.stdout"
    local case_stderr="${case_root}/run.stderr"
    local case_combined="${case_root}/run.combined"
    local allow_all_marker="${case_root}/allow-all.marker"
    local case_hash
    local case_exit
    local run_path=""
    local state_path=""
    local errors_path=""
    local artifact_failure_function="${failure_function}"
    local -a case_environment=(
        env
        -u RHYOLITE_HARNESS
        -u RHYOLITE_LAUNCHER_HARNESS
        "COPILOT_HOME=${runner_source_home}"
        "RHYOLITE_WORKER_CAPTURE=${case_capture}"
        "RHYOLITE_ALLOW_ALL_MARKER=${allow_all_marker}"
        "TMPDIR=${case_tmp}"
        "PATH=${runner_mock_bin}:/usr/bin:/bin"
    )
    local -a run_arguments=(
        --harness copilot
        --repo https://github.com/octocat/Hello-World
        --scope 1
        --workspace-root "${case_workspace}"
        --output-root "${case_output}"
        --non-interactive
    )
    local -a plan_arguments=("${run_arguments[@]}")

    mkdir -p -- "${case_root}" "${case_tmp}" "${case_capture}"
    if [[ "${failure_function}" != harness_allow_all_detected ]]; then
        plan_arguments+=(--no-open-html)
    fi
    fixture_plugin="$(
        contract_copy_fixture_plugin "${case_name}" "${failure_function}"
    )"
    fixture_runner="${fixture_plugin}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh"
    env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
        PATH="${runner_mock_bin}:/usr/bin:/bin" \
        "${fixture_runner}" \
        "${plan_arguments[@]}" \
        --plan-only >"${case_plan}" 2>"${case_plan_stderr}" ||
        fail "${case_name}: plan-only fixture failed"
    [[ ! -s "${case_plan_stderr}" ]] ||
        fail "${case_name}: plan-only fixture wrote stderr"
    case_hash="$(contract_plan_hash "${case_plan}")"
    run_arguments+=(--expected-plan-hash "${case_hash}")
    if [[ "${failure_function}" != harness_allow_all_detected ]]; then
        run_arguments+=(--no-open-html)
    fi
    if [[ "${failure_function}" == harness_extract_final_report ]]; then
        case_environment+=("RHYOLITE_MOCK_INCOMPLETE=1")
    fi
    if [[ "${case_name}" == cleanup ]]; then
        artifact_failure_function='harness_sanitize_runtime_home'
        case_environment+=(
            "RHYOLITE_CLEANUP_FAIL_ROOT=${case_tmp}"
            "PATH=${cleanup_mock_bin}:${runner_mock_bin}:/usr/bin:/bin"
        )
    fi

    set +e
    "${case_environment[@]}" \
        "${fixture_runner}" \
        "${run_arguments[@]}" >"${case_stdout}" 2>"${case_stderr}"
    case_exit=$?
    set -e
    cat "${case_stdout}" "${case_stderr}" > "${case_combined}"

    if [[ "${failure_function}" == harness_allow_all_detected ]]; then
        ((case_exit == 0)) ||
            fail "${case_name}: allow-all predicate failure failed the run"
        [[ -f "${allow_all_marker}" ]] ||
            fail "${case_name}: runner did not invoke allow-all detection"
        [[ -f "${case_capture}/started" ]] ||
            fail "${case_name}: worker did not start"
        return
    fi

    if [[ "${failure_function}" == harness_require_cli ||
        "${failure_function}" == harness_prepare_run ]]; then
        ((case_exit == 2)) ||
            fail "${case_name}: top-level harness failure returned ${case_exit}"
        assert_contains \
            "${case_combined}" \
            "Stage: harness copilot ${failure_function}" \
            "${case_name} terminal stage"
        assert_contains \
            "${case_combined}" \
            '(exit code 2)' \
            "${case_name} terminal exit code"
        assert_contains \
            "${case_combined}" \
            'Support: https://github.com/xjamesmorris/rhyolite/issues' \
            "${case_name} published support"
        assert_contains \
            "${case_combined}" \
            'Contribute: https://github.com/xjamesmorris/rhyolite/pulls' \
            "${case_name} published contribution"
        [[ ! -e "${case_workspace}" && ! -e "${case_output}" ]] ||
            fail "${case_name}: top-level failure created workspace or output roots"
        [[ ! -f "${case_capture}/started" ]] ||
            fail "${case_name}: top-level failure started the worker"
        contract_assert_sanitized_file \
            "${case_combined}" \
            "${case_name} top-level sanitization"
        for replacement in \
            'Authorization: [credential omitted]' \
            'https://[credentials omitted]@example.com/path' \
            '[email omitted]'; do
            assert_contains \
                "${case_combined}" \
                "${replacement}" \
                "${case_name} sanitization replacement"
        done
        return
    fi

    ((case_exit != 0)) ||
        fail "${case_name}: lifecycle failure unexpectedly succeeded"
    run_path="$(contract_run_path "${case_stdout}")"
    [[ -d "${run_path}" ]] ||
        fail "${case_name}: lifecycle failure did not preserve artifacts"
    state_path="${run_path}/github--octocat--hello-world/state.json"
    errors_path="${run_path}/github--octocat--hello-world/errors.txt"
    assert_contains \
        "${case_combined}" \
        "Stage: ${expected_terminal_stage}" \
        "${case_name} terminal stage"
    assert_contains \
        "${errors_path}" \
        "Harness failure stage: harness copilot ${artifact_failure_function}" \
        "${case_name} artifact stage"
    contract_assert_sanitized_file \
        "${case_combined}" \
        "${case_name} terminal sanitization"
    contract_assert_sanitized_tree \
        "${run_path}" \
        "${case_name} artifact sanitization"
    if [[ "${case_name}" != cleanup ]]; then
        for replacement in \
            'Authorization: [credential omitted]' \
            'https://[credentials omitted]@example.com/path' \
            '[email omitted]'; do
            assert_contains \
                "${errors_path}" \
                "${replacement}" \
                "${case_name} artifact replacement"
        done
    fi

    if ((worker_started)); then
        [[ -f "${case_capture}/started" ]] ||
            fail "${case_name}: expected the worker to start"
    else
        [[ ! -f "${case_capture}/started" ]] ||
            fail "${case_name}: worker started before lifecycle failure"
    fi
    node - \
        "${state_path}" \
        "${expected_status}" \
        "${worker_started}" <<'JS'
const fs = require("fs");
const [statePath, expectedStatus, workerStartedText] = process.argv.slice(2);
const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
const workerStarted = workerStartedText === "1";
if (state.SchemaVersion !== 5 ||
    state.Harness !== "copilot" ||
    state.ReasoningEffort !== "max" ||
    state.Provider?.Id !== "github-copilot" ||
    state.Status !== expectedStatus ||
    state.ExitCode === 0) {
  throw new Error("lifecycle failure state is not truthful");
}
if (workerStarted) {
  if (!state.Session.Id || !state.Session.Name) {
    throw new Error("started worker lost session identity");
  }
} else if (state.Session.Id !== "" || state.Session.Name !== "") {
  throw new Error("pre-worker failure retained synthetic session identity");
}
JS
}

contract_run_failure_case \
    require-cli \
    harness_require_cli \
    ReviewFailed \
    0 \
    'harness copilot harness_require_cli'
contract_run_failure_case \
    prepare-run \
    harness_prepare_run \
    ReviewFailed \
    0 \
    'harness copilot harness_prepare_run'
contract_run_failure_case \
    render-request \
    harness_render_request \
    ReviewFailed \
    0 \
    'harness copilot harness_render_request'
contract_run_failure_case \
    worker-argv \
    harness_worker_argv \
    ReviewFailed \
    0 \
    'harness copilot harness_worker_argv'
contract_run_failure_case \
    prepare-worker-home \
    harness_prepare_worker_home \
    ReviewFailed \
    0 \
    'harness copilot harness_prepare_worker_home'
contract_run_failure_case \
    worker-env \
    harness_worker_env \
    ReviewFailed \
    0 \
    'harness copilot harness_worker_env'
contract_run_failure_case \
    persist-state \
    harness_persist_agent_state \
    ReviewFailed \
    1 \
    'harness copilot harness_persist_agent_state'
contract_run_failure_case \
    verify-isolation \
    harness_verify_isolation \
    ReviewFailed \
    1 \
    'harness copilot harness_verify_isolation'
contract_run_failure_case \
    extract-report \
    harness_extract_final_report \
    ReviewFailed \
    1 \
    'harness copilot harness_extract_final_report'
contract_run_failure_case \
    cleanup \
    none \
    ReviewFailed \
    1 \
    cleanup
contract_run_failure_case \
    allow-all \
    harness_allow_all_detected \
    Completed \
    1 \
    ''

unsafe_workspace="${fixture_root}/unsafe-worker-workspace"
unsafe_output="${fixture_root}/unsafe-worker-output"
unsafe_capture="${runner_capture_root}/unsafe-worker"
unsafe_plan="${fixture_root}/unsafe-worker-plan.json"
unsafe_plan_stderr="${fixture_root}/unsafe-worker-plan.stderr"
unsafe_stdout="${fixture_root}/unsafe-worker.stdout"
unsafe_stderr="${fixture_root}/unsafe-worker.stderr"
unsafe_combined="${fixture_root}/unsafe-worker.combined"
mkdir -p -- "${unsafe_capture}"
env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${runner_mock_bin}:/usr/bin:/bin" \
    "${RUNNER}" \
    --harness copilot \
    --repo https://github.com/octocat/Hello-World \
    --scope 1 \
    --workspace-root "${unsafe_workspace}" \
    --output-root "${unsafe_output}" \
    --non-interactive \
    --no-open-html \
    --plan-only >"${unsafe_plan}" 2>"${unsafe_plan_stderr}" ||
    fail 'Unsafe worker artifact plan failed.'
[[ ! -s "${unsafe_plan_stderr}" ]] ||
    fail 'Unsafe worker artifact plan wrote stderr.'
unsafe_plan_hash="$(contract_plan_hash "${unsafe_plan}")"
set +e
env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    COPILOT_HOME="${runner_source_home}" \
    RHYOLITE_WORKER_CAPTURE="${unsafe_capture}" \
    RHYOLITE_MOCK_UNSAFE_TEXT=1 \
    TMPDIR="${runner_tmp_root}" \
    PATH="${runner_mock_bin}:/usr/bin:/bin" \
    "${RUNNER}" \
    --harness copilot \
    --repo https://github.com/octocat/Hello-World \
    --scope 1 \
    --workspace-root "${unsafe_workspace}" \
    --output-root "${unsafe_output}" \
    --expected-plan-hash "${unsafe_plan_hash}" \
    --non-interactive \
    --no-open-html >"${unsafe_stdout}" 2>"${unsafe_stderr}"
unsafe_status=$?
set -e
((unsafe_status != 0)) ||
    fail 'Unsafe worker artifact fixture unexpectedly succeeded.'
cat "${unsafe_stdout}" "${unsafe_stderr}" > "${unsafe_combined}"
unsafe_run="$(contract_run_path "${unsafe_stdout}")"
[[ -d "${unsafe_run}" && -f "${unsafe_capture}/started" ]] ||
    fail 'Unsafe worker artifact fixture did not start and preserve a run.'
unsafe_repository="${unsafe_run}/github--octocat--hello-world"
unsafe_state="${unsafe_repository}/state.json"
unsafe_errors="${unsafe_repository}/errors.txt"
unsafe_timeline="${unsafe_repository}/analysis-timeline.txt"
unsafe_transcript="${unsafe_repository}/session.md"
unsafe_request="${unsafe_repository}/request.txt"
contract_assert_worker_contract \
    "${unsafe_run}" \
    "${unsafe_capture}" \
    0 \
    "${fixture_root}/unsafe-worker.normalized"
contract_assert_sanitized_file \
    "${unsafe_combined}" \
    'Unsafe worker terminal sanitization'
contract_assert_sanitized_tree \
    "${unsafe_run}" \
    'Unsafe worker artifact sanitization'
for visible_artifact in \
    "${unsafe_timeline}" \
    "${unsafe_transcript}" \
    "${unsafe_request}"; do
    assert_contains \
        "${visible_artifact}" \
        'ABCDEFGH' \
        'Unsafe worker visible-text preservation'
done
for replacement in \
    'Authorization: [credential omitted]' \
    'https://[credentials omitted]@example.com/path' \
    '[email omitted]'; do
    assert_contains \
        "${unsafe_errors}" \
        "${replacement}" \
        'Unsafe worker error redaction'
done
node - "${unsafe_state}" <<'JS'
const fs = require("fs");
const state = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (state.Status !== "ReviewFailed" ||
    state.ExitCode !== 17 ||
    !state.Session.Id ||
    !state.Session.Name) {
  throw new Error("unsafe worker failure lost status or started-session identity");
}
JS

launcher_mock_bin="${fixture_root}/launcher-mock-bin"
launcher_caller="${fixture_root}/launcher-caller"
launcher_default_state="${fixture_root}/launcher-default-state"
launcher_explicit_state="${fixture_root}/launcher-explicit-state"
launcher_default_capture="${fixture_root}/launcher-default.capture"
launcher_explicit_capture="${fixture_root}/launcher-explicit.capture"
mkdir -p -- \
    "${launcher_mock_bin}" \
    "${launcher_caller}" \
    "${launcher_default_state}" \
    "${launcher_explicit_state}"
chmod 0700 -- "${launcher_default_state}" "${launcher_explicit_state}"
cat > "${launcher_mock_bin}/copilot" <<'MOCK_LAUNCHER_COPILOT'
#!/usr/bin/env bash
set -euo pipefail
: "${RHYOLITE_LAUNCHER_CAPTURE:?}"
{
    printf 'HARNESS\0%s\0' "${RHYOLITE_LAUNCHER_HARNESS-}"
    printf 'ARGS\0'
    printf '%s\0' "$@"
} > "${RHYOLITE_LAUNCHER_CAPTURE}"
MOCK_LAUNCHER_COPILOT
chmod +x "${launcher_mock_bin}/copilot"

rm -f -- "${launcher_default_capture}"
launcher_help="$(
    env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
        RHYOLITE_LAUNCHER_CAPTURE="${launcher_default_capture}" \
        PATH="${launcher_mock_bin}:/usr/bin:/bin" \
        "${LAUNCHER}" --help
)"
[[ "${launcher_help}" == \
    *'--harness ID  Select the review harness (currently: copilot).'* ]] ||
    fail 'Launcher help does not document the I1a Copilot harness selector.'
[[ ! -e "${launcher_default_capture}" ]] ||
    fail 'Launcher help unexpectedly invoked the downstream Copilot CLI.'

assert_launcher_pre_activity_failure() {
    local name="$1"
    local marker_mode="$2"
    local marker_value="$3"
    local expected_stage="$4"
    local expected_detail="$5"
    local expected_remediation="$6"
    shift 6
    local capture_path="${fixture_root}/${name}.launcher.capture"
    local state_path="${fixture_root}/${name}.launcher-state"
    local stdout_path="${fixture_root}/${name}.launcher.stdout"
    local stderr_path="${fixture_root}/${name}.launcher.stderr"
    local status
    local -a launcher_environment=(
        env
        -u RHYOLITE_HARNESS
    )

    case "${marker_mode}" in
        unset)
            launcher_environment+=(-u RHYOLITE_LAUNCHER_HARNESS)
            ;;
        set)
            launcher_environment+=(
                "RHYOLITE_LAUNCHER_HARNESS=${marker_value}"
            )
            ;;
        *)
            fail "Invalid launcher marker mode: ${marker_mode}"
            ;;
    esac
    launcher_environment+=(
        NO_COLOR=1
        "XDG_STATE_HOME=${state_path}"
        "RHYOLITE_LAUNCHER_CAPTURE=${capture_path}"
        "PATH=${launcher_mock_bin}:/usr/bin:/bin"
    )

    rm -rf -- "${state_path}"
    rm -f -- "${capture_path}"
    set +e
    (
        cd "${launcher_caller}"
        "${launcher_environment[@]}" "${LAUNCHER}" "$@"
    ) >"${stdout_path}" 2>"${stderr_path}"
    status=$?
    set -e

    ((status == 2)) ||
        fail "${name}: launcher failure returned ${status}, expected 2"
    [[ ! -s "${stdout_path}" ]] ||
        fail "${name}: launcher failure wrote stdout"
    assert_contains "${stderr_path}" "Stage: ${expected_stage}" "${name}"
    assert_contains "${stderr_path}" "${expected_detail}" "${name}"
    assert_contains \
        "${stderr_path}" \
        "${expected_remediation}" \
        "${name} remediation"
    assert_no_terminal_controls "${stderr_path}" "${name}"
    [[ ! -e "${capture_path}" ]] ||
        fail "${name}: launcher invoked Copilot before failing"
    [[ ! -e "${state_path}" ]] ||
        fail "${name}: launcher created state before failing"
}

assert_launcher_pre_activity_failure \
    launcher-equals-codex \
    unset \
    '' \
    'launcher argument validation' \
    'The launcher accepts the harness identifier only as a separate argument.' \
    'Use --harness ID, for example --harness copilot.' \
    --harness=codex
assert_launcher_pre_activity_failure \
    launcher-equals-empty \
    unset \
    '' \
    'launcher argument validation' \
    'The launcher accepts the harness identifier only as a separate argument.' \
    'Use --harness ID, for example --harness copilot.' \
    --harness=
assert_launcher_pre_activity_failure \
    launcher-marker-mismatch \
    set \
    bogus \
    'launcher harness context' \
    "Launcher harness 'bogus' does not match selected harness 'copilot'." \
    'unsetting RHYOLITE_LAUNCHER_HARNESS' \
    --harness copilot
assert_launcher_pre_activity_failure \
    launcher-marker-malformed \
    set \
    '../copilot' \
    'launcher harness context' \
    'The launcher harness marker is empty or contains unsupported characters.' \
    'unsetting RHYOLITE_LAUNCHER_HARNESS' \
    --harness copilot

assert_launcher_state_path_failure() {
    local name="$1"
    local state_path="$2"
    local capture_path="${fixture_root}/${name}.launcher.capture"
    local stdout_path="${fixture_root}/${name}.launcher.stdout"
    local stderr_path="${fixture_root}/${name}.launcher.stderr"
    local status

    rm -f -- "${capture_path}"
    set +e
    (
        cd "${launcher_caller}"
        env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
            NO_COLOR=1 \
            XDG_STATE_HOME="${state_path}" \
            RHYOLITE_LAUNCHER_CAPTURE="${capture_path}" \
            PATH="${launcher_mock_bin}:/usr/bin:/bin" \
            "${LAUNCHER}" \
                --repo https://example.com/owner/repository \
                --fleet-mode standard \
                --model gpt-5.6-sol
    ) >"${stdout_path}" 2>"${stderr_path}"
    status=$?
    set -e

    ((status == 2)) ||
        fail "${name}: unsafe launcher state returned ${status}, expected 2"
    [[ ! -s "${stdout_path}" ]] ||
        fail "${name}: unsafe launcher state wrote stdout"
    assert_contains \
        "${stderr_path}" \
        'Stage: launcher state creation' \
        "${name} stage"
    assert_contains \
        "${stderr_path}" \
        'must be owned by the current user, contain no symlink components, and have no group/world-writable components' \
        "${name} detail"
    [[ ! -e "${capture_path}" ]] ||
        fail "${name}: unsafe launcher state invoked Copilot"
}

launcher_writable_state="${fixture_root}/launcher-writable-state"
mkdir -p -- "${launcher_writable_state}"
chmod 0770 -- "${launcher_writable_state}"
assert_launcher_state_path_failure \
    launcher-writable-state \
    "${launcher_writable_state}"
[[ ! -e "${launcher_writable_state}/rhyolite" ]] ||
    fail 'Writable launcher state was modified before rejection.'

launcher_symlink_state_target="${fixture_root}/launcher-symlink-state-target"
launcher_symlink_state="${fixture_root}/launcher-symlink-state"
mkdir -p -- "${launcher_symlink_state_target}"
chmod 0700 -- "${launcher_symlink_state_target}"
ln -s -- "${launcher_symlink_state_target}" "${launcher_symlink_state}"
assert_launcher_state_path_failure \
    launcher-symlink-state \
    "${launcher_symlink_state}"
[[ ! -e "${launcher_symlink_state_target}/rhyolite" ]] ||
    fail 'Symlinked launcher state target was modified before rejection.'

(
    cd "${launcher_caller}"
    env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
        XDG_STATE_HOME="${launcher_default_state}" \
        RHYOLITE_LAUNCHER_CAPTURE="${launcher_default_capture}" \
        PATH="${launcher_mock_bin}:/usr/bin:/bin" \
        "${LAUNCHER}" \
            --repo https://example.com/owner/repository \
            --fleet-mode standard \
            --model gpt-5.6-sol
)
(
    cd "${launcher_caller}"
    env -u RHYOLITE_LAUNCHER_HARNESS \
        RHYOLITE_HARNESS=bogus \
        XDG_STATE_HOME="${launcher_explicit_state}" \
        RHYOLITE_LAUNCHER_CAPTURE="${launcher_explicit_capture}" \
        PATH="${launcher_mock_bin}:/usr/bin:/bin" \
        "${LAUNCHER}" \
            --harness copilot \
            --repo https://example.com/owner/repository \
            --fleet-mode standard \
            --model gpt-5.6-sol
)

normalize_launcher_capture() {
    local input_path="$1"
    local output_path="$2"
    local -a fields=()
    local index

    mapfile -d '' -t fields < "${input_path}"
    [[ "${fields[0]-}" == HARNESS &&
        "${fields[1]-}" == copilot &&
        "${fields[2]-}" == ARGS ]] ||
        fail "Launcher capture has invalid harness context: ${input_path}"

    : > "${output_path}"
    index=3
    while ((index < ${#fields[@]})); do
        [[ "${fields[index]}" != *'--harness'* ]] ||
            fail "Launcher forwarded --harness to Copilot: ${input_path}"
        printf '%s\0' "${fields[index]}" >> "${output_path}"
        if [[ "${fields[index]}" == --log-dir ]]; then
            index=$((index + 1))
            ((index < ${#fields[@]})) ||
                fail "Launcher --log-dir is missing its value: ${input_path}"
            printf '%s\0' '<generated-log-dir>' >> "${output_path}"
        fi
        index=$((index + 1))
    done
}

launcher_default_vector="${fixture_root}/launcher-default.vector"
launcher_explicit_vector="${fixture_root}/launcher-explicit.vector"
normalize_launcher_capture \
    "${launcher_default_capture}" \
    "${launcher_default_vector}"
normalize_launcher_capture \
    "${launcher_explicit_capture}" \
    "${launcher_explicit_vector}"
cmp -s "${launcher_default_vector}" "${launcher_explicit_vector}" ||
    fail 'Default and explicit Copilot outer-launcher vectors differ.'

expected_prompt="$(
    cat <<'PROMPT'
RHYOLITE_START_COMMAND_V1
RHYOLITE_LAUNCHER_SETUP_V1
Source=https://example.com/owner/repository
FleetMode=standard
Model=gpt-5.6-sol
RememberPreferences=true
END_RHYOLITE_LAUNCHER_SETUP_V1
Begin Rhyolite's guided repository-review setup now.
PROMPT
)"
expected_launcher_args=(
    --experimental
    -C "${launcher_caller}"
    --plugin-dir "${PLUGIN_ROOT}"
    --mode interactive
    --agent rhyolite:repo-review
    --model gpt-5.6-sol
    --reasoning-effort max
    --context long_context
    --log-dir '<generated-log-dir>'
    --no-custom-instructions
    -i "${expected_prompt}"
)
expected_launcher_vector="${fixture_root}/launcher-expected.vector"
printf '%s\0' "${expected_launcher_args[@]}" > "${expected_launcher_vector}"
cmp -s "${expected_launcher_vector}" "${launcher_default_vector}" ||
    fail 'Copilot outer-launcher argv changed from the I1a baseline.'

printf 'Harness contract validation passed.\n'
