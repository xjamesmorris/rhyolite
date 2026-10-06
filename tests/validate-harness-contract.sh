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
PLUGIN_MANIFEST="${PLUGIN_ROOT}/plugin.json"
MARKETPLACE_MANIFEST="${ROOT}/.github/plugin/marketplace.json"
NOOP_FIXTURE_ROOT="${ROOT}/tests/fixtures/harnesses"
NOOP_ADAPTER_FIXTURE="${NOOP_FIXTURE_ROOT}/noop.sh"
NOOP_WORKER_FIXTURE="${NOOP_FIXTURE_ROOT}/noop-worker.sh"
REPOSITORY_DISCOVERY_CURL_FIXTURE="${ROOT}/tests/fixtures/repository-discovery-curl.sh"

required_contract_functions=(
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
    harness_render_request
    harness_extract_final_report
    harness_extract_report_repair
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

offline_curl_guard_bin="${fixture_root}/offline-curl-guard-bin"
mkdir -p -- "${offline_curl_guard_bin}"
cp -- "${REPOSITORY_DISCOVERY_CURL_FIXTURE}" \
    "${offline_curl_guard_bin}/curl"
chmod +x "${offline_curl_guard_bin}/curl"
PATH="${offline_curl_guard_bin}:${PATH}"
export PATH

for path in \
    "${RUNNER}" \
    "${PROMPT}" \
    "${OUTPUT_HELPER}" \
    "${LAUNCHER}" \
    "${PREFERENCE_HELPER}" \
    "${PLUGIN_MANIFEST}" \
    "${MARKETPLACE_MANIFEST}" \
    "${NOOP_ADAPTER_FIXTURE}" \
    "${NOOP_WORKER_FIXTURE}" \
    "${REPOSITORY_DISCOVERY_CURL_FIXTURE}"; do
    [[ -f "${path}" ]] || fail "Required production file is missing: ${path}"
done
[[ -f "${HARNESS_COMMON}" ]] ||
    fail "Harness common module is missing: ${HARNESS_COMMON}"
[[ ! -e "${PLUGIN_ROOT}/lib/harness/noop.sh" ]] ||
    fail 'The development-only no-op adapter entered the production plugin tree.'
assert_not_contains \
    "${PLUGIN_MANIFEST}" \
    'noop' \
    'Production plugin manifest'
assert_not_contains \
    "${MARKETPLACE_MANIFEST}" \
    'noop' \
    'Production marketplace manifest'
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
assert_equal '4' \
    "${RHYOLITE_HARNESS_CONTRACT_VERSION}" \
    'Harness contract version'
production_registry_path=''
rhyolite_harness_registry_lookup \
    production_registry_path "${PLUGIN_ROOT}" copilot ||
    fail 'Production fixed registry did not resolve Copilot.'
assert_equal \
    "${PLUGIN_ROOT}/lib/harness/copilot.sh" \
    "${production_registry_path}" \
    'Production fixed Copilot registry path'
if rhyolite_harness_registry_lookup \
    production_registry_path "${PLUGIN_ROOT}" noop; then
    fail 'Production fixed registry unexpectedly mapped the no-op fixture.'
fi
assert_equal \
    "Harness 'noop' is not supported by this Rhyolite installation." \
    "${RHYOLITE_HARNESS_ERROR_DETAIL}" \
    'Production no-op registry rejection'
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
        fail "Copilot adapter is missing Contract-v4 function: ${function_name}"
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

for unsupported_id in noop bogus codex claude; do
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
[[ ${#model_choices[@]} -eq 3 &&
    "${model_choices[0]}" == \
        'GPT-5.6 Sol (Recommended) - gpt-5.6-sol' &&
    "${model_choices[1]}" == \
        'Claude Fable 5 - claude-fable-5' &&
    "${model_choices[2]}" == 'List available model IDs' ]] ||
    fail 'Copilot model choices lost their exact text or order.'
mapfile -t available_models < <(harness_list_models)
[[ " ${available_models[*]} " == *' gpt-5.6-sol '* &&
    " ${available_models[*]} " == *' claude-fable-5 '* &&
    " ${available_models[*]} " == *' gpt-6-sol '* ]] ||
    fail 'Copilot available-model catalog lost expected current model IDs.'
for valid_model in gpt-5.6-sol claude-fable-5 gpt-6-sol; do
    harness_validate_model_id "${valid_model}" ||
        fail "Copilot adapter rejected an available model ID: ${valid_model}"
done
for invalid_model in '' '../model' 'model/name' 'model name' '-model' \
    gpt-6_sol model.1; do
    if harness_validate_model_id "${invalid_model}"; then
        fail "Copilot adapter accepted an unsafe model ID: ${invalid_model}"
    fi
    for valid_effort in high xhigh max; do
        harness_validate_reasoning_effort "${valid_effort}" ||
            fail "Copilot adapter rejected supported effort: ${valid_effort}"
    done
    for invalid_effort in none minimal low medium extreme; do
        if harness_validate_reasoning_effort "${invalid_effort}"; then
            fail "Copilot adapter accepted unsupported effort: ${invalid_effort}"
        fi
    done
    assert_equal long_context \
        "$(harness_default_context_tier)" \
        'Copilot default context tier'
    for valid_context in default long_context; do
        harness_validate_context_tier "${valid_context}" ||
            fail "Copilot adapter rejected supported context: ${valid_context}"
    done
    if harness_validate_context_tier huge >/dev/null 2>&1; then
        fail 'Copilot adapter accepted an unsupported context tier.'
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
preference_contract_repository='https://github.com/octocat/Hello-World.git'
rhyolite_write_preference \
    "${preference_contract_repository}" \
    copilot \
    native \
    gpt-5.6-sol \
    max \
    long_context \
    "${preference_contract_root}" ||
    fail 'Contract-v4 preference write failed.'
preference_contract_path="$(
    rhyolite_preference_path \
        "${preference_contract_repository}" \
        "${preference_contract_root}"
)"
preference_contract_peer='https://github.com/octocat/Hello-World'
preference_contract_peer_path="$(
    rhyolite_preference_path \
        "${preference_contract_peer}" \
        "${preference_contract_root}"
)"
[[ "${preference_contract_path}" != "${preference_contract_peer_path}" ]] ||
    fail 'Contract-v4 preferences merged .git and non-.git source identities.'
rhyolite_write_preference \
    "${preference_contract_peer}" \
    copilot \
    standard \
    gpt-6-sol \
    xhigh \
    default \
    "${preference_contract_root}" ||
    fail 'Contract-v4 non-.git peer preference write failed.'
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
    "reasoningEffort",
    "contextTier",
    "updatedAt",
}:
    raise SystemExit("preference schema 3 keys are invalid")
if (
    preference["schemaVersion"] != 3
    or preference["canonicalRepository"] !=
        "https://github.com/octocat/Hello-World.git"
    or preference["harness"] != "copilot"
    or preference["fleetMode"] != "native"
    or preference["model"] != "gpt-5.6-sol"
    or preference["reasoningEffort"] != "max"
    or preference["contextTier"] != "long_context"
):
    raise SystemExit("preference schema 3 values are invalid")
PY
rhyolite_read_preference \
    "${preference_contract_repository}" \
    copilot \
    "${preference_contract_root}" ||
    fail 'Contract-v4 preference read failed.'
[[ "${RHYOLITE_PREFERENCE_HARNESS}" == copilot &&
    "${RHYOLITE_PREFERENCE_FLEET_MODE}" == native &&
    "${RHYOLITE_PREFERENCE_MODEL}" == gpt-5.6-sol &&
    "${RHYOLITE_PREFERENCE_REASONING_EFFORT}" == max &&
    "${RHYOLITE_PREFERENCE_CONTEXT_TIER}" == long_context ]] ||
    fail 'Contract-v4 preference values did not round-trip.'
rhyolite_read_preference \
    "${preference_contract_peer}" \
    copilot \
    "${preference_contract_root}" ||
    fail 'Contract-v4 non-.git peer preference read failed.'
[[ "${RHYOLITE_PREFERENCE_FLEET_MODE}" == standard &&
    "${RHYOLITE_PREFERENCE_MODEL}" == gpt-6-sol &&
    "${RHYOLITE_PREFERENCE_REASONING_EFFORT}" == xhigh &&
    "${RHYOLITE_PREFERENCE_CONTEXT_TIER}" == default ]] ||
    fail 'Contract-v4 .git and non-.git preferences were not independent.'
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
            long_context \
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

repair_workdir="${fixture_root}/report-repair-workdir"
repair_transcript="${fixture_root}/report-repair/session.md"
repair_session_name='repair-fixture-run'
repair_session_id='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
mkdir -p -- "${repair_workdir}" "$(dirname -- "${repair_transcript}")"
declare -a repair_arguments=()
harness_report_repair_argv \
    repair_arguments \
    "${repair_workdir}" \
    "${repair_session_name}" \
    "${repair_session_id}" \
    gpt-5.6-sol \
    max \
    long_context \
    "${authentication_variables_csv}" \
    "${repair_transcript}" ||
    fail 'Copilot adapter could not build report-repair argv.'
expected_repair_arguments=(
    -C "${repair_workdir}"
    --name "${repair_session_name}"
    --session-id "${repair_session_id}"
    --model gpt-5.6-sol
    --reasoning-effort max
    --context long_context
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
    --secret-env-vars "${authentication_variables_csv}"
    --excluded-tools 'builtin:*' 'mcp:*' 'custom:*'
    --deny-tool read
    --deny-tool write
    --deny-tool shell
    --deny-tool url
    --stream off
    --share "${repair_transcript}"
    --silent
)
repair_arguments_vector="${fixture_root}/report-repair-argv.vector"
expected_repair_arguments_vector="${fixture_root}/report-repair-argv-expected.vector"
printf '%s\0' "${repair_arguments[@]}" > "${repair_arguments_vector}"
printf '%s\0' \
    "${expected_repair_arguments[@]}" \
    > "${expected_repair_arguments_vector}"
cmp -s \
    "${expected_repair_arguments_vector}" \
    "${repair_arguments_vector}" ||
    fail 'Copilot report-repair argv changed from the Contract-v4 zero-tool vector.'
for forbidden_repair_argument in \
    --allow-all \
    --allow-all-tools \
    --allow-all-paths \
    --allow-all-urls \
    --allow-tool \
    --available-tools \
    --plugin-dir \
    --agent \
    --additional-mcp-config \
    --attachment \
    --add-dir \
    --fleet \
    --autopilot \
    --resume \
    --continue; do
    for captured_repair_argument in "${repair_arguments[@]}"; do
        [[ "${captured_repair_argument}" != \
            "${forbidden_repair_argument}" &&
            "${captured_repair_argument}" != \
            "${forbidden_repair_argument}="* ]] ||
            fail "Copilot report repair gained forbidden argument ${forbidden_repair_argument}."
    done
