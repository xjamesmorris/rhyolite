#!/usr/bin/env bash
# Codex adapter section of the focused harness contract validator.
# Production common.sh intentionally remains a two-entry registry.

CODEX_HARNESS="${PLUGIN_ROOT}/lib/harness/codex.sh"
CODEX_PLUGIN_MANIFEST="${PLUGIN_ROOT}/.codex-plugin/plugin.json"
CODEX_SETUP_SKILL="${PLUGIN_ROOT}/codex/skills/repo-review-setup/SKILL.md"
CODEX_APPROVAL_SKILL="${PLUGIN_ROOT}/codex/skills/repo-review-approval/SKILL.md"
CODEX_GUIDED_STAGE="${PLUGIN_ROOT}/scripts/run-codex-guided-stage.sh"
for path in \
    "${CODEX_HARNESS}" \
    "${CODEX_PLUGIN_MANIFEST}" \
    "${CODEX_SETUP_SKILL}" \
    "${CODEX_APPROVAL_SKILL}" \
    "${CODEX_GUIDED_STAGE}"; do
    [[ -f "${path}" ]] || fail "Required unregistered Codex asset is missing: ${path}"
done
bash -n "${CODEX_HARNESS}" ||
    fail 'Codex adapter has a Bash syntax error.'
bash -n "${CODEX_GUIDED_STAGE}" ||
    fail 'Codex guided-stage helper has a Bash syntax error.'
[[ -x "${CODEX_GUIDED_STAGE}" ]] ||
    fail 'Codex guided-stage helper is not executable.'
[[ "$(grep -Fc -- '-c features.plugins=true' "${CODEX_GUIDED_STAGE}")" == 3 &&
    "$(grep -Fc -- "-c 'plugins._default.enabled=true'" "${CODEX_GUIDED_STAGE}")" == 2 ]] ||
    fail 'Codex guided-stage plugin management or launch lost explicit enable overrides.'
[[ ! -e "${ROOT}/.agents/plugins/marketplace.json" ]] ||
    fail 'Codex marketplace registration was exposed before production enablement.'
node - "${CODEX_PLUGIN_MANIFEST}" "${ROOT}/VERSION" <<'JS'
const fs = require("fs");
const manifest = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const version = fs.readFileSync(process.argv[3], "utf8").trim();
if (manifest.name !== "rhyolite" || manifest.version !== version ||
    JSON.stringify(manifest.skills) !== JSON.stringify(["./codex/skills"]) ||
    "mcpServers" in manifest || "hooks" in manifest || "apps" in manifest) {
  throw new Error("unregistered Codex plugin manifest changed");
}
JS
for skill in "${CODEX_SETUP_SKILL}" "${CODEX_APPROVAL_SKILL}"; do
    grep -Fq 'request_user_input' "${skill}" ||
        fail "Codex guided skill lost native question instructions: ${skill}"
    ! grep -Eqi 'Bash\(|shell tool|execute the runner' "${skill}" ||
        fail "Codex guided skill gained shell authority: ${skill}"
done

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
if [[ "${1-}" == plugin ]]; then
    printf '%s\n' '{}'
    exit 0
fi
if [[ "${RHYOLITE_CODEX_REQUIRE_TTY:-0}" == 1 ]]; then
    [[ -t 0 && -t 1 ]] || {
        printf '%s\n' 'Native Codex stage lost its terminal.' >&2
        exit 2
    }
fi
prompt="${!#}"
case "${prompt}" in
    *'$rhyolite:repo-review-setup'*)
        native_stage=setup
        final='{"Protocol":"RHYOLITE_CODEX_SETUP_V1","Action":"continue","OutputRoot":"/tmp/rhyolite-output","Scope":1,"ProvenanceLookbackMonths":null,"ResearchCookies":null}'
        ;;
    *'$rhyolite:repo-review-approval'*)
        native_stage=approval
        approval_hash="$(
            grep -Eo '[0-9a-f]{64}' <<< "${prompt}" | head -n 1
        )"
        [[ -n "${approval_hash}" ]]
        final="{\"Protocol\":\"RHYOLITE_CODEX_APPROVAL_V1\",\"Action\":\"run\",\"ApprovalHash\":\"${approval_hash}\"}"
        ;;
    *)
        exit 2
        ;;
