#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="${ROOT}/.test-output/install-test-$$"
TEST_HOME="${TEST_ROOT}/home"
COPILOT_HOME="${TEST_HOME}/copilot-checkout"

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}

COPILOT_BIN="$(command -v copilot)" ||
    fail 'The GitHub Copilot CLI is required.'
command -v node >/dev/null 2>&1 ||
    fail 'Node.js is required for installation payload assertions.'

mkdir -p -- "${ROOT}/.test-output"
mkdir -- "${TEST_ROOT}" ||
    fail 'Could not create a unique installation fixture directory.'
trap cleanup EXIT
mkdir -p -- "${COPILOT_HOME}" "${TEST_HOME}/config" \
    "${TEST_HOME}/cache" "${TEST_HOME}/state" "${TEST_ROOT}/scratch" \
    "${TEST_ROOT}/launcher-probe-bin"
export COPILOT_HOME

isolated_env() {
    env -i PATH="${PATH}" HOME="${TEST_HOME}" \
        COPILOT_HOME="${COPILOT_HOME}" \
        XDG_CONFIG_HOME="${TEST_HOME}/config" \
        XDG_CACHE_HOME="${TEST_HOME}/cache" \
        XDG_STATE_HOME="${TEST_HOME}/state" \
        TMPDIR="${TEST_ROOT}/scratch" \
        GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
        GIT_TERMINAL_PROMPT=0 NO_COLOR=1 TERM=dumb LANG=C.UTF-8 "$@"
}

copilot() {
    isolated_env "${COPILOT_BIN}" "$@"
}

cat > "${TEST_ROOT}/launcher-probe-bin/copilot" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'Unexpected launcher Copilot invocation\n' > "${INSTALL_COPILOT_PROBE_LOG:?}"
exit 99
SH
chmod 700 -- "${TEST_ROOT}/launcher-probe-bin/copilot"

offline_launcher() {
    isolated_env env PATH="${TEST_ROOT}/launcher-probe-bin:${PATH}" \
        INSTALL_COPILOT_PROBE_LOG="${TEST_ROOT}/launcher-copilot-called" "$@"
}

