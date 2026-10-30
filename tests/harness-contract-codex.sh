#!/usr/bin/env bash
# Codex adapter section of the focused harness contract validator.
# Codex is a registered production harness; these fixtures still load it
# through a test-owned registry copy so that they never depend on the
# production plugin tree.

CODEX_HARNESS="${PLUGIN_ROOT}/lib/harness/codex.sh"
CODEX_GUIDED_REVIEW="${PLUGIN_ROOT}/scripts/run-codex-guided-review.sh"
for path in "${CODEX_HARNESS}" "${CODEX_GUIDED_REVIEW}"; do
    [[ -f "${path}" ]] || fail "Required Codex asset is missing: ${path}"
done
bash -n "${CODEX_HARNESS}" ||
    fail 'Codex adapter has a Bash syntax error.'
bash -n "${CODEX_GUIDED_REVIEW}" ||
    fail 'Codex guided review controller has a Bash syntax error.'
[[ -x "${CODEX_GUIDED_REVIEW}" ]] ||
    fail 'Codex guided review controller is not executable.'
# The launcher is the only Codex entrypoint and asks Rhyolite's questions in
# its own terminal. A root marketplace would offer Rhyolite to ordinary Codex
# sessions, which can never start a review.
[[ ! -e "${ROOT}/.agents/plugins/marketplace.json" ]] ||
    fail 'A root Codex marketplace would expose Rhyolite to ordinary Codex sessions.'

codex_test_plugin="${fixture_root}/codex-test-plugin"
mkdir -p -- "${codex_test_plugin}/lib/harness"
cp -- "${HARNESS_COMMON}" "${codex_test_plugin}/lib/harness/common.sh"
cp -- "${CODEX_HARNESS}" "${codex_test_plugin}/lib/harness/codex.sh"
cat >> "${codex_test_plugin}/lib/harness/common.sh" <<'CODEX_TEST_REGISTRY'

rhyolite_harness_list_registered() {
    printf '%s\n' codex
}

rhyolite_harness_registry_lookup() {
    local output_variable="$1"
    local plugin_root="$2"
    local selected_harness="$3"
    [[ "${selected_harness}" == codex ]] || return 1
    printf -v "${output_variable}" '%s' "${plugin_root}/lib/harness/codex.sh"
}
CODEX_TEST_REGISTRY

codex_home="${fixture_root}/codex-source-home"
codex_runtime="${fixture_root}/codex-runtime"
codex_session_root="${fixture_root}/codex-session"
codex_repair_root="${fixture_root}/codex-repair"
codex_agent_state="${fixture_root}/codex-agent-state"
codex_transcript="${fixture_root}/codex-session.md"
codex_fake_bin="${fixture_root}/codex-bin"
mkdir -p -- \
    "${codex_home}" \
    "${codex_runtime}" \
    "${codex_session_root}" \
    "${codex_repair_root}" \
    "${codex_agent_state}" \
    "${codex_fake_bin}"
chmod 700 -- \
    "${codex_home}" \
    "${codex_runtime}" \
    "${codex_session_root}" \
    "${codex_repair_root}" \
    "${codex_agent_state}"
cat > "${codex_home}/config.toml" <<'CODEX_CONFIG'
model = "gpt-5.6-sol"
model_provider = "fixture-provider"

[model_providers.fixture-provider]
name = "Fixture provider"
base_url = "https://fixture.example.org/v1"
wire_api = "responses"
env_key = "FIXTURE_CODEX_KEY"
CODEX_CONFIG
chmod 600 -- "${codex_home}/config.toml"
cat > "${codex_fake_bin}/codex" <<'CODEX_FAKE'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1-}" == --version ]]; then
    printf '%s\n' 'codex-cli 0.163.0'
    exit 0
fi
# Rhyolite starts Codex only as the runner's isolated workers, which these
# fixtures never reach: record any other call and fail it.
if [[ -n "${RHYOLITE_CODEX_FAKE_CALLS-}" ]]; then
    printf '%s\0' "$@" >> "${RHYOLITE_CODEX_FAKE_CALLS}"
fi
exit 2
CODEX_FAKE
chmod 700 -- "${codex_fake_bin}/codex"

export CODEX_HOME="${codex_home}"
export FIXTURE_CODEX_KEY='fixture-secret-value'
PATH="${codex_fake_bin}:${PATH}"

# Load through a literal test-only registry and prove production remains closed.
source "${codex_test_plugin}/lib/harness/common.sh"
rhyolite_harness_load "${codex_test_plugin}" codex ||
    fail 'The test-only Codex registry could not load the complete adapter.'
assert_equal codex "${RHYOLITE_HARNESS_LOADED_ID}" \
    'Codex loaded harness ID'
assert_equal codex "$(harness_id)" 'Codex adapter ID'
assert_equal 'OpenAI Codex CLI' "$(harness_display_name)" \
    'Codex display name'
assert_equal codex "$(harness_cli_name)" 'Codex CLI name'
harness_require_cli || fail 'Codex CLI discovery failed with a fixture executable.'

assert_equal gpt-5.6-sol "$(harness_default_model)" \
    'Codex default model'
assert_equal gpt-5.6-sol "$(harness_list_models)" \
    'Codex offline model catalog'
harness_validate_model_id gpt-5.6-sol ||
    fail 'Codex rejected its verified model.'
if harness_validate_model_id auto >/dev/null 2>&1 ||
    harness_validate_model_id example-unlisted-model >/dev/null 2>&1; then
    fail 'Codex accepted a selector or unverified model.'
fi
assert_equal max "$(harness_max_reasoning_effort gpt-5.6-sol)" \
    'Codex maximum effort'
for effort in high xhigh max; do
    harness_validate_reasoning_effort "${effort}" ||
        fail "Codex rejected supported effort ${effort}."
done
if harness_validate_reasoning_effort medium >/dev/null 2>&1 ||
    harness_validate_reasoning_effort ultra >/dev/null 2>&1; then
    fail 'Codex accepted an effort below the minimum or one that enables delegation.'
fi
assert_equal long_context "$(harness_default_context_tier)" \
    'Codex default context'
for tier in default long_context; do
    harness_validate_context_tier "${tier}" ||
        fail "Codex rejected context tier ${tier}."
done
assert_equal FIXTURE_CODEX_KEY "$(harness_auth_secret_env_vars)" \
    'Codex authentication variable'
node - "$(harness_provider_summary)" <<'JS'
const provider = JSON.parse(process.argv[2]);
if (provider.Id !== "codex-fixture-provider" ||
    provider.Host !== "fixture.example.org" ||
    JSON.stringify(provider.ForwardedEnvVarNames) !==
      JSON.stringify(["FIXTURE_CODEX_KEY"])) {
  throw new Error("Codex provider summary changed");
}
JS
for capability in \
    shell_denial structured_questions web_research \
    builtin_research_specialist final_message_file worker_continuation; do
    assert_equal yes "$(harness_capability "${capability}")" \
        "Codex ${capability} capability"
done
for capability in subagents builtin_security_specialist; do
    assert_equal no "$(harness_capability "${capability}")" \
        "Codex ${capability} capability"
done
assert_equal local-stdio-mcp-snapshot-read-v1 \
    "$(harness_snapshot_transport)" 'Codex snapshot transport'
harness_prepare_run >/dev/null ||
    fail 'Codex run preparation failed with fixture authentication.'
# The runner builds worker arguments before it creates and prepares the
# runtime home, so argv construction must not touch any runtime home.
codex_session_id='00000000-0000-4000-8000-000000000021'
declare -a codex_worker_argv=()
declare -a codex_worker_env=()
harness_worker_argv \
    codex_worker_argv \
    "${codex_session_root}" \
    "${PLUGIN_ROOT}" \
    codex-fixture-session \
    "${codex_session_id}" \
    gpt-5.6-sol \
    max \
    long_context \
    FIXTURE_CODEX_KEY \
    view,glob,rg,skill \
    "${codex_transcript}" \
    0 ||
    fail 'Codex review argv construction failed.'
[[ -z "$(find "${codex_runtime}" -mindepth 1 -print -quit)" &&
    " ${codex_worker_argv[*]} " != *'model_instructions_file'* ]] ||
    fail 'Codex review argv depended on a runtime home that the runner had not prepared.'
harness_prepare_worker_home \
    "${codex_runtime}" max long_context review ||
    fail 'Codex review runtime preparation failed.'
[[ "$(stat -c '%a' "${codex_runtime}/config.toml")" == 600 ]] ||
    fail 'Codex runtime config is not private.'
[[ "$(stat -c '%a' "${codex_runtime}/model-catalog.json")" == 600 ]] ||
    fail 'Codex runtime model catalog is not private.'
[[ "$(stat -c '%a' "${codex_runtime}/review-worker-instructions.md")" == 600 ]] ||
    fail 'Codex review instructions are not private.'
python3 -I - \
    "${codex_runtime}/config.toml" \
    "${codex_runtime}/model-catalog.json" \
    "${codex_runtime}/review-worker-instructions.md" <<'PY'
import json
import sys
import tomllib

with open(sys.argv[1], "rb") as stream:
    config = tomllib.load(stream)
with open(sys.argv[2], encoding="utf-8") as stream:
    catalog = json.load(stream)
provider = config["model_providers"]["fixture-provider"]
assert config["model_catalog_json"] == sys.argv[2]
assert config["model_instructions_file"] == sys.argv[3]
assert "model_instructions_file" not in provider
assert config["model_reasoning_effort"] == "max"
assert config["model_context_window"] == 872000
assert config["model_auto_compact_token_limit"] == 784800
assert config["approval_policy"] == "never"
assert config["sandbox_mode"] == "read-only"
assert config["web_search"] == "disabled"
assert config["project_doc_max_bytes"] == 0
# No project root above the working directory: Codex reads no ancestor .codex.
assert config["project_root_markers"] == []
assert config["agents"]["enabled"] is False
for feature in (
    "shell_tool", "shell_snapshot", "unified_exec", "multi_agent",
    "multi_agent_v2", "plugins", "plugin_hooks", "worktrees",
    "daemon_auto_start",
):
    assert config["features"][feature] is False
assert provider["base_url"] == "https://fixture.example.org/v1"
assert provider["env_key"] == "FIXTURE_CODEX_KEY"
assert provider["request_max_retries"] == 4
assert provider["stream_max_retries"] == 5
assert len(catalog["models"]) == 1
model = catalog["models"][0]
assert model["slug"] == "gpt-5.6-sol"
assert model["shell_type"] == "disabled"
assert model["tool_mode"] is None
assert model["multi_agent_version"] is None
assert [item["effort"] for item in model["supported_reasoning_levels"]] == [
    "high", "xhigh", "max",
]
assert model["max_context_window"] == 872000
PY

harness_worker_env codex_worker_env ||
    fail 'Codex review environment construction failed.'
[[ "${codex_worker_argv[0]}" == --no-daemon &&
    "${codex_worker_argv[1]}" == exec &&
    "${codex_worker_argv[-1]}" == - ]] ||
    fail 'Codex review argv lost its native exec framing.'
for required_argument in \
    --strict-config --ignore-rules --json --skip-git-repo-check \
    --output-last-message; do
    [[ " ${codex_worker_argv[*]} " == *" ${required_argument} "* ]] ||
        fail "Codex review argv lost ${required_argument}."
done
for forbidden_argument in \
    --worktree --add-dir --search \
    --dangerously-bypass-approvals-and-sandbox; do
    [[ " ${codex_worker_argv[*]} " != *" ${forbidden_argument} "* ]] ||
        fail "Codex review argv gained ${forbidden_argument}."
done
grep -Fq 'RHYOLITE_AGENT_SELF_CHECK_V2' \
    "${codex_runtime}/review-worker-instructions.md" ||
    fail 'Codex review instruction bundle lost the shared self-check.'
[[ " ${codex_worker_env[*]} " == *" CODEX_HOME=${codex_runtime} "* &&
    " ${codex_worker_env[*]} " == *' NO_COLOR=1 '* ]] ||
    fail 'Codex review environment lost isolation.'

# Inherited Codex control variables and other provider credentials never
# reach the worker; the approved provider key and the CA certificate that only
# adds TLS trust for the provider connection do.
(
    export CODEX_EXEC_SERVER_URL=fixture-hostile-exec-server
    export CODEX_SQLITE_HOME="${fixture_root}/codex-hostile-sqlite"
    export CODEX_API_KEY=fixture-hostile-key
    export CODEX_INTERNAL_ORIGINATOR_OVERRIDE=fixture-hostile-originator
    export OPENAI_API_KEY=fixture-hostile-openai-key
    export OPENAI_BASE_URL=fixture-hostile-base-url
    export CODEX_THREAD_ID=fixture-hostile-thread
    export CODEX_CA_CERTIFICATE="${fixture_root}/codex-fixture-ca.pem"
    declare -a codex_scrubbed_env=()
    harness_worker_env codex_scrubbed_env ||
        fail 'Codex review environment construction failed with inherited Codex variables.'
    [[ "$(printf '%s\n' "${codex_scrubbed_env[@]}" | grep -cx CODEX_THREAD_ID)" == 1 ]] ||
        fail 'Codex worker environment removed a fixed Codex variable twice.'
    for name in CODEX_EXEC_SERVER_URL CODEX_SQLITE_HOME CODEX_API_KEY \
        CODEX_INTERNAL_ORIGINATOR_OVERRIDE OPENAI_API_KEY OPENAI_BASE_URL \
        CODEX_THREAD_ID; do
        ! env "${codex_scrubbed_env[@]}" printenv "${name}" >/dev/null ||
            fail "Codex worker environment kept inherited ${name}."
    done
    [[ "$(env "${codex_scrubbed_env[@]}" printenv CODEX_CA_CERTIFICATE)" == \
        "${fixture_root}/codex-fixture-ca.pem" &&
        "$(env "${codex_scrubbed_env[@]}" printenv FIXTURE_CODEX_KEY)" == \
        fixture-secret-value &&
        "$(env "${codex_scrubbed_env[@]}" printenv CODEX_HOME)" == \
        "${codex_runtime}" ]] ||
        fail 'Codex worker environment lost its provider trust, approved key, or runtime home.'
    # A provider may name OPENAI_API_KEY itself as its approved key.
    CODEX_PROVIDER_ENV_KEY=OPENAI_API_KEY
    harness_worker_env codex_scrubbed_env ||
        fail 'Codex review environment construction failed for an OPENAI_API_KEY provider.'
    [[ "$(env "${codex_scrubbed_env[@]}" printenv OPENAI_API_KEY)" == \
        fixture-hostile-openai-key ]] &&
        ! env "${codex_scrubbed_env[@]}" printenv OPENAI_BASE_URL >/dev/null ||
        fail 'Codex worker environment removed the approved provider key or kept another provider URL.'
) || fail 'Codex worker environment scrub regression failed.'

# Codex applies /etc/codex to every session, and its legacy managed
# configuration overrides even command-line settings, so no run or worker home
# is prepared while that directory has content or is not a plain directory.
(
    codex_system="${fixture_root}/codex-system-configuration"
    CODEX_SYSTEM_CONFIGURATION_DIRECTORY="${codex_system}"
    codex_require_no_system_configuration ||
        fail 'Codex rejected an absent system configuration directory.'
    mkdir -- "${codex_system}"
    harness_prepare_run >/dev/null ||
        fail 'Codex rejected an empty system configuration directory.'
    printf '%s\n' 'model = "fixture-other"' > "${codex_system}/managed_config.toml"
    if harness_prepare_run >/dev/null 2>&1; then
        fail 'Codex prepared a run despite system configuration.'
    fi
    assert_equal \
        "Codex system configuration exists in ${codex_system}. Codex applies it to every session, including the legacy managed_config.toml that overrides command-line settings, so Rhyolite cannot keep the worker within the approved plan. Remove or relocate it, or use another harness." \
        "${RHYOLITE_HARNESS_ERROR_DETAIL}" \
        'Codex system configuration rejection'
    codex_system_home="${fixture_root}/codex-system-runtime"
    mkdir -m 700 -- "${codex_system_home}"
    if harness_prepare_worker_home \
        "${codex_system_home}" max long_context review >/dev/null 2>&1; then
        fail 'Codex prepared a worker home despite system configuration.'
    fi
    [[ -z "$(find "${codex_system_home}" -mindepth 1 -print -quit)" ]] ||
        fail 'Codex wrote a worker home despite system configuration.'
    rm -f -- "${codex_system}/managed_config.toml"
    rmdir -- "${codex_system}"
    : > "${codex_system}"
    if codex_require_no_system_configuration >/dev/null 2>&1; then
        fail 'Codex accepted a non-directory system configuration path.'
    fi
    rm -f -- "${codex_system}"
    mkdir -- "${codex_system}-target"
    ln -s -- "${codex_system}-target" "${codex_system}"
    if codex_require_no_system_configuration >/dev/null 2>&1; then
        fail 'Codex accepted a symbolic link as its system configuration directory.'
    fi
) || fail 'Codex system configuration regression failed.'