esac
final="${RHYOLITE_CODEX_FAKE_FINAL:-${final}}"
native_tool="${RHYOLITE_CODEX_FAKE_TOOL:-request_user_input}"
# A real model's interactive session records its reasoning as a completed item.
native_item="${RHYOLITE_CODEX_FAKE_ITEM:-Reasoning}"
if [[ "${RHYOLITE_CODEX_REQUIRE_TTY:-0}" == 1 ]]; then
    printf 'RHYOLITE_CODEX_NATIVE_UI %s TERM=%s\n' "${native_stage}" "${TERM-}"
fi
escaped_final="${final//\\/\\\\}"
escaped_final="${escaped_final//\"/\\\"}"
session_id='00000000-0000-4000-8000-000000000044'
session_dir="${CODEX_HOME}/sessions/2026/10/21"
mkdir -p -- "${session_dir}"
cat > "${session_dir}/rollout.jsonl" <<EOF
{"type":"session_meta","payload":{"session_id":"${session_id}","id":"${session_id}","originator":"codex_cli","cli_version":"0.163.0","source":"cli"}}
{"type":"event_msg","payload":{"type":"task_started","model_context_window":828400}}
{"type":"turn_context","payload":{"approval_policy":"never","sandbox_policy":{"type":"read-only"},"model":"gpt-5.6-sol","effort":"max","multi_agent_version":"disabled","collaboration_mode":{"mode":"default","settings":{"model":"gpt-5.6-sol","reasoning_effort":"max"}}}}
{"type":"event_msg","payload":{"type":"item_completed","thread_id":"${session_id}","turn_id":"fixture-turn","item":{"type":"${native_item}","id":"fixture-item","summary_text":[],"raw_content":[]}}}
{"type":"response_item","payload":{"type":"function_call","name":"${native_tool}","arguments":"{}","call_id":"fixture-call"}}
{"type":"response_item","payload":{"type":"message","role":"assistant","phase":"final_answer","content":[{"type":"output_text","text":"${escaped_final}"}]}}
EOF
exit 0
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
    builtin_research_specialist final_message_file; do
    assert_equal yes "$(harness_capability "${capability}")" \
        "Codex ${capability} capability"
done
for capability in subagents builtin_security_specialist; do
    assert_equal no "$(harness_capability "${capability}")" \
        "Codex ${capability} capability"
done
assert_equal unverified "$(harness_capability worker_continuation)" \
    'Codex continuation remains gated on an adapter-built live probe'
assert_equal local-stdio-mcp-snapshot-read-v1 \
    "$(harness_snapshot_transport)" 'Codex snapshot transport'
harness_prepare_run >/dev/null ||
    fail 'Codex run preparation failed with fixture authentication.'
harness_prepare_worker_home \
    "${codex_runtime}" max long_context review ||
    fail 'Codex review runtime preparation failed.'
[[ "$(stat -c '%a' "${codex_runtime}/config.toml")" == 600 ]] ||
    fail 'Codex runtime config is not private.'
[[ "$(stat -c '%a' "${codex_runtime}/model-catalog.json")" == 600 ]] ||
    fail 'Codex runtime model catalog is not private.'
python3 -I - \
    "${codex_runtime}/config.toml" \
    "${codex_runtime}/model-catalog.json" <<'PY'
import json
import sys
import tomllib

with open(sys.argv[1], "rb") as stream:
    config = tomllib.load(stream)
with open(sys.argv[2], encoding="utf-8") as stream:
    catalog = json.load(stream)
provider = config["model_providers"]["fixture-provider"]
assert config["model_catalog_json"] == sys.argv[2]
assert config["model_reasoning_effort"] == "max"
assert config["model_context_window"] == 872000
assert config["model_auto_compact_token_limit"] == 784800
assert config["approval_policy"] == "never"
assert config["sandbox_mode"] == "read-only"
assert config["web_search"] == "disabled"
assert config["agents"]["enabled"] is False
for feature in (
    "shell_tool", "unified_exec", "multi_agent", "multi_agent_v2",
    "plugins", "plugin_hooks", "worktrees", "daemon_auto_start",
):
    assert config["features"][feature] is False
assert provider["base_url"] == "https://fixture.example.org/v1"
assert provider["env_key"] == "FIXTURE_CODEX_KEY"
assert provider["request_max_retries"] == 0
assert provider["stream_max_retries"] == 0
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
harness_prepare_worker_home \
    "${codex_research_runtime}" max long_context research ||
    fail 'Codex research runtime preparation failed.'
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
codex_research_tools_json='["research_capabilities", "fetch_public_url", "search_public_github", "search_public_web", "research_network_summary"]'
harness_write_research_mcp_config \
    "${codex_research_config}" \
    "${codex_research_launcher}" \
    codex_research_broker_arguments \
    "${codex_research_tools_json}" ||
    fail 'Codex research MCP configuration failed.'