done

for path_isolation_fragment in \
    'canonicalize_directory_path "${report_repair_workdir}"' \
    'canonicalize_directory_path "${report_repair_runtime_home}"' \
    'require_outside_git_repository "${report_repair_workdir}"' \
    'require_outside_git_repository "${report_repair_runtime_home}"' \
    'directory_contains_physical "${RUN_WORKSPACE}" "${report_repair_workdir}"' \
    'directory_contains_physical "${RUN_RESULTS}" "${report_repair_workdir}"' \
    'directory_contains_physical "${RUN_WORKSPACE}" "${report_repair_runtime_home}"' \
    'directory_contains_physical "${RUN_RESULTS}" "${report_repair_runtime_home}"'; do
    assert_contains \
        "${RUNNER}" \
        "${path_isolation_fragment}" \
        'Report-repair runtime path isolation'
done
repair_path_validation_line="$(
    grep -nF \
        'directory_contains_physical "${RUN_RESULTS}" "${report_repair_runtime_home}"' \
        "${RUNNER}" |
        head -n 1 |
        cut -d: -f1
)"
repair_home_preparation_line="$(
    grep -nF \
        '! rhyolite_harness_invoke harness_prepare_worker_home \' \
        "${RUNNER}" |
        head -n 1 |
        cut -d: -f1
)"
repair_environment_application_line="$(
    grep -nF \
        'env "${repair_environment[@]}" \' \
        "${RUNNER}" |
        head -n 1 |
        cut -d: -f1
)"
repair_timeout_invocation_line="$(
    grep -nF \
        'timeout --signal=TERM --kill-after=30s \' \
        "${RUNNER}" |
        head -n 1 |
        cut -d: -f1
)"
repair_worker_invocation_line="$(
    grep -nF \
        '"${HARNESS_CLI_NAME}" "${repair_arguments[@]}" \' \
        "${RUNNER}" |
        head -n 1 |
        cut -d: -f1
)"
[[ "${repair_path_validation_line}" =~ ^[0-9]+$ &&
    "${repair_home_preparation_line}" =~ ^[0-9]+$ &&
    "${repair_environment_application_line}" =~ ^[0-9]+$ &&
    "${repair_timeout_invocation_line}" =~ ^[0-9]+$ &&
    "${repair_worker_invocation_line}" =~ ^[0-9]+$ &&
    repair_path_validation_line -lt repair_home_preparation_line &&
    repair_home_preparation_line -lt repair_environment_application_line &&
    repair_environment_application_line -lt repair_timeout_invocation_line &&
    repair_timeout_invocation_line -lt repair_worker_invocation_line ]] ||
    fail 'Report-repair path isolation and environment application no longer precede timeout and worker invocation.'

if harness_report_repair_argv \
    'bad[destination]' \
    "${repair_workdir}" \
    "${repair_session_name}" \
    "${repair_session_id}" \
    gpt-5.6-sol \
    max \
    long_context \
    "${authentication_variables_csv}" \
    "${repair_transcript}" >/dev/null 2>&1; then
    fail 'Copilot report-repair argv accepted an unsafe array destination.'
fi
printf 'not empty\n' > "${repair_workdir}/forbidden"
if harness_report_repair_argv \
    repair_arguments \
    "${repair_workdir}" \
    "${repair_session_name}" \
    "${repair_session_id}" \
    gpt-5.6-sol \
    max \
    long_context \
    "${authentication_variables_csv}" \
    "${repair_transcript}" >/dev/null 2>&1; then
    fail 'Copilot report-repair argv accepted a nonempty working directory.'
fi
rm -f -- "${repair_workdir}/forbidden"
if harness_report_repair_argv \
    repair_arguments \
    "${repair_workdir}" \
    "${repair_session_name}" \
    "${repair_session_id}" \
    gpt-5.6-sol \
    max \
    long_context \
    'COPILOT_GITHUB_TOKEN,unsafe-name!' \
    "${repair_transcript}" >/dev/null 2>&1; then
    fail 'Copilot report-repair argv accepted an invalid protected-name list.'
fi

source_copilot_home="${fixture_root}/source-copilot-home"
runtime_home="${fixture_root}/runtime-copilot-home"
repair_runtime_home="${fixture_root}/runtime-copilot-report-repair"
agent_state="${fixture_root}/agent-state"
mkdir -m 700 -- \
    "${source_copilot_home}" \
    "${runtime_home}" \
    "${repair_runtime_home}"
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
harness_prepare_worker_home "${runtime_home}" max long_context ||
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
harness_prepare_worker_home \
    "${repair_runtime_home}" max long_context report-repair ||
    fail 'Copilot adapter could not prepare the report-repair home.'
for private_file in \
    "${repair_runtime_home}/settings.json" \
    "${repair_runtime_home}/config.json"; do
    [[ "$(stat -c '%a' "${private_file}")" == 600 ]] ||
        fail "Copilot report-repair runtime file is not mode 600: ${private_file}"
done
assert_contains \
    "${repair_runtime_home}/settings.json" \
    '"disableAllHooks": true' \
    'Copilot report-repair hook isolation'
assert_contains \
    "${repair_runtime_home}/settings.json" \
    '"memory": false' \
    'Copilot report-repair memory isolation'
assert_contains \
    "${repair_runtime_home}/settings.json" \
    '"autoConnect": false' \
    'Copilot report-repair IDE isolation'
assert_not_contains \
    "${repair_runtime_home}/settings.json" \
    '"subagents"' \
    'Copilot report-repair subagent isolation'
assert_not_contains \
    "${repair_runtime_home}/settings.json" \
    '"customAgents"' \
    'Copilot report-repair custom-agent isolation'
assert_contains \
    "${repair_runtime_home}/config.json" \
    '"copilotTokens":{"fixture-user":"bridge-secret"}' \
    'Copilot report-repair narrow authentication bridge'
invalid_phase_home="${fixture_root}/runtime-copilot-invalid-phase"
mkdir -m 700 -- "${invalid_phase_home}"
if harness_prepare_worker_home \
    "${invalid_phase_home}" max long_context unsupported \
    >/dev/null 2>&1; then
    fail 'Copilot adapter accepted an unsupported runtime-home phase.'
fi
[[ -z "$(find "${invalid_phase_home}" -mindepth 1 -print -quit)" ]] ||
    fail 'Unsupported Copilot runtime-home phase wrote configuration.'

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
harness_prepare_worker_home \
    "${metadata_runtime_home}" max long_context ||
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
    harness_prepare_worker_home "${case_runtime}" max long_context ||
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

repair_environment_vector="${fixture_root}/report-repair-environment.vector"
repair_reference_environment_vector="${fixture_root}/report-repair-reference-environment.vector"
repair_process_bin="${fixture_root}/report-repair-process-bin"
repair_process_capture="${fixture_root}/report-repair-process-capture"
repair_parent_home="${fixture_root}/report-repair-parent-home"
repair_parent_config="${fixture_root}/report-repair-parent-config"
repair_parent_cache="${fixture_root}/report-repair-parent-cache"
repair_parent_data="${fixture_root}/report-repair-parent-data"
repair_parent_state="${fixture_root}/report-repair-parent-state"
repair_fake_auth='fixture-report-repair-auth-value-must-not-enter-argv'
repair_fake_provider='fixture-report-repair-provider-value-must-not-enter-argv'
repair_expected_loader="$(command -v copilot)"
mkdir -p -- \
    "${repair_process_bin}" \
    "${repair_process_capture}" \
    "${repair_parent_home}" \
    "${repair_parent_config}" \
    "${repair_parent_cache}" \
    "${repair_parent_data}" \
    "${repair_parent_state}"
cat > "${repair_process_bin}/timeout" <<'REPAIR_PROCESS_PROBE'
#!/usr/bin/env bash
set -euo pipefail

: "${RHYOLITE_REPAIR_PROCESS_CAPTURE:?}"
tr '\0' '\n' < "/proc/$$/cmdline" \
    > "${RHYOLITE_REPAIR_PROCESS_CAPTURE}/cmdline.txt"
env | LC_ALL=C sort \
    > "${RHYOLITE_REPAIR_PROCESS_CAPTURE}/environment.txt"
command -v copilot \
    > "${RHYOLITE_REPAIR_PROCESS_CAPTURE}/copilot-loader.txt"
REPAIR_PROCESS_PROBE
chmod +x "${repair_process_bin}/timeout"
(
    export HOME="${repair_parent_home}"
    export XDG_CONFIG_HOME="${repair_parent_config}"
    export XDG_CACHE_HOME="${repair_parent_cache}"
    export XDG_DATA_HOME="${repair_parent_data}"
    export XDG_STATE_HOME="${repair_parent_state}"
    export COPILOT_HOME="${source_copilot_home}"
    export COPILOT_GITHUB_TOKEN="${repair_fake_auth}"
    export COPILOT_PROVIDER_API_KEY="${repair_fake_provider}"
    export COPILOT_OFFLINE=true
    export COPILOT_ALLOW_ALL=true
    export COPILOT_SKILLS_DIRS='/forbidden/skills'
    export COPILOT_CUSTOM_INSTRUCTIONS_DIRS='/forbidden/instructions'
    export COPILOT_DYNAMIC_RETRIEVAL_SKILLS=true
    export COPILOT_EMBEDDING_ONLY_SKILLS=true
    export RHYOLITE_REPAIR_PROCESS_CAPTURE="${repair_process_capture}"
    declare -a repair_environment=()
    declare -a reference_environment=()
    original_runtime_home="${COPILOT_RUNTIME_HOME}"
    COPILOT_RUNTIME_HOME="${repair_runtime_home}"
    harness_worker_env reference_environment
    COPILOT_RUNTIME_HOME="${original_runtime_home}"
    harness_report_repair_env \
        repair_environment "${repair_runtime_home}"
    printf '%s\0' "${repair_environment[@]}" \
        > "${repair_environment_vector}"
    printf '%s\0' "${reference_environment[@]}" \
        > "${repair_reference_environment_vector}"
    env "${repair_environment[@]}" \
        "${repair_process_bin}/timeout" \
        --signal=TERM --kill-after=30s 60s copilot repair
)
expected_repair_environment=(
    -u COPILOT_ALLOW_ALL
    -u COPILOT_SKILLS_DIRS
    -u COPILOT_CUSTOM_INSTRUCTIONS_DIRS
    -u COPILOT_DYNAMIC_RETRIEVAL_SKILLS
    -u COPILOT_EMBEDDING_ONLY_SKILLS
    "COPILOT_HOME=${repair_runtime_home}"
)
expected_repair_environment_vector="${fixture_root}/report-repair-environment-expected.vector"
printf '%s\0' \
    "${expected_repair_environment[@]}" \
    > "${expected_repair_environment_vector}"