codex_snapshot_launcher="${fixture_root}/codex-snapshot-launcher"
printf '#!/usr/bin/env bash\nexit 0\n' > "${codex_snapshot_launcher}"
chmod 700 -- "${codex_snapshot_launcher}"
declare -a codex_snapshot_arguments=(
    --runtime-root "${fixture_root}/snapshot-runtime"
    --grant-manifest "${fixture_root}/snapshot-grants.json"
    --expected-policy-digest "$(printf '%064d' 0)"
)
codex_snapshot_config="${fixture_root}/codex-snapshot-config.json"
harness_configure_snapshot_transport \
    review codex_worker_argv "${codex_runtime}" \
    "${codex_snapshot_config}" "${codex_snapshot_launcher}" \
    codex_snapshot_arguments \
    '["snapshot_capabilities", "list_snapshot_paths", "read_snapshot_text", "search_snapshot_text"]' ||
    fail 'Codex snapshot configuration failed.'
[[ "$(stat -c '%a' "${codex_snapshot_config}")" == 600 &&
    "${codex_worker_argv[-1]}" == - ]] ||
    fail 'Codex snapshot configuration or stdin framing is unsafe.'
for tool in \
    snapshot_capabilities list_snapshot_paths read_snapshot_text search_snapshot_text; do
    [[ " ${codex_worker_argv[*]} " == \
        *" mcp_servers.rhyolite_snapshot.tools.${tool}.approval_mode=\"approve\" "* ]] ||
        fail "Codex snapshot tool ${tool} is not explicitly preapproved."
done
[[ " ${codex_worker_argv[*]} " == \
    *' mcp_servers.rhyolite_snapshot.env={RHYOLITE_BROKER_OWNER_PID="'* &&
    " ${codex_worker_argv[*]} " == \
    *'RHYOLITE_BROKER_OWNER_START_TIME="'* ]] ||
    fail 'Codex snapshot MCP did not bind the detached broker to its trusted runner owner.'

# A home prepared before any worker argv gets no worker instructions; the
# worker environment then fails closed instead of launching an uninstructed
# worker. Each pending record is consumed once.
(
    codex_order_runtime="${fixture_root}/codex-order-runtime"
    mkdir -- "${codex_order_runtime}" "${codex_order_runtime}-second"
    chmod 700 -- "${codex_order_runtime}" "${codex_order_runtime}-second"
    harness_prepare_worker_home \
        "${codex_order_runtime}" max long_context review ||
        fail 'Codex home-first runtime preparation failed.'
    [[ ! -e "${codex_order_runtime}/review-worker-instructions.md" ]] &&
        ! grep -Fq model_instructions_file "${codex_order_runtime}/config.toml" ||
        fail 'Codex wrote worker instructions without a recorded worker argv.'
    declare -a codex_order_argv=()
    declare -a codex_order_env=()
    harness_worker_argv \
        codex_order_argv "${codex_session_root}" "${PLUGIN_ROOT}" \
        codex-order-session '00000000-0000-4000-8000-000000000024' \
        gpt-5.6-sol max long_context FIXTURE_CODEX_KEY view,glob,rg,skill \
        "${fixture_root}/codex-order-session.md" 0 ||
        fail 'Codex home-first argv construction failed.'
    if harness_worker_env codex_order_env >/dev/null 2>&1; then
        fail 'Codex built a worker environment for a home without instructions.'
    fi
    assert_contains <(printf '%s\n' "${RHYOLITE_HARNESS_ERROR_DETAIL}") \
        'The Codex worker instructions are not ready in the current runtime home' \
        'Codex uninstructed worker rejection'
    harness_prepare_worker_home \
        "${codex_order_runtime}-second" max long_context research ||
        fail 'Codex mismatched-phase runtime preparation failed.'
    harness_prepare_worker_home \
        "${codex_order_runtime}-second" max long_context review ||
        fail 'Codex consumed-record runtime preparation failed.'
    [[ -z "$(find "${codex_order_runtime}-second" -name '*-worker-instructions.md' -print -quit)" ]] ||
        fail 'Codex reused a worker instruction record for another phase or home.'
    if harness_worker_env codex_order_env >/dev/null 2>&1; then
        fail 'Codex reused worker instructions after their record was consumed.'
    fi
) || fail 'Codex worker-instruction ordering regression failed.'

codex_repair_runtime="${fixture_root}/codex-repair-runtime"
mkdir -- "${codex_repair_runtime}"
chmod 700 -- "${codex_repair_runtime}"
harness_prepare_worker_home \
    "${codex_repair_runtime}" max long_context report-repair ||
    fail 'Codex repair runtime preparation failed.'
declare -a codex_repair_argv=()
declare -a codex_repair_env=()
harness_report_repair_argv \
    codex_repair_argv \
    "${codex_repair_root}" \
    codex-repair \
    '00000000-0000-4000-8000-000000000022' \
    gpt-5.6-sol max long_context FIXTURE_CODEX_KEY \
    "${fixture_root}/codex-repair-session.md" ||
    fail 'Codex repair argv construction failed.'
harness_report_repair_env codex_repair_env "${codex_repair_runtime}" ||
    fail 'Codex repair environment construction failed.'
[[ " ${codex_repair_argv[*]} " == *' --ephemeral '* &&
    " ${codex_repair_argv[*]} " != *' mcp_servers.'* &&
    "${codex_repair_argv[-1]}" == - ]] ||
    fail 'Codex repair is not a fresh zero-tool invocation.'

codex_research_runtime="${fixture_root}/codex-research-runtime"
mkdir -- "${codex_research_runtime}"
chmod 700 -- "${codex_research_runtime}"
codex_research_launcher="${fixture_root}/codex-research-launcher"
printf '#!/usr/bin/env bash\nexit 0\n' > "${codex_research_launcher}"
chmod 700 -- "${codex_research_launcher}"
declare -a codex_research_broker_arguments=(
    --runtime-root "${fixture_root}/research-runtime"
    --policy "${fixture_root}/policy.json"
    --scope 2
    --network-root "${fixture_root}/network"
    --repository-url https://github.com/octocat/Hello-World
    --expected-policy-digest "$(printf '%064d' 0)"
)
codex_research_config="${fixture_root}/codex-research-config.json"
# The runner passes the broker's own compact policy tool list; derive it the
# same way so this fixture cannot drift from the real format.
mapfile -d '' -t codex_research_policy_fields < <(
    python3 "${PLUGIN_ROOT}/skills/readonly-repository-review/scripts/research-egress-broker.py" \
        --policy "${PLUGIN_ROOT}/skills/readonly-repository-review/research-policy.json" \
        --scope 2 --web-search-provider duckduckgo-html-v1 \
        --describe-policy --describe-format nul
)
((${#codex_research_policy_fields[@]} == 10)) ||
    fail 'The research broker policy description changed shape.'
codex_research_tools_json="${codex_research_policy_fields[9]}"
[[ "${codex_research_tools_json}" == '["research_capabilities","fetch_public_url","search_public_github","search_public_web","research_network_summary"]' ]] ||
    fail 'The research broker tool list changed.'
harness_write_research_mcp_config \
    "${codex_research_config}" \
    "${codex_research_launcher}" \
    codex_research_broker_arguments \
    "${codex_research_tools_json}" ||
    fail 'Codex research MCP configuration failed.'
declare -a codex_research_argv=()
declare -a codex_research_env=()
(
    declare -a codex_mismatched_argv=()
    if harness_research_worker_argv \
        codex_mismatched_argv "${codex_session_root}" "${PLUGIN_ROOT}" \
        codex-research '00000000-0000-4000-8000-000000000023' \
        gpt-5.6-sol max long_context FIXTURE_CODEX_KEY \
        "${codex_research_config}" \
        research_capabilities,fetch_public_url,search_public_github,research_network_summary \
        "${fixture_root}/codex-research-session.md" >/dev/null 2>&1; then
        fail 'Codex research argv accepted a tool list that differs from its MCP configuration.'
    fi
    assert_equal \
        'The Codex research tool names differ from the research MCP configuration.' \
        "${RHYOLITE_HARNESS_ERROR_DETAIL}" \
        'Codex research tool-list mismatch detail'
) || fail 'Codex research tool-list mismatch regression failed.'
harness_research_worker_argv \
    codex_research_argv \
    "${codex_session_root}" \
    "${PLUGIN_ROOT}" \
    codex-research \
    '00000000-0000-4000-8000-000000000023' \
    gpt-5.6-sol max long_context FIXTURE_CODEX_KEY \
    "${codex_research_config}" \
    research_capabilities,fetch_public_url,search_public_github,search_public_web,research_network_summary \
    "${fixture_root}/codex-research-session.md" ||
    fail 'Codex research argv construction failed.'
[[ -z "$(find "${codex_research_runtime}" -mindepth 1 -print -quit)" &&
    " ${codex_research_argv[*]} " != *'model_instructions_file'* ]] ||
    fail 'Codex research argv depended on a runtime home that the runner had not prepared.'
harness_prepare_worker_home \
    "${codex_research_runtime}" max long_context research ||
    fail 'Codex research runtime preparation failed.'
grep -Fq 'Rhyolite shared review contract' \
    "${codex_research_runtime}/research-worker-instructions.md" &&
    grep -Fxq "model_instructions_file = \"${codex_research_runtime}/research-worker-instructions.md\"" \
        "${codex_research_runtime}/config.toml" ||
    fail 'Codex research runtime home lost its worker instructions.'
harness_research_worker_env codex_research_env ||
    fail 'Codex research environment construction failed.'
[[ "${codex_research_argv[-1]}" == - &&
    " ${codex_research_argv[*]} " == *' mcp_servers.rhyolite_research.required=true '* &&
    " ${codex_research_argv[*]} " == \
      *' mcp_servers.rhyolite_research.env={RHYOLITE_BROKER_OWNER_PID="'* ]] ||
    fail 'Codex research argv lost its strict local MCP server.'

# Synthetic native session evidence exercises mapping, normalization, outcome,
# continuation, and live rejection without invoking Codex.
CODEX_RUNTIME_HOME="${codex_runtime}"
CODEX_REVIEW_RUNTIME_HOME="${codex_runtime}"
CODEX_HOME_PHASE=review
CODEX_CONTEXT_TIER=long_context
CODEX_APPROVED_MODEL=gpt-5.6-sol
CODEX_APPROVED_EFFORT=max
CODEX_TRANSCRIPT_PATH="${codex_transcript}"
CODEX_REVIEW_FINAL_MESSAGE="${fixture_root}/codex-final-message.txt"
codex_native_id='00000000-0000-4000-8000-000000000099'
codex_session_dir="${codex_runtime}/sessions/2026/10/21"
mkdir -p -- "${codex_session_dir}"
cat > "${codex_session_dir}/rollout.jsonl" <<EOF
{"type":"session_meta","payload":{"session_id":"${codex_native_id}","id":"${codex_native_id}","originator":"codex_exec","cli_version":"0.163.0","source":"exec"}}
{"type":"event_msg","payload":{"type":"task_started","model_context_window":828400}}
{"type":"turn_context","payload":{"approval_policy":"never","sandbox_policy":{"type":"read-only"},"model":"gpt-5.6-sol","effort":"max","collaboration_mode":{"mode":"default","settings":{"model":"gpt-5.6-sol","reasoning_effort":"max"}}}}
{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"fixture request"}]}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200000,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":200010},"last_token_usage":{"input_tokens":185172,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":185182},"model_context_window":828400},"rate_limits":null}}
{"type":"compacted","payload":{"message":"","window_id":"fixture-window-1"}}
{"type":"compacted","payload":{"message":"","window_id":"fixture-window-1"}}
{"type":"compacted","payload":{"message":""}}
{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":214810,"cached_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":214830},"last_token_usage":{"input_tokens":14810,"cached_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":0,"total_tokens":14820},"model_context_window":828400},"rate_limits":null}}
{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"EXACT_CODEX_FIXTURE_REPLY"}]}}
EOF
codex_raw="${fixture_root}/codex-output.raw"
cat > "${codex_raw}" <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item-1","type":"agent_message","text":"EXACT_CODEX_FIXTURE_REPLY"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
printf '%s' 'EXACT_CODEX_FIXTURE_REPLY' > "${CODEX_REVIEW_FINAL_MESSAGE}"
harness_persist_agent_state \
    "${codex_runtime}" "${codex_agent_state}" max long_context ||
    fail 'Codex session persistence failed.'
assert_equal verified "${CODEX_TRANSCRIPT_STATUS}" \
    'Codex session verification status'
assert_equal "${codex_native_id}" "${CODEX_NATIVE_THREAD_ID}" \
    'Codex native thread mapping'
codex_normalized="${fixture_root}/codex-output.normalized"
codex_reply="${fixture_root}/codex-final.raw"
harness_normalize_worker_output \
    review "${codex_raw}" gpt-5.6-sol max \
    "${codex_normalized}" "${codex_reply}" ||
    fail 'Codex exact output normalization failed.'
[[ "$(cat "${codex_reply}")" == EXACT_CODEX_FIXTURE_REPLY ]] ||
    fail 'Codex exact final reply changed.'
[[ ! -e "${CODEX_REVIEW_FINAL_MESSAGE}" ]] ||
    fail 'Codex left its unsanitized final-message file after normalization.'
codex_outcome="${fixture_root}/codex-outcome.json"
harness_worker_outcome \
    review "${codex_raw}" "${codex_runtime}" \
    "${codex_session_id}" gpt-5.6-sol max "${codex_outcome}" ||
    fail 'Codex worker outcome failed.'
assert_equal completed \
    "$(rhyolite_harness_validate_outcome_json "${codex_outcome}" review)" \
    'Codex completed outcome'
# Outcome schema 3 reads the private rollout: the approved usable window, the
# largest per-response prompt, and each compaction once by its window ID.
python3 - "${codex_outcome}" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert (data["Schema"], data["PromptBudget"], data["PeakPromptTokens"],
        data["Compactions"], data["ContentRefusals"], data["FallbackModel"]) == (
    3, 828400, 185172, 2, 0, ""), data
PY
declare -a codex_resumed_argv=()
harness_worker_continuation_argv \
    codex_resumed_argv codex_worker_argv ||
    fail 'Codex continuation argv construction failed.'
[[ "${codex_resumed_argv[-2]}" == "${codex_native_id}" &&
    "${codex_resumed_argv[-1]}" == - ]] ||
    fail 'Codex continuation does not resume the mapped native thread.'
[[ "$(printf '%s\n' "${codex_resumed_argv[@]}" | grep -cx resume)" == 1 ]] ||
    fail 'Codex continuation does not contain exactly one resume command.'

# Codex fails before it creates a session when, for example, a required MCP
# server does not start: its error goes to stderr, and it leaves no structured
# output, final message, or session record. That is the worker's own failure,
# never an adapter one, but only while all three are absent.
(
    codex_unstarted_home="${fixture_root}/codex-unstarted-runtime"
    codex_unstarted_raw="${fixture_root}/codex-unstarted.raw"
    codex_unstarted_normalized="${fixture_root}/codex-unstarted.normalized"
    codex_unstarted_reply="${fixture_root}/codex-unstarted.reply"
    mkdir -m 700 -- "${codex_unstarted_home}"
    CODEX_RUNTIME_HOME="${codex_unstarted_home}"
    CODEX_TRANSCRIPT_PATH="${fixture_root}/codex-unstarted-session.md"
    : > "${codex_unstarted_raw}"
    rm -f -- "${CODEX_REVIEW_FINAL_MESSAGE}"
    harness_persist_agent_state \
        "${codex_unstarted_home}" "${fixture_root}/codex-unstarted-state" \
        max long_context ||
        fail 'Codex reported a session that never started as a persistence failure.'
    assert_equal missing "${CODEX_TRANSCRIPT_STATUS}" \
        'Codex unstarted session status'
    [[ ! -e "${CODEX_TRANSCRIPT_PATH}" &&
        ! -e "${fixture_root}/codex-unstarted-state" ]] ||
        fail 'Codex recorded session evidence for a session that never started.'
    harness_normalize_worker_output \
        review "${codex_unstarted_raw}" gpt-5.6-sol max \
        "${codex_unstarted_normalized}" "${codex_unstarted_reply}" ||
        fail 'Codex reported a session that never started as a normalization failure.'
    [[ -f "${codex_unstarted_normalized}" && ! -s "${codex_unstarted_normalized}" &&
        -f "${codex_unstarted_reply}" && ! -s "${codex_unstarted_reply}" ]] ||
        fail 'Codex produced a narrative or reply for a session that never started.'
    harness_verify_isolation "${codex_unstarted_normalized}" ||
        fail 'Codex reported a session that never started as an isolation failure.'
    rm -f -- "${codex_unstarted_normalized}" "${codex_unstarted_reply}"
    printf '{"type":"thread.started","thread_id":"%s"}\n' "${codex_native_id}" \
        > "${codex_unstarted_raw}"
    if harness_normalize_worker_output \
        review "${codex_unstarted_raw}" gpt-5.6-sol max \
        "${codex_unstarted_normalized}" "${codex_unstarted_reply}" \
        >/dev/null 2>&1; then
        fail 'Codex accepted structured output without a session record.'
    fi
    assert_equal \
        'The Codex review session record did not verify the approved model, effort, context, and no-subagent boundary.' \
        "${RHYOLITE_HARNESS_ERROR_DETAIL}" \
        'Codex structured output without a session record'
    if harness_verify_isolation "${codex_unstarted_normalized}" >/dev/null 2>&1; then
        fail 'Codex accepted a missing session record after structured output.'
    fi
    : > "${codex_unstarted_raw}"
    printf '%s' 'EXACT_CODEX_FIXTURE_REPLY' > "${CODEX_REVIEW_FINAL_MESSAGE}"
    if harness_normalize_worker_output \
        review "${codex_unstarted_raw}" gpt-5.6-sol max \
        "${codex_unstarted_normalized}" "${codex_unstarted_reply}" \
        >/dev/null 2>&1; then
        fail 'Codex accepted a final message without a session record.'
    fi
    assert_equal \
        'The Codex review session record did not verify the approved model, effort, context, and no-subagent boundary.' \
        "${RHYOLITE_HARNESS_ERROR_DETAIL}" \
        'Codex final message without a session record'
) || fail 'Codex unstarted-session regression failed.'