declare -a codex_research_argv=()
declare -a codex_research_env=()
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

codex_reroute_raw="${fixture_root}/codex-reroute.raw"
cat > "${codex_reroute_raw}" <<EOF
{"type":"thread.started","thread_id":"${codex_native_id}"}
{"type":"item.completed","item":{"id":"item-1","type":"error","message":"model rerouted: gpt-5.6-sol -> fixture-other (FixtureReason)"}}
{"type":"item.completed","item":{"id":"item-2","type":"agent_message","text":"EXACT_CODEX_FIXTURE_REPLY"}}
{"type":"turn.completed","usage":{"input_tokens":1,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":1,"reasoning_output_tokens":0}}
EOF
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

harness_allow_all_detected &&
    fail 'Codex inherited an allow-all signal.'

codex_guided_work="${fixture_root}/codex-guided-work"
mkdir -- "${codex_guided_work}"
# Run one command with a pseudo-terminal on stdin and stderr, where the
# native Codex questions appear, its stdout in the first named file, and the
# terminal output in the second.
codex_run_with_terminal() {
    local stdout_path="$1"
    local terminal_path="$2"
    shift 2
    python3 -I - "${stdout_path}" "${terminal_path}" "$@" <<'PY'
import errno
import os
import pty
import subprocess
import sys

stdout_path, terminal_path, command = sys.argv[1], sys.argv[2], sys.argv[3:]
master, slave = pty.openpty()
with open(stdout_path, "wb") as stdout:
    process = subprocess.Popen(
        command, stdin=slave, stdout=stdout, stderr=slave,
        start_new_session=True,
    )
    status = process.wait(timeout=60)
os.close(slave)
terminal = bytearray()
while True:
    try:
        chunk = os.read(master, 65536)
    except OSError as error:
        if error.errno != errno.EIO:
            raise
        break
    if not chunk:
        break
    terminal.extend(chunk)
os.close(master)
with open(terminal_path, "wb") as output:
    output.write(bytes(terminal))
sys.exit(status)
PY
}
codex_setup_input="${fixture_root}/codex-setup-input.txt"
cat > "${codex_setup_input}" <<'SETUP_INPUT'
RHYOLITE_CODEX_SETUP_INPUT_V1
CurrentDirectoryOutput=/tmp/current/rhyolite-output/repo-review
HomeDirectoryOutput=/tmp/home/rhyolite-output/repo-review
CurrentOutput=NOT SELECTED
CurrentScope=NOT SELECTED
CurrentProvenanceLookbackMonths=NOT SELECTED
CurrentResearchCookies=NOT SELECTED
END_RHYOLITE_CODEX_SETUP_INPUT_V1
SETUP_INPUT
codex_setup_result="${fixture_root}/codex-setup-result.json"
if "${CODEX_GUIDED_STAGE}" \
    --stage setup \
    --plugin-root "${PLUGIN_ROOT}" \
    --working-directory "${codex_guided_work}" \
    --input "${codex_setup_input}" \
    --result "${codex_setup_result}" \
    --model gpt-5.6-sol \
    --reasoning-effort max \
    --context long_context \
    < /dev/null > /dev/null 2> "${fixture_root}/codex-stage-no-terminal.stderr"; then
    fail 'Codex guided setup ran without a terminal.'
fi
assert_contains "${fixture_root}/codex-stage-no-terminal.stderr" \
    'Codex guided stage failed: terminal' 'Codex guided stage terminal check'
[[ ! -e "${codex_setup_result}" ]] ||
    fail 'Codex guided setup wrote a result without a terminal.'
codex_run_with_terminal "${fixture_root}/codex-setup.stdout" \
    "${fixture_root}/codex-setup.terminal" \
    "${CODEX_GUIDED_STAGE}" \
    --stage setup \
    --plugin-root "${PLUGIN_ROOT}" \
    --working-directory "${codex_guided_work}" \
    --input "${codex_setup_input}" \
    --result "${codex_setup_result}" \
    --model gpt-5.6-sol \
    --reasoning-effort max \
    --context long_context ||
    fail 'Codex guided setup helper failed with the fixture CLI.'
node - "${codex_setup_result}" <<'JS'
const fs = require("fs");
const value = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (value.Protocol !== "RHYOLITE_CODEX_SETUP_V1" ||
    value.Action !== "continue" ||
    value.OutputRoot !== "/tmp/rhyolite-output" ||
    value.Scope !== 1 ||
    value.ProvenanceLookbackMonths !== null ||
    value.ResearchCookies !== null) {
  throw new Error("Codex guided setup result changed");
}
JS
codex_approval_hash="$(printf 'a%.0s' {1..64})"
codex_approval_input="${fixture_root}/codex-approval-input.txt"
cat > "${codex_approval_input}" <<EOF
RHYOLITE_CODEX_APPROVAL_INPUT_V1
ApprovalHash=${codex_approval_hash}
END_RHYOLITE_CODEX_APPROVAL_INPUT_V1
EOF
codex_approval_result="${fixture_root}/codex-approval-result.json"
codex_run_with_terminal "${fixture_root}/codex-approval.stdout" \
    "${fixture_root}/codex-approval.terminal" \
    "${CODEX_GUIDED_STAGE}" \
    --stage approval \
    --plugin-root "${PLUGIN_ROOT}" \
    --working-directory "${codex_guided_work}" \
    --input "${codex_approval_input}" \
    --result "${codex_approval_result}" \
    --model gpt-5.6-sol \
    --reasoning-effort max \
    --context long_context ||
    fail 'Codex guided approval helper failed with the fixture CLI.'
node - "${codex_approval_result}" "${codex_approval_hash}" <<'JS'
const fs = require("fs");
const value = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (value.Protocol !== "RHYOLITE_CODEX_APPROVAL_V1" ||
    value.Action !== "run" ||
    value.ApprovalHash !== process.argv[3]) {
  throw new Error("Codex guided approval result changed");
}
JS
# A native reply outside the strict stage contract, or any tool other than
# the native question tool, writes no result.
codex_invalid_stage_case() {
    local name="$1"
    local stage="$2"
    local input="$3"
    local final="$4"
    local tool="$5"
    local item="${6:-Reasoning}"
    local detail="${7-}"
    local result="${fixture_root}/codex-invalid-${name}.json"

    if RHYOLITE_CODEX_FAKE_FINAL="${final}" RHYOLITE_CODEX_FAKE_TOOL="${tool}" \
        RHYOLITE_CODEX_FAKE_ITEM="${item}" \
        codex_run_with_terminal "${fixture_root}/codex-invalid-${name}.stdout" \
        "${fixture_root}/codex-invalid-${name}.terminal" \
        "${CODEX_GUIDED_STAGE}" \
        --stage "${stage}" \
        --plugin-root "${PLUGIN_ROOT}" \
        --working-directory "${codex_guided_work}" \
        --input "${input}" \
        --result "${result}" \
        --model gpt-5.6-sol \
        --reasoning-effort max \
        --context long_context; then
        fail "Codex guided stage accepted the invalid ${name} reply."
    fi
    assert_contains "${fixture_root}/codex-invalid-${name}.terminal" \
        "Codex guided stage failed: result${detail:+ (${detail})}" \
        "Codex invalid ${name} reply"
    [[ ! -e "${result}" ]] ||
        fail "Codex guided stage wrote a result for the invalid ${name} reply."
    if [[ -n "${detail}" ]]; then
        assert_equal "result: ${detail}" "$(cat -- "${result%.json}.failure")" \
            "Codex invalid ${name} failure record"
    fi
}
codex_invalid_stage_case setup-scope setup "${codex_setup_input}" \
    '{"Protocol":"RHYOLITE_CODEX_SETUP_V1","Action":"continue","OutputRoot":"/tmp/rhyolite-output","Scope":4,"ProvenanceLookbackMonths":null,"ResearchCookies":null}' \
    request_user_input
codex_invalid_stage_case setup-extra setup "${codex_setup_input}" \
    '{"Protocol":"RHYOLITE_CODEX_SETUP_V1","Action":"continue","OutputRoot":"/tmp/rhyolite-output","Scope":1,"ProvenanceLookbackMonths":null,"ResearchCookies":null,"Shell":"allowed"}' \
    request_user_input
codex_invalid_stage_case setup-tool setup "${codex_setup_input}" '' shell \
    Reasoning 'unexpected tool call shell'
codex_invalid_stage_case setup-command-item setup "${codex_setup_input}" '' \
    request_user_input CommandExecution 'unexpected completed item CommandExecution'
codex_invalid_stage_case approval-action approval "${codex_approval_input}" \
    "{\"Protocol\":\"RHYOLITE_CODEX_APPROVAL_V1\",\"Action\":\"execute\",\"ApprovalHash\":\"${codex_approval_hash}\"}" \
    request_user_input

codex_controller_plugin="${fixture_root}/codex-controller-plugin"
codex_controller_session="${fixture_root}/codex-controller-session"
codex_controller_work="${fixture_root}/codex-controller-work"
codex_controller_output="${fixture_root}/codex-controller-output"
codex_controller_capture="${fixture_root}/codex-controller-capture"
mkdir -p -- \
    "${codex_controller_plugin}/scripts" \
    "${codex_controller_plugin}/skills/readonly-repository-review/scripts" \
    "${codex_controller_session}" \
    "${codex_controller_work}" \
    "${codex_controller_output}" \
    "${codex_controller_capture}"
cp -- "${PLUGIN_ROOT}/scripts/run-codex-guided-review.sh" \
    "${codex_controller_plugin}/scripts/"
cat > "${codex_controller_plugin}/scripts/run-codex-guided-stage.sh" <<'CODEX_STAGE_FIXTURE'
#!/usr/bin/env bash
set -euo pipefail
stage=''
result=''
while (($# > 0)); do
    case "$1" in
        --stage) stage="$2"; shift 2 ;;
        --result) result="$2"; shift 2 ;;
        *) shift ;;
    esac
done
case "${stage}" in
    setup)
        printf '%s\n' \
            '{"Action":"continue","OutputRoot":"'"${RHYOLITE_CODEX_CONTROLLER_OUTPUT:?}"'","Protocol":"RHYOLITE_CODEX_SETUP_V1","ProvenanceLookbackMonths":null,"ResearchCookies":null,"Scope":1}' \
            > "${result}"
        ;;
    approval)
        hash="$(
            grep -h -Eo '[0-9a-f]{64}' "${RHYOLITE_CODEX_CONTROLLER_SESSION:?}"/codex-approval-*.txt |
                tail -n 1
        )"
        printf '{"Action":"run","ApprovalHash":"%s","Protocol":"RHYOLITE_CODEX_APPROVAL_V1"}\n' \
            "${hash}" > "${result}"
        ;;
    *) exit 2 ;;