cmp -s \
    "${expected_repair_environment_vector}" \
    "${repair_environment_vector}" ||
    fail 'Copilot report-repair environment diverged from normal worker clearing semantics.'
cmp -s \
    "${repair_reference_environment_vector}" \
    "${repair_environment_vector}" ||
    fail 'Copilot report-repair and normal worker environment vectors differ.'
for secret_value in \
    "${repair_fake_auth}" \
    "${repair_fake_provider}"; do
    for nonsecret_vector in \
        "${repair_arguments_vector}" \
        "${repair_environment_vector}" \
        "${repair_process_capture}/cmdline.txt"; do
        assert_not_contains \
            "${nonsecret_vector}" \
            "${secret_value}" \
            'Report-repair process argv secret safety'
    done
done
for inherited_environment_line in \
    "HOME=${repair_parent_home}" \
    "XDG_CONFIG_HOME=${repair_parent_config}" \
    "XDG_CACHE_HOME=${repair_parent_cache}" \
    "XDG_DATA_HOME=${repair_parent_data}" \
    "XDG_STATE_HOME=${repair_parent_state}" \
    "COPILOT_HOME=${repair_runtime_home}" \
    "COPILOT_GITHUB_TOKEN=${repair_fake_auth}" \
    "COPILOT_PROVIDER_API_KEY=${repair_fake_provider}" \
    'COPILOT_OFFLINE=true'; do
    assert_contains \
        "${repair_process_capture}/environment.txt" \
        "${inherited_environment_line}" \
        'Report-repair inherited environment'
done
for cleared_environment_name in \
    COPILOT_ALLOW_ALL \
    COPILOT_SKILLS_DIRS \
    COPILOT_CUSTOM_INSTRUCTIONS_DIRS \
    COPILOT_DYNAMIC_RETRIEVAL_SKILLS \
    COPILOT_EMBEDDING_ONLY_SKILLS; do
    assert_not_contains \
        "${repair_process_capture}/environment.txt" \
        "${cleared_environment_name}=" \
        'Report-repair environment clearing'
done
assert_equal \
    "${repair_expected_loader}" \
    "$(tr -d '\r\n' < "${repair_process_capture}/copilot-loader.txt")" \
    'Report-repair inherited Copilot loader'

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
harness_persist_agent_state \
    "${runtime_home}" "${agent_state}" max long_context ||
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

An earlier response must not be selected.

### `view`

Tool output must not be selected as the assistant reply.

### Info

Informational transcript blocks must not be selected.

### Copilot

================================================================================
REPOSITORY REVIEW REPORT
Complete deterministic report recovered from the transcript.
### `view`
This real tool-shaped heading remains assistant report content in main mode.
### `view` — Failed
This real failed-tool heading remains assistant report content in main mode.
### task (Completed)
This real task-status heading remains assistant report content in main mode.
### Info
This information heading remains assistant report content in main mode.
### Alert 1
This internal assistant-report heading must remain part of the final response.
================================================================================

---