codex_reroute_raw="${fixture_root}/codex-reroute.raw"
cat > "${codex_reroute_raw}" <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"item.completed","item":{"id":"item-1","type":"error","message":"model rerouted: gpt-5.6-sol -> fixture-other (FixtureReason)"}}
{"type":"item.completed","item":{"id":"item-2","type":"agent_message","text":"EXACT_CODEX_FIXTURE_REPLY"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
printf '%s' 'EXACT_CODEX_FIXTURE_REPLY' > "${CODEX_REVIEW_FINAL_MESSAGE}"
if harness_normalize_worker_output \
    review "${codex_reroute_raw}" gpt-5.6-sol max \
    "${fixture_root}/reroute-normalized" "${fixture_root}/reroute-reply" \
    >/dev/null 2>&1; then
    fail 'Codex accepted a model-rerouted reply.'
fi
assert_equal \
    'Codex recorded a model reroute; Rhyolite does not accept substituted output.' \
    "${RHYOLITE_HARNESS_ERROR_DETAIL}" \
    'Codex reroute rejection'
[[ ! -e "${CODEX_REVIEW_FINAL_MESSAGE}" ]] ||
    fail 'Codex left a rejected unsanitized final-message file.'
codex_reroute_outcome="${fixture_root}/codex-reroute-outcome.json"
harness_worker_outcome \
    review "${codex_reroute_raw}" "${codex_runtime}" \
    "${codex_session_id}" gpt-5.6-sol max "${codex_reroute_outcome}" ||
    fail 'Codex reroute outcome failed.'
assert_equal substituted \
    "$(rhyolite_harness_validate_outcome_json "${codex_reroute_outcome}" review)" \
    'Codex substituted outcome'

# Codex CLI 0.163.0 records a provider refusal of the approved model as its
# only reroute reason, HighRiskCyberActivity, or as a turn that the content
# filter or a provider policy stopped. Each is refused, never retried, and
# its fallback output is never accepted.
codex_outcome_case() {
    local name="$1"
    local expected="$2"
    local expected_refusals="$3"
    local expected_fallback="$4"
    local raw="${fixture_root}/codex-${name}.raw"
    local result="${fixture_root}/codex-${name}-outcome.json"

    cat > "${raw}"
    harness_worker_outcome \
        review "${raw}" "${codex_runtime}" \
        "${codex_session_id}" gpt-5.6-sol max "${result}" ||
        fail "Codex ${name} outcome failed."
    assert_equal "${expected}" \
        "$(rhyolite_harness_validate_outcome_json "${result}" review)" \
        "Codex ${name} outcome"
    python3 - "${result}" "${expected_refusals}" "${expected_fallback}" <<'PY' ||
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["ContentRefusals"] == int(sys.argv[2]), data
assert data["FallbackModel"] == sys.argv[3], data
PY
        fail "Codex ${name} outcome evidence changed."
}
codex_outcome_case cyber-reroute refused 1 fixture-other <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item-1","type":"agent_message","text":"FALLBACK_REPLY"}}
{"type":"item.completed","item":{"id":"item-2","type":"error","message":"model rerouted: gpt-5.6-sol -> fixture-other (HighRiskCyberActivity)"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
printf '%s' 'FALLBACK_REPLY' > "${CODEX_REVIEW_FINAL_MESSAGE}"
if harness_normalize_worker_output \
    review "${fixture_root}/codex-cyber-reroute.raw" gpt-5.6-sol max \
    "${fixture_root}/cyber-normalized" "${fixture_root}/cyber-reply" \
    >/dev/null 2>&1; then
    fail 'Codex accepted a reply after a provider refusal reroute.'
fi
assert_contains <(printf '%s\n' "${RHYOLITE_HARNESS_ERROR_DETAIL}") \
    'provider refusal of the approved model' 'Codex refusal rejection'
codex_outcome_case content-filter refused 1 '' <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"turn.started"}
{"type":"error","message":"stream disconnected before completion: Incomplete response returned, reason: content_filter"}
{"type":"turn.failed","error":{"message":"stream disconnected before completion: Incomplete response returned, reason: content_filter"}}
EOF
codex_outcome_case cyber-policy refused 1 '' <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"turn.started"}
{"type":"turn.failed","error":{"message":"This request has been flagged for possible cybersecurity risk."}}
EOF
codex_outcome_case rate-limit transient-failure 0 '' <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"turn.started"}
{"type":"turn.failed","error":{"message":"exceeded retry limit, last status: 429 Too Many Requests"}}
EOF
codex_outcome_case quota failed 0 '' <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"turn.started"}
{"type":"turn.failed","error":{"message":"Quota exceeded. Check your plan and billing details."}}
EOF
# Codex 0.163.0 announces each built-in retry of the same request as a
# top-level "Reconnecting... n/max (reason)" error event within the turn. A
# retried request is not a failed turn, but a retried refusal still refuses.
codex_outcome_case retried-completion completed 0 '' <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"turn.started"}
{"type":"error","message":"Reconnecting... 1/5 (stream disconnected before completion: The server had an error processing your request.)"}
{"type":"error","message":"Reconnecting... 2/5 (We’re currently experiencing high demand, which may cause temporary errors.)"}
{"type":"item.completed","item":{"id":"item-1","type":"agent_message","text":"EXACT_CODEX_FIXTURE_REPLY"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
codex_outcome_case retried-refusal refused 1 '' <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"turn.started"}
{"type":"error","message":"Reconnecting... 1/5 (stream disconnected before completion: Incomplete response returned, reason: content_filter)"}
{"type":"item.completed","item":{"id":"item-1","type":"agent_message","text":"EXACT_CODEX_FIXTURE_REPLY"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
codex_outcome_case retries-exhausted transient-failure 0 '' <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"turn.started"}
{"type":"error","message":"Reconnecting... 5/5 (stream disconnected before completion: The server had an error processing your request.)"}
{"type":"error","message":"stream disconnected before completion: The server had an error processing your request."}
{"type":"turn.failed","error":{"message":"stream disconnected before completion: The server had an error processing your request."}}
EOF
python3 - \
    "${fixture_root}/codex-retried-completion-outcome.json" \
    "${fixture_root}/codex-retried-refusal-outcome.json" \
    "${fixture_root}/codex-retries-exhausted-outcome.json" <<'PY' ||
import json
import sys

completed, refused, exhausted = (
    json.load(open(path, encoding="utf-8")) for path in sys.argv[1:4]
)
assert (completed["TurnRetries"], completed["ModelCallFailures"],
        completed["SessionErrors"]) == (2, 0, []), completed
assert refused["TurnRetries"] == 1 and refused["SessionErrors"], refused
assert (exhausted["TurnRetries"], exhausted["ModelCallFailures"],
        exhausted["Retryable"]) == (1, 1, True), exhausted
PY
    fail 'Codex retry notices were not classified as retries.'
# Codex writes no final-message file for a failed or interrupted turn. Such
# an ordinary turn is the worker's failure, not an adapter one: it normalizes
# to its narrative and an empty reply, so the runner decides from its exit
# status and the outcome what happened. Refusal, forbidden-tool, and
# stale-reply evidence still fail, and a completed turn still needs its exact
# final message.
rm -f -- "${CODEX_REVIEW_FINAL_MESSAGE}"
harness_normalize_worker_output \
    review "${fixture_root}/codex-retries-exhausted.raw" gpt-5.6-sol max \
    "${fixture_root}/failed-turn-normalized" "${fixture_root}/failed-turn-reply" ||
    fail 'Codex treated an ordinary failed turn as an adapter failure.'
[[ -f "${fixture_root}/failed-turn-reply" && ! -s "${fixture_root}/failed-turn-reply" ]] &&
    cmp -s -- "${fixture_root}/failed-turn-normalized" \
        "${fixture_root}/codex-retries-exhausted.raw" ||
    fail 'Codex failed-turn normalization changed the narrative or produced a reply.'
# A stop or timeout ends Codex with SIGTERM, which it does not handle: its
# output simply ends mid-turn, as recorded live by the offline lifecycle
# probe, with no terminal event and no final message. A partial agent
# message from an unfinished turn never becomes the reply.
cat > "${fixture_root}/codex-interrupted.raw" <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"turn.started"}
{"type":"item.started","item":{"id":"item_0","type":"mcp_tool_call","server":"rhyolite_snapshot","tool":"read_snapshot_text","arguments":{"grant":"snapshot","path":"README"},"result":null,"error":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_0","type":"mcp_tool_call","server":"rhyolite_snapshot","tool":"read_snapshot_text","arguments":{"grant":"snapshot","path":"README"},"result":{"content":[],"structured_content":null},"error":null,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"PARTIAL_REPLY"}}
EOF
harness_normalize_worker_output \
    review "${fixture_root}/codex-interrupted.raw" gpt-5.6-sol max \
    "${fixture_root}/interrupted-normalized" "${fixture_root}/interrupted-reply" ||
    fail 'Codex treated a stopped or timed-out turn as an adapter failure.'
[[ -f "${fixture_root}/interrupted-reply" && ! -s "${fixture_root}/interrupted-reply" ]] &&
    cmp -s -- "${fixture_root}/interrupted-normalized" \
        "${fixture_root}/codex-interrupted.raw" ||
    fail 'Codex turned the partial output of an unfinished turn into a reply.'
cat > "${fixture_root}/codex-failed-forbidden.raw" <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"turn.started"}
{"type":"item.completed","item":{"id":"item-1","type":"command_execution","command":"true","status":"completed"}}
{"type":"turn.failed","error":{"message":"stream disconnected before completion: The server had an error processing your request."}}
EOF
codex_failed_turn_rejected() {
    local raw="$1"
    local expected="$2"
    local name="${raw##*/}"

    if harness_normalize_worker_output \
        review "${raw}" gpt-5.6-sol max \
        "${fixture_root}/${name}.normalized" "${fixture_root}/${name}.reply" \
        >/dev/null 2>&1; then
        fail "Codex normalized ${name} as acceptable."
    fi
    assert_contains <(printf '%s\n' "${RHYOLITE_HARNESS_ERROR_DETAIL}") \
        "${expected}" "Codex ${name} rejection"
    [[ ! -e "${fixture_root}/${name}.normalized" &&
        ! -e "${fixture_root}/${name}.reply" &&
        ! -e "${CODEX_REVIEW_FINAL_MESSAGE}" ]] ||
        fail "Codex left normalization output behind for ${name}."
}
codex_failed_turn_rejected "${fixture_root}/codex-content-filter.raw" \
    'provider refusal of the approved model'
codex_failed_turn_rejected "${fixture_root}/codex-failed-forbidden.raw" \
    'Codex recorded a tool outside the approved phase inventory.'
printf '%s' 'STALE_REPLY' > "${CODEX_REVIEW_FINAL_MESSAGE}"
codex_failed_turn_rejected "${fixture_root}/codex-retries-exhausted.raw" \
    'Codex recorded a failed worker turn.'
codex_failed_turn_rejected "${codex_raw}" \
    'Codex did not write its exact final-message artifact.'
printf '%s' 'EXACT_CODEX_FIXTURE_REPLY' > "${CODEX_REVIEW_FINAL_MESSAGE}"
harness_normalize_worker_output \
    review "${fixture_root}/codex-retried-completion.raw" gpt-5.6-sol max \
    "${fixture_root}/retried-normalized" "${fixture_root}/retried-reply" ||
    fail 'Codex rejected a reply that completed after a retried request.'
[[ "$(cat "${fixture_root}/retried-reply")" == EXACT_CODEX_FIXTURE_REPLY ]] ||
    fail 'Codex changed the final reply of a retried request.'
printf '%s' 'EXACT_CODEX_FIXTURE_REPLY' > "${CODEX_REVIEW_FINAL_MESSAGE}"
if harness_normalize_worker_output \
    review "${fixture_root}/codex-retried-refusal.raw" gpt-5.6-sol max \
    "${fixture_root}/retried-refusal-normalized" "${fixture_root}/retried-refusal-reply" \
    >/dev/null 2>&1; then
    fail 'Codex accepted output after it retried a provider refusal.'
fi
assert_contains <(printf '%s\n' "${RHYOLITE_HARNESS_ERROR_DETAIL}") \
    'provider refusal of the approved model' 'Codex retried-refusal rejection'
codex_retry_cursor="${fixture_root}/codex-retry-cursor"
harness_detect_worker_violation \
    review "${fixture_root}/codex-retried-completion.raw" gpt-5.6-sol max \
    "${codex_retry_cursor}" ||
    fail 'Codex live enforcement stopped a worker for an ordinary retry.'
rm -f -- "${codex_retry_cursor}"
set +e
harness_detect_worker_violation \
    review "${fixture_root}/codex-retried-refusal.raw" gpt-5.6-sol max \
    "${codex_retry_cursor}"
codex_retry_status=$?
set -e
((codex_retry_status == RHYOLITE_HARNESS_WORKER_REFUSAL_STATUS)) ||
    fail 'Codex live enforcement did not stop a worker whose refusal Codex retried.'
codex_refusal_cursor="${fixture_root}/codex-refusal-cursor"
set +e
harness_detect_worker_violation \
    review "${fixture_root}/codex-cyber-reroute.raw" gpt-5.6-sol max \
    "${codex_refusal_cursor}"
codex_refusal_status=$?
set -e
((codex_refusal_status == RHYOLITE_HARNESS_WORKER_REFUSAL_STATUS)) ||
    fail 'Codex live enforcement did not report a provider refusal.'
assert_contains <(printf '%s\n' "${RHYOLITE_HARNESS_ERROR_DETAIL}") \
    'declined the approved model gpt-5.6-sol' 'Codex live refusal detail'
rm -f -- "${codex_refusal_cursor}"
set +e
harness_detect_worker_violation \
    review "${fixture_root}/codex-content-filter.raw" gpt-5.6-sol max \
    "${codex_refusal_cursor}"
codex_refusal_status=$?
set -e
((codex_refusal_status == RHYOLITE_HARNESS_WORKER_REFUSAL_STATUS)) ||
    fail 'Codex live enforcement did not report a content-filter refusal.'

codex_collab_raw="${fixture_root}/codex-collab.raw"
printf '%s\n' \
    '{"type":"item.completed","item":{"id":"item-1","type":"collab_tool_call","tool":"spawn_agent","status":"completed"}}' \
    > "${codex_collab_raw}"
codex_cursor="${fixture_root}/codex-cursor"
set +e
harness_detect_worker_violation \
    review "${codex_collab_raw}" gpt-5.6-sol max "${codex_cursor}"
codex_violation_status=$?
set -e
((codex_violation_status == RHYOLITE_HARNESS_WORKER_VIOLATION_STATUS)) ||
    fail 'Codex live enforcement did not reject a collab tool call.'
assert_contains <(printf '%s\n' "${RHYOLITE_HARNESS_ERROR_DETAIL}") \
    'collab/subagent' 'Codex collab rejection detail'

# A recorded model, effort, or subagent outside the approved plan surfaces as
# the runner's approved-model enforcement stage for every harness, so each
# Codex detail must use the vocabulary of the runner's own classifier.
(
    eval "$(sed -n '/^errors_report_approved_plan_violation() {/,/^}/p' "${RUNNER}")"
    declare -F errors_report_approved_plan_violation >/dev/null ||
        fail 'The runner approved-plan violation classifier could not be read.'
    codex_violation_detail_file="${fixture_root}/codex-violation-detail.txt"
    codex_expect_enforcement_detail() {
        printf '%s\n' "${RHYOLITE_HARNESS_ERROR_DETAIL}" \
            > "${codex_violation_detail_file}"
        errors_report_approved_plan_violation "${codex_violation_detail_file}" ||
            fail "Codex $1 detail would not reach the approved-model enforcement stage: ${RHYOLITE_HARNESS_ERROR_DETAIL}"
    }
    codex_expect_live_violation() {
        local raw="${fixture_root}/codex-live-$1.raw"
        local status=0

        printf '%s\n' "$2" > "${raw}"
        rm -f -- "${fixture_root}/codex-live-$1.cursor"
        harness_detect_worker_violation \
            review "${raw}" gpt-5.6-sol max \
            "${fixture_root}/codex-live-$1.cursor" || status=$?
        ((status == RHYOLITE_HARNESS_WORKER_VIOLATION_STATUS)) ||
            fail "Codex live enforcement did not reject $1."
        codex_expect_enforcement_detail "live $1"
    }
    codex_expect_live_violation reroute \
        '{"type":"item.completed","item":{"id":"item-1","type":"error","message":"model rerouted: gpt-5.6-sol -> fixture-other (FixtureReason)"}}'
    codex_expect_live_violation subagent \
        '{"type":"item.completed","item":{"id":"item-1","type":"collab_tool_call","tool":"spawn_agent","status":"completed"}}'
    CODEX_TRANSCRIPT_STATUS=verified
    codex_collab_normalized_raw="${fixture_root}/codex-collab-normalized.raw"
    printf '%s\n' \
        "{\"type\":\"thread.started\",\"thread_id\":\"${codex_native_id}\"}" \
        '{"type":"item.completed","item":{"id":"item-1","type":"collab_tool_call","tool":"spawn_agent","status":"completed"}}' \
        '{"type":"item.completed","item":{"id":"item-2","type":"agent_message","text":"EXACT_CODEX_FIXTURE_REPLY"}}' \
        '{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}' \
        > "${codex_collab_normalized_raw}"
    printf '%s' 'EXACT_CODEX_FIXTURE_REPLY' > "${CODEX_REVIEW_FINAL_MESSAGE}"
    codex_failed_turn_rejected "${codex_collab_normalized_raw}" 'collab/subagent'
    codex_expect_enforcement_detail 'normalized subagent'
    for CODEX_TRANSCRIPT_STATUS in substituted effort-changed subagent; do
        codex_review_record_error 'fixture fallback detail' || true
        codex_expect_enforcement_detail "${CODEX_TRANSCRIPT_STATUS} session record"
    done
    CODEX_TRANSCRIPT_STATUS=unreadable
    codex_review_record_error 'fixture fallback detail' || true
    assert_equal 'fixture fallback detail' "${RHYOLITE_HARNESS_ERROR_DETAIL}" \
        'Codex unverified session record detail'
) || fail 'Codex approved-model enforcement vocabulary regression failed.'

harness_allow_all_detected &&
    fail 'Codex inherited an allow-all signal.'

codex_controller_plugin="${fixture_root}/codex-controller-plugin"
codex_controller_work="${fixture_root}/codex-controller-work"
codex_controller_home="${fixture_root}/codex-controller-home"
codex_controller_calls="${fixture_root}/codex-controller-codex-calls"
mkdir -p -- \
    "${codex_controller_plugin}/scripts" \
    "${codex_controller_plugin}/skills/readonly-repository-review/scripts" \
    "${codex_controller_work}" \
    "${codex_controller_home}"
cp -- "${CODEX_GUIDED_REVIEW}" "${codex_controller_plugin}/scripts/"
cat > "${codex_controller_plugin}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh" <<'CODEX_RUNNER_FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
call_count="$(
    find "${RHYOLITE_CODEX_CONTROLLER_CAPTURE:?}" -type f -name 'call-*.nul' |
        wc -l
)"
call_count="${call_count//[[:space:]]/}"
printf '%s\0' "$@" > "${RHYOLITE_CODEX_CONTROLLER_CAPTURE}/call-$((call_count + 1)).nul"
if [[ " $* " == *' --request-stop '* ]]; then
    touch "${RHYOLITE_CODEX_CONTROLLER_CAPTURE}/stop-called"
    if [[ -f "${RHYOLITE_CODEX_CONTROLLER_CAPTURE}/runner.pid" ]]; then
        runner_pid="$(< "${RHYOLITE_CODEX_CONTROLLER_CAPTURE}/runner.pid")"
        [[ "${runner_pid}" =~ ^[1-9][0-9]*$ ]]
        kill -TERM "${runner_pid}" 2>/dev/null || true
        for _ in {1..50}; do
            kill -0 "${runner_pid}" 2>/dev/null || break
            sleep 0.02
        done
    fi
    exit 0
fi
if [[ " $* " == *' --plan-only '* ]]; then
    printf '%s\n' \
        '{"ApprovalHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","Harness":"codex","Model":"gpt-5.6-sol","ReasoningEffort":"max","ContextTier":"long_context","Scope":{"Number":1,"Name":"1 - Core repository review"}}'
    exit 0
fi
[[ " $* " == *' --expected-plan-hash aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa '* ]]
if [[ "${RHYOLITE_CODEX_CONTROLLER_MODE:-}" == mismatch &&
    ! -e "${RHYOLITE_CODEX_CONTROLLER_CAPTURE}/mismatch-reported" ]]; then
    touch "${RHYOLITE_CODEX_CONTROLLER_CAPTURE}/mismatch-reported"
    printf '%s\n' 'Review execution did not start: the approved plan changed; regenerate and reconfirm.' >&2
    exit 2
fi
if [[ "${RHYOLITE_CODEX_CONTROLLER_MODE:-}" == stop ]]; then
    run_folder="${RHYOLITE_CODEX_CONTROLLER_CAPTURE}/live-run"
    mkdir -p -- "${run_folder}"
    printf '%s\n' \
        '{"RunId":"fixture-run","Status":"Running","Repositories":[],"Paths":{"WritableOutput":"'"${run_folder}"'"}}' \
        > "${run_folder}/state.json"
    printf 'RHYOLITE PROGRESS | run | started | 1 repositories; output %s\n' \
        "${run_folder}"
    printf '%s\n' "$$" > "${RHYOLITE_CODEX_CONTROLLER_CAPTURE}/runner.pid"
    trap 'exit 130' TERM INT HUP
    while true; do sleep 1; done
fi
printf '%s\n' '/tmp/rhyolite-controller-run'
CODEX_RUNNER_FIXTURE
chmod 700 -- \
    "${codex_controller_plugin}/scripts/run-codex-guided-review.sh" \
    "${codex_controller_plugin}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh"

# Drive one command at a pseudo-terminal: its stdin and stderr are the
# terminal unless --stdin or --stderr names a file for that stream instead,
# its stdout goes to the first file, and everything the terminal showed to
# the second. Each "<text>\t<answer>" line of the steps file waits until
# <text> appears on the terminal after the previous step, or for
# "stdout:<text>" in the stdout file, and then types <answer> and Enter;
# <EOF> types Ctrl-D instead.
#   driver <stdout> <terminal> <steps> [--stdin FILE] [--stderr FILE] -- command...
codex_terminal_driver="${fixture_root}/codex-terminal-driver.py"
cat > "${codex_terminal_driver}" <<'PY'
import errno
import os
import pathlib
import pty
import select
import signal
import subprocess
import sys
import time

arguments = sys.argv[1:sys.argv.index("--")]
stdout_path, terminal_path, steps_path = arguments[:3]
options = dict(zip(arguments[3::2], arguments[4::2]))
assert set(options) <= {"--stdin", "--stderr"}, options
command = sys.argv[sys.argv.index("--") + 1:]
steps = [
    tuple(line.split("\t", 1)) if "\t" in line else (line, "")
    for line in pathlib.Path(steps_path).read_text(encoding="utf-8").splitlines()
    if line
]
master, slave = pty.openpty()
stdin = open(options["--stdin"], "rb") if "--stdin" in options else slave
stderr = open(options["--stderr"], "wb") if "--stderr" in options else slave
with open(stdout_path, "wb") as stdout:
    process = subprocess.Popen(
        command, stdin=stdin, stdout=stdout, stderr=stderr, start_new_session=True,
    )
for stream in (stdin, stderr):
    if stream is not slave:
        stream.close()
os.close(slave)
terminal = bytearray()
position = 0


def pump(timeout):
    ready, _, _ = select.select([master], [], [], timeout)
    if not ready:
        return False
    try:
        chunk = os.read(master, 65536)
    except OSError as error:
        if error.errno != errno.EIO:
            raise
        return False
    terminal.extend(chunk)
    return bool(chunk)


def finish(status, message=""):
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
    while pump(0.1):
        pass
    os.close(master)
    pathlib.Path(terminal_path).write_bytes(bytes(terminal))
    if message:
        print(f"terminal driver: {message}", file=sys.stderr)
    sys.exit(status)


def seen(text):
    global position
    if text.startswith("stdout:"):
        return text[7:].encode() in pathlib.Path(stdout_path).read_bytes()
    index = terminal.find(text.encode(), position)
    if index < 0:
        return False
    position = index + len(text.encode())
    return True


for text, answer in steps:
    deadline = time.monotonic() + 30
    while not seen(text):
        if not pump(0.1) and process.poll() is not None and not seen(text):
            finish(98, f"the command ended before {text!r}")
        if time.monotonic() > deadline:
            finish(98, f"timed out waiting for {text!r}")
    time.sleep(0.05)
    os.write(master, b"\x04" if answer == "<EOF>" else answer.encode() + b"\n")
try:
    process.wait(timeout=60)
except subprocess.TimeoutExpired:
    finish(98, "the command did not finish")
finish(process.returncode)
PY

# Print driver steps from prompt and answer pairs.
codex_steps() {
    printf '%s\t%s\n' "$@"
}

# Run the controller for one named case at a pseudo-terminal, answering its
# prompts as the steps say. The case's session and runner-call folders are
# codex-controller-<name>-session and codex-controller-<name>-capture under
# the fixture root; its terminal output is codex-controller-<name>.terminal.
#   codex_controller_case <name> <steps> [controller option...]
codex_controller_case() {
    local name="$1"
    local steps="$2"
    shift 2
    local session="${fixture_root}/codex-controller-${name}-session"
    local capture="${fixture_root}/codex-controller-${name}-capture"

    mkdir -p -- "${session}" "${capture}"
    printf '%s\n' "${steps}" > "${fixture_root}/codex-controller-${name}.steps"
    RHYOLITE_CODEX_CONTROLLER_CAPTURE="${capture}" \
    RHYOLITE_CODEX_FAKE_CALLS="${codex_controller_calls}" \
    HOME="${codex_controller_home}" \
    python3 -I "${codex_terminal_driver}" \
        "${fixture_root}/codex-controller-${name}.stdout" \
        "${fixture_root}/codex-controller-${name}.terminal" \
        "${fixture_root}/codex-controller-${name}.steps" \
        -- \
        "${codex_controller_plugin}/scripts/run-codex-guided-review.sh" \
        --plugin-root "${codex_controller_plugin}" \
        --working-directory "${codex_controller_work}" \
        --session-directory "${session}" \
        --model gpt-5.6-sol \
        --reasoning-effort max \
        --context long_context \
        --repo https://github.com/octocat/Hello-World \
        "$@" || {
            cat -- "${fixture_root}/codex-controller-${name}.terminal" >&2 || true
            return 1
        }
}

# Compare one case's runner calls and session records with expectations.
#   codex_controller_expect <name> <python expectations>
codex_controller_expect() {
    python3 -I - \
        "${fixture_root}/codex-controller-$1-capture" \
        "${fixture_root}/codex-controller-$1-session" \
        "${codex_controller_work}" \
        "${codex_controller_home}" \
        "$2" <<'PY'
import json
import pathlib
import stat
import sys

capture, session = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
work, home, expectations = sys.argv[3], sys.argv[4], sys.argv[5]
calls = [
    [item.decode() for item in path.read_bytes().split(b"\0") if item]
    for path in sorted(capture.glob("call-*.nul"), key=lambda p: int(p.stem[5:]))
]


def records(kind):
    paths = sorted(session.glob(f"codex-{kind}-*.json"), key=lambda p: int(p.stem.split("-")[-1]))
    for path in paths:
        assert stat.S_IMODE(path.stat().st_mode) == 0o600, path
    return [json.loads(path.read_text(encoding="utf-8")) for path in paths]


def value(call, option):
    return call[call.index(option) + 1] if option in call else None


current_output = f"{work}/rhyolite-output/repo-review"
home_output = f"{home}/rhyolite-output/repo-review"
setups, approvals = records("setup"), records("approval")
exec(expectations)
PY
}

codex_default_steps="$(codex_steps \
    'Select output [1]: ' '' 'Select scope [1]: ' '' 'Select action: ' 1)"
codex_controller_case defaults "${codex_default_steps}" ||
    fail 'Codex guided review controller failed with default answers.'
codex_controller_expect defaults '
assert len(calls) == 2
plan, run = calls
assert "--plan-only" in plan and "--expected-plan-hash" not in plan
assert "--plan-only" not in run and value(run, "--expected-plan-hash") == "a" * 64
assert value(plan, "--output-root") == current_output
assert "--fleet-mode" not in plan and "--commit" not in plan
for expected in (
    "--harness", "codex", "--security-scans", "1",
    "--model", "gpt-5.6-sol", "--reasoning-effort", "max",
    "--context", "long_context", "--scope", "1",
    "--remember-preferences", "--non-interactive", "--no-open-html",
    "--repo", "https://github.com/octocat/Hello-World",
):
    assert expected in plan and expected in run, expected
assert "--research-cookies" not in plan and "--provenance-lookback-months" not in plan
assert setups == [{"Action": "continue", "OutputRoot": current_output,
                   "ProvenanceLookbackMonths": None, "ResearchCookies": None, "Scope": 1}]
assert approvals == [{"Action": "run", "ApprovalHash": "a" * 64}]
'
assert_contains "${fixture_root}/codex-controller-defaults.stdout" \
    'EFFECTIVE REVIEW PLAN' 'Codex controller plan display'
assert_contains "${fixture_root}/codex-controller-defaults.stdout" \
    '  Scope: 1 - Core repository review' 'Codex controller plan summary scope'
assert_contains "${fixture_root}/codex-controller-defaults.stdout" \
    '/tmp/rhyolite-controller-run' 'Codex controller execution output'
for codex_prompt_line in \
    'Output location' \
    "  1. Current directory - ${codex_controller_work}/rhyolite-output/repo-review" \
    "  2. Home directory - ${codex_controller_home}/rhyolite-output/repo-review" \
    '  3. Enter another absolute path' \
    'Select output [1]: ' \
    'Scope 1 covers source, history, architecture, quality, and the full dedicated security pass' \
    '  1. Scope 1 - Core repository review (Recommended) - 15-45 minutes' \
    '  3. Scope 3 - Full + generated-code provenance review - 60-120+ minutes' \
    'Select scope [1]: ' \
    '  1. Run review' \
    '  2. Edit setup' \
    '  3. Explain scope' \
    'Type stop to leave without starting a review.' \
    'Select action: '; do
    assert_contains "${fixture_root}/codex-controller-defaults.terminal" \
        "${codex_prompt_line}" 'Codex controller terminal question'
done
for codex_absent_line in 'Provenance lookback' 'Research cookies' 'RHYOLITE ERROR'; do
    assert_not_contains "${fixture_root}/codex-controller-defaults.terminal" \
        "${codex_absent_line}" 'Codex controller scope-1 setup'
done

# --auto-defaults skips only the setup questions: the plan still needs an
# explicit approval.
codex_auto_commit="$(printf 'b%.0s' {1..40})"
codex_controller_case auto "$(codex_steps 'Select action: ' 1)" \
    --commit "${codex_auto_commit}" --auto-defaults ||
    fail 'Codex guided controller failed with --auto-defaults.'
codex_controller_expect auto '
assert len(calls) == 2 and setups == []
assert approvals == [{"Action": "run", "ApprovalHash": "a" * 64}]
for call in calls:
    assert value(call, "--commit") == "b" * 40
    assert value(call, "--scope") == "1"
    assert value(call, "--output-root") == home_output
'
assert_not_contains "${fixture_root}/codex-controller-auto.terminal" \
    'Output location' 'Codex --auto-defaults setup questions'
if "${codex_controller_plugin}/scripts/run-codex-guided-review.sh" \
    --plugin-root "${codex_controller_plugin}" \
    --working-directory "${codex_controller_work}" \
    --session-directory "${fixture_root}/codex-controller-defaults-session" \
    --model gpt-5.6-sol \
    --reasoning-effort max \
    --context long_context \
    --repo https://github.com/octocat/Hello-World \
    --repo https://github.com/octocat/Spoon-Knife \
    --commit "${codex_auto_commit}" \
    < /dev/null > /dev/null 2> "${fixture_root}/codex-controller-several-commit.stderr"; then
    fail 'Codex guided controller pinned one commit for several repositories.'
fi
assert_contains "${fixture_root}/codex-controller-several-commit.stderr" \
    'Codex guided review controller failed: validation' \
    'Codex controller several-repository commit validation'

# The questions need stdin and stderr on a terminal. With either one
# redirected, the controller asks nothing and starts nothing, so piped answers
# never approve a plan even when the questions would show on a terminal.
printf '\n\n1\n' > "${fixture_root}/codex-controller-piped.stdin"
codex_controller_no_terminal_case() {
    local name="$1"
    shift
    local capture="${fixture_root}/codex-controller-${name}-capture"
    local combined="${fixture_root}/codex-controller-${name}.combined"

    mkdir -p -- "${capture}" "${fixture_root}/codex-controller-${name}-session"
    : > "${fixture_root}/codex-controller-${name}.steps"
    if RHYOLITE_CODEX_CONTROLLER_CAPTURE="${capture}" \
        RHYOLITE_CODEX_FAKE_CALLS="${codex_controller_calls}" \
        HOME="${codex_controller_home}" \
        python3 -I "${codex_terminal_driver}" \
            "${fixture_root}/codex-controller-${name}.stdout" \
            "${fixture_root}/codex-controller-${name}.terminal" \
            "${fixture_root}/codex-controller-${name}.steps" \
            "$@" \
            -- \
            "${codex_controller_plugin}/scripts/run-codex-guided-review.sh" \
            --plugin-root "${codex_controller_plugin}" \
            --working-directory "${codex_controller_work}" \
            --session-directory "${fixture_root}/codex-controller-${name}-session" \
            --model gpt-5.6-sol \
            --reasoning-effort max \
            --context long_context \
            --repo https://github.com/octocat/Hello-World; then
        fail "Codex guided controller ran its questions with ${name}."
    fi
    cat -- "${fixture_root}/codex-controller-${name}.terminal" \
        "${fixture_root}/codex-controller-${name}".stderr \
        > "${combined}" 2>/dev/null || true
    assert_contains "${combined}" \
        'The Codex setup and approval questions need an interactive terminal on standard input and standard error.' \
        "Codex controller terminal requirement with ${name}"
    assert_not_contains "${combined}" 'Output location' \
        "Codex controller question with ${name}"
    [[ -z "$(find "${capture}" -name 'call-*.nul' -print -quit)" ]] ||
        fail "Codex guided controller planned a review with ${name}."
}
codex_controller_no_terminal_case piped-stdin \
    --stdin "${fixture_root}/codex-controller-piped.stdin"
codex_controller_no_terminal_case redirected-stderr \
    --stderr "${fixture_root}/codex-controller-redirected-stderr.stderr"

# A plan mismatch keeps the setup answers: the controller regenerates the
# plan and asks only for approval again.
RHYOLITE_CODEX_CONTROLLER_MODE=mismatch \
    codex_controller_case mismatch "$(codex_steps \
        'Select output [1]: ' '' 'Select scope [1]: ' '' \
        'Select action: ' 1 'Select action: ' 1)" ||
    fail 'Codex guided controller did not recover from a plan mismatch.'
assert_contains "${fixture_root}/codex-controller-mismatch.terminal" \
    'regenerating it with the preserved setup' 'Codex plan mismatch notice'
codex_controller_expect mismatch '
assert len(calls) == 4 and len(setups) == 1
assert [item["Action"] for item in approvals] == ["run", "run"]
assert [value(call, "--output-root") for call in calls] == [current_output] * 4
'
[[ "$(grep -c '^Output location' "${fixture_root}/codex-controller-mismatch.terminal")" == 1 ]] ||
    fail 'Codex plan mismatch asked the setup questions again.'

# Every setup path: another output path after invalid answers, scope 2 with
# its cookie question, a rejected empty approval, Change scope to scope 3
# with a custom lookback after an out-of-range one, Explain scope, and Edit
# setup back to the home output and scope 1, whose defaults are the current
# answers.
codex_custom_output="${fixture_root}/codex-custom-output"
codex_edit_steps="$(codex_steps \
    'Select output [1]: ' 3 \
    'Absolute output path: ' relative/path \
    'Select output [1]: ' 9 \
    'Select output [1]: ' 3 \
    'Absolute output path: ' "${codex_custom_output}" \
    'Select scope [1]: ' 2 \
    'Select cookies [1]: ' '' \
    'Select action: ' '' \
    'Select action: ' 'Change scope' \
    'Select scope [2]: ' 3 \
    'Select lookback [1]: ' 5 \
    'Months (1-60): ' 61 \
    'Select lookback [1]: ' 5 \
    'Months (1-60): ' 9 \
    'Select cookies [1]: ' 2 \
    'Select action: ' 'Explain scope' \
    'Select action: ' 'Edit setup' \
    'Select output [1]: ' 3 \
    'Select scope [3]: ' 1 \
    'Select action: ' 'Run review')"
codex_controller_case edits "${codex_edit_steps}" ||
    fail 'Codex guided controller failed through edit, change-scope, and explain answers.'
codex_controller_expect edits '
custom = sys.argv[3].rsplit("/", 1)[0] + "/codex-custom-output"
assert len(calls) == 4
plans, run = calls[:3], calls[3]
assert all("--plan-only" in call for call in plans)
assert [value(call, "--output-root") for call in calls] == [custom, custom, home_output, home_output]
assert [value(call, "--scope") for call in calls] == ["2", "3", "1", "1"]
assert [value(call, "--research-cookies") for call in calls] == ["off", "ephemeral", None, None]
assert [value(call, "--provenance-lookback-months") for call in calls] == [None, "9", None, None]
assert [call for call in run if call != "--expected-plan-hash" and call != "a" * 64] == \
    [call for call in plans[2] if call != "--plan-only"]
assert setups == [
    {"Action": "continue", "OutputRoot": custom, "ProvenanceLookbackMonths": None,
     "ResearchCookies": "off", "Scope": 2},
    {"Action": "continue", "OutputRoot": custom, "ProvenanceLookbackMonths": 9,
     "ResearchCookies": "ephemeral", "Scope": 3},
    {"Action": "continue", "OutputRoot": home_output, "ProvenanceLookbackMonths": None,
     "ResearchCookies": None, "Scope": 1},
]
assert [item["Action"] for item in approvals] == ["change-scope", "explain", "edit", "run"]
'
for codex_prompt_line in \
    'Enter an absolute path without control characters.' \
    'Enter one of the displayed choice numbers.' \
    'Raw Set-Cookie values from research stay only in a private per-repository ledger' \
    '  1. Do not replay research cookies (Recommended)' \
    'Enter 1, 2, or 3, or type stop.' \
    'Select scope [2]: ' \
    '  1. 6 months (Recommended)' \
    '  5. Enter another number of months from 1 through 60' \
    'Enter a whole number from 1 through 60.' \
    "  1. Keep current output - ${codex_custom_output}" \
    "  3. Home directory - ${codex_controller_home}/rhyolite-output/repo-review" \
    'Select scope [3]: '; do
    assert_contains "${fixture_root}/codex-controller-edits.terminal" \
        "${codex_prompt_line}" 'Codex controller edit path'
done
[[ "$(grep -c '^Scope 2 adds public prior-art/community research' "${fixture_root}/codex-controller-edits.terminal")" == 4 ]] ||
    fail 'Codex controller did not explain the scopes before each scope question and on request.'

# End of input, or exact stop or cancel, at any question leaves without a
# review; only an answered setup reaches plan generation.
codex_controller_stop_case() {
    local name="$1"
    local calls="$2"
    shift 2

    codex_controller_case "${name}" "$(codex_steps "$@")" ||
        fail "Codex guided controller failed after ${name}."
    assert_contains "${fixture_root}/codex-controller-${name}.terminal" \
        'Rhyolite stopped without starting a review.' \
        "Codex controller ${name} stop"
    codex_controller_expect "${name}" "
assert len(calls) == ${calls}, calls
assert approvals == []
"
}
codex_controller_stop_case eof-setup 0 'Select output [1]: ' '<EOF>'
codex_controller_stop_case cancel-scope 0 \
    'Select output [1]: ' '' 'Select scope [1]: ' cancel
codex_controller_stop_case stop-approval 1 \
    'Select output [1]: ' '' 'Select scope [1]: ' '' 'Select action: ' stop
codex_controller_stop_case eof-approval 1 \
    'Select output [1]: ' '' 'Select scope [1]: ' '' 'Select action: ' '<EOF>'

codex_controller_stop_capture="${fixture_root}/codex-controller-stop-capture"
RHYOLITE_CODEX_CONTROLLER_MODE=stop \
    codex_controller_case stop "$(codex_steps \
        'Select output [1]: ' '' 'Select scope [1]: ' '' 'Select action: ' 1 \
        'stdout:RHYOLITE PROGRESS | run | started' '/rhyolite:status' \
        'stdout:RHYOLITE STATUS' stop)" ||
    fail 'Codex guided controller did not treat exact stop as a clean terminal state.'
[[ -f "${codex_controller_stop_capture}/stop-called" ]] ||
    fail 'Codex guided controller did not invoke the trusted request-stop path.'
assert_contains "${fixture_root}/codex-controller-stop.stdout" \
    'RHYOLITE STATUS' 'Codex controller status command'
# The status reports the live stage from the runner's progress output, since
# the runner writes its run state only when it finishes.
for codex_status_line in \
    'Command: repo-review' \
    'Stage: run | started | 1 repositories; output ' \
    'Elapsed: 0m ' \
    'Harness: codex' \
    'Source: https://github.com/octocat/Hello-World' \
    'Model: gpt-5.6-sol (max, long_context)' \
    'Scope: 1' \
    'Review run: fixture-run (Running)'; do
    assert_contains "${fixture_root}/codex-controller-stop.stdout" \
        "${codex_status_line}" 'Codex controller status field'
done
assert_contains "${fixture_root}/codex-controller-stop.terminal" \
    'Rhyolite review stopped.' 'Codex controller stopped state'

# At a terminal, answers typed before the plan appeared never approve it: the
# controller discards them, and only an answer given at the approval
# question starts the review.
python3 -I - "${codex_controller_plugin}" "${fixture_root}" \
    "${codex_controller_calls}" <<'PY'
import errno
import os
import pathlib
import pty
import select
import signal
import subprocess
import sys
import time

plugin, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
session = root / "codex-controller-terminal-session"
capture = root / "codex-controller-terminal-capture"
for path in (session, capture):
    path.mkdir(mode=0o700)
environment = dict(
    os.environ,
    RHYOLITE_CODEX_CONTROLLER_CAPTURE=str(capture),
    RHYOLITE_CODEX_FAKE_CALLS=sys.argv[3],
    HOME=str(root / "codex-controller-home"),
)
master, slave = pty.openpty()
# Enter for the output and scope defaults, then an early approval.
os.write(master, b"\n\n1\n")
process = subprocess.Popen(
    [
        str(plugin / "scripts/run-codex-guided-review.sh"),
        "--plugin-root", str(plugin),
        "--working-directory", str(root / "codex-controller-work"),
        "--session-directory", str(session),
        "--model", "gpt-5.6-sol",
        "--reasoning-effort", "max",
        "--context", "long_context",
        "--repo", "https://github.com/octocat/Hello-World",
    ],
    env=environment,
    stdin=slave,
    stdout=subprocess.PIPE,
    stderr=slave,
    start_new_session=True,
)
os.close(slave)
terminal = bytearray()


def read_terminal(timeout):
    ready, _, _ = select.select([master], [], [], timeout)
    if not ready:
        return False
    try:
        chunk = os.read(master, 65536)
    except OSError as error:
        if error.errno != errno.EIO:
            raise
        return False
    terminal.extend(chunk)
    return bool(chunk)


try:
    deadline = time.monotonic() + 30
    while b"Select action: " not in terminal and time.monotonic() < deadline:
        read_terminal(0.2)
    assert b"Select action: " in terminal, terminal.decode("utf-8", "replace")
    time.sleep(0.5)
    while read_terminal(0.1):
        pass
    assert len(list(capture.glob("call-*.nul"))) == 1, "an early answer approved the plan"
    os.write(master, b"1\n")
    stdout, _ = process.communicate(timeout=30)
    while read_terminal(0.2):
        pass
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=5)
    os.close(master)