esac
chmod 600 -- "${result}"
CODEX_STAGE_FIXTURE
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
        '{"ApprovalHash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","Harness":"codex","Model":"gpt-5.6-sol","ReasoningEffort":"max","ContextTier":"long_context","Scope":1}'
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
    "${codex_controller_plugin}/scripts/run-codex-guided-stage.sh" \
    "${codex_controller_plugin}/scripts/run-codex-guided-review.sh" \
    "${codex_controller_plugin}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh"
RHYOLITE_CODEX_CONTROLLER_OUTPUT="${codex_controller_output}" \
RHYOLITE_CODEX_CONTROLLER_SESSION="${codex_controller_session}" \
RHYOLITE_CODEX_CONTROLLER_CAPTURE="${codex_controller_capture}" \
HOME="${fixture_root}/codex-controller-home" \
"${codex_controller_plugin}/scripts/run-codex-guided-review.sh" \
    --plugin-root "${codex_controller_plugin}" \
    --working-directory "${codex_controller_work}" \
    --session-directory "${codex_controller_session}" \
    --model gpt-5.6-sol \
    --reasoning-effort max \
    --context long_context \
    --repo https://github.com/octocat/Hello-World \
    > "${fixture_root}/codex-controller.stdout" \
    2> "${fixture_root}/codex-controller.stderr" ||
    fail 'Codex guided review controller failed with fixture stages.'
