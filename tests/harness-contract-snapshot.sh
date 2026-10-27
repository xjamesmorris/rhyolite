#!/usr/bin/env bash

# Sourced by the focused contract suite after its ordinary no-op scenarios.
# It stages a literal test registry; production keeps Codex/noop unregistered.

snapshot_test_plugin="${fixture_root}/snapshot-test-plugin"
cp -a -- "${noop_test_plugin}" "${snapshot_test_plugin}"
snapshot_test_scripts="${snapshot_test_plugin}/skills/readonly-repository-review/scripts"
cp -- "${PLUGIN_ROOT}/skills/readonly-repository-review/scripts/research-egress-broker.py" \
    "${PLUGIN_ROOT}/skills/readonly-repository-review/scripts/launch-snapshot-read-broker.sh" \
    "${snapshot_test_scripts}/"
cat >> "${snapshot_test_plugin}/lib/harness/noop.sh" <<'SNAPSHOT_TEST_ADAPTER'

harness_snapshot_transport() {
    printf '%s\n' local-stdio-mcp-snapshot-read-v1
}

harness_configure_snapshot_transport() {
    local phase="$1" destination_name="$2" runtime_home="$3" config="$4"
    local launcher="$5" arguments_name="$6" tools_json="$7"
    local -n approved_arguments="${destination_name}"
    local -n broker_arguments="${arguments_name}"
    [[ "${phase}" == review && -d "${runtime_home}" ]] || return 1
    [[ -z "${RHYOLITE_SNAPSHOT_TEST_CONFIG_FAIL-}" ]] || {
        rhyolite_harness_set_error 'Development snapshot fixture refused configuration.'
        return 1
    }
    python3 -I - "${config}" "${launcher}" "${tools_json}" "${broker_arguments[@]}" <<'PY'
import json
import os
import sys

descriptor = os.open(sys.argv[1], os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
with os.fdopen(descriptor, "w", encoding="utf-8") as output:
    json.dump({"Command": sys.argv[2], "Tools": json.loads(sys.argv[3]),
               "Arguments": sys.argv[4:]}, output)
PY
    approved_arguments+=(--snapshot-mcp-config "${config}")
}
SNAPSHOT_TEST_ADAPTER

snapshot_runner="${snapshot_test_scripts}/run-parallel-reviews.sh"
snapshot_workspace="${fixture_root}/snapshot-workspace"
snapshot_output="${fixture_root}/snapshot-output"
snapshot_plan="${fixture_root}/snapshot-plan.json"
snapshot_native_plan="${fixture_root}/snapshot-native-plan.json"
snapshot_cli_path="${noop_worker_bin}:${runner_mock_bin}:/usr/bin:/bin"
snapshot_run_arguments=(
    --harness noop --repo https://github.com/octocat/Hello-World --scope 1
    --workspace-root "${snapshot_workspace}" --output-root "${snapshot_output}"
    --non-interactive --no-open-html
)
env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${snapshot_cli_path}" "${snapshot_runner}" \
    "${snapshot_run_arguments[@]}" --plan-only > "${snapshot_plan}" 2>/dev/null ||
    fail 'Offline snapshot fixture plan failed.'
env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${snapshot_cli_path}" "${noop_runner}" \
    "${snapshot_run_arguments[@]}" --plan-only > "${snapshot_native_plan}" 2>/dev/null ||
    fail 'Native snapshot comparison plan failed.'
node - "${snapshot_plan}" "${snapshot_native_plan}" <<'JS'
const fs = require("fs");
const [mcp, native] = process.argv.slice(2).map(p => JSON.parse(fs.readFileSync(p, "utf8")));
const transport = mcp.SnapshotTransport;
if (mcp.SchemaVersion !== 5 || transport.ContractVersion !== 11 ||
    transport.Policy.Network !== "disabled" || transport.Policy.Resources !== "none" ||
    transport.Policy.ToolSchemas.length !== 4 || !/^[0-9a-f]{64}$/.test(transport.PolicyDigest) ||
    native.SnapshotTransport !== undefined || mcp.ApprovalHash === native.ApprovalHash ||
    mcp.WorkerRecoveryPolicy.RetryBackoff.Multiplier !== 2) {
  throw new Error("snapshot policy/schema/approval boundary was not preserved");
}
JS
snapshot_hash="$(contract_plan_hash "${snapshot_plan}")"
snapshot_native_hash="$(contract_plan_hash "${snapshot_native_plan}")"
if env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${snapshot_cli_path}" "${snapshot_runner}" \
    "${snapshot_run_arguments[@]}" --expected-plan-hash "${snapshot_native_hash}" \
    > "${fixture_root}/snapshot-mismatch.stdout" 2> "${fixture_root}/snapshot-mismatch.stderr"; then
    fail 'Snapshot transport accepted an approval for native reads.'
fi
[[ ! -e "${snapshot_workspace}" && ! -e "${snapshot_output}" ]] ||
    fail 'Snapshot approval mismatch created execution paths.'

for snapshot_retry_delay in '' 301 999 -1 1.5 030 invalid; do
    if env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
        PATH="${snapshot_cli_path}" \
        RHYOLITE_WORKER_RETRY_DELAY_SECONDS="${snapshot_retry_delay}" \
        "${snapshot_runner}" "${snapshot_run_arguments[@]}" --plan-only \
        > "${fixture_root}/retry-invalid.stdout" \
        2> "${fixture_root}/retry-invalid.stderr"; then
        fail 'An invalid initial retry delay was accepted.'
    fi
    grep -Fq 'Stage: worker retry policy' "${fixture_root}/retry-invalid.stderr" ||
        fail 'Invalid retry delay did not report its policy failure.'
done
[[ ! -e "${snapshot_workspace}" && ! -e "${snapshot_output}" ]] ||
    fail 'Invalid retry policy created execution paths.'

# Scan reports are outside the offline snapshot grants, so an offline-reader
# harness keeps the integrated security pass.
if env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${snapshot_cli_path}" "${snapshot_runner}" \
    "${snapshot_run_arguments[@]}" --security-scans 2 \
    --scan-model noop-fixture-alternate --plan-only \
    > "${fixture_root}/snapshot-scans.stdout" \
    2> "${fixture_root}/snapshot-scans.stderr"; then
    fail 'Offline snapshot transport accepted independent security scans.'
fi
assert_contains "${fixture_root}/snapshot-scans.stderr" \
    'Independent security scans are unavailable for this harness.' \
    'Offline snapshot scan rejection'
[[ ! -e "${snapshot_workspace}" && ! -e "${snapshot_output}" ]] ||
    fail 'Offline snapshot scan rejection created execution paths.'

snapshot_stdout="${fixture_root}/snapshot-run.stdout"
snapshot_stderr="${fixture_root}/snapshot-run.stderr"
snapshot_capture="${runner_capture_root}/snapshot"
mkdir -p -- "${snapshot_capture}"
env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${snapshot_cli_path}" TMPDIR="${noop_tmp_root}" \
    RHYOLITE_NOOP_CAPTURE_ROOT="${snapshot_capture}" \
    "${snapshot_runner}" "${snapshot_run_arguments[@]}" \
    --expected-plan-hash "${snapshot_hash}" \
    > "${snapshot_stdout}" 2> "${snapshot_stderr}" || {
        cat -- "${snapshot_stdout}" "${snapshot_stderr}" >&2
        fail 'Offline snapshot fixture execution failed.'
    }