text = terminal.decode("utf-8", errors="replace")
assert process.returncode == 0, text
assert text.count("Select action: ") == 1, text
assert "Enter 1, 2, or 3, or type stop." not in text, text
assert "Review started. Type exact stop or cancel to interrupt" in text, text
assert b"/tmp/rhyolite-controller-run" in stdout
assert len(list(capture.glob("call-*.nul"))) == 2
PY
[[ ! -e "${codex_controller_calls}" ]] ||
    fail 'The Codex guided review controller started a Codex session.'

codex_launcher_plugin="${fixture_root}/codex-launcher-plugin"
codex_launcher_caller="${fixture_root}/codex-launcher-caller"
codex_launcher_state="${fixture_root}/codex-launcher-state"
codex_launcher_capture="${fixture_root}/codex-launcher.capture"
codex_launcher_calls="${fixture_root}/codex-launcher-codex-calls"
cp -a -- "${PLUGIN_ROOT}" "${codex_launcher_plugin}"
mkdir -p -- "${codex_launcher_caller}" "${codex_launcher_state}"
cat >> "${codex_launcher_plugin}/lib/harness/common.sh" <<'CODEX_LAUNCHER_TEST_REGISTRY'

rhyolite_harness_list_registered() {
    printf '%s\n' copilot claude codex
}