assert_contains "${fixture_root}/codex-controller.stdout" \
    'EFFECTIVE REVIEW PLAN' 'Codex controller plan display'
assert_contains "${fixture_root}/codex-controller.stdout" \
    '/tmp/rhyolite-controller-run' 'Codex controller execution output'
[[ -z "$(cat "${fixture_root}/codex-controller.stderr")" ]] ||
    fail 'Codex guided review controller emitted fixture errors.'
controller_call_count="$(
    find "${codex_controller_capture}" -type f -name 'call-*.nul' | wc -l
)"
[[ "${controller_call_count//[[:space:]]/}" == 2 ]] ||
    fail 'Codex guided controller did not invoke one plan and one execution.'
python3 -I - "${codex_controller_capture}" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
calls = []
for path in sorted(root.glob("call-*.nul")):
    raw = path.read_bytes().split(b"\0")
    calls.append([item.decode() for item in raw if item])
assert len(calls) == 2
plan, run = calls
assert "--plan-only" in plan and "--expected-plan-hash" not in plan
assert "--plan-only" not in run
assert run[run.index("--expected-plan-hash") + 1] == "a" * 64
assert "--fleet-mode" not in plan and "--commit" not in plan
assert plan[plan.index("--security-scans") + 1] == "1"
for expected in (
    "--harness", "codex", "--security-scans", "1",
    "--model", "gpt-5.6-sol", "--reasoning-effort", "max",
    "--context", "long_context", "--scope", "1",
    "--non-interactive", "--no-open-html",
    "--repo", "https://github.com/octocat/Hello-World",
):
    assert expected in plan and expected in run