<sub>Generated by [GitHub Copilot CLI](https://github.com/features/copilot/cli)</sub>
EOF
fallback_main_reply="${fixture_root}/fallback-main-reply.txt"
copilot_extract_latest_assistant_reply \
    "${fallback_transcript}" > "${fallback_main_reply}" ||
    fail 'Copilot main reply extraction failed.'
for preserved_main_heading in \
    '### `view`' \
    '### `view` — Failed' \
    '### task (Completed)' \
    '### Info' \
    '### Alert 1' \
    '<sub>Generated by [GitHub Copilot CLI](https://github.com/features/copilot/cli)</sub>'; do
    assert_contains \
        "${fallback_main_reply}" \
        "${preserved_main_heading}" \
        'Copilot main extraction through EOF'
done
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
assert_contains \
    "${fallback_report}" \
    '### Alert 1' \
    'Copilot main extraction internal heading preservation'
for preserved_report_heading in \
    '### `view`' \
    '### `view` — Failed' \
    '### task (Completed)' \
    '### Info'; do
    assert_contains \
        "${fallback_report}" \
        "${preserved_report_heading}" \
        'Copilot main report heading preservation'
done
[[ ! -e "${fallback_final_message}" ]] ||
    fail 'Copilot transcript fallback left a temporary final-message file.'

repair_descriptor_stdout='{"ProtocolVersion":1,"Section":"OVERALL ASSESSMENT","Field":"Confidence:","Occurrence":1,"OriginalValueSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","ConservativeLevel":"Low"}'
repair_descriptor_transcript='{"ProtocolVersion":1,"Section":"OVERALL ASSESSMENT","Field":"Confidence:","Occurrence":1,"OriginalValueSha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","ConservativeLevel":"Medium"}'
repair_timeline="${fixture_root}/repair-extraction-timeline.txt"
repair_extraction_transcript="${fixture_root}/repair-extraction-transcript.md"
repair_reply="${fixture_root}/repair-extraction-reply.json"
printf '%s\n' "${repair_descriptor_stdout}" > "${repair_timeline}"
cat > "${repair_extraction_transcript}" <<EOF
# Copilot report-repair session

### User

${repair_descriptor_stdout}

### Copilot

An earlier assistant response must not be selected.

### \`view\`

${repair_descriptor_stdout}

### Info

Tool and informational blocks are not assistant replies.

### Copilot

${repair_descriptor_transcript}

---

<sub>Generated by [GitHub Copilot CLI](https://github.com/features/copilot/cli)</sub>
EOF
harness_extract_report_repair \
    "${repair_timeline}" \
    "${repair_extraction_transcript}" \
    "${repair_reply}" ||
    fail 'Copilot report-repair stdout extraction failed.'
assert_equal \
    "${repair_descriptor_stdout}" \
    "$(cat -- "${repair_reply}")" \
    'Copilot report-repair stdout precedence'

printf '%s\n' 'sanitized non-descriptor worker output' \
    > "${repair_timeline}"
harness_extract_report_repair \
    "${repair_timeline}" \
    "${repair_extraction_transcript}" \
    "${repair_reply}" ||
    fail 'Copilot report-repair transcript fallback failed.'
assert_equal \
    "${repair_descriptor_transcript}" \
    "$(cat -- "${repair_reply}")" \
    'Copilot report-repair latest assistant reply'

repair_boundary_markers=(
    '### System'
    '### `view`'
    '### `view` — Failed'
    '### task (Completed)'
    '### Info'
    '### User'
)
for assistant_boundary in "${repair_boundary_markers[@]}"; do
    cat > "${repair_extraction_transcript}" <<EOF
# Copilot report-repair session

### Copilot

${repair_descriptor_transcript}

${assistant_boundary}

${repair_descriptor_stdout}
EOF
    harness_extract_report_repair \
        "${repair_timeline}" \
        "${repair_extraction_transcript}" \
        "${repair_reply}" ||
        fail "Copilot report-repair boundary extraction failed: ${assistant_boundary}"
    assert_equal \
        "${repair_descriptor_transcript}" \
        "$(cat -- "${repair_reply}")" \
        "Copilot report-repair assistant boundary ${assistant_boundary}"
done

for nonassistant_marker in "${repair_boundary_markers[@]}"; do
    cat > "${repair_extraction_transcript}" <<EOF
# Copilot report-repair session

${nonassistant_marker}

${repair_descriptor_stdout}
EOF
    set +e
    harness_extract_report_repair \
        "${repair_timeline}" \
        "${repair_extraction_transcript}" \
        "${repair_reply}" >/dev/null
    repair_extraction_status=$?
    set -e
    [[ "${repair_extraction_status}" -eq 42 ]] ||
        fail "Copilot non-assistant repair extraction returned ${repair_extraction_status}, expected 42: ${nonassistant_marker}"
    [[ ! -e "${repair_reply}" ]] ||
        fail "Copilot non-assistant repair extraction left a reply file: ${nonassistant_marker}"
    assert_equal \
        'Copilot report repair did not return a supported confidence-edit descriptor.' \
        "${RHYOLITE_HARNESS_ERROR_DETAIL}" \
        "Copilot report-repair missing descriptor detail ${nonassistant_marker}"
done

printf '%s\n%s\n' \
    'stdout prefix' \
    "${repair_descriptor_stdout}" > "${repair_timeline}"
printf '# Transcript without a Copilot assistant reply\n' \
    > "${repair_extraction_transcript}"
set +e
rhyolite_harness_invoke \
    harness_extract_report_repair \
    "${repair_timeline}" \
    "${repair_extraction_transcript}" \
    "${repair_reply}" >/dev/null
repair_invoke_status=$?
set -e
[[ "${repair_invoke_status}" -eq 1 &&
    "${RHYOLITE_HARNESS_LAST_STATUS}" -eq 42 ]] ||
    fail 'Guarded report-repair extraction did not preserve adapter status 42.'

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
set +e
rhyolite_harness_invoke \
    harness_extract_final_report \
    "${fallback_timeline}" \
    "${missing_section_transcript}" \
    "${missing_section_temp}" \
    "${missing_section_report}" >/dev/null
missing_section_invoke_status=$?
set -e
[[ "${missing_section_invoke_status}" -eq 1 &&
    "${RHYOLITE_HARNESS_LAST_STATUS}" -eq 42 ]] ||
    fail 'Guarded harness invocation did not preserve the adapter status 42.'

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
harness_sanitize_runtime_home "${repair_runtime_home}" ||
    fail 'Copilot adapter could not remove the report-repair runtime home.'
[[ ! -e "${repair_runtime_home}" ]] ||
    fail 'Copilot adapter left the report-repair runtime home after cleanup.'
harness_sanitize_runtime_home "${repair_runtime_home}" ||
    fail 'Copilot report-repair runtime-home cleanup is not idempotent.'

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
plan_timeout_one="${fixture_root}/plan-timeout-one.json"
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
cp -- "${REPOSITORY_DISCOVERY_CURL_FIXTURE}" \
    "${plan_mock_bin}/curl"
chmod +x "${plan_mock_bin}/date" "${plan_mock_bin}/curl"
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
    'Provider=%s' \
    'ReportRepairPolicy=%s'; do
    assert_contains \
        "${RUNNER}" \
        "${hash_fragment}" \
        'Harness identity approval-hash material'
done
assert_contains \
    "${RUNNER}" \
    '{"Mode":"isolated-confidence-edit","ProtocolVersion":1,"AttemptLimit":%s,"TimeoutSeconds":%s,"DeterministicNormalizations":["markdown-table-rows"]}' \
    'Report-repair policy compact key order'
assert_contains \
    "${RUNNER}" \
    '"${REPORT_REPAIR_TIMEOUT_SECONDS}s"' \
    'Report-repair runtime uses the effective timeout bound'

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
env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${plan_mock_bin}:${PATH}" \
    "${RUNNER}" "${plan_arguments[@]}" \
    --timeout-minutes 1 \
    >"${plan_timeout_one}" 2>"${plan_stderr}" ||
    fail 'One-minute Copilot plan-only invocation failed.'
[[ ! -s "${plan_stderr}" ]] ||
    fail 'One-minute Copilot plan-only invocation wrote stderr.'
[[ ! -e "${plan_mock_bin}/curl.log" ]] ||
    fail 'Plan-only harness selection invoked repository transport discovery.'

python3 - \
    "${plan_default}" \
    "${plan_environment}" \
    "${plan_explicit}" \
    "${plan_override}" \
    "${plan_timeout_one}" <<'PY'
import json
import pathlib
import sys

plans = [json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
         for path in sys.argv[1:5]]
timeout_one = json.loads(
    pathlib.Path(sys.argv[5]).read_text(encoding="utf-8")
)
for index, plan in enumerate(plans):
    if plan.get("SchemaVersion") != 5:
        raise SystemExit(f"plan {index} did not use harness-aware schema 5")
    if plan.get("Harness") != "copilot":
        raise SystemExit(f"plan {index} lost the selected harness")
    if plan.get("ReasoningEffort") != "max":
        raise SystemExit(f"plan {index} lost resolved reasoning effort")
    if plan.get("ContextTier") != "long_context":
        raise SystemExit(f"plan {index} lost resolved context tier")
    if plan.get("ReportRepairPolicy") != {
        "Mode": "isolated-confidence-edit",
        "ProtocolVersion": 1,
        "AttemptLimit": 1,
        "TimeoutSeconds": 300,
        "DeterministicNormalizations": ["markdown-table-rows"],
    }:
        raise SystemExit(f"plan {index} changed the fixed report-repair policy")
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
if timeout_one.get("SchemaVersion") != 5:
    raise SystemExit("one-minute plan changed schema")
if timeout_one.get("SessionTimeoutMinutes") != 1:
    raise SystemExit("one-minute plan lost its approved session timeout")
if timeout_one.get("ReportRepairPolicy") != {
    "Mode": "isolated-confidence-edit",
    "ProtocolVersion": 1,
    "AttemptLimit": 1,
    "TimeoutSeconds": 60,
    "DeterministicNormalizations": ["markdown-table-rows"],
}:
    raise SystemExit("one-minute plan did not cap report repair at 60 seconds")
if timeout_one.get("ApprovalHash") in hashes:
    raise SystemExit("one-minute repair bound did not change approval identity")
PY
assert_contains \
    "${plan_default}" \
    '"ReportRepairPolicy": {"Mode":"isolated-confidence-edit","ProtocolVersion":1,"AttemptLimit":1,"TimeoutSeconds":300,"DeterministicNormalizations":["markdown-table-rows"]}' \
    'Default report-repair policy JSON'
assert_contains \
    "${plan_timeout_one}" \
    '"ReportRepairPolicy": {"Mode":"isolated-confidence-edit","ProtocolVersion":1,"AttemptLimit":1,"TimeoutSeconds":60,"DeterministicNormalizations":["markdown-table-rows"]}' \
    'Capped report-repair policy JSON'

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
    noop-load \
    'harness noop load' \
    explicit \
    noop \
    unset
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
    '"SchemaVersion": 5' \
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

assert_anonymous_clone_operation() {
    [[ "${HOME}" == */.anonymous-git-home ]] || exit 60
    [[ "${USERPROFILE-}" == "${HOME}" ]] || exit 61
    [[ "${XDG_CONFIG_HOME-}" == "${HOME}" ]] || exit 62
    [[ "${CURL_HOME-}" == "${HOME}" ]] || exit 63
    [[ "${GIT_CONFIG_NOSYSTEM-}" == 1 ]] || exit 64
    [[ "${GIT_CONFIG_GLOBAL-}" == /dev/null ]] || exit 65
    [[ "${GIT_NO_REPLACE_OBJECTS-}" == 1 ]] || exit 66
    [[ -z "${COPILOT_GITHUB_TOKEN-}" &&
        -z "${GH_TOKEN-}" &&
        -z "${GITHUB_TOKEN-}" &&
        -z "${GIT_ASKPASS-}" &&
        -z "${SSH_ASKPASS-}" &&
        -z "${SSH_AUTH_SOCK-}" &&
        -z "${NETRC-}" &&
        -z "${http_proxy-}" &&
        -z "${https_proxy-}" &&
        -z "${all_proxy-}" &&
        -z "${no_proxy-}" &&
        -z "${HTTP_PROXY-}" &&
        -z "${HTTPS_PROXY-}" &&
        -z "${ALL_PROXY-}" &&
        -z "${NO_PROXY-}" ]] || exit 67
    [[ " $* " == *" credential.helper= "* ]] || exit 68
    [[ " $* " == *" credential.interactive=false "* ]] || exit 69
    [[ " $* " == *" http.extraHeader= "* ]] || exit 70
    [[ " $* " == *" http.proxy= "* ]] || exit 71
    [[ " $* " == *" http.sslVerify=true "* ]] || exit 72
    [[ " $* " == *" http.followRedirects=false "* ]] || exit 73
    [[ " $* " == *" http.curloptResolve=github.com:443:93.184.216.34 "* ]] ||
        exit 74
}

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

if [[ "${working_directory}" == *-readonly ]]; then
    assert_anonymous_clone_operation "$@"
fi

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
        printf '%s\n' \
            "${RHYOLITE_MOCK_REPOSITORY_CONTENT:-# mock repository}" \
            > "${destination}/README.md"
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

if [[ "${1-}" == help && "${2-}" == config ]]; then
    cat <<'EOF'
  `model`: AI model to use for Copilot CLI.
    - "gpt-6-sol"
    - "gpt-5.6-sol"
    - "claude-fable-5"
  `reasoning_effort`: Reasoning effort.
EOF
    exit 0
fi

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

cp -- "${REPOSITORY_DISCOVERY_CURL_FIXTURE}" \
    "${runner_mock_bin}/curl"
cat > "${runner_mock_bin}/curl.map" <<'EOF'
https://github.com/octocat/Hello-World/info/refs?service=git-upload-pack|200||github.com:443:93.184.216.34
EOF
chmod +x \
    "${runner_mock_bin}/date" \
    "${runner_mock_bin}/python3" \
    "${runner_mock_bin}/git" \
    "${runner_mock_bin}/copilot" \
    "${runner_mock_bin}/curl"

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
if (state.SchemaVersion !== 6 ||
    state.Harness !== "copilot" ||
    state.Model !== "gpt-5.6-sol" ||
    state.ReasoningEffort !== "max" ||
    state.ContextTier !== "long_context" ||
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
  throw new Error("runner seam state lost harness contract-v4 identity");
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
  if (plan.SchemaVersion !== 5) {
    throw new Error(`runner seam plan ${index} changed schema`);
  }
  if (!/^[0-9a-f]{64}$/.test(plan.ApprovalHash)) {
    throw new Error(`runner seam plan ${index} has invalid hash`);
  }
  if (plan.Harness !== "copilot" ||
      plan.Model !== "gpt-5.6-sol" ||
      plan.ReasoningEffort !== "max" ||
      plan.ContextTier !== "long_context" ||
      JSON.stringify(plan.ReportRepairPolicy) !== JSON.stringify({
        Mode: "isolated-confidence-edit",
        ProtocolVersion: 1,
        AttemptLimit: 1,
        TimeoutSeconds: 300,
        DeterministicNormalizations: ["markdown-table-rows"],
      }) ||
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

noop_test_plugin="${fixture_root}/noop-test-plugin"
noop_test_skill="${noop_test_plugin}/skills/readonly-repository-review"
noop_test_scripts="${noop_test_skill}/scripts"
noop_worker_bin="${fixture_root}/noop-worker-bin"
mkdir -p -- \
    "${noop_test_plugin}/lib/harness" \
    "${noop_test_plugin}/scripts" \
    "${noop_test_plugin}/branding" \
    "${noop_test_scripts}" \
    "${noop_worker_bin}"
cp -- "${HARNESS_COMMON}" \
    "${noop_test_plugin}/lib/harness/common.sh"
cp -- "${PLUGIN_ROOT}/lib/harness/copilot.sh" \
    "${noop_test_plugin}/lib/harness/copilot.sh"
cp -- "${NOOP_ADAPTER_FIXTURE}" \
    "${noop_test_plugin}/lib/harness/noop.sh"
cp -- "${PREFERENCE_HELPER}" \
    "${noop_test_plugin}/scripts/launcher-preferences.sh"
cp -- "${PLUGIN_ROOT}/branding/welcome-metadata.json" \
    "${noop_test_plugin}/branding/welcome-metadata.json"
cp -- "${RUNNER}" \
    "${noop_test_scripts}/run-parallel-reviews.sh"
cp -- "${OUTPUT_HELPER}" \
    "${noop_test_scripts}/review-output.sh"
cp -- "${PROMPT}" "${noop_test_skill}/review-prompt.txt"
cp -- "${NOOP_WORKER_FIXTURE}" "${noop_worker_bin}/noop-worker"
chmod +x \
    "${noop_test_scripts}/run-parallel-reviews.sh" \
    "${noop_worker_bin}/noop-worker"
cat >> "${noop_test_plugin}/lib/harness/common.sh" <<'NOOP_TEST_REGISTRY'

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
        noop)
            printf -v "${output_variable}" '%s' \
                "${plugin_root%/}/lib/harness/noop.sh"
            ;;
        *)
            rhyolite_harness_set_error \
                "Harness '${selected_harness}' is not supported by this focused test registry."
            return 1
            ;;
    esac
}
NOOP_TEST_REGISTRY

for fixture_harness in copilot noop; do
    (
        unset RHYOLITE_HARNESS RHYOLITE_LAUNCHER_HARNESS
        # shellcheck source=/dev/null
        source "${noop_test_plugin}/lib/harness/common.sh"
        rhyolite_harness_load \
            "${noop_test_plugin}" "${fixture_harness}" ||
            fail "Copied fixed registry could not load ${fixture_harness}."
        assert_equal \
            "${fixture_harness}" \
            "${RHYOLITE_HARNESS_LOADED_ID}" \
            "Copied fixed registry loaded ID ${fixture_harness}"
        assert_equal \
            "${noop_test_plugin}/lib/harness/${fixture_harness}.sh" \
            "${RHYOLITE_HARNESS_LOADED_PATH}" \
            "Copied fixed registry loaded path ${fixture_harness}"
        for function_name in "${required_contract_functions[@]}"; do
            declare -F "${function_name}" >/dev/null ||
                fail "Copied ${fixture_harness} adapter is missing ${function_name}."
        done
    )
done

(
    PATH="${noop_worker_bin}:/usr/bin:/bin"
    export PATH
    unset RHYOLITE_HARNESS RHYOLITE_LAUNCHER_HARNESS
    # shellcheck source=/dev/null
    source "${noop_test_plugin}/lib/harness/common.sh"
    rhyolite_harness_load "${noop_test_plugin}" noop ||
        fail 'Development no-op adapter did not load.'
    assert_equal 'noop' "$(harness_id)" 'No-op harness ID'
    assert_equal \
        'Development No-op Fixture' \
        "$(harness_display_name)" \
        'No-op display name'
    assert_equal 'noop-worker' "$(harness_cli_name)" 'No-op CLI name'
    harness_require_cli ||
        fail 'No-op adapter did not accept its fixture worker.'
    assert_equal \
        'noop-fixture-model' \
        "$(harness_default_model)" \
        'No-op default model'
    harness_validate_model_id noop-fixture-model ||
        fail 'No-op adapter rejected its fixture model.'
    if harness_validate_model_id gpt-5.6-sol; then
        fail 'No-op adapter accepted the Copilot model.'
    fi
    assert_equal \
        'max' \
        "$(harness_max_reasoning_effort noop-fixture-model)" \
        'No-op maximum reasoning effort'
    mapfile -t noop_model_choices < <(harness_model_choices)
    [[ ${#noop_model_choices[@]} -eq 1 &&
        "${noop_model_choices[0]}" == \
            'Development no-op fixture (diagnostic only) - noop-fixture-model' ]] ||
        fail 'No-op model choices are not deterministic.'

    declare -A noop_expected_capabilities=(
        [fleet]=no
        [structured_questions]=no
        [subagents]=no
        [builtin_security_specialist]=no
        [builtin_research_specialist]=no
        [web_research]=no
        [shell_denial]=yes
        [final_message_file]=yes
    )
    for capability in "${!noop_expected_capabilities[@]}"; do
        assert_equal \
            "${noop_expected_capabilities[${capability}]}" \
            "$(harness_capability "${capability}")" \
            "No-op capability ${capability}"
    done
    assert_equal \
        'unverified' \
        "$(harness_capability future_unknown_capability)" \
        'No-op unknown capability'
    [[ -z "$(harness_auth_secret_env_vars)" ]] ||
        fail 'No-op adapter exposed an authentication-variable name.'
    assert_equal \
        'This development-only no-op fixture requires no authentication and must never be used for a real review.' \
        "$(harness_login_remediation)" \
        'No-op login remediation'
    assert_equal \
        'Do not resume this development-only no-op fixture; rerun the focused harness contract validator.' \
        "$(harness_resume_policy)" \
        'No-op resume policy'
    noop_provider_path="${fixture_root}/noop-provider-summary.json"
    harness_provider_summary > "${noop_provider_path}"
    python3 - "${noop_provider_path}" <<'PY'
import json
import pathlib
import sys

summary = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
if summary != {
    "Id": "fixture-noop",
    "Host": "fixture.invalid",
    "ForwardedEnvVarNames": [],
}:
    raise SystemExit("development no-op provider summary is invalid")
PY
    if harness_allow_all_detected; then
        fail 'No-op adapter reported inherited allow-all state.'
    fi
)

noop_repair_descriptor='{"ProtocolVersion":1,"Section":"OVERALL ASSESSMENT","Field":"Confidence:","Occurrence":1,"OriginalValueSha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","ConservativeLevel":"Low"}'
(
    PATH="${noop_worker_bin}:/usr/bin:/bin"
    export PATH
    unset RHYOLITE_HARNESS RHYOLITE_LAUNCHER_HARNESS
    # shellcheck source=/dev/null
    source "${noop_test_plugin}/lib/harness/common.sh"
    rhyolite_harness_load "${noop_test_plugin}" noop ||
        fail 'Development no-op repair adapter did not load.'
    harness_require_cli ||
        fail 'Development no-op repair worker was unavailable.'
    harness_prepare_run ||
        fail 'Development no-op repair run preparation failed.'

    run_noop_repair_fixture() {
        local response_mode="$1"
        local expect_success="$2"
        local case_root="${fixture_root}/noop-repair-${response_mode}"
        local workdir="${case_root}/workdir"
        local runtime_home="${case_root}/runtime-home"
        local transcript="${case_root}/artifacts/session.md"
        local request="${case_root}/artifacts/request.txt"
        local timeline="${case_root}/artifacts/timeline.txt"
        local reply="${case_root}/artifacts/reply.json"
        local capture="${case_root}/capture"
        local session_name="noop-repair-${response_mode}"
        local session_id='11111111-2222-4333-8444-555555555555'
        local status=0
        local -a repair_arguments=()
        local -a repair_environment=()

        mkdir -m 700 -- \
            "${case_root}" \
            "${workdir}" \
            "${runtime_home}" \
            "${case_root}/artifacts" \
            "${capture}"
        RHYOLITE_NOOP_CAPTURE_ROOT="${capture}"
        RHYOLITE_NOOP_REPAIR_RESPONSE_MODE="${response_mode}"
        harness_prepare_worker_home \
            "${runtime_home}" max long_context report-repair ||
            fail "No-op report-repair home preparation failed: ${response_mode}"
        harness_report_repair_argv \
            repair_arguments \
            "${workdir}" \
            "${session_name}" \
            "${session_id}" \
            noop-fixture-model \
            max \
            long_context \
            '' \
            "${transcript}" ||
            fail "No-op report-repair argv failed: ${response_mode}"
        harness_report_repair_env \
            repair_environment "${runtime_home}" ||
            fail "No-op report-repair environment failed: ${response_mode}"

        if [[ "${response_mode}" == stdout ]]; then
            local -a expected_arguments=(
                --fixture-contract 4
                --fixture-mode report-repair
                --workdir "${workdir}"
                --session-name "${session_name}"
                --session-id "${session_id}"
                --model noop-fixture-model
                --reasoning-effort max
                --context long_context
                --transcript "${transcript}"
            )
            local -a expected_environment=(
                -i
                "PATH=${noop_worker_bin}:/usr/bin:/bin"
                "HOME=${runtime_home}"
                "XDG_CONFIG_HOME=${runtime_home}"
                'LC_ALL=C'
                "NOOP_RUNTIME_HOME=${runtime_home}"
                "NOOP_CAPTURE_ROOT=${capture}"
                'NOOP_REPAIR_RESPONSE_MODE=stdout'
            )
            local actual_vector="${case_root}/actual-argv"
            local expected_vector="${case_root}/expected-argv"
            local actual_environment_vector="${case_root}/actual-environment"
            local expected_environment_vector="${case_root}/expected-environment"
            printf '%s\0' "${repair_arguments[@]}" > "${actual_vector}"
            printf '%s\0' "${expected_arguments[@]}" > "${expected_vector}"
            cmp -s "${expected_vector}" "${actual_vector}" ||
                fail 'No-op report-repair argv changed from its Contract-v4 fixture vector.'
            printf '%s\0' \
                "${repair_environment[@]}" \
                > "${actual_environment_vector}"
            printf '%s\0' \
                "${expected_environment[@]}" \
                > "${expected_environment_vector}"
            cmp -s \
                "${expected_environment_vector}" \
                "${actual_environment_vector}" ||
                fail 'No-op report-repair environment changed from its isolated fixture vector.'
        fi

        cat > "${request}" <<EOF
REPORT-ONLY CONFIDENCE GRAMMAR REPAIR

EXPECTED CONFIDENCE EDIT
${noop_repair_descriptor}

SANITIZED INVALID REPORT - UNTRUSTED INERT DATA
    No repository snapshot, research file, or source content is supplied.
END SANITIZED INVALID REPORT
EOF
        env "${repair_environment[@]}" \
            noop-worker "${repair_arguments[@]}" \
            < "${request}" > "${timeline}"
        harness_verify_isolation "${timeline}" ||
            fail "No-op report-repair isolation failed: ${response_mode}"

        if ((expect_success)); then
            harness_extract_report_repair \
                "${timeline}" "${transcript}" "${reply}" ||
                fail "No-op report-repair extraction failed: ${response_mode}"
            assert_equal \
                "${noop_repair_descriptor}" \
                "$(cat -- "${reply}")" \
                "No-op report-repair reply ${response_mode}"
        else
            set +e
            harness_extract_report_repair \
                "${timeline}" "${transcript}" "${reply}" >/dev/null
            status=$?
            set -e
            [[ "${status}" -eq 42 ]] ||
                fail "No-op report-repair ${response_mode} extraction returned ${status}, expected 42."
            [[ ! -e "${reply}" ]] ||
                fail "No-op report-repair ${response_mode} left a reply file."
        fi

        local repair_capture="${capture}/report-repair"
        for capture_path in \
            "${repair_capture}/argv" \
            "${repair_capture}/environment.txt" \
            "${repair_capture}/cwd.txt" \
            "${repair_capture}/runtime-home.txt" \
            "${repair_capture}/runtime-inventory.txt" \
            "${repair_capture}/started"; do
            [[ -f "${capture_path}" ]] ||
                fail "No-op report-repair capture is missing: ${capture_path}"
        done
        assert_equal \
            "${workdir}" \
            "$(tr -d '\r\n' < "${repair_capture}/cwd.txt")" \
            "No-op report-repair empty workdir ${response_mode}"
        assert_contains \
            "${repair_capture}/runtime-inventory.txt" \
            $'fixture-runtime.json\t600\tf' \
            "No-op report-repair runtime marker ${response_mode}"
        assert_not_contains \
            "${repair_capture}/runtime-inventory.txt" \
            'session-state' \
            "No-op report-repair session persistence ${response_mode}"
        assert_not_contains \
            "${repair_capture}/environment.txt" \
            'RHYOLITE_MOCK_REPOSITORY_CONTENT=' \
            "No-op report-repair source isolation ${response_mode}"
        assert_not_contains \
            "${repair_capture}/environment.txt" \
            'RESEARCH_' \
            "No-op report-repair research isolation ${response_mode}"
        [[ -z "$(find "${workdir}" -mindepth 1 -print -quit)" ]] ||
            fail "No-op report-repair worker wrote into its empty workdir: ${response_mode}"
        harness_sanitize_runtime_home "${runtime_home}" ||
            fail "No-op report-repair cleanup failed: ${response_mode}"
        [[ ! -e "${runtime_home}" ]] ||
            fail "No-op report-repair runtime home survived cleanup: ${response_mode}"
    }

    run_noop_repair_fixture stdout 1
    run_noop_repair_fixture transcript 1
    run_noop_repair_fixture missing 0
    run_noop_repair_fixture user-only 0
    run_noop_repair_fixture system-only 0
    run_noop_repair_fixture view-only 0
    run_noop_repair_fixture view-failed 0
    run_noop_repair_fixture task-completed 0
    run_noop_repair_fixture info-only 0

    failure_root="${fixture_root}/noop-repair-function-failures"
    failure_workdir="${failure_root}/workdir"
    failure_runtime="${failure_root}/runtime"
    failure_transcript="${failure_root}/session.md"
    failure_timeline="${failure_root}/timeline.txt"
    failure_reply="${failure_root}/reply.json"
    mkdir -p -- "${failure_workdir}" "${failure_runtime}"
    printf '%s\n' "${noop_repair_descriptor}" > "${failure_timeline}"
    harness_prepare_worker_home \
        "${failure_runtime}" max long_context report-repair ||
        fail 'No-op failure fixture could not prepare its repair home.'
    declare -a failure_arguments=()
    declare -a failure_environment=()
    for failure_function in \
        harness_report_repair_argv \
        harness_report_repair_env \
        harness_extract_report_repair; do
        RHYOLITE_NOOP_FAIL_FUNCTION="${failure_function}"
        set +e
        case "${failure_function}" in
            harness_report_repair_argv)
                harness_report_repair_argv \
                    failure_arguments \
                    "${failure_workdir}" \
                    noop-repair-failure \
                    99999999-8888-4777-8666-555555555555 \
                    noop-fixture-model \
                    max \
                    long_context \
                    '' \
                    "${failure_transcript}" >/dev/null
                ;;
            harness_report_repair_env)
                harness_report_repair_env \
                    failure_environment "${failure_runtime}" >/dev/null
                ;;
            harness_extract_report_repair)
                harness_extract_report_repair \
                    "${failure_timeline}" \
                    "${failure_transcript}" \
                    "${failure_reply}" >/dev/null
                ;;
        esac
        failure_status=$?
        set -e
        ((failure_status != 0)) ||
            fail "No-op injected ${failure_function} failure unexpectedly succeeded."
        assert_equal \
            "Development-only no-op fixture injected failure in ${failure_function}." \
            "${RHYOLITE_HARNESS_ERROR_DETAIL}" \
            "No-op injected ${failure_function} detail"
    done
    unset RHYOLITE_NOOP_FAIL_FUNCTION

    RHYOLITE_NOOP_FAIL_FUNCTION=harness_sanitize_runtime_home
    if harness_sanitize_runtime_home "${failure_runtime}" >/dev/null 2>&1; then
        fail 'No-op injected report-repair cleanup failure unexpectedly succeeded.'
    fi
    [[ -d "${failure_runtime}" ]] ||
        fail 'No-op injected report-repair cleanup failure lost runtime evidence.'
    unset RHYOLITE_NOOP_FAIL_FUNCTION
    harness_sanitize_runtime_home "${failure_runtime}" ||
        fail 'No-op report-repair runtime cleanup did not recover after injected failure.'
)