rhyolite_harness_registry_lookup() {
    local output_variable="$1"
    local plugin_root="$2"
    local selected_harness="$3"
    case "${selected_harness}" in
        codex)
            printf -v "${output_variable}" '%s' "${plugin_root}/lib/harness/codex.sh"
            ;;
        *)
            RHYOLITE_HARNESS_ERROR_DETAIL='Fixture registry supports only Codex for this case.'
            return 1
            ;;
    esac
}
CODEX_LAUNCHER_TEST_REGISTRY
cat > "${codex_launcher_plugin}/scripts/run-codex-guided-review.sh" <<'CODEX_LAUNCHER_CONTROLLER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'FIXTURE CODEX CONTROLLER STARTED' >&2
printf '%s\0' "$@" > "${RHYOLITE_CODEX_LAUNCHER_CAPTURE:?}"
CODEX_LAUNCHER_CONTROLLER
chmod 700 -- "${codex_launcher_plugin}/scripts/run-codex-guided-review.sh"
# The Codex questions need a terminal on stdin and stderr. With stdout
# captured, the launcher asks none of its own questions.
: > "${fixture_root}/codex-launcher.steps"
(
    cd -- "${codex_launcher_caller}"
    env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
        HOME="${fixture_root}/codex-launcher-home" \
        CODEX_HOME="${codex_home}" \
        FIXTURE_CODEX_KEY='fixture-secret-value' \
        XDG_STATE_HOME="${codex_launcher_state}" \
        RHYOLITE_CODEX_LAUNCHER_CAPTURE="${codex_launcher_capture}" \
        RHYOLITE_CODEX_FAKE_CALLS="${codex_launcher_calls}" \
        PATH="${codex_fake_bin}:/usr/bin:/bin" \
        python3 -I "${codex_terminal_driver}" \
        "${fixture_root}/codex-launcher.stdout" \
        "${fixture_root}/codex-launcher.terminal" \
        "${fixture_root}/codex-launcher.steps" \
        -- \
        "${codex_launcher_plugin}/bin/rhyolite" \
        --harness codex \
        --repo https://github.com/octocat/Hello-World \
        --fleet-mode standard \
        --model gpt-5.6-sol \
        --reasoning-effort max \
        --context long_context
) || {
    cat -- "${fixture_root}/codex-launcher.terminal" >&2 || true
    fail 'Staged Codex launcher branch failed.'
}
[[ -f "${codex_launcher_capture}" ]] ||
    fail 'Staged Codex launcher did not invoke its Bash controller.'
python3 -I - \
    "${codex_launcher_capture}" \
    "${codex_launcher_plugin}" \
    "${codex_launcher_caller}" \
    "${codex_launcher_state}" <<'PY'
import pathlib
import sys

capture, plugin, caller, state = map(pathlib.Path, sys.argv[1:5])
args = [item.decode() for item in capture.read_bytes().split(b"\0") if item]
def value(option):
    return args[args.index(option) + 1]
assert value("--plugin-root") == str(plugin)
assert value("--working-directory") == str(caller)
session = pathlib.Path(value("--session-directory"))
assert session.is_relative_to(state)
assert value("--model") == "gpt-5.6-sol"
assert value("--reasoning-effort") == "max"
assert value("--context") == "long_context"
assert value("--repo") == "https://github.com/octocat/Hello-World"
PY
assert_not_contains "${fixture_root}/codex-launcher.terminal" \
    'RHYOLITE ERROR' 'Staged Codex launcher error output'
# No harness hook runs before the terminal setup questions, so the launcher
# prints the plaque itself, before the controller starts.
python3 -I - "${fixture_root}/codex-launcher.terminal" \
    "${PLUGIN_ROOT}/branding/banner.txt" "${ROOT}/VERSION" <<'PY'
import pathlib
import re
import sys

text = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
text = text.replace("\r", "")
banner = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").rstrip("\n").split("\n")
version = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8").strip()
width = max(len(line) for line in banner)
version_line = f"v{version} Beta".rjust(width)
plaque = "\n".join(banner + [version_line, "",
    "Rhyolite is an open-source software analysis platform.",
    "repo-review is its initial and default module; automatic guided setup is starting.",
    "Answer the setup questions below; during the review, use /rhyolite:status for current progress.",
]) + "\n"
assert text.count(plaque) == 1, text
assert text.index(plaque) < text.index("FIXTURE CODEX CONTROLLER STARTED"), text
PY
codex_launcher_commit="$(printf 'c%.0s' {1..40})"
rm -f -- "${codex_launcher_capture}"
(
    cd -- "${codex_launcher_caller}"
    env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
        HOME="${fixture_root}/codex-launcher-home" \
        CODEX_HOME="${codex_home}" \
        FIXTURE_CODEX_KEY='fixture-secret-value' \
        XDG_STATE_HOME="${codex_launcher_state}" \
        RHYOLITE_CODEX_LAUNCHER_CAPTURE="${codex_launcher_capture}" \
        RHYOLITE_CODEX_FAKE_CALLS="${codex_launcher_calls}" \
        PATH="${codex_fake_bin}:/usr/bin:/bin" \
        python3 -I "${codex_terminal_driver}" \
        "${fixture_root}/codex-launcher-auto.stdout" \
        "${fixture_root}/codex-launcher-auto.terminal" \
        "${fixture_root}/codex-launcher.steps" \
        -- \
        "${codex_launcher_plugin}/bin/rhyolite" \
        --harness codex \
        --repo https://github.com/octocat/Hello-World \
        --commit "${codex_launcher_commit}" \
        --auto-defaults
) || {
    cat -- "${fixture_root}/codex-launcher-auto.terminal" >&2 || true
    fail 'Staged Codex launcher failed with --auto-defaults.'
}
python3 -I - "${codex_launcher_capture}" "${codex_launcher_commit}" <<'PY'
import pathlib
import sys