assert_payload() {
    node - "$@" <<'JS'
const fs = require("fs");
const path = require("path");

const [root, version, reference, marketplaceRoot] = process.argv.slice(2);
const expect = (condition, message) => {
    if (!condition) throw new Error(message);
};
const json = (file) => JSON.parse(fs.readFileSync(file, "utf8"));
const manifest = json(path.join(root, "plugin.json"));
const marketplace = json(path.join(marketplaceRoot, ".github/plugin/marketplace.json"));
expect(/^\d+\.\d+\.\d+$/.test(version), "Machine version is not stable semver");
expect(fs.readFileSync(path.join(marketplaceRoot, "VERSION"), "utf8").trim() === version,
    "Exported VERSION does not match the selected release");
expect(manifest.name === "rhyolite" && manifest.version === version,
    "Plugin version does not match the selected release");
expect(marketplace.name === "rhyolite-tools" &&
    marketplace.metadata.version === version && marketplace.plugins.length === 1 &&
    marketplace.plugins[0].name === "rhyolite" &&
    marketplace.plugins[0].version === version,
    "Marketplace version does not match the selected release");
expect(fs.realpathSync(path.resolve(marketplaceRoot, marketplace.plugins[0].source)) ===
    fs.realpathSync(reference), "Marketplace selected an unexpected package");
for (const [key, value] of Object.entries({
    agents: "agents/", commands: "commands/", skills: "skills/",
    hooks: "hooks.json", extensions: "extensions/",
})) {
    expect(manifest[key] === value, `Packaged ${key} registration is incorrect`);
}

const required = [
    "plugin.json", "hooks.json", "branding/banner.txt", "branding/welcome-metadata.json",
    "agents/repo-review.agent.md", "agents/repo-review-worker.agent.md",
    "agents/repo-research-worker.agent.md", "commands/start.md",
    "commands/repo-review.md", "commands/help.md", "commands/status.md",
    "commands/version.md", "extensions/repo-review/extension.mjs",
    "lib/harness/common.sh", "lib/harness/copilot.sh", "scripts/launcher-preferences.sh",
    "skills/readonly-repository-review/SKILL.md",
    "skills/readonly-repository-review/review-prompt.txt",
    "skills/readonly-repository-review/research-prompt.txt",
    "skills/readonly-repository-review/research-policy.json",
    "skills/research-source-assessment/SKILL.md",
];
const executables = [
    "bin/rhyolite", "scripts/show-welcome-panel.sh",
    "skills/readonly-repository-review/scripts/discover-repositories.sh",
    "skills/readonly-repository-review/scripts/run-parallel-reviews.sh",
    "skills/readonly-repository-review/scripts/review-output.sh",
    "skills/readonly-repository-review/scripts/research-egress-broker.py",
    "skills/readonly-repository-review/scripts/launch-research-egress-broker.sh",
];
for (const file of [...required, ...executables]) {
    expect(fs.existsSync(path.join(root, file)) &&
        fs.lstatSync(path.join(root, file)).isFile(), `Required packaged asset is missing: ${file}`);
}
for (const file of executables) {
    fs.accessSync(path.join(root, file), fs.constants.X_OK);
}
expect(!fs.existsSync(path.join(root, "rhyolite")),
    "Installed plugin unexpectedly contains a root-level launcher");
expect(fs.readFileSync(path.join(root, "commands/version.md"), "utf8")
    .split("\n").includes(`Rhyolite v${version} Beta`),
    "Packaged version command is stale");

function inventory(directory, prefix = "") {
    const files = [];
    for (const name of fs.readdirSync(directory).sort()) {
        const relative = prefix ? `${prefix}/${name}` : name;
        const file = path.join(directory, name);
        const stat = fs.lstatSync(file);
        expect(!stat.isSymbolicLink(), `Unexpected packaged symlink: ${relative}`);
        expect(!/\.(?:ps1|psm1|psd1|cmd|bat)$/i.test(name),
            `Installed plugin contains an unsupported alternate-shell artifact: ${relative}`);
        expect(![".git", ".github", "tests", "fixtures", "tools", "__pycache__"].includes(name) &&
            !/\.py[co]$/i.test(name) &&
            !["rhyolite-ui-validator.agent.md", "rhyolite-tui-runtime-validator.agent.md",
                "noop.sh", "noop-worker.sh"].includes(name),
            `Installed plugin contains a development-only artifact: ${relative}`);
        if (stat.isDirectory()) files.push(...inventory(file, relative));
        else {
            expect(stat.isFile(), `Unexpected packaged entry: ${relative}`);
            files.push(relative);
        }
    }
    return files;
}
const actualFiles = inventory(root);
const expectedFiles = inventory(reference);
expect(JSON.stringify(actualFiles) === JSON.stringify(expectedFiles),
    "Installed package file inventory differs from the exported payload");
for (const file of expectedFiles) {
    expect(fs.readFileSync(path.join(root, file)).equals(fs.readFileSync(path.join(reference, file))),
        `Installed package content differs from the exported payload: ${file}`);
}
JS
}