noop_runner="${noop_test_scripts}/run-parallel-reviews.sh"
copied_copilot_plan="${fixture_root}/copied-copilot-plan.json"
noop_plan="${fixture_root}/noop-plan.json"
noop_plan_stderr="${fixture_root}/noop-plan.stderr"
env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${noop_worker_bin}:${plan_mock_bin}:${PATH}" \
    "${noop_runner}" --harness copilot "${plan_arguments[@]}" \
    > "${copied_copilot_plan}" 2> "${noop_plan_stderr}" ||
    fail 'Copied-tree Copilot plan failed.'
[[ ! -s "${noop_plan_stderr}" ]] ||
    fail 'Copied-tree Copilot plan wrote stderr.'
env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${noop_worker_bin}:${plan_mock_bin}:${PATH}" \
    "${noop_runner}" --harness noop "${plan_arguments[@]}" \
    > "${noop_plan}" 2> "${noop_plan_stderr}" ||
    fail 'Copied-tree no-op plan failed.'
[[ ! -s "${noop_plan_stderr}" ]] ||
    fail 'Copied-tree no-op plan wrote stderr.'

python3 - \
    "${plan_default}" \
    "${copied_copilot_plan}" \
    "${noop_plan}" <<'PY'
import json
import pathlib
import sys