args = [item.decode() for item in pathlib.Path(sys.argv[1]).read_bytes().split(b"\0") if item]
assert args[args.index("--commit") + 1] == sys.argv[2]
assert "--auto-defaults" in args
assert args[args.index("--model") + 1] == "gpt-5.6-sol"
PY
# A launch with stdin or stderr off the terminal stops before the plaque and
# the controller, even when the other stream is a terminal.
printf '1\n' > "${fixture_root}/codex-launcher-piped.stdin"
codex_launcher_no_terminal_case() {
    local name="$1"
    shift
    local combined="${fixture_root}/codex-launcher-${name}.combined"

    rm -f -- "${codex_launcher_capture}"
    if (
        cd -- "${codex_launcher_caller}"
        env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
            HOME="${fixture_root}/codex-launcher-home" \
            CODEX_HOME="${codex_home}" \
            FIXTURE_CODEX_KEY='fixture-secret-value' \
            XDG_STATE_HOME="${codex_launcher_state}" \
            RHYOLITE_CODEX_LAUNCHER_CAPTURE="${codex_launcher_capture}" \
            RHYOLITE_CODEX_FAKE_CALLS="${codex_launcher_calls}" \
            PATH="${codex_fake_bin}:/usr/bin:/bin" \
            python3 -I "${codex_terminal_driver}" \
            "${fixture_root}/codex-launcher-${name}.stdout" \
            "${fixture_root}/codex-launcher-${name}.terminal" \
            "${fixture_root}/codex-launcher.steps" \
            "$@" \
            -- \
            "${codex_launcher_plugin}/bin/rhyolite" \
            --harness codex \
            --repo https://github.com/octocat/Hello-World \
            --auto-defaults
    ); then
        fail "Staged Codex launcher started with ${name}."
    fi
    cat -- "${fixture_root}/codex-launcher-${name}.terminal" \
        "${fixture_root}/codex-launcher-${name}".stderr \
        > "${combined}" 2>/dev/null || true
    assert_contains "${combined}" 'Stage: Codex terminal' \
        "Staged Codex launcher terminal stage with ${name}"
    assert_not_contains "${combined}" 'automatic guided setup is starting' \
        "Staged Codex launcher plaque with ${name}"
    [[ ! -e "${codex_launcher_capture}" ]] ||
        fail "Staged Codex launcher started its controller with ${name}."
}
codex_launcher_no_terminal_case piped-stdin \
    --stdin "${fixture_root}/codex-launcher-piped.stdin"
codex_launcher_no_terminal_case redirected-stderr \
    --stderr "${fixture_root}/codex-launcher-redirected-stderr.stderr"
rm -f -- "${codex_launcher_capture}"
if (
    cd -- "${codex_launcher_caller}"
    env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
        HOME="${fixture_root}/codex-launcher-home" \
        CODEX_HOME="${codex_home}" \
        FIXTURE_CODEX_KEY='fixture-secret-value' \
        XDG_STATE_HOME="${codex_launcher_state}" \
        RHYOLITE_CODEX_LAUNCHER_CAPTURE="${codex_launcher_capture}" \
        RHYOLITE_CODEX_FAKE_CALLS="${codex_launcher_calls}" \
        PATH="${codex_fake_bin}:/usr/bin:/bin" \
        "${codex_launcher_plugin}/bin/rhyolite" \
        --harness codex \
        --repo https://github.com/octocat/Hello-World \
        --security-scans 2
) > "${fixture_root}/codex-launcher-scans.stdout" \
    2> "${fixture_root}/codex-launcher-scans.stderr"; then
    fail 'Staged Codex launcher accepted independent security scans.'
fi
assert_contains "${fixture_root}/codex-launcher-scans.stderr" \
    'Independent security scans are unavailable for this harness.' \
    'Staged Codex launcher scan rejection'
[[ ! -e "${codex_launcher_capture}" ]] ||
    fail 'Staged Codex launcher started its controller after rejecting scans.'

# Before any question or model request, the launcher stops when this
# environment cannot run a Codex review: here another CLI release, then a
# missing provider key.
codex_other_version_bin="${fixture_root}/codex-other-version-bin"
mkdir -p -- "${codex_other_version_bin}"
printf '%s\n' '#!/usr/bin/env bash' \
    'if [[ "${1-}" == --version ]]; then printf "%s\n" "codex-cli 0.164.0"; exit 0; fi' \
    'exit 99' > "${codex_other_version_bin}/codex"
chmod 700 -- "${codex_other_version_bin}/codex"
codex_launcher_not_ready() {
    local name="$1"
    local expected="$2"
    shift 2

    rm -f -- "${codex_launcher_capture}"
    if (
        cd -- "${codex_launcher_caller}"
        env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
            "$@" \
            HOME="${fixture_root}/codex-launcher-home" \
            CODEX_HOME="${codex_home}" \
            XDG_STATE_HOME="${codex_launcher_state}" \
            RHYOLITE_CODEX_LAUNCHER_CAPTURE="${codex_launcher_capture}" \
            "${codex_launcher_plugin}/bin/rhyolite" \
            --harness codex \
            --repo https://github.com/octocat/Hello-World \
            --auto-defaults
    ) > "${fixture_root}/codex-launcher-${name}.stdout" \
        2> "${fixture_root}/codex-launcher-${name}.stderr"; then
        fail "Codex launcher started despite ${name}."
    fi
    assert_contains "${fixture_root}/codex-launcher-${name}.stderr" \
        'Stage: Codex readiness' "Codex launcher ${name} stage"
    assert_contains "${fixture_root}/codex-launcher-${name}.stderr" \
        "${expected}" "Codex launcher ${name} detail"
    assert_not_contains "${fixture_root}/codex-launcher-${name}.stderr" \
        'fixture-secret-value' "Codex launcher ${name} secret"
    [[ ! -e "${codex_launcher_capture}" ]] ||
        fail "Codex launcher started its controller despite ${name}."
}
codex_launcher_not_ready other-cli-release \
    'the installed CLI reported codex-cli 0.164.0' \
    FIXTURE_CODEX_KEY='fixture-secret-value' \
    PATH="${codex_other_version_bin}:/usr/bin:/bin"
codex_launcher_not_ready missing-provider-key \
    'The configured Codex provider environment variable FIXTURE_CODEX_KEY is not set.' \
    -u FIXTURE_CODEX_KEY \
    PATH="${codex_fake_bin}:/usr/bin:/bin"
[[ ! -e "${codex_launcher_calls}" ]] ||
    fail 'The Codex launcher started a Codex session.'

# The real runner drives the Codex adapter end to end with a fake Codex
# worker: worker argv before runtime-home preparation, the isolated
# environment, the snapshot broker launched from the adapter's own MCP
# arguments, live monitoring, outcome, session verification, normalization,
# report validation, and cleanup.
codex_e2e_plugin="${fixture_root}/codex-e2e-plugin"
codex_e2e_bin="${fixture_root}/codex-e2e-bin"
codex_e2e_tmp="${fixture_root}/codex-e2e-tmp"
codex_e2e_home="${fixture_root}/codex-e2e-home"
codex_e2e_capture="${fixture_root}/codex-e2e-capture"
codex_e2e_report="${fixture_root}/codex-e2e-report.txt"
codex_e2e_runner="${codex_e2e_plugin}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh"
cp -a -- "${PLUGIN_ROOT}" "${codex_e2e_plugin}"
cat >> "${codex_e2e_plugin}/lib/harness/common.sh" <<'CODEX_E2E_TEST_REGISTRY'

rhyolite_harness_list_registered() {
    printf '%s\n' codex
}

rhyolite_harness_registry_lookup() {
    local output_variable="$1"
    local plugin_root="$2"
    local selected_harness="$3"
    [[ "${selected_harness}" == codex ]] || {
        RHYOLITE_HARNESS_ERROR_DETAIL='Fixture registry supports only Codex for this case.'
        return 1
    }
    printf -v "${output_variable}" '%s' "${plugin_root}/lib/harness/codex.sh"
}
CODEX_E2E_TEST_REGISTRY
mkdir -p -- "${codex_e2e_bin}" "${codex_e2e_tmp}" "${codex_e2e_home}" "${codex_e2e_capture}"
chmod 700 -- "${codex_e2e_bin}" "${codex_e2e_tmp}" "${codex_e2e_home}" "${codex_e2e_capture}"
awk '
    /^=+$/ && length($0) >= 80 { delimiters++ }
    delimiters >= 1 { print }
    delimiters == 2 { exit }
' "${NOOP_WORKER_FIXTURE}" > "${codex_e2e_report}"
grep -Fxq 'REPOSITORY REVIEW REPORT' "${codex_e2e_report}" ||
    fail 'Codex end-to-end fixture report could not be prepared.'
cat > "${codex_e2e_bin}/codex-worker.py" <<'CODEX_E2E_WORKER'
import json
import os
import pathlib
import subprocess
import sys
import tomllib

report_path, capture_path, *args = sys.argv[1:]


def fail(message):
    print(f"Codex fixture worker: {message}", file=sys.stderr)
    raise SystemExit(3)


if args[:2] != ["--no-daemon", "exec"] or args[-1] != "-":
    fail("unexpected command framing")
# A same-session continuation inserts `resume` before --model and names the
# native thread before the final "-".
resumed = "resume" in args
if resumed and (args.count("resume") != 1 or "--model" not in args
                or args.index("resume") > args.index("--model")):
    fail("unexpected resume framing")
options, overrides, index = {}, {}, 2
while index < len(args) - (2 if resumed else 1):
    argument = args[index]
    if argument == "resume":
        index += 1
    elif argument == "-c":
        key, separator, value = args[index + 1].partition("=")
        if not separator:
            fail("malformed configuration override")
        overrides[key] = tomllib.loads("value = " + value)["value"]
        index += 2
    elif argument in {"--sandbox", "--cd", "--model", "--output-last-message"}:
        options[argument] = args[index + 1]
        index += 2
    elif argument in {"--strict-config", "--ignore-rules", "--json", "--skip-git-repo-check",
                      "--ephemeral"}:
        options[argument] = True
        index += 1
    else:
        fail("unexpected argument " + argument)
home = pathlib.Path(os.environ["CODEX_HOME"])
config = tomllib.loads((home / "config.toml").read_text(encoding="utf-8"))
if resumed and options.get("--ephemeral"):
    fail("an ephemeral session cannot be resumed")
if options.get("--ephemeral"):
    # The runner's fresh, tool-less confidence edit: no MCP server, no worker
    # instructions, and an empty trusted working directory.
    if (overrides or "model_instructions_file" in config
            or options.get("--sandbox") != "read-only"
            or not os.path.samefile(os.getcwd(), options["--cd"])
            or os.listdir(os.getcwd())):
        fail("the report repair session is not tool-less and isolated")
    request = sys.stdin.read().splitlines()
    descriptor = request[request.index("EXPECTED CONFIDENCE EDIT") + 1]
    pathlib.Path(options["--output-last-message"]).write_text(descriptor, encoding="utf-8")
    for event in (
        {"type": "thread.started", "thread_id": "00000000-0000-4000-8000-0000000000e4"},
        {"type": "turn.started"},
        {"type": "item.completed", "item": {"id": "item_0", "type": "agent_message",
                                            "text": descriptor}},
        {"type": "turn.completed", "usage": {"input_tokens": 1, "cached_input_tokens": 0,
                                             "output_tokens": 1, "reasoning_output_tokens": 0}},
    ):
        print(json.dumps(event), flush=True)
    (pathlib.Path(capture_path) / "report-repair.json").write_text(
        json.dumps({"Descriptor": json.loads(descriptor)}), encoding="utf-8")
    raise SystemExit(0)
phase = "research" if "mcp_servers.rhyolite_research.command" in overrides else "review"
instructions = pathlib.Path(config.get("model_instructions_file", "/nonexistent"))
instruction_text = instructions.read_text(encoding="utf-8") if instructions.is_file() else ""
if (instructions.parent != home or instructions.name != f"{phase}-worker-instructions.md"
        or "RHYOLITE_AGENT_SELF_CHECK_V2" not in instruction_text
        or (phase == "research" and "research_capabilities" not in instruction_text)):
    fail("the runtime home has no trusted worker instructions for this phase")
if (options.get("--sandbox") != "read-only"
        or not os.path.samefile(os.getcwd(), options["--cd"])):
    fail("unexpected sandbox or working directory")
prompt = sys.stdin.read()

# The real Codex 0.163.0 error when a required MCP server does not start: it
# fails before it creates a session, so it leaves no structured output, final
# message, or session record.
if (phase == "review" and not resumed
        and pathlib.Path(__file__).with_name("startup-failure-mode").exists()):
    print("Error: thread/start: thread/start failed: error creating thread: Fatal error: "
          "Failed to initialize session: required MCP servers failed to initialize: "
          "rhyolite_snapshot: local stdio MCP server `rhyolite_snapshot` requires a local "
          "environment (code -32603)", file=sys.stderr)
    raise SystemExit(1)


def use_server(server_name, calls):
    prefix = f"mcp_servers.{server_name}."
    if overrides.get(prefix + "required") is not True or overrides.get(prefix + "env_vars") != []:
        fail(f"{server_name} is not a required, environment-isolated MCP server")
    environment = {name: os.environ[name] for name in ("HOME", "PATH", "TMPDIR") if name in os.environ}
    environment.update(overrides[prefix + "env"])
    server = subprocess.Popen(
        [overrides[prefix + "command"], *overrides[prefix + "args"]],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, env=environment,
    )
    try:
        def call(identifier, method, params):
            server.stdin.write(json.dumps({"jsonrpc": "2.0", "id": identifier,
                                          "method": method, "params": params}) + "\n")
            server.stdin.flush()
            response = json.loads(server.stdout.readline())
            if "result" not in response:
                fail(f"{server_name} {method} failed")
            return response["result"]

        call(1, "initialize", {"protocolVersion": "2025-06-18", "capabilities": {},
                               "clientInfo": {"name": "codex-fixture", "version": "0.163.0"}})
        server.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        tools = [tool["name"] for tool in call(2, "tools/list", {})["tools"]]
        if tools != overrides[prefix + "enabled_tools"]:
            fail(f"the {server_name} tool inventory changed")
        results = []
        for offset, (tool, arguments) in enumerate(calls):
            result = call(3 + offset, "tools/call", {"name": tool, "arguments": arguments})
            if result.get("isError"):
                fail(f"{server_name} {tool} failed")
            results.append(json.dumps(result))
        server.stdin.close()
        if server.wait(timeout=10) != 0:
            fail(f"the {server_name} broker did not exit cleanly")
        return tools, results
    finally:
        if server.poll() is None:
            server.terminate()
            server.wait(timeout=10)


tools, snapshot_results = use_server("rhyolite_snapshot", [
    ("read_snapshot_text", {"grant": "snapshot", "path": "README.md"}),
])
if "mock repository" not in snapshot_results[0]:
    fail("the snapshot read failed")
research_tools = []
if phase == "research":
    research_tools, _ = use_server("rhyolite_research", [("research_capabilities", {})])

model = options["--model"]
effort = config["model_reasoning_effort"]
window = config["model_context_window"] * 95 // 100
thread = "00000000-0000-4000-8000-0000000000e2" if phase == "review" else "00000000-0000-4000-8000-0000000000e3"
usage = {"input_tokens": 24000, "cached_input_tokens": 0, "output_tokens": 900,
         "reasoning_output_tokens": 0, "total_tokens": 24900}
turn_records = [
    {"type": "event_msg", "payload": {"type": "task_started", "model_context_window": window}},
    {"type": "turn_context", "payload": {
        "approval_policy": "never", "sandbox_policy": {"type": "read-only"},
        "model": model, "effort": effort,
        "collaboration_mode": {"mode": "default",
                               "settings": {"model": model, "reasoning_effort": effort}}}},
    {"type": "response_item", "payload": {"type": "message", "role": "user",
                                          "content": [{"type": "input_text", "text": prompt}]}},
    {"type": "event_msg", "payload": {"type": "token_count", "info": {
        "total_token_usage": usage, "last_token_usage": usage,
        "model_context_window": window}, "rate_limits": None}},
]
snapshot_read = {"type": "item.completed", "item": {
    "id": "item_0", "type": "mcp_tool_call", "server": "rhyolite_snapshot",
    "tool": "read_snapshot_text", "arguments": {"grant": "snapshot", "path": "README.md"},
    "status": "completed"}}


def assistant(text):
    return {"type": "response_item", "payload": {
        "type": "message", "role": "assistant", "phase": "final_answer",
        "content": [{"type": "output_text", "text": text}]}}


