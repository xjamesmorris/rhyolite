#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="${ROOT}/.test-output/install-test"
COPILOT_HOME="${TEST_ROOT}/copilot-home"

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

cleanup() {
    rm -rf -- "${TEST_ROOT}"
}
trap cleanup EXIT

command -v copilot >/dev/null 2>&1 ||
    fail 'The GitHub Copilot CLI is required.'

rm -rf -- "${TEST_ROOT}"
mkdir -p -- "${COPILOT_HOME}"
chmod 700 -- "${TEST_ROOT}" "${COPILOT_HOME}"
export COPILOT_HOME

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

list_output="$(copilot plugin list 2>&1)" || {
    printf '%s\n' "${list_output}" >&2
    fail 'Could not list installed plugins.'
}
grep -Fq 'rhyolite@rhyolite-tools' <<< "${list_output}" ||
    fail 'Installed plugin list does not contain rhyolite@rhyolite-tools.'

mapfile -t installed_start_commands < <(
    find "${COPILOT_HOME}" -type f \
        -path '*/installed-plugins/*/commands/start.md' \
        -print |
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
    grep -Fq "from ${ROOT}" <<< "${list_output}"; then
    installed_plugin_root="${ROOT}/plugins/rhyolite"
    grep -Fq 'RHYOLITE_START_COMMAND_V1' \
        "${installed_plugin_root}/commands/start.md" ||
        fail 'Live plugin start command is missing its trusted marker.'
else
    fail 'Could not resolve exactly one installed or live Rhyolite plugin root.'
fi

[[ -x "${installed_plugin_root}/bin/rhyolite" ]] ||
    fail 'Installed plugin is missing the executable Bash launcher.'
[[ ! -e "${installed_plugin_root}/rhyolite" ]] ||
    fail 'Installed plugin unexpectedly contains a root-level launcher.'
[[ ! -e "${installed_plugin_root}/agents/rhyolite-ui-validator.agent.md" ]] ||
    fail 'Installed plugin contains the repository-only UI validator.'
[[ ! -e "${installed_plugin_root}/agents/rhyolite-tui-runtime-validator.agent.md" ]] ||
    fail 'Installed plugin contains the repository-only TUI validator.'
if find "${installed_plugin_root}" -type f \
    \( -name '*.ps1' -o -name '*.psm1' \) -print -quit |
    grep -q .; then
    fail 'Installed plugin contains an unsupported alternate-shell artifact.'
fi

printf 'Installation test passed.\n'