production_copilot, copied_copilot, noop = [
    json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
    for path in sys.argv[1:]
]
if production_copilot["ApprovalHash"] != copied_copilot["ApprovalHash"]:
    raise SystemExit("copied fixed registry changed the Copilot approval hash")
if noop.get("SchemaVersion") != 5:
    raise SystemExit("no-op plan did not use schema 5")
if noop.get("Harness") != "noop":
    raise SystemExit("no-op plan lost harness identity")
if noop.get("Model") != "noop-fixture-model":
    raise SystemExit("no-op plan lost adapter-owned model identity")
if noop.get("ReasoningEffort") != "max":
    raise SystemExit("no-op plan lost adapter-owned reasoning effort")
if noop.get("ReportRepairPolicy") != {
    "Mode": "isolated-confidence-edit",
    "ProtocolVersion": 1,
    "AttemptLimit": 1,
    "TimeoutSeconds": 300,
    "DeterministicNormalizations": ["markdown-table-rows"],
}:
    raise SystemExit("no-op plan changed the fixed report-repair policy")
if noop.get("Provider") != {
    "Id": "fixture-noop",
    "Host": "fixture.invalid",
    "ForwardedEnvVarNames": [],
}:
    raise SystemExit("no-op plan lost adapter-owned provider identity")
if noop["ApprovalHash"] == copied_copilot["ApprovalHash"]:
    raise SystemExit("Copilot and no-op plans shared an approval hash")
PY

copied_copilot_plan_hash="$(contract_plan_hash "${copied_copilot_plan}")"
noop_plan_hash="$(contract_plan_hash "${noop_plan}")"
noop_execution_arguments=(
    --repo https://github.com/octocat/Hello-World
    --scope 1
    --workspace-root "${plan_workspace}"
    --output-root "${plan_output}"
    --non-interactive
    --no-open-html
)

noop_research_workspace="${fixture_root}/noop-research-workspace"
noop_research_output="${fixture_root}/noop-research-output"
noop_research_stdout="${fixture_root}/noop-research.stdout"
noop_research_stderr="${fixture_root}/noop-research.stderr"
set +e
env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${noop_worker_bin}:${plan_mock_bin}:/usr/bin:/bin" \
    "${noop_runner}" \
    --harness noop \
    --repo https://github.com/octocat/Hello-World \
    --scope 2 \
    --workspace-root "${noop_research_workspace}" \
    --output-root "${noop_research_output}" \
    --non-interactive \
    --no-open-html \
    --plan-only > "${noop_research_stdout}" 2> "${noop_research_stderr}"
noop_research_status=$?
set -e
((noop_research_status == 2)) ||
    fail 'No-op fixture unexpectedly reached Copilot-specific public research.'
assert_contains \
    "${noop_research_stderr}" \
    'Stage: harness noop harness_capability' \
    'No-op public-research rejection stage'
assert_contains \
    "${noop_research_stderr}" \
    'The dedicated public-research worker remains runner-owned and Copilot-specific.' \
    'No-op public-research rejection detail'
[[ ! -e "${noop_research_workspace}" &&
    ! -e "${noop_research_output}" ]] ||
    fail 'No-op public-research rejection created workspace or output roots.'

contract_output_run_count() {
    local output_root="$1"

    if [[ ! -d "${output_root}" ]]; then
        printf '0\n'
        return
    fi
    find "${output_root}" -mindepth 1 -maxdepth 1 -type d |
        wc -l | tr -d '[:space:]'
}

assert_cross_harness_mismatch() {
    local name="$1"
    local harness="$2"
    local expected_hash="$3"
    local stdout_path="${fixture_root}/${name}.stdout"
    local stderr_path="${fixture_root}/${name}.stderr"
    local copilot_capture="${fixture_root}/${name}-copilot-capture"
    local noop_capture="${fixture_root}/${name}-noop-capture"
    local before_count
    local after_count
    local status

    before_count="$(contract_output_run_count "${plan_output}")"
    set +e
    env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
        COPILOT_HOME="${runner_source_home}" \
        RHYOLITE_WORKER_CAPTURE="${copilot_capture}" \
        RHYOLITE_NOOP_CAPTURE_ROOT="${noop_capture}" \
        TMPDIR="${runner_tmp_root}" \
        PATH="${noop_worker_bin}:${runner_mock_bin}:/usr/bin:/bin" \
        "${noop_runner}" \
        --harness "${harness}" \
        "${noop_execution_arguments[@]}" \
        --expected-plan-hash "${expected_hash}" \
        > "${stdout_path}" 2> "${stderr_path}"
    status=$?
    set -e
    after_count="$(contract_output_run_count "${plan_output}")"

    ((status == 2)) ||
        fail "${name}: cross-harness approval mismatch returned ${status}"
    assert_contains \
        "${stderr_path}" \
        'approved plan changed; regenerate and reconfirm' \
        "${name} approval mismatch"
    assert_equal \
        "${before_count}" \
        "${after_count}" \
        "${name} output run count"
    [[ ! -e "${copilot_capture}" && ! -e "${noop_capture}" ]] ||
        fail "${name}: cross-harness mismatch started a worker"
}

assert_cross_harness_mismatch \
    noop-with-copilot-approval \
    noop \
    "${copied_copilot_plan_hash}"
assert_cross_harness_mismatch \
    copilot-with-noop-approval \
    copilot \
    "${noop_plan_hash}"