def emit(events):
    for event in ({"type": "thread.started", "thread_id": thread}, {"type": "turn.started"},
                  *events):
        print(json.dumps(event), flush=True)


if resumed:
    # Codex appends the resumed turn to the same rollout after restarting the
    # required MCP servers (the snapshot read above), and answers the
    # runner's report delivery page from the fixture report.
    rollouts = sorted((home / "sessions").glob(f"**/rollout-*-{thread}.jsonl"))
    if phase != "review" or args[-2] != thread or len(rollouts) != 1:
        fail("only the review session may be resumed, by its own native thread")
    request = prompt.splitlines()
    report = pathlib.Path(report_path).read_text(encoding="utf-8").splitlines()
    page_id = next(line.split(": ", 1)[1] for line in request if line.startswith("Request: "))
    sections = []
    for line in request[request.index("Requested sections, in this exact order:") + 1:]:
        if not line.startswith("- "):
            break
        sections.append(line[2:])
    headings = {
        "REVIEW CONTEXT", "EXECUTIVE SUMMARY", "FINDINGS",
        "AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT",
        "CLAIMS AND REPUTATION INTEGRITY ASSESSMENT", "COMMUNITY HEALTH ASSESSMENT",
        "AREAS REVIEWED WITHOUT QUALIFYING FINDINGS", "PRIORITIZED REMEDIATION",
        "OVERALL ASSESSMENT",
    }
    page = [f"Delivering {len(sections)} section(s).", f"RHYOLITE REPORT PAGE {page_id} BEGIN"]
    for section in sections:
        body = []
        for line in report[report.index(section) + 1:]:
            if line in headings or (len(line) >= 80 and set(line) == {"="}):
                break
            body.append(line)
        page.extend([section, "\n".join(body).rstrip("\n"), ""])
    page.append(f"RHYOLITE REPORT PAGE {page_id} END")
    reply = "\n".join(page)
    with rollouts[0].open("a", encoding="utf-8") as stream:
        for record in (*turn_records, assistant(reply)):
            stream.write(json.dumps(record) + "\n")
    pathlib.Path(options["--output-last-message"]).write_text(reply, encoding="utf-8")
    emit((snapshot_read,
          {"type": "item.completed", "item": {"id": "item_1", "type": "agent_message",
                                              "text": reply}},
          {"type": "turn.completed", "usage": usage}))
    continuations = pathlib.Path(capture_path) / "review-continuations.json"
    entries = json.loads(continuations.read_text(encoding="utf-8")) if continuations.exists() else []
    entries.append({"Page": page_id, "Sections": sections, "SnapshotTools": tools})
    continuations.write_text(json.dumps(entries), encoding="utf-8")
    raise SystemExit(0)

# Codex 0.163.0 writes no final-message file when a turn fails: here every
# built-in stream retry of a transient model-service error was exhausted.
transient = phase == "review" and pathlib.Path(__file__).with_name("transient-mode").exists()
# A session timeout stops Codex with SIGTERM, which it does not handle: its
# output ends mid-turn without a terminal event or final message, and the
# runner sees the 124 exit status of `timeout`.
stopped = phase == "review" and pathlib.Path(__file__).with_name("timeout-mode").exists()
# A provider that answers with another model makes Codex record a reroute
# notice before the reply; Rhyolite never accepts that output.
rerouted = phase == "review" and pathlib.Path(__file__).with_name("reroute-mode").exists()
# The provider's content filter declines the approved model, the only one a
# Codex plan can name.
refused = (phase == "review" and not resumed
           and pathlib.Path(__file__).with_name("refusal-mode").exists())
reply = pathlib.Path(report_path).read_text(encoding="utf-8").rstrip("\n") if phase == "review" else ""
if phase == "review" and pathlib.Path(__file__).with_name("repair-mode").exists():
    # The compound value of a real incident: no deterministic normalization
    # applies, so the runner must hand it to the isolated confidence edit.
    reply = reply.replace(
        "Confidence: High.",
        "Confidence: High for counts and Medium for adoption interpretation.",
        1,
    )
records = [
    {"type": "session_meta", "payload": {"id": thread, "originator": "codex_exec",
                                         "cli_version": "0.163.0", "source": "exec"}},
    *turn_records,
]
if phase == "review" and not transient and not stopped and not refused:
    records.append(assistant(reply))
sessions = home / "sessions" / "2026" / "10" / "01"
sessions.mkdir(parents=True)
(sessions / f"rollout-2026-10-01T12-00-00-{thread}.jsonl").write_text(
    "".join(json.dumps(record) + "\n" for record in records), encoding="utf-8")
if stopped:
    events = (
        {"type": "item.started", "item": {**snapshot_read["item"], "status": "in_progress"}},
        snapshot_read,
    )
elif transient:
    failure = ("stream disconnected before completion: "
               "The server had an error processing your request.")
    events = (
        snapshot_read,
        *({"type": "error", "message": f"Reconnecting... {attempt}/5 ({failure})"}
          for attempt in range(1, 6)),
        {"type": "error", "message": failure},
        {"type": "turn.failed", "error": {"message": failure}},
    )
elif refused:
    refusal = ("stream disconnected before completion: "
               "Incomplete response returned, reason: content_filter")
    events = (
        snapshot_read,
        {"type": "error", "message": refusal},
        {"type": "turn.failed", "error": {"message": refusal}},
    )
elif phase == "review":
    pathlib.Path(options["--output-last-message"]).write_text(reply, encoding="utf-8")
    reroute = ({"type": "item.completed", "item": {
        "id": "item_r", "type": "error",
        "message": f"model rerouted: {model} -> fixture-other-model (FixtureReason)"}},)
    events = (
        {"type": "error", "message": "Reconnecting... 1/5 (stream disconnected before completion: "
                                     "The server had an error processing your request.)"},
        snapshot_read,
        *(reroute if rerouted else ()),
        {"type": "item.completed", "item": {"id": "item_1", "type": "agent_message", "text": reply}},
        {"type": "turn.completed", "usage": usage},
    )
else:
    events = (
        {"type": "item.completed", "item": {
            "id": "item_0", "type": "mcp_tool_call", "server": "rhyolite_research",
            "tool": "research_capabilities", "arguments": {}, "status": "completed"}},
        {"type": "turn.failed", "error": {
            "message": "fixture research worker stopped before public retrieval"}},
    )
emit(events)
(pathlib.Path(capture_path) / f"{phase}.json").write_text(json.dumps({
    "Instructions": instructions.name, "SnapshotTools": tools, "ResearchTools": research_tools,
    "PromptHasCommit": "7fd1a60b01f91b314f59955a4e4d4e80d8edf11d" in prompt,
}), encoding="utf-8")
raise SystemExit(124 if stopped else 0 if phase == "review" and not transient and not refused else 1)
CODEX_E2E_WORKER
{
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf 'codex_e2e_bin=%q\n' "${codex_e2e_bin}"
    printf 'codex_e2e_report=%q\n' "${codex_e2e_report}"
    printf 'codex_e2e_capture=%q\n' "${codex_e2e_capture}"
    cat <<'CODEX_E2E_FAKE'
if [[ "${1-}" == --version ]]; then
    printf '%s\n' 'codex-cli 0.163.0'
    exit 0
fi
exec python3 -I "${codex_e2e_bin}/codex-worker.py" \
    "${codex_e2e_report}" "${codex_e2e_capture}" "$@"
CODEX_E2E_FAKE
} > "${codex_e2e_bin}/codex"
chmod 700 -- "${codex_e2e_bin}/codex"
codex_e2e_environment=(
    env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS
    HOME="${codex_e2e_home}"
    XDG_STATE_HOME="${codex_e2e_home}/state"
    CODEX_HOME="${codex_home}"
    FIXTURE_CODEX_KEY='fixture-secret-value'
    TMPDIR="${codex_e2e_tmp}"
    PATH="${codex_e2e_bin}:${runner_mock_bin}:/usr/bin:/bin"
)
codex_e2e_arguments=(
    --harness codex
    --repo https://github.com/octocat/Hello-World
    --commit 7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
    --scope 1
    --model gpt-5.6-sol
    --reasoning-effort max
    --context long_context
    --security-scans 1
    --workspace-root "${fixture_root}/codex-e2e-workspace"
    --output-root "${fixture_root}/codex-e2e-output"
    --non-interactive
    --no-open-html
)
"${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_arguments[@]}" --plan-only \
    > "${fixture_root}/codex-e2e-plan.json" \
    2> "${fixture_root}/codex-e2e-plan.stderr" || {
        cat -- "${fixture_root}/codex-e2e-plan.stderr" >&2
        fail 'Codex end-to-end plan failed.'
    }
"${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_arguments[@]}" \
    --expected-plan-hash "$(contract_plan_hash "${fixture_root}/codex-e2e-plan.json")" \
    > "${fixture_root}/codex-e2e.stdout" \
    2> "${fixture_root}/codex-e2e.stderr" || {
        cat -- "${fixture_root}/codex-e2e.stdout" "${fixture_root}/codex-e2e.stderr" >&2
        cat -- "$(contract_run_path "${fixture_root}/codex-e2e.stdout")/github--octocat--hello-world/errors.txt" >&2 || true
        fail 'Codex end-to-end runner execution failed.'
    }