assert_install() {
    local marketplace_root="$1"
    local version="$2"
    local expected_payload="$3"
    local label="$4"
    local launcher_version launcher_help load_status
    local link_dir="${TEST_ROOT}/launcher links/${label}"
    local -a installed_start_commands=()

    list_output="$(copilot plugin list 2>&1)" || {
        printf '%s\n' "${list_output}" >&2
        fail 'Could not list installed plugins.'
    }
    grep -Fq "rhyolite@rhyolite-tools (v${version})" <<< "${list_output}" ||
        fail 'Installed plugin list does not contain the selected Rhyolite version.'

    mapfile -t installed_start_commands < <(
        find "${COPILOT_HOME}" -type f \
            -path '*/installed-plugins/*/commands/start.md' -print |
            while IFS= read -r command_path; do
                if grep -Fq 'RHYOLITE_START_COMMAND_V1' "${command_path}"; then
                    printf '%s\n' "${command_path}"
                fi
            done
    )
    if ((${#installed_start_commands[@]} == 1)); then
        installed_plugin_root="$(
            cd -- "$(dirname -- "${installed_start_commands[0]}")/.." && pwd
        )"
    elif ((${#installed_start_commands[@]} == 0)) &&
        grep -Fq 'Live Plugins' <<< "${list_output}" &&
        grep -Fq "from ${marketplace_root}" <<< "${list_output}"; then
        installed_plugin_root="${expected_payload}"
        grep -Fq 'RHYOLITE_START_COMMAND_V1' \
            "${installed_plugin_root}/commands/start.md" ||
            fail 'Live plugin start command is missing its trusted marker.'
    else
        fail 'Could not resolve exactly one installed or live Rhyolite plugin root.'
    fi

    assert_payload "${installed_plugin_root}" "${version}" \
        "${expected_payload}" "${marketplace_root}" ||
        fail 'Installed package integrity validation failed.'

    mkdir -p -- "${link_dir}"
    ln -s -- "$(realpath --relative-to="${link_dir}" \
        "${installed_plugin_root}/bin/rhyolite")" "${link_dir}/rhyolite"
    launcher_version="$(offline_launcher "${link_dir}/rhyolite" --version)" ||
        fail 'Installed launcher failed through a relative symlink with spaces.'
    [[ "${launcher_version}" == "Rhyolite v${version} Beta" ]] ||
        fail 'Installed launcher version is stale.'
    launcher_help="$(offline_launcher "${link_dir}/rhyolite" --help)" ||
        fail 'Installed launcher help failed.'
    [[ "${launcher_help}" == "Rhyolite v${version} Beta"$'\n'* ]] ||
        fail 'Installed launcher help version is stale.'
    offline_launcher \
        "${installed_plugin_root}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh" \
        --help > "${TEST_ROOT}/${label}-runner-help.txt" ||
        fail 'Installed Bash runner could not load its packaged helpers.'

    load_status="$(isolated_env bash \
        "${installed_plugin_root}/scripts/show-welcome-panel.sh" --progress)" ||
        fail 'Installed load-status hook failed.'
    node - "${load_status}" "${version}" <<'JS'
const [output, version] = process.argv.slice(2);
const progress = JSON.parse(output);
if (progress.type !== "progress" ||
    progress.message !== `Rhyolite v${version} Beta loaded — type /rhyolite:start to start.`) {
    throw new Error("Installed load-status version is stale");
}
JS
    printf 'Verified %s installation: Rhyolite v%s Beta and complete Bash/Copilot payload.\n' \
        "${label}" "${version}"
}

version="$(tr -d '\r\n' < "${ROOT}/VERSION")"
marketplace_output="$(
    copilot plugin marketplace add "${ROOT}" 2>&1
)" || {
    printf '%s\n' "${marketplace_output}" >&2
    fail 'Could not register the local Rhyolite marketplace.'
}

install_output="$(
    copilot plugin install 'rhyolite@rhyolite-tools' 2>&1
)" || {
    printf '%s\n' "${install_output}" >&2
    fail 'Could not install Rhyolite from the local marketplace.'
}
assert_install "${ROOT}" "${version}" "${ROOT}/plugins/rhyolite" checkout

fixture="${TEST_ROOT}/exported marketplace with spaces"
# A Git-free package copy exercises exported payloads without the networked release workflow.
mkdir -p -- "${fixture}/.github/plugin" "${fixture}/plugins" \
    "${fixture}/previous/plugins"
cp -a -- "${ROOT}/plugins/rhyolite" "${fixture}/plugins/"
cp -a -- "${ROOT}/plugins/rhyolite" "${fixture}/previous/plugins/"
cp -- "${ROOT}/.github/plugin/marketplace.json" \
    "${fixture}/.github/plugin/marketplace.json"
cp -- "${ROOT}/VERSION" "${fixture}/VERSION"

# Local marketplaces can be live; retain both versioned payloads and switch the catalog source.
previous_version="$(node - "${fixture}" "${version}" <<'JS'
const fs = require("fs");
const path = require("path");
const [root, current] = process.argv.slice(2);
if (!/^\d+\.\d+\.\d+$/.test(current)) throw new Error("Invalid release version");
const [major, minor, patch] = current.split(".").map(Number);
const previous = patch > 0 ? `${major}.${minor}.${patch - 1}` :
    minor > 0 ? `${major}.${minor - 1}.0` : major > 0 ? `${major - 1}.0.0` : null;
if (!previous) throw new Error("A previous-version fixture requires a release after 0.0.0");
const manifestPath = path.join(root, "previous/plugins/rhyolite/plugin.json");
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
manifest.version = previous;
fs.writeFileSync(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
for (const file of ["commands/version.md", "agents/repo-review.agent.md"]) {
    const target = path.join(root, "previous/plugins/rhyolite", file);
    fs.writeFileSync(target, fs.readFileSync(target, "utf8")
        .replaceAll(`v${current} Beta`, `v${previous} Beta`));
}
const marketplacePath = path.join(root, ".github/plugin/marketplace.json");
const marketplace = JSON.parse(fs.readFileSync(marketplacePath, "utf8"));
marketplace.metadata.version = previous;
marketplace.plugins[0].version = previous;
marketplace.plugins[0].source = "previous/plugins/rhyolite";
fs.writeFileSync(marketplacePath, `${JSON.stringify(marketplace, null, 2)}\n`);
fs.writeFileSync(path.join(root, "VERSION"), `${previous}\n`);
console.log(previous);
JS
)"
printf 'Previous-version-only fixture asset\n' \
    > "${fixture}/previous/plugins/rhyolite/install-coverage-obsolete.txt"
[[ ! -e "${fixture}/.git" ]] ||
    fail 'Exported marketplace fixture unexpectedly contains Git metadata.'

COPILOT_HOME="${TEST_HOME}/copilot-fixture"
mkdir -- "${COPILOT_HOME}"
marketplace_output="$(copilot plugin marketplace add "${fixture}" 2>&1)" || {
    printf '%s\n' "${marketplace_output}" >&2
    fail 'Could not register the Git-free marketplace fixture with spaces.'
}
install_output="$(copilot plugin install 'rhyolite@rhyolite-tools' 2>&1)" || {
    printf '%s\n' "${install_output}" >&2
    fail 'Could not install the previous-version fixture.'
}
assert_install "${fixture}" "${previous_version}" \
    "${fixture}/previous/plugins/rhyolite" previous

cp -- "${ROOT}/.github/plugin/marketplace.json" \
    "${fixture}/.github/plugin/marketplace.json"
cp -- "${ROOT}/VERSION" "${fixture}/VERSION"
update_output="$(
    copilot plugin marketplace update rhyolite-tools &&
        copilot plugin update rhyolite@rhyolite-tools
)" || {
    printf '%s\n' "${update_output}" >&2
    fail 'Manual marketplace and plugin update failed.'
}
assert_install "${fixture}" "${version}" "${fixture}/plugins/rhyolite" updated
[[ ! -e "${installed_plugin_root}/install-coverage-obsolete.txt" ]] ||
    fail 'Manual update still selects the obsolete previous-version payload.'