noop_capture="${runner_capture_root}/noop"
noop_tmp_root="${fixture_root}/noop-runner-tmp"
noop_stdout="${fixture_root}/noop-runner.stdout"
noop_stderr="${fixture_root}/noop-runner.stderr"
noop_snapshot_marker='NOOP_SNAPSHOT_CONTENT_MUST_NOT_BE_OBSERVED'
noop_parent_secret='noop-parent-secret-must-not-cross'
mkdir -p -- "${noop_capture}" "${noop_tmp_root}"
env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    COPILOT_GITHUB_TOKEN="${noop_parent_secret}" \
    GH_TOKEN="${noop_parent_secret}" \
    OPENAI_API_KEY="${noop_parent_secret}" \
    RHYOLITE_MOCK_REPOSITORY_CONTENT="${noop_snapshot_marker}" \
    RHYOLITE_NOOP_CAPTURE_ROOT="${noop_capture}" \
    RHYOLITE_NOOP_FORBIDDEN_TEXT="${noop_snapshot_marker}" \
    TMPDIR="${noop_tmp_root}" \
    PATH="${noop_worker_bin}:${runner_mock_bin}:/usr/bin:/bin" \
    "${noop_runner}" \
    --harness noop \
    "${noop_execution_arguments[@]}" \
    --expected-plan-hash "${noop_plan_hash}" \
    > "${noop_stdout}" 2> "${noop_stderr}" ||
    fail 'Development no-op runner seam execution failed.'
[[ ! -s "${noop_stderr}" ]] ||
    fail 'Development no-op runner seam execution wrote stderr.'

noop_run="$(contract_run_path "${noop_stdout}")"
[[ -d "${noop_run}" ]] ||
    fail 'Development no-op execution did not create an output bundle.'
noop_repository="${noop_run}/github--octocat--hello-world"
noop_state="${noop_repository}/state.json"
noop_run_state="${noop_run}/state.json"
noop_manifest="${noop_run}/manifest.json"
noop_report="${noop_repository}/review.txt"
noop_timeline="${noop_repository}/analysis-timeline.txt"
noop_transcript="${noop_repository}/session.md"
noop_request="${noop_repository}/request.txt"
noop_agent_state="${noop_repository}/agent-state"
noop_repo_handoff="${noop_repository}/handoff.md"
noop_run_handoff="${noop_run}/handoff.md"
noop_run_plan="${noop_run}/review-plan.json"
noop_run_plan_text="${noop_run}/review-plan.txt"
for path in \
    "${noop_state}" \
    "${noop_run_state}" \
    "${noop_manifest}" \
    "${noop_report}" \
    "${noop_timeline}" \
    "${noop_transcript}" \
    "${noop_request}" \
    "${noop_repo_handoff}" \
    "${noop_run_handoff}" \
    "${noop_run_plan}" \
    "${noop_run_plan_text}" \
    "${noop_capture}/argv" \
    "${noop_capture}/environment.txt" \
    "${noop_capture}/cwd.txt" \
    "${noop_capture}/runtime-home.txt" \
    "${noop_capture}/runtime-inventory.txt" \
    "${noop_capture}/started"; do
    [[ -f "${path}" ]] || fail "No-op contract artifact is missing: ${path}"
done