PY

codex_auto_session="${fixture_root}/codex-controller-auto-session"
codex_auto_capture="${fixture_root}/codex-controller-auto-capture"
codex_auto_commit="$(printf 'b%.0s' {1..40})"
mkdir -p -- "${codex_auto_session}" "${codex_auto_capture}"
RHYOLITE_CODEX_CONTROLLER_OUTPUT="${codex_controller_output}" \
RHYOLITE_CODEX_CONTROLLER_SESSION="${codex_auto_session}" \
RHYOLITE_CODEX_CONTROLLER_CAPTURE="${codex_auto_capture}" \
HOME="${fixture_root}/codex-controller-home" \
"${codex_controller_plugin}/scripts/run-codex-guided-review.sh" \
    --plugin-root "${codex_controller_plugin}" \
    --working-directory "${codex_controller_work}" \
    --session-directory "${codex_auto_session}" \
    --model gpt-5.6-sol \
    --reasoning-effort max \
    --context long_context \
    --repo https://github.com/octocat/Hello-World \
    --commit "${codex_auto_commit}" \
    --auto-defaults \
    > "${fixture_root}/codex-controller-auto.stdout" \
    2> "${fixture_root}/codex-controller-auto.stderr" ||
    fail 'Codex guided controller failed with --auto-defaults.'
[[ -z "$(find "${codex_auto_session}" -name 'codex-setup-*' -print -quit)" &&
    -n "$(find "${codex_auto_session}" -name 'codex-approval-*.json' -print -quit)" ]] ||
    fail 'Codex --auto-defaults did not skip only the setup questions.'
python3 -I - "${codex_auto_capture}" "${fixture_root}/codex-controller-home" \
    "${codex_auto_commit}" <<'PY'
import pathlib
import sys

root, home, commit = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
calls = [
    [item.decode() for item in path.read_bytes().split(b"\0") if item]
    for path in sorted(root.glob("call-*.nul"))
]
assert len(calls) == 2
for call in calls:
    assert call[call.index("--commit") + 1] == commit
    assert call[call.index("--scope") + 1] == "1"
    assert call[call.index("--output-root") + 1] == f"{home}/rhyolite-output/repo-review"
PY
if "${codex_controller_plugin}/scripts/run-codex-guided-review.sh" \
    --plugin-root "${codex_controller_plugin}" \
    --working-directory "${codex_controller_work}" \
    --session-directory "${codex_auto_session}" \
    --model gpt-5.6-sol \
    --reasoning-effort max \
    --context long_context \
    --repo https://github.com/octocat/Hello-World \
    --repo https://github.com/octocat/Spoon-Knife \
    --commit "${codex_auto_commit}" \
    >/dev/null 2>&1; then
    fail 'Codex guided controller pinned one commit for several repositories.'
fi

# A plan mismatch keeps the setup answers: the controller regenerates the
# plan and asks only for approval again.
codex_mismatch_session="${fixture_root}/codex-controller-mismatch-session"
codex_mismatch_capture="${fixture_root}/codex-controller-mismatch-capture"
mkdir -p -- "${codex_mismatch_session}" "${codex_mismatch_capture}"
RHYOLITE_CODEX_CONTROLLER_OUTPUT="${codex_controller_output}" \
RHYOLITE_CODEX_CONTROLLER_SESSION="${codex_mismatch_session}" \
RHYOLITE_CODEX_CONTROLLER_CAPTURE="${codex_mismatch_capture}" \
RHYOLITE_CODEX_CONTROLLER_MODE=mismatch \
HOME="${fixture_root}/codex-controller-home" \
"${codex_controller_plugin}/scripts/run-codex-guided-review.sh" \
    --plugin-root "${codex_controller_plugin}" \
    --working-directory "${codex_controller_work}" \
    --session-directory "${codex_mismatch_session}" \
    --model gpt-5.6-sol \
    --reasoning-effort max \
    --context long_context \
    --repo https://github.com/octocat/Hello-World \
    > "${fixture_root}/codex-controller-mismatch.stdout" \
    2> "${fixture_root}/codex-controller-mismatch.stderr" ||
    fail 'Codex guided controller did not recover from a plan mismatch.'