snapshot_run="$(contract_run_path "${snapshot_stdout}")"
node - "${snapshot_run}" <<'JS'
const fs = require("fs"), path = require("path");
const root = process.argv[2], repo = path.join(root, "github--octocat--hello-world");
const plan = JSON.parse(fs.readFileSync(path.join(root, "review-plan.json"), "utf8"));
const values = [JSON.parse(fs.readFileSync(path.join(root, "state.json"), "utf8")),
  JSON.parse(fs.readFileSync(path.join(repo, "state.json"), "utf8")),
  ...JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))];
for (const value of values) {
  if (value.Status !== "Completed" || value.SchemaVersion !== 6 ||
      JSON.stringify(value.SnapshotTransport) !== JSON.stringify(plan.SnapshotTransport) ||
      value.ResearchTransport.Enabled !== false) {
    throw new Error("snapshot transport identity or research-free execution was lost");
  }
}
if (fs.existsSync(path.join(repo, "research"))) throw new Error("scope 1 created research");
for (const p of [path.join(repo, "handoff.md"), path.join(root, "handoff.md")]) {
  if (!fs.readFileSync(p, "utf8").includes(plan.SnapshotTransport.PolicyDigest)) {
    throw new Error("snapshot digest missing from handoff");
  }
}
JS
[[ -z "$(find "${noop_tmp_root}" -maxdepth 1 -name 'rhyolite-snapshot-read.*' -print -quit)" ]] ||
    fail 'Offline snapshot broker runtime survived finalization.'