mapfile -d '' -t noop_state_values < <(
    node - "${noop_state}" <<'JS'
const fs = require("fs");
const state = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
for (const value of [
  state.Session.Name,
  state.Session.Id,
  state.Paths.ReadOnlyCheckout,
  state.Artifacts.Transcript,
  state.Artifacts.Request,
]) {
  process.stdout.write(`${value}\0`);
}
JS
)
[[ ${#noop_state_values[@]} -eq 5 ]] ||
    fail 'No-op state did not expose expected worker contract fields.'
noop_expected_arguments=(
    --fixture-contract 2
    --session-name "${noop_state_values[0]}"
    --session-id "${noop_state_values[1]}"
    --model noop-fixture-model
    --reasoning-effort max
    --context long_context
    --transcript "${noop_state_values[3]}"
)
noop_expected_vector="${noop_capture}/expected-argv"
printf '%s\0' "${noop_expected_arguments[@]}" > "${noop_expected_vector}"
cmp -s "${noop_expected_vector}" "${noop_capture}/argv" ||
    fail 'No-op adapter worker argv changed from its deterministic contract.'

noop_runtime_home="$(
    tr -d '\r\n' < "${noop_capture}/runtime-home.txt"
)"
[[ "${noop_runtime_home}" == \
    "${noop_tmp_root}/rhyolite-repo-review-noop."* ]] ||
    fail 'No-op adapter used an unexpected runtime-home path.'
[[ ! -e "${noop_runtime_home}" ]] ||
    fail 'No-op adapter left its temporary runtime home.'
assert_contains \
    "${noop_capture}/runtime-inventory.txt" \
    $'fixture-runtime.json\t600\tf' \
    'No-op runtime marker inventory'
assert_contains \
    "${noop_capture}/runtime-inventory.txt" \
    $'session-state/ephemeral/state.json\t600\tf' \
    'No-op ephemeral state inventory'

python3 - \
    "${noop_capture}/environment.txt" \
    "${noop_runtime_home}" \
    "${noop_capture}" \
    "${noop_worker_bin}" \
    "${noop_parent_secret}" \
    "${noop_snapshot_marker}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
runtime_home = sys.argv[2]
capture_root = sys.argv[3]
worker_bin = sys.argv[4]
secret = sys.argv[5]
snapshot_marker = sys.argv[6]
text = path.read_text(encoding="utf-8")
values = {}
for line in text.splitlines():
    name, separator, value = line.partition("=")
    if not separator:
        raise SystemExit(f"invalid environment capture line: {line!r}")
    values[name] = value
required = {
    "HOME": runtime_home,
    "XDG_CONFIG_HOME": runtime_home,
    "LC_ALL": "C",
    "NOOP_RUNTIME_HOME": runtime_home,
    "NOOP_CAPTURE_ROOT": capture_root,
    "PATH": f"{worker_bin}:/usr/bin:/bin",
}
for name, expected in required.items():
    if values.get(name) != expected:
        raise SystemExit(f"no-op worker environment changed {name}")
for forbidden in (
    "COPILOT_GITHUB_TOKEN",
    "GH_TOKEN",
    "GITHUB_TOKEN",
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "COPILOT_ALLOW_ALL",
    "COPILOT_HOME",
):
    if forbidden in values:
        raise SystemExit(f"no-op worker inherited forbidden variable {forbidden}")
if secret in text or snapshot_marker in text:
    raise SystemExit("no-op worker environment exposed parent or repository data")
PY

noop_worker_cwd="$(tr -d '\r\n' < "${noop_capture}/cwd.txt")"
case "${noop_worker_cwd}" in
    "${noop_state_values[2]}"|"${noop_state_values[2]}"/*)
        fail 'No-op worker ran inside the read-only snapshot.'
        ;;
esac
for worker_facing_path in \
    "${noop_capture}/argv" \
    "${noop_capture}/environment.txt" \
    "${noop_capture}/cwd.txt" \
    "${noop_request}" \
    "${noop_timeline}" \
    "${noop_transcript}" \
    "${noop_report}"; do
    if grep -aFq -- "${noop_state_values[2]}" "${worker_facing_path}" ||
        grep -aFq -- "${noop_snapshot_marker}" "${worker_facing_path}"; then
        fail "No-op worker-facing artifact exposed snapshot data: ${worker_facing_path}"
    fi
done
for forbidden_repository_value in \
    'https://github.com/octocat/Hello-World' \
    '7fd1a60b01f91b314f59955a4e4d4e80d8edf11d'; do
    for worker_facing_path in \
        "${noop_capture}/argv" \
        "${noop_capture}/environment.txt" \
        "${noop_request}" \
        "${noop_timeline}" \
        "${noop_transcript}" \
        "${noop_report}"; do
        if grep -aFq -- \
            "${forbidden_repository_value}" "${worker_facing_path}"; then
            fail "No-op worker received repository identity: ${worker_facing_path}"
        fi
    done
done

assert_contains \
    "${noop_request}" \
    'RHYOLITE DEVELOPMENT-ONLY NO-OP HARNESS REQUEST' \
    'No-op diagnostic request'
assert_contains \
    "${noop_timeline}" \
    'NOOP FIXTURE: repository analysis intentionally skipped.' \
    'No-op diagnostic timeline'
assert_not_contains \
    "${noop_timeline}" \
    'REPOSITORY REVIEW REPORT' \
    'No-op transcript-only extraction path'
assert_contains \
    "${noop_report}" \
    'DEVELOPMENT-ONLY NO-OP HARNESS DIAGNOSTIC.' \
    'No-op diagnostic canonical report'
assert_contains \
    "${noop_report}" \
    'This is not a real repository review.' \
    'No-op non-review warning'
assert_contains \
    "${noop_report}" \
    'Repository analysis performed: No.' \
    'No-op analysis denial'
assert_contains \
    "${noop_transcript}" \
    'Development No-op Fixture Session Transcript' \
    'No-op transcript harness identity'
assert_not_contains \
    "${noop_transcript}" \
    'Copilot Session Transcript' \
    'No-op transcript masquerade prevention'
[[ -d "${noop_agent_state}" ]] ||
    fail 'No-op finalization omitted the empty agent-state directory.'
[[ -z "$(find "${noop_agent_state}" -mindepth 1 -print -quit)" ]] ||
    fail 'No-op adapter persisted fixture session state.'

node - \
    "${noop_run_plan}" \
    "${noop_state}" \
    "${noop_run_state}" \
    "${noop_manifest}" <<'JS'
const fs = require("fs");
const [planPath, repositoryStatePath, runStatePath, manifestPath] =
  process.argv.slice(2);
const plan = JSON.parse(fs.readFileSync(planPath, "utf8"));
const repositoryState = JSON.parse(
  fs.readFileSync(repositoryStatePath, "utf8"));
const runState = JSON.parse(fs.readFileSync(runStatePath, "utf8"));
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
const provider = {
  Id: "fixture-noop",
  Host: "fixture.invalid",
  ForwardedEnvVarNames: [],
};
function assertIdentity(value, label) {
  if (value.SchemaVersion !== 6 ||
      value.Harness !== "noop" ||
      value.Model !== "noop-fixture-model" ||
      value.ReasoningEffort !== "max" ||
      value.ContextTier !== "long_context" ||
      JSON.stringify(value.Provider) !== JSON.stringify(provider)) {
    throw new Error(`${label} lost no-op harness/provider identity`);
  }
}
if (plan.SchemaVersion !== 5 ||
    plan.Harness !== "noop" ||
    plan.Model !== "noop-fixture-model" ||
    plan.ReasoningEffort !== "max" ||
    plan.ContextTier !== "long_context" ||
    JSON.stringify(plan.Provider) !== JSON.stringify(provider)) {
  throw new Error("executed no-op plan lost adapter-owned identity");
}
assertIdentity(repositoryState, "repository state");
assertIdentity(runState, "run state");
if (repositoryState.Status !== "Completed" ||
    repositoryState.Session.ResumePolicy !==
      "Do not resume this development-only no-op fixture; rerun the focused harness contract validator.") {
  throw new Error("no-op repository state is not truthful")
}
if (!Array.isArray(manifest) || manifest.length !== 1) {
  throw new Error("no-op manifest shape is invalid");
}
assertIdentity(manifest[0], "manifest entry");
JS

for identity_artifact in \
    "${noop_repo_handoff}" \
    "${noop_run_handoff}" \
    "${noop_run_plan_text}"; do
    assert_contains \
        "${identity_artifact}" \
        'Development No-op Fixture (noop)' \
        'No-op handoff/plan harness identity'
    assert_contains \
        "${identity_artifact}" \
        'fixture-noop' \
        'No-op handoff/plan provider identity'
    assert_contains \
        "${identity_artifact}" \
        'fixture.invalid' \
        'No-op handoff/plan provider host'
done
if grep -RFl -- "${noop_parent_secret}" \
    "${noop_run}" "${noop_capture}" >/dev/null; then
    fail 'No-op run or capture exposed an inherited credential value.'
fi

contract_run_noop_failure_case() {
    local case_name="$1"
    local failure_function="$2"
    local worker_started="$3"
    local expected_terminal_stage="$4"
    local case_root="${fixture_root}/noop-failure-${case_name}"
    local case_capture="${case_root}/capture"
    local case_tmp="${case_root}/tmp"
    local case_stdout="${case_root}/run.stdout"
    local case_stderr="${case_root}/run.stderr"
    local case_combined="${case_root}/run.combined"
    local case_exit
    local run_path
    local state_path
    local errors_path

    mkdir -p -- "${case_capture}" "${case_tmp}"
    set +e
    env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
        COPILOT_GITHUB_TOKEN="${noop_parent_secret}" \
        RHYOLITE_MOCK_REPOSITORY_CONTENT="${noop_snapshot_marker}" \
        RHYOLITE_NOOP_CAPTURE_ROOT="${case_capture}" \
        RHYOLITE_NOOP_FAIL_FUNCTION="${failure_function}" \
        RHYOLITE_NOOP_FORBIDDEN_TEXT="${noop_snapshot_marker}" \
        TMPDIR="${case_tmp}" \
        PATH="${noop_worker_bin}:${runner_mock_bin}:/usr/bin:/bin" \
        "${noop_runner}" \
        --harness noop \
        "${noop_execution_arguments[@]}" \
        --expected-plan-hash "${noop_plan_hash}" \
        > "${case_stdout}" 2> "${case_stderr}"
    case_exit=$?
    set -e
    cat "${case_stdout}" "${case_stderr}" > "${case_combined}"

    if [[ "${failure_function}" == harness_require_cli ||
        "${failure_function}" == harness_prepare_run ]]; then
        ((case_exit == 2)) ||
            fail "${case_name}: top-level no-op failure returned ${case_exit}"
        assert_contains \
            "${case_combined}" \
            "Stage: harness noop ${failure_function}" \
            "${case_name} no-op terminal stage"
        [[ ! -f "${case_capture}/started" ]] ||
            fail "${case_name}: no-op worker started after top-level failure"
        assert_not_contains \
            "${case_combined}" \
            "${noop_parent_secret}" \
            "${case_name} no-op credential sanitization"
        return
    fi

    ((case_exit != 0)) ||
        fail "${case_name}: no-op lifecycle failure unexpectedly succeeded"
    run_path="$(contract_run_path "${case_stdout}")"
    [[ -d "${run_path}" ]] ||
        fail "${case_name}: no-op lifecycle failure lost its artifacts"
    state_path="${run_path}/github--octocat--hello-world/state.json"
    errors_path="${run_path}/github--octocat--hello-world/errors.txt"
    assert_contains \
        "${case_combined}" \
        "Stage: ${expected_terminal_stage}" \
        "${case_name} no-op terminal stage"
    assert_contains \
        "${errors_path}" \
        "Harness failure stage: harness noop ${failure_function}" \
        "${case_name} no-op artifact stage"
    if ((worker_started)); then
        [[ -f "${case_capture}/started" ]] ||
            fail "${case_name}: expected the no-op worker to start"
    else
        [[ ! -f "${case_capture}/started" ]] ||
            fail "${case_name}: no-op worker started before adapter setup completed"
    fi
    node - \
        "${state_path}" \
        "${worker_started}" <<'JS'
const fs = require("fs");
const state = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const workerStarted = process.argv[3] === "1";
if (state.SchemaVersion !== 6 ||
    state.Harness !== "noop" ||
    state.Model !== "noop-fixture-model" ||
    state.Provider?.Id !== "fixture-noop" ||
    state.Provider?.Host !== "fixture.invalid" ||
    state.ReasoningEffort !== "max" ||
    state.ContextTier !== "long_context" ||
    state.Status !== "ReviewFailed" ||
    state.ExitCode === 0) {
  throw new Error("no-op lifecycle failure state is not truthful");
}
if (workerStarted) {
  if (!state.Session.Id || !state.Session.Name) {
    throw new Error("started no-op worker lost session identity");
  }
} else if (state.Session.Id !== "" || state.Session.Name !== "") {
  throw new Error("pre-worker no-op failure retained session identity");
}
JS
    if grep -RFl -- "${noop_parent_secret}" \
        "${run_path}" "${case_capture}" >/dev/null; then
        fail "${case_name}: no-op failure exposed an inherited credential"
    fi
    if [[ "${failure_function}" == harness_sanitize_runtime_home ]]; then
        failed_runtime_home="$(
            tr -d '\r\n' < "${case_capture}/runtime-home.txt"
        )"
        [[ -d "${failed_runtime_home}" ]] ||
            fail 'No-op cleanup failure did not leave verifiable runtime evidence.'
    elif [[ -f "${case_capture}/runtime-home.txt" ]]; then
        cleaned_runtime_home="$(
            tr -d '\r\n' < "${case_capture}/runtime-home.txt"
        )"
        [[ ! -e "${cleaned_runtime_home}" ]] ||
            fail "${case_name}: no-op runtime home survived non-cleanup failure"
    fi
}

contract_run_noop_failure_case \
    noop-require-cli \
    harness_require_cli \
    0 \
    'harness noop harness_require_cli'
contract_run_noop_failure_case \
    noop-prepare-run \
    harness_prepare_run \
    0 \
    'harness noop harness_prepare_run'
contract_run_noop_failure_case \
    noop-render-request \
    harness_render_request \
    0 \
    'harness noop harness_render_request'
contract_run_noop_failure_case \
    noop-worker-argv \
    harness_worker_argv \
    0 \
    'harness noop harness_worker_argv'
contract_run_noop_failure_case \
    noop-prepare-worker-home \
    harness_prepare_worker_home \
    0 \
    'harness noop harness_prepare_worker_home'
contract_run_noop_failure_case \
    noop-worker-env \
    harness_worker_env \
    0 \
    'harness noop harness_worker_env'
contract_run_noop_failure_case \
    noop-persist-state \
    harness_persist_agent_state \
    1 \
    'harness noop harness_persist_agent_state'
contract_run_noop_failure_case \
    noop-verify-isolation \
    harness_verify_isolation \
    1 \
    'harness noop harness_verify_isolation'
contract_run_noop_failure_case \
    noop-extract-report \
    harness_extract_final_report \
    1 \
    'harness noop harness_extract_final_report'
contract_run_noop_failure_case \
    noop-cleanup \
    harness_sanitize_runtime_home \
    1 \
    cleanup

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
        harness_require_cli|harness_prepare_run|harness_prepare_worker_home|harness_worker_env|harness_report_repair_env|harness_render_request|harness_verify_isolation|harness_persist_agent_state|harness_extract_final_report|harness_extract_report_repair)
            cat >> "${fixture_plugin}/lib/harness/copilot.sh" <<EOF

${failure_function}() {
    fixture_adapter_failure
}
EOF
            ;;
        harness_worker_argv|harness_report_repair_argv)
            cat >> "${fixture_plugin}/lib/harness/copilot.sh" <<EOF

${failure_function}() {
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
        [[ ! -f "${allow_all_marker}" ]] ||
            fail "${case_name}: runner still invoked allow-all detection"
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
if (state.SchemaVersion !== 6 ||
    state.Harness !== "copilot" ||
    state.Model !== "gpt-5.6-sol" ||
    state.ReasoningEffort !== "max" ||
    state.ContextTier !== "long_context" ||
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
if [[ "${1-}" == help && "${2-}" == config ]]; then
    cat <<'EOF'
  `model`: AI model to use for Copilot CLI.
    - "gpt-6-sol"
    - "gpt-5.6-sol"
    - "claude-fable-5"
  `reasoning_effort`: Reasoning effort.
EOF
    exit 0
fi
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
[[ "${launcher_help}" == *'--harness ID        Select a registered review harness.'* &&
    "${launcher_help}" == *'Available harnesses:'* &&
    "${launcher_help}" == *'  - copilot'* ]] ||
    fail 'Launcher help does not document the I1a Copilot harness selector.'
[[ "${launcher_help}" != *noop* ]] ||
    fail 'Launcher help exposed the development-only no-op harness.'
[[ ! -e "${launcher_default_capture}" ]] ||
    fail 'Launcher help unexpectedly invoked the downstream Copilot CLI.'
runner_help="$("${RUNNER}" --help)"
[[ "${runner_help}" != *noop* ]] ||
    fail 'Production runner help exposed the development-only no-op harness.'

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
    launcher-noop \
    unset \
    '' \
    'launcher harness validation' \
    "Harness 'noop' is not supported by this Rhyolite installation." \
    'Use --harness copilot with a complete Rhyolite plugin installation.' \
    --harness noop
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
                --repo https://example.com/owner/repository.git \
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
            --repo https://example.com/owner/repository.git \
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
            --repo https://example.com/owner/repository.git \
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
Source=https://example.com/owner/repository.git
FleetMode=standard
Model=gpt-5.6-sol
ReasoningEffort=max
ContextTier=long_context
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