plugins_before="${list_output}"
if missing_output="$(copilot plugin install 'install-coverage-missing@rhyolite-tools' 2>&1)"; then
    fail 'Installing an unknown local-marketplace plugin unexpectedly succeeded.'
fi
[[ "$(copilot plugin list)" == "${plugins_before}" ]] ||
    fail 'Failed installation changed the registered plugin state.'

invalid_marketplace="${TEST_ROOT}/invalid marketplace"
mkdir -p -- "${invalid_marketplace}/.github/plugin"
printf '{ malformed marketplace\n' > "${invalid_marketplace}/.github/plugin/marketplace.json"
marketplaces_before="$(copilot plugin marketplace list)"
if invalid_output="$(copilot plugin marketplace add "${invalid_marketplace}" 2>&1)"; then
    fail 'Registering a malformed local marketplace unexpectedly succeeded.'
fi
[[ "$(copilot plugin marketplace list)" == "${marketplaces_before}" ]] ||
    fail 'Failed marketplace registration changed the registered marketplaces.'

damaged="${TEST_ROOT}/damaged installed package"
cp -a -- "${installed_plugin_root}" "${damaged}"
rm -- "${damaged}/lib/harness/common.sh"
if assert_payload "${damaged}" "${version}" \
    "${fixture}/plugins/rhyolite" "${fixture}" \
    > "${TEST_ROOT}/damaged-payload.log" 2>&1; then
    fail 'Package validation accepted a missing canonical Bash helper.'