assert_contains "${fixture_root}/codex-controller-mismatch.stderr" \
    'regenerating it with the preserved setup' 'Codex plan mismatch notice'
[[ "$(find "${codex_mismatch_session}" -name 'codex-setup-*.json' | wc -l)" == 1 &&
    "$(find "${codex_mismatch_session}" -name 'codex-approval-*.json' | wc -l)" == 2 &&
    "$(find "${codex_mismatch_capture}" -name 'call-*.nul' | wc -l)" == 4 ]] ||
    fail 'Codex plan mismatch did not regenerate the plan from preserved setup answers.'

codex_controller_stop_session="${fixture_root}/codex-controller-stop-session"
codex_controller_stop_capture="${fixture_root}/codex-controller-stop-capture"
mkdir -p -- "${codex_controller_stop_session}" "${codex_controller_stop_capture}"
(
    sleep 1
    printf '%s\n' '/rhyolite:status'
    sleep 1
    printf '%s\n' stop
) |
RHYOLITE_CODEX_CONTROLLER_OUTPUT="${codex_controller_output}" \
RHYOLITE_CODEX_CONTROLLER_SESSION="${codex_controller_stop_session}" \
RHYOLITE_CODEX_CONTROLLER_CAPTURE="${codex_controller_stop_capture}" \
RHYOLITE_CODEX_CONTROLLER_MODE=stop \
HOME="${fixture_root}/codex-controller-home" \
"${codex_controller_plugin}/scripts/run-codex-guided-review.sh" \
    --plugin-root "${codex_controller_plugin}" \
    --working-directory "${codex_controller_work}" \
    --session-directory "${codex_controller_stop_session}" \
    --model gpt-5.6-sol \
    --reasoning-effort max \
    --context long_context \
    --repo https://github.com/octocat/Hello-World \
    > "${fixture_root}/codex-controller-stop.stdout" \
    2> "${fixture_root}/codex-controller-stop.stderr" || {
        cat -- \
            "${fixture_root}/codex-controller-stop.stdout" \
            "${fixture_root}/codex-controller-stop.stderr" >&2
        find "${codex_controller_stop_capture}" -maxdepth 2 -type f \
            -printf '%P\n' >&2 || true
        fail 'Codex guided controller did not treat exact stop as a clean terminal state.'
    }
[[ -f "${codex_controller_stop_capture}/stop-called" ]] ||
    fail 'Codex guided controller did not invoke the trusted request-stop path.'
assert_contains "${fixture_root}/codex-controller-stop.stdout" \
    'RHYOLITE STATUS' 'Codex controller status command'
assert_contains "${fixture_root}/codex-controller-stop.stderr" \
    'Rhyolite review stopped.' 'Codex controller stopped state'

cp -- "${CODEX_GUIDED_STAGE}" \
    "${codex_controller_plugin}/scripts/run-codex-guided-stage.sh"
mkdir -p -- "${codex_controller_plugin}/lib/harness"
cp -- "${HARNESS_COMMON}" "${CODEX_HARNESS}" \
    "${codex_controller_plugin}/lib/harness/"
cp -a -- "${PLUGIN_ROOT}/.codex-plugin" "${PLUGIN_ROOT}/codex" \
    "${codex_controller_plugin}/"
python3 -I - "${codex_controller_plugin}" "${fixture_root}" <<'PY'
import errno
import os
import pathlib
import pty
import signal
import subprocess
import sys

plugin = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
session = root / "codex-controller-terminal-session"
capture = root / "codex-controller-terminal-capture"
temporary = session / "tmp"
for path in (session, capture, temporary):
    path.mkdir(mode=0o700)
environment = dict(
    os.environ,
    RHYOLITE_CODEX_REQUIRE_TTY="1",
    TERM="dumb",
    RHYOLITE_CODEX_CONTROLLER_SESSION=str(session),
    RHYOLITE_CODEX_CONTROLLER_CAPTURE=str(capture),
    TMPDIR=str(temporary),
)
master, slave = pty.openpty()
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
try:
    stdout, _ = process.communicate(timeout=30)
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
    os.close(slave)