node - "$(contract_run_path "${fixture_root}/codex-e2e.stdout")" "${codex_e2e_capture}" <<'JS'
const fs = require("fs"), path = require("path");
const [root, capturePath] = process.argv.slice(2);
const repo = path.join(root, "github--octocat--hello-world");
const read = (name) => JSON.parse(fs.readFileSync(name, "utf8"));
const plan = read(path.join(root, "review-plan.json"));
const capture = read(path.join(capturePath, "review.json"));
for (const state of [read(path.join(root, "state.json")), read(path.join(repo, "state.json"))]) {
  if (state.Status !== "Completed" || state.Harness !== "codex" ||
      state.Model !== "gpt-5.6-sol" || state.ReasoningEffort !== "max" ||
      JSON.stringify(state.SnapshotTransport) !== JSON.stringify(plan.SnapshotTransport)) {
    throw new Error(`Codex end-to-end state is wrong: ${state.Status}`);
  }
}
if (plan.SnapshotTransport.ContractVersion !== 11) throw new Error("snapshot contract changed");
if (!fs.readFileSync(path.join(repo, "review.txt"), "utf8").includes("REPOSITORY REVIEW REPORT")) {
  throw new Error("Codex end-to-end report is missing");
}
if (capture.Instructions !== "review-worker-instructions.md" || !capture.PromptHasCommit ||
    capture.SnapshotTools.length !== 4) {
  throw new Error("Codex worker did not start with instructions, request, and snapshot tools");
}
const sessions = fs.readdirSync(path.join(repo, "agent-state", "codex-home", "sessions"));
if (sessions.length !== 1 || !fs.readFileSync(path.join(repo, "session.md"), "utf8").includes("### Codex")) {
  throw new Error("Codex session evidence was not persisted");
}
JS
[[ -z "$(find "${codex_e2e_tmp}" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
    fail 'Codex end-to-end run left a runtime home or snapshot broker runtime.'
[[ -z "$(find "$(contract_run_path "${fixture_root}/codex-e2e.stdout")" \
    -name '*.codex-final' -print -quit)" ]] ||
    fail 'Codex end-to-end run left an unsanitized final-message file.'

# Scope 2 drives the research phase through the adapter-built research argv,
# runtime home, environment, and both real brokers. The fake research worker
# records a real broker capability check and then stops, so the run must end
# as a research-worker failure, never as an adapter or capability failure.
codex_e2e_research_arguments=(
    --harness codex
    --repo https://github.com/octocat/Hello-World
    --commit 7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
    --scope 2
    --research-cookies off
    --model gpt-5.6-sol
    --reasoning-effort max
    --context long_context
    --security-scans 1
    --workspace-root "${fixture_root}/codex-e2e-research-workspace"
    --output-root "${fixture_root}/codex-e2e-research-output"
    --non-interactive
    --no-open-html
)
"${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_research_arguments[@]}" --plan-only \
    > "${fixture_root}/codex-e2e-research-plan.json" \
    2> "${fixture_root}/codex-e2e-research-plan.stderr" || {
        cat -- "${fixture_root}/codex-e2e-research-plan.stderr" >&2
        fail 'Codex end-to-end research plan failed.'
    }
if "${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_research_arguments[@]}" \
    --expected-plan-hash "$(contract_plan_hash "${fixture_root}/codex-e2e-research-plan.json")" \
    > "${fixture_root}/codex-e2e-research.stdout" \
    2> "${fixture_root}/codex-e2e-research.stderr"; then
    fail 'Codex end-to-end research fixture unexpectedly completed.'
fi
node - "$(contract_run_path "${fixture_root}/codex-e2e-research.stdout")" \
    "${codex_e2e_capture}" <<'JS'
const fs = require("fs"), path = require("path");
const [root, captureRoot] = process.argv.slice(2);
const repo = path.join(root, "github--octocat--hello-world");
const read = (name) => JSON.parse(fs.readFileSync(name, "utf8"));
const research = read(path.join(repo, "research", "research-state.json"));
const errors = fs.readFileSync(path.join(repo, "research", "research-errors.txt"), "utf8");
if (research.Status !== "ResearchFailed" || research.Attempts.Count !== 1) {
  throw new Error(`Codex research did not fail as a worker after launch: ${research.Status}\n${errors}`);
}
if (!errors.includes("fixture research worker stopped before public retrieval")) {
  throw new Error(`Codex research errors lost the worker's own failure:\n${errors}`);
}
for (const forbidden of ["harness_research_worker_argv", "harness_prepare_worker_home",
  "harness_research_worker_env", "harness_configure_snapshot_transport",
  "did not record a verifiable lifecycle exit", "cleanup failed"]) {
  if (errors.includes(forbidden)) throw new Error(`Codex research launch path failed: ${forbidden}\n${errors}`);
}
const events = fs.readFileSync(path.join(repo, "research", "network", "events.jsonl"), "utf8");
if (!events.includes('"capabilities_checked"')) {
  throw new Error("the real research broker did not record the capability check");
}
const capture = read(path.join(captureRoot, "research.json"));
if (capture.Instructions !== "research-worker-instructions.md" || !capture.PromptHasCommit ||
    capture.SnapshotTools.length !== 4 ||
    JSON.stringify(capture.ResearchTools) !== JSON.stringify([
      "research_capabilities", "fetch_public_url", "search_public_github",
      "search_public_web", "research_network_summary"])) {
  throw new Error("Codex research worker did not start with its instructions and both MCP servers");
}
JS
[[ -z "$(find "${codex_e2e_tmp}" -mindepth 1 -maxdepth 1 -print -quit)" ]] ||
    fail 'Codex end-to-end research run left a runtime home or broker runtime.'

# A report whose assessment confidence needs the isolated confidence edit runs
# the real report repair through a fresh, tool-less Codex session.
touch -- "${codex_e2e_bin}/repair-mode"
codex_e2e_repair_arguments=(
    --harness codex
    --repo https://github.com/octocat/Hello-World
    --commit 7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
    --scope 1
    --model gpt-5.6-sol
    --reasoning-effort max
    --context long_context
    --security-scans 1
    --workspace-root "${fixture_root}/codex-e2e-repair-workspace"
    --output-root "${fixture_root}/codex-e2e-repair-output"
    --non-interactive
    --no-open-html
)
"${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_repair_arguments[@]}" --plan-only \
    > "${fixture_root}/codex-e2e-repair-plan.json" \
    2> "${fixture_root}/codex-e2e-repair-plan.stderr" || {
        cat -- "${fixture_root}/codex-e2e-repair-plan.stderr" >&2
        fail 'Codex end-to-end repair plan failed.'
    }
"${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_repair_arguments[@]}" \
    --expected-plan-hash "$(contract_plan_hash "${fixture_root}/codex-e2e-repair-plan.json")" \
    > "${fixture_root}/codex-e2e-repair.stdout" \
    2> "${fixture_root}/codex-e2e-repair.stderr" || {
        cat -- "${fixture_root}/codex-e2e-repair.stdout" "${fixture_root}/codex-e2e-repair.stderr" >&2
        cat -- "$(contract_run_path "${fixture_root}/codex-e2e-repair.stdout")/github--octocat--hello-world/errors.txt" >&2 || true
        fail 'Codex end-to-end report repair failed.'
    }
rm -f -- "${codex_e2e_bin}/repair-mode"
node - "$(contract_run_path "${fixture_root}/codex-e2e-repair.stdout")" \
    "${codex_e2e_capture}" <<'JS'
const fs = require("fs"), path = require("path");
const [root, captureRoot] = process.argv.slice(2);
const repo = path.join(root, "github--octocat--hello-world");
const state = JSON.parse(fs.readFileSync(path.join(repo, "state.json"), "utf8"));
const report = fs.readFileSync(path.join(repo, "review.txt"), "utf8");
const capture = JSON.parse(fs.readFileSync(path.join(captureRoot, "report-repair.json"), "utf8"));
if (state.Status !== "Completed" || state.ReportRepair.Status !== "Succeeded" ||
    state.ReportRepair.AttemptCount !== 1 ||
    capture.Descriptor.Section !== "AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT" ||
    capture.Descriptor.ConservativeLevel !== "Medium" ||
    !report.includes("Confidence: Medium - Original confidence detail: " +
      "High for counts and Medium for adoption interpretation.")) {
  throw new Error(`Codex report repair did not succeed: ${JSON.stringify(state.ReportRepair)}`);
}
JS
[[ -z "$(find "${codex_e2e_tmp}" -mindepth 1 -maxdepth 1 -print -quit)" &&
    -z "$(find "$(contract_run_path "${fixture_root}/codex-e2e-repair.stdout")" \
        -name '*.codex-final' -print -quit)" ]] ||
    fail 'Codex end-to-end report repair left a runtime home or final-message file.'

# A review turn that exhausts Codex's built-in retries of a transient
# model-service error ends without a final message. The runner resumes the
# same native session with the adapter's continuation argv, waits for the
# previous snapshot broker before each resume, lets every resumed session
# restart that broker, and assembles the report from strictly validated
# pages; the adapter re-verifies the appended session after each turn.
touch -- "${codex_e2e_bin}/transient-mode"
rm -f -- "${codex_e2e_capture}/review-continuations.json"
codex_e2e_recovery_arguments=(
    --harness codex
    --repo https://github.com/octocat/Hello-World
    --commit 7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
    --scope 1
    --model gpt-5.6-sol
    --reasoning-effort max
    --context long_context
    --security-scans 1
    --workspace-root "${fixture_root}/codex-e2e-recovery-workspace"
    --output-root "${fixture_root}/codex-e2e-recovery-output"
    --non-interactive
    --no-open-html
)
"${codex_e2e_environment[@]}" RHYOLITE_WORKER_RETRY_DELAY_SECONDS=0 \
    "${codex_e2e_runner}" "${codex_e2e_recovery_arguments[@]}" --plan-only \
    > "${fixture_root}/codex-e2e-recovery-plan.json" \
    2> "${fixture_root}/codex-e2e-recovery-plan.stderr" || {
        cat -- "${fixture_root}/codex-e2e-recovery-plan.stderr" >&2
        fail 'Codex end-to-end recovery plan failed.'
    }
"${codex_e2e_environment[@]}" RHYOLITE_WORKER_RETRY_DELAY_SECONDS=0 \
    "${codex_e2e_runner}" "${codex_e2e_recovery_arguments[@]}" \
    --expected-plan-hash "$(contract_plan_hash "${fixture_root}/codex-e2e-recovery-plan.json")" \
    > "${fixture_root}/codex-e2e-recovery.stdout" \
    2> "${fixture_root}/codex-e2e-recovery.stderr" || {
        cat -- "${fixture_root}/codex-e2e-recovery.stdout" "${fixture_root}/codex-e2e-recovery.stderr" >&2
        cat -- "$(contract_run_path "${fixture_root}/codex-e2e-recovery.stdout")/github--octocat--hello-world/errors.txt" >&2 || true
        fail 'Codex end-to-end same-session recovery failed.'
    }
rm -f -- "${codex_e2e_bin}/transient-mode"
codex_e2e_recovery_repository="$(contract_run_path "${fixture_root}/codex-e2e-recovery.stdout")/github--octocat--hello-world"
node - "$(contract_run_path "${fixture_root}/codex-e2e-recovery.stdout")" \
    "${codex_e2e_capture}" <<'JS'
const fs = require("fs"), path = require("path");
const [root, captureRoot] = process.argv.slice(2);
const repo = path.join(root, "github--octocat--hello-world");
const read = (name) => JSON.parse(fs.readFileSync(name, "utf8"));
const plan = read(path.join(root, "review-plan.json"));
const state = read(path.join(repo, "state.json"));
const recovery = state.WorkerRecovery;
const pages = read(path.join(captureRoot, "review-continuations.json"));
if (state.Status !== "Completed" || plan.WorkerRecoveryPolicy?.Available !== true ||
    recovery?.Status !== "Recovered" || recovery.Trigger !== "interrupted" ||
    recovery.Available !== true || recovery.TransientRetries !== 1 ||
    recovery.Continuations < 1 || recovery.Continuations !== pages.length ||
    recovery.PagesAccepted !== pages.length) {
  throw new Error(`Codex transient failure was not recovered in the same session: ${JSON.stringify(recovery)}`);
}
if (pages.some((page) => page.SnapshotTools.length !== 4)) {
  throw new Error("a resumed Codex session did not restart the snapshot broker");
}
const sessions = path.join(repo, "agent-state", "codex-home", "sessions");
const records = fs.readdirSync(sessions);
const turns = fs.readFileSync(path.join(sessions, records[0]), "utf8").split("\n")
  .filter((line) => line.includes('"type":"turn_context"')).length;
if (records.length !== 1 || turns !== 1 + pages.length) {
  throw new Error(`Codex did not re-record every resumed turn: ${records.length} record(s), ${turns} turn(s)`);
}
const errorsPath = path.join(repo, "errors.txt");
const errors = fs.existsSync(errorsPath) ? fs.readFileSync(errorsPath, "utf8") : "";
if (errors.includes("Harness failure stage:")) {
  throw new Error(`an ordinary failed Codex turn was reported as an adapter failure:\n${errors}`);
}
JS
cmp -s <(grep -v '^$' "${codex_e2e_recovery_repository}/review.txt") \
    <(grep -v '^$' "${codex_e2e_report}") ||
    fail 'Codex same-session recovery did not reassemble the canonical report.'
[[ -z "$(find "${codex_e2e_tmp}" -mindepth 1 -maxdepth 1 -print -quit)" &&
    -z "$(find "$(contract_run_path "${fixture_root}/codex-e2e-recovery.stdout")" \
        -name '*.codex-final' -print -quit)" ]] ||
    fail 'Codex same-session recovery left a runtime home, broker runtime, or final-message file.'

# A session timeout stops Codex mid-turn. The run must report the timeout,
# not an adapter failure, and still clean up the runtime home and broker.
touch -- "${codex_e2e_bin}/timeout-mode"
codex_e2e_timeout_arguments=(
    --harness codex
    --repo https://github.com/octocat/Hello-World
    --commit 7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
    --scope 1
    --model gpt-5.6-sol
    --reasoning-effort max
    --context long_context
    --security-scans 1
    --workspace-root "${fixture_root}/codex-e2e-timeout-workspace"
    --output-root "${fixture_root}/codex-e2e-timeout-output"
    --non-interactive
    --no-open-html
)
"${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_timeout_arguments[@]}" --plan-only \
    > "${fixture_root}/codex-e2e-timeout-plan.json" \
    2> "${fixture_root}/codex-e2e-timeout-plan.stderr" || {
        cat -- "${fixture_root}/codex-e2e-timeout-plan.stderr" >&2
        fail 'Codex end-to-end timeout plan failed.'
    }
if "${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_timeout_arguments[@]}" \
    --expected-plan-hash "$(contract_plan_hash "${fixture_root}/codex-e2e-timeout-plan.json")" \
    > "${fixture_root}/codex-e2e-timeout.stdout" \
    2> "${fixture_root}/codex-e2e-timeout.stderr"; then
    fail 'Codex end-to-end timeout fixture unexpectedly completed.'
fi
rm -f -- "${codex_e2e_bin}/timeout-mode"
node - "$(contract_run_path "${fixture_root}/codex-e2e-timeout.stdout")" <<'JS'
const fs = require("fs"), path = require("path");
const repo = path.join(process.argv[2], "github--octocat--hello-world");
const state = JSON.parse(fs.readFileSync(path.join(repo, "state.json"), "utf8"));
const analysis = JSON.parse(fs.readFileSync(path.join(repo, "failure-analysis.json"), "utf8"));
const errors = fs.readFileSync(path.join(repo, "errors.txt"), "utf8");
if (state.Status !== "TimedOut" || state.ExitCode !== 124 ||
    analysis.Stage !== "worker timeout" || !errors.includes("Session exceeded") ||
    errors.includes("Harness failure stage:")) {
  throw new Error(`a Codex session timeout was not reported as a timeout: ${state.Status}, ${analysis.Stage}\n${errors}`);
}
JS
[[ -z "$(find "${codex_e2e_tmp}" -mindepth 1 -maxdepth 1 -print -quit)" &&
    -z "$(find "$(contract_run_path "${fixture_root}/codex-e2e-timeout.stdout")" \
        -name '*.codex-final' -print -quit)" ]] ||
    fail 'Codex session timeout left a runtime home, broker runtime, or final-message file.'

# Codex can fail before it creates a session, for example when a required MCP
# server does not start. The run must report that worker failure with the
# CLI's own error, not an adapter failure, and still clean up.
touch -- "${codex_e2e_bin}/startup-failure-mode"
codex_e2e_startup_arguments=(
    --harness codex
    --repo https://github.com/octocat/Hello-World
    --commit 7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
    --scope 1
    --model gpt-5.6-sol
    --reasoning-effort max
    --context long_context
    --security-scans 1
    --workspace-root "${fixture_root}/codex-e2e-startup-workspace"
    --output-root "${fixture_root}/codex-e2e-startup-output"
    --non-interactive
    --no-open-html
)
"${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_startup_arguments[@]}" --plan-only \
    > "${fixture_root}/codex-e2e-startup-plan.json" \
    2> "${fixture_root}/codex-e2e-startup-plan.stderr" || {
        cat -- "${fixture_root}/codex-e2e-startup-plan.stderr" >&2
        fail 'Codex end-to-end startup-failure plan failed.'
    }
if "${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_startup_arguments[@]}" \
    --expected-plan-hash "$(contract_plan_hash "${fixture_root}/codex-e2e-startup-plan.json")" \
    > "${fixture_root}/codex-e2e-startup.stdout" \
    2> "${fixture_root}/codex-e2e-startup.stderr"; then
    fail 'Codex end-to-end startup-failure fixture unexpectedly completed.'
fi
rm -f -- "${codex_e2e_bin}/startup-failure-mode"
node - "$(contract_run_path "${fixture_root}/codex-e2e-startup.stdout")" <<'JS'
const fs = require("fs"), path = require("path");
const repo = path.join(process.argv[2], "github--octocat--hello-world");
const state = JSON.parse(fs.readFileSync(path.join(repo, "state.json"), "utf8"));
const analysis = JSON.parse(fs.readFileSync(path.join(repo, "failure-analysis.json"), "utf8"));
const errors = fs.readFileSync(path.join(repo, "errors.txt"), "utf8");
if (state.Status !== "ReviewFailed" || state.ExitCode !== 1 ||
    analysis.Stage !== "worker analysis" ||
    !errors.includes("Failed to initialize session: required MCP servers failed to initialize") ||
    errors.includes("Harness failure stage:") || errors.includes("No such file or directory")) {
  throw new Error(`a Codex startup failure was not reported as the worker's: ${state.Status}, ${analysis.Stage}\n${errors}`);
}
JS
[[ -z "$(find "${codex_e2e_tmp}" -mindepth 1 -maxdepth 1 -print -quit)" &&
    -z "$(find "$(contract_run_path "${fixture_root}/codex-e2e-startup.stdout")" \
        -name '*.codex-final' -print -quit)" ]] ||
    fail 'Codex startup failure left a runtime home, broker runtime, or final-message file.'

# A provider that answers with another model is never accepted: the run must
# fail at the runner's approved-model enforcement stage, as with every other
# harness, and must not continue the session.
touch -- "${codex_e2e_bin}/reroute-mode"
codex_e2e_reroute_arguments=(
    --harness codex
    --repo https://github.com/octocat/Hello-World
    --commit 7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
    --scope 1
    --model gpt-5.6-sol
    --reasoning-effort max
    --context long_context
    --security-scans 1
    --workspace-root "${fixture_root}/codex-e2e-reroute-workspace"
    --output-root "${fixture_root}/codex-e2e-reroute-output"
    --non-interactive
    --no-open-html
)
"${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_reroute_arguments[@]}" --plan-only \
    > "${fixture_root}/codex-e2e-reroute-plan.json" \
    2> "${fixture_root}/codex-e2e-reroute-plan.stderr" || {
        cat -- "${fixture_root}/codex-e2e-reroute-plan.stderr" >&2
        fail 'Codex end-to-end reroute plan failed.'
    }
if "${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_reroute_arguments[@]}" \
    --expected-plan-hash "$(contract_plan_hash "${fixture_root}/codex-e2e-reroute-plan.json")" \
    > "${fixture_root}/codex-e2e-reroute.stdout" \
    2> "${fixture_root}/codex-e2e-reroute.stderr"; then
    fail 'Codex end-to-end reroute fixture unexpectedly completed.'
fi
rm -f -- "${codex_e2e_bin}/reroute-mode"
node - "$(contract_run_path "${fixture_root}/codex-e2e-reroute.stdout")" <<'JS'
const fs = require("fs"), path = require("path");
const repo = path.join(process.argv[2], "github--octocat--hello-world");
const state = JSON.parse(fs.readFileSync(path.join(repo, "state.json"), "utf8"));
const analysis = JSON.parse(fs.readFileSync(path.join(repo, "failure-analysis.json"), "utf8"));
const errors = fs.readFileSync(path.join(repo, "errors.txt"), "utf8");
if (state.Status !== "ReviewFailed" || analysis.Stage !== "approved model enforcement" ||
    !errors.includes("does not accept substituted output") ||
    state.WorkerRecovery.Continuations !== 0 ||
    fs.readFileSync(path.join(repo, "review.txt"), "utf8").includes("FINDINGS")) {
  throw new Error(`a Codex model reroute was not rejected at approved-model enforcement: ${state.Status}, ${analysis.Stage}\n${errors}`);
}
JS
[[ -z "$(find "${codex_e2e_tmp}" -mindepth 1 -maxdepth 1 -print -quit)" &&
    -z "$(find "$(contract_run_path "${fixture_root}/codex-e2e-reroute.stdout")" \
        -name '*.codex-final' -print -quit)" ]] ||
    fail 'Codex reroute rejection left a runtime home, broker runtime, or final-message file.'

# A provider refusal of the only approved model fails the review at stage
# `provider refusal`, and the remediation must not suggest scan models that
# a Codex plan cannot add.
touch -- "${codex_e2e_bin}/refusal-mode"
codex_e2e_refusal_arguments=(
    --harness codex
    --repo https://github.com/octocat/Hello-World
    --commit 7fd1a60b01f91b314f59955a4e4d4e80d8edf11d
    --scope 1
    --model gpt-5.6-sol
    --reasoning-effort max
    --context long_context
    --security-scans 1
    --workspace-root "${fixture_root}/codex-e2e-refusal-workspace"
    --output-root "${fixture_root}/codex-e2e-refusal-output"
    --non-interactive
    --no-open-html
)
"${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_refusal_arguments[@]}" --plan-only \
    > "${fixture_root}/codex-e2e-refusal-plan.json" \
    2> "${fixture_root}/codex-e2e-refusal-plan.stderr" || {
        cat -- "${fixture_root}/codex-e2e-refusal-plan.stderr" >&2
        fail 'Codex end-to-end refusal plan failed.'
    }
if "${codex_e2e_environment[@]}" "${codex_e2e_runner}" \
    "${codex_e2e_refusal_arguments[@]}" \
    --expected-plan-hash "$(contract_plan_hash "${fixture_root}/codex-e2e-refusal-plan.json")" \
    > "${fixture_root}/codex-e2e-refusal.stdout" \
    2> "${fixture_root}/codex-e2e-refusal.stderr"; then
    fail 'Codex end-to-end refusal fixture unexpectedly completed.'
fi
rm -f -- "${codex_e2e_bin}/refusal-mode"
assert_contains "${fixture_root}/codex-e2e-refusal.stdout" \
    'allows no additional security scan models' \
    'Codex provider refusal remediation'
assert_not_contains "${fixture_root}/codex-e2e-refusal.stdout" \
    'Approve a plan that adds security scan models' \
    'Codex provider refusal remediation'
node - "$(contract_run_path "${fixture_root}/codex-e2e-refusal.stdout")" <<'JS'
const fs = require("fs"), path = require("path");
const repo = path.join(process.argv[2], "github--octocat--hello-world");
const state = JSON.parse(fs.readFileSync(path.join(repo, "state.json"), "utf8"));
const analysis = JSON.parse(fs.readFileSync(path.join(repo, "failure-analysis.json"), "utf8"));
const actions = analysis.RecommendedActions.join("\n");
const events = (state.ProviderRefusals || {}).Events || [];
if (state.Status !== "ReviewFailed" || analysis.Stage !== "provider refusal" ||
    events.length !== 1 || events[0].Model !== "gpt-5.6-sol" ||
    !actions.includes("allows no additional security scan models") ||
    actions.includes("Approve a plan that adds security scan models") ||
    state.WorkerRecovery.Continuations !== 0) {
  throw new Error(`a Codex provider refusal was not reported with a Codex remediation: ${state.Status}, ${analysis.Stage}\n${actions}`);
}
JS
[[ -z "$(find "${codex_e2e_tmp}" -mindepth 1 -maxdepth 1 -print -quit)" &&
    -z "$(find "$(contract_run_path "${fixture_root}/codex-e2e-refusal.stdout")" \
        -name '*.codex-final' -print -quit)" ]] ||
    fail 'Codex refusal left a runtime home, broker runtime, or final-message file.'
unset CODEX_HOME FIXTURE_CODEX_KEY
printf 'Codex adapter contract validation passed.\n'