fi
damaged_status=0
offline_launcher "${damaged}/bin/rhyolite" --version \
    > "${TEST_ROOT}/damaged-launcher.stdout" \
    2> "${TEST_ROOT}/damaged-launcher.stderr" || damaged_status=$?
[[ "${damaged_status}" -eq 2 ]] &&
    grep -Fq 'RHYOLITE ERROR' "${TEST_ROOT}/damaged-launcher.stderr" &&
    grep -Fq 'Stage: launcher harness validation' "${TEST_ROOT}/damaged-launcher.stderr" &&
    grep -Eq '^Remediation: .+' "${TEST_ROOT}/damaged-launcher.stderr" ||
    fail 'An incomplete installed package did not fail closed with repair guidance.'
cp -- "${installed_plugin_root}/lib/harness/common.sh" "${damaged}/lib/harness/common.sh"
printf '\nInert changed payload fixture\n' \
    >> "${damaged}/skills/readonly-repository-review/review-prompt.txt"
if assert_payload "${damaged}" "${version}" \
    "${fixture}/plugins/rhyolite" "${fixture}" \
    > "${TEST_ROOT}/changed-payload.log" 2>&1; then
    fail 'Package validation accepted changed installed payload content.'
fi
grep -Fq 'Installed package content differs from the exported payload:' \
    "${TEST_ROOT}/changed-payload.log" ||
    fail 'Changed payload failed for a reason other than content integrity.'

for forbidden in \
    scripts/unsupported.ps1 \
    scripts/install-coverage.pyc \
    scripts/install-coverage.pyo \
    lib/harness/noop.sh \
    agents/rhyolite-ui-validator.agent.md \
    agents/rhyolite-tui-runtime-validator.agent.md; do
    printf 'Inert installation exclusion fixture\n' \
        > "${fixture}/plugins/rhyolite/${forbidden}"
    if assert_payload "${fixture}/plugins/rhyolite" "${version}" \
        "${fixture}/plugins/rhyolite" "${fixture}" \
        > "${TEST_ROOT}/forbidden-payload.log" 2>&1; then
        fail "Package validation accepted a forbidden artifact: ${forbidden}"
    fi
    grep -Eq 'unsupported alternate-shell artifact:|development-only artifact:' \
        "${TEST_ROOT}/forbidden-payload.log" ||
        fail 'Forbidden payload failed for a reason other than package exclusion.'
    rm -- "${fixture}/plugins/rhyolite/${forbidden}"
done
cache_fixture="${fixture}/plugins/rhyolite/scripts/__pycache__"
mkdir -- "${cache_fixture}"
if assert_payload "${fixture}/plugins/rhyolite" "${version}" \
    "${fixture}/plugins/rhyolite" "${fixture}" \
    > "${TEST_ROOT}/cache-payload.log" 2>&1; then
    fail 'Package validation accepted a development bytecode-cache directory.'
fi
grep -Fq 'development-only artifact: scripts/__pycache__' \
    "${TEST_ROOT}/cache-payload.log" ||
    fail 'Cache payload failed for a reason other than package exclusion.'
rmdir -- "${cache_fixture}"
[[ ! -e "${TEST_ROOT}/launcher-copilot-called" ]] ||
    fail 'Offline launcher help, version, or failure checks unexpectedly invoked Copilot.'
[[ "$(stat -c '%a' "${TEST_ROOT}")" == 700 &&
    "$(stat -c '%a' "${TEST_HOME}")" == 700 &&
    "$(stat -c '%a' "${COPILOT_HOME}")" == 700 ]] ||
    fail 'Installation fixtures are not restricted to the current user.'

printf 'Installation test passed (checkout, Git-free package, prior-version manual update, failure isolation).\n'