# Contract behavior is the same on a prelaunch adapter failure: no child,
# no stale session identity, truthful state, and no broker/config leftovers.
snapshot_failure_stdout="${fixture_root}/snapshot-failure.stdout"
if env -u RHYOLITE_HARNESS -u RHYOLITE_LAUNCHER_HARNESS \
    PATH="${snapshot_cli_path}" TMPDIR="${noop_tmp_root}" \
    RHYOLITE_SNAPSHOT_TEST_CONFIG_FAIL=1 \
    "${snapshot_runner}" "${snapshot_run_arguments[@]}" \
    --expected-plan-hash "${snapshot_hash}" \
    > "${snapshot_failure_stdout}" 2> "${fixture_root}/snapshot-failure.stderr"; then
    fail 'Offline snapshot configuration failure was accepted.'
fi
snapshot_failed_run="$(contract_run_path "${snapshot_failure_stdout}")"
node - "${snapshot_failed_run}/github--octocat--hello-world/state.json" <<'JS'
const fs = require("fs");
const state = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (state.Status !== "ReviewFailed" || state.Session.Id || state.Session.Name ||
    state.SnapshotTransport.ContractVersion !== 11) {
  throw new Error("snapshot configuration failure lost truthful state");
}
JS
[[ -z "$(find "${noop_tmp_root}" -maxdepth 1 -name 'rhyolite-snapshot-read.*' -print -quit)" ]] ||
    fail 'Snapshot prelaunch failure left a broker runtime.'

# Extract only the pure retry helpers; fake sleep records the requested waits
# so these tests prove increasing/capped waits and timeout refusal quickly.
python3 - "${RUNNER}" "${fixture_root}/retry-helpers.sh" <<'PY'
import pathlib
import sys

source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
definitions = []
for name in ("worker_retry_backoff_seconds", "wait_worker_retry_backoff"):
    start = source.index(name + "() {\n")
    end = source.index("\n}\n", start) + 3
    definitions.append(source[start:end])
pathlib.Path(sys.argv[2]).write_text("\n".join(definitions), encoding="utf-8")
PY
(
    source "${fixture_root}/retry-helpers.sh"
    WORKER_RECOVERY_RETRY_DELAY_SECONDS=30
    WORKER_RECOVERY_RETRY_MAX_DELAY_SECONDS=300
    WORKER_RECOVERY_MINIMUM_SECONDS=120
    slug=fixture MODEL=example-approved-model REASONING_EFFORT=max
    review_progress() { :; }
    sleep() { printf '%s\n' "$1" >> "${fixture_root}/backoff-waits.txt"; }
    assert_equal 30 "$(worker_retry_backoff_seconds 1)" 'First retry delay'
    assert_equal 60 "$(worker_retry_backoff_seconds 2)" 'Second retry delay'
    assert_equal 300 "$(worker_retry_backoff_seconds 8)" 'Retry delay cap'
    wait_worker_retry_backoff 1 recovery 1000 || fail 'First retry backoff failed.'
    wait_worker_retry_backoff 2 recovery 1000 || fail 'Second retry backoff failed.'
    assert_equal $'30\n30\n30' "$(cat "${fixture_root}/backoff-waits.txt")" \
        'Backoff sleeps in bounded chunks'
    if wait_worker_retry_backoff 2 recovery 179 2>/dev/null; then
        fail 'Retry backoff ignored the approved timeout.'
    fi
)

printf 'Snapshot transport and retry-backoff contract validation passed.\n'