terminal = bytearray()
try:
    while True:
        try:
            chunk = os.read(master, 65536)
        except OSError as error:
            if error.errno != errno.EIO:
                raise
            break
        if not chunk:
            break
        terminal.extend(chunk)
finally:
    os.close(master)
assert process.returncode == 0, terminal.decode("utf-8", errors="replace")
for stage in ("setup", "approval"):
    marker = f"RHYOLITE_CODEX_NATIVE_UI {stage}".encode()
    assert marker in terminal, f"{stage} UI did not reach the terminal"
    assert f"{stage} TERM=xterm-256color".encode() in terminal, \
        f"{stage} UI kept the worker terminal type"
    assert marker not in stdout, f"{stage} UI contaminated controller stdout"
assert b"EFFECTIVE REVIEW PLAN" in stdout
assert b"/tmp/rhyolite-controller-run" in stdout
assert b"codex-setup-1.json" not in stdout
assert b"codex-approval-1.json" not in stdout
assert (session / "codex-setup-1.json").is_file()
assert (session / "codex-approval-1.json").is_file()
assert len(list(capture.glob("call-*.nul"))) == 2
assert not list(temporary.iterdir()), "guided-stage runtime was not removed"
PY

codex_launcher_plugin="${fixture_root}/codex-launcher-plugin"
codex_launcher_caller="${fixture_root}/codex-launcher-caller"
codex_launcher_state="${fixture_root}/codex-launcher-state"
codex_launcher_capture="${fixture_root}/codex-launcher.capture"
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
printf '%s\0' "$@" > "${RHYOLITE_CODEX_LAUNCHER_CAPTURE:?}"
CODEX_LAUNCHER_CONTROLLER
chmod 700 -- "${codex_launcher_plugin}/scripts/run-codex-guided-review.sh"
(
    cd -- "${codex_launcher_caller}"
    env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
        HOME="${fixture_root}/codex-launcher-home" \
        CODEX_HOME="${codex_home}" \
        FIXTURE_CODEX_KEY='fixture-secret-value' \
        XDG_STATE_HOME="${codex_launcher_state}" \
        RHYOLITE_CODEX_LAUNCHER_CAPTURE="${codex_launcher_capture}" \
        PATH="${codex_fake_bin}:/usr/bin:/bin" \
        "${codex_launcher_plugin}/bin/rhyolite" \
        --harness codex \
        --repo https://github.com/octocat/Hello-World \
        --fleet-mode standard \
        --model gpt-5.6-sol \
        --reasoning-effort max \
        --context long_context
) > "${fixture_root}/codex-launcher.stdout" \
    2> "${fixture_root}/codex-launcher.stderr" ||
    fail 'Staged Codex launcher branch failed.'
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
assert_not_contains "${fixture_root}/codex-launcher.stderr" \
    'RHYOLITE ERROR' 'Staged Codex launcher error output'
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
        PATH="${codex_fake_bin}:/usr/bin:/bin" \
        "${codex_launcher_plugin}/bin/rhyolite" \
        --harness codex \
        --repo https://github.com/octocat/Hello-World \
        --commit "${codex_launcher_commit}" \
        --auto-defaults
) > "${fixture_root}/codex-launcher-auto.stdout" \
    2> "${fixture_root}/codex-launcher-auto.stderr" ||
    fail 'Staged Codex launcher failed with --auto-defaults.'
python3 -I - "${codex_launcher_capture}" "${codex_launcher_commit}" <<'PY'
import pathlib
import sys

args = [item.decode() for item in pathlib.Path(sys.argv[1]).read_bytes().split(b"\0") if item]
assert args[args.index("--commit") + 1] == sys.argv[2]
assert "--auto-defaults" in args
assert args[args.index("--model") + 1] == "gpt-5.6-sol"
PY
rm -f -- "${codex_launcher_capture}"
if (
    cd -- "${codex_launcher_caller}"
    env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
        HOME="${fixture_root}/codex-launcher-home" \
        CODEX_HOME="${codex_home}" \
        FIXTURE_CODEX_KEY='fixture-secret-value' \
        XDG_STATE_HOME="${codex_launcher_state}" \
        RHYOLITE_CODEX_LAUNCHER_CAPTURE="${codex_launcher_capture}" \
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
unset CODEX_HOME FIXTURE_CODEX_KEY
printf 'Codex unregistered adapter contract validation passed.\n'
