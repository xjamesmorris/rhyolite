#!/usr/bin/env bash

set -euo pipefail

fail() {
    printf 'Rhyolite welcome helper: %s\n' "$1" >&2
    exit 1
}

json_unescape() {
    local value="$1"
    value="${value//\\\//\/}"
    value="${value//\\n/$'\n'}"
    value="${value//\\r/$'\r'}"
    value="${value//\\t/$'\t'}"
    value="${value//\\\"/\"}"
    value="${value//\\\\/\\}"
    printf '%s' "${value}"
}

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\033'/\\u001b}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "${value}"
}

color_enabled() {
    [[ -z "${NO_COLOR+x}" ]] &&
        [[ "${COPILOT_NO_COLOR-}" != "1" ]] &&
        [[ "${FORCE_COLOR-}" != "0" ]] &&
        [[ "${TERM-}" != "dumb" ]]
}

launcher_started_immediately() {
    [[ "${RHYOLITE_LAUNCHER_IMMEDIATE_START-}" == \
        'RHYOLITE_LAUNCHER_IMMEDIATE_START_V1' ]]
}

prompt_requests_review_start() {
    local hook_input="$1"
    local hook_prompt
    local command

    [[ "${hook_input}" != *'--rhyolite-resume'* ]] || return 1
    hook_prompt="$(
        printf '%s' "${hook_input}" |
            sed -nE \
                's/.*"prompt"[[:space:]]*:[[:space:]]*"([^"]*).*/\1/p' |
            head -n 1
    )"
    hook_prompt="${hook_prompt#"${hook_prompt%%[![:space:]]*}"}"

    for command in \
        '/rhyolite:start' \
        '/rhyolite:repo-review' \
        '/repo-review'; do
        case "${hook_prompt}" in
            "${command}"|"${command} "*|"${command}\\n"*|"${command}\\r"*|"${command}\\t"*)
                return 0
                ;;
        esac
    done
    return 1
}

terminal_cell_length() {
    local value="$1"

    value="${value//█/x}"
    value="${value//▄/x}"
    value="${value//▀/x}"
    printf '%s' "${#value}"
}

banner_display_width() {
    local line
    local line_length=0
    local max_width=0

    while IFS= read -r line; do
        line_length="$(terminal_cell_length "${line}")"
        if ((line_length > max_width)); then
            max_width=${line_length}
        fi
    done < "${banner_path}"

    printf '%s' "${max_width}"
}

version_line_text() {
    local version_text="v${version}"
    local padding=$((banner_width - ${#version_text}))

    if ((padding < 0)); then
        padding=0
    fi

    printf '%*s%s' "${padding}" '' "${version_text}"
}

review_plaque_plain() {
    cat "${banner_path}"
    version_line
    plaque_sentences
}

version_line() {
    printf '%s\n' "$(version_line_text)"
}

plaque_sentences() {
    if launcher_started_immediately; then
        printf '%s\n' \
            '' \
            'Rhyolite is running in automatic guided mode.' \
            'Startup is continuing automatically; wait for the first setup prompt before responding.' \
            'Use /rhyolite:help for commands or /rhyolite:status for current progress.'
        return
    fi

    printf '%s\n' \
        '' \
        'Rhyolite guides evidence-based, read-only reviews of public HTTPS Git repositories.' \
        'Use /rhyolite:start to begin a review.' \
        'Use /rhyolite:help for commands or /rhyolite:status for current progress.'
}

review_plaque() {
    local colors=(
        '118;234;255'
        '90;220;255'
        '66;203;255'
        '54;182;255'
        '68;148;248'
        '88;122;230'
    )
    local index=0
    local line
    local version_color="${colors[$((${#colors[@]} - 1))]}"

    if ! color_enabled; then
        review_plaque_plain
        return
    fi

    while IFS= read -r line; do
        printf '\033[38;2;%sm%s\033[0m\n' \
            "${colors[index % ${#colors[@]}]}" "${line}"
        ((index += 1))
    done < "${banner_path}"

    printf '\033[38;2;%sm%s\033[0m\n' \
        "${version_color}" "$(version_line_text)"
    plaque_sentences
}

read_json_string() {
    local file="$1"
    local field="$2"
    local value

    value="$(
        sed -nE \
            "s/^[[:space:]]*\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[[:space:]]*,?[[:space:]]*$/\\1/p" \
            "${file}" | head -n 1
    )"
    [[ -n "${value}" ]] || fail "missing JSON string field ${field} in ${file}"
    json_unescape "${value}"
}

read_json_string_array() {
    local file="$1"
    local field="$2"

    sed -nE \
        "/\"${field}\"[[:space:]]*:[[:space:]]*\[/,/\]/{s/^[[:space:]]*\"([^\"]*)\"[[:space:]]*,?[[:space:]]*$/\\1/p;}" \
        "${file}" |
        while IFS= read -r value; do
            json_unescape "${value}"
            printf '\n'
        done
}

public_repository_urls_resolved() {
    local value

    for value in \
        "${home_url}" \
        "${docs_url}" \
        "${support_url}" \
        "${issues_url}" \
        "${pulls_url}"; do
        case "${value}" in
            ''|*'<PUBLIC_'*'>'*) return 1 ;;
        esac
    done
    return 0
}

mode="panel"
while (($# > 0)); do
    case "$1" in
        --panel)
            mode="panel"
            ;;
        --progress)
            mode="progress"
            ;;
        --prompt-plaque)
            mode="prompt-plaque"
            ;;
        --mode)
            shift
            [[ $# -gt 0 ]] || fail 'missing value after --mode'
            case "$1" in
                panel|progress|prompt-plaque)
                    mode="$1"
                    ;;
                *)
                    fail "unsupported mode ${1}"
                    ;;
            esac
            ;;
        *)
            fail "unsupported argument ${1}"
            ;;
    esac
    shift
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
METADATA_PATH="${PLUGIN_ROOT}/branding/welcome-metadata.json"
PLUGIN_MANIFEST_PATH="${PLUGIN_ROOT}/plugin.json"

[[ -f "${METADATA_PATH}" ]] || fail "metadata file not found: ${METADATA_PATH}"
[[ -f "${PLUGIN_MANIFEST_PATH}" ]] || fail "plugin manifest not found: ${PLUGIN_MANIFEST_PATH}"

display_name="$(read_json_string "${METADATA_PATH}" 'displayName')"
tagline="$(read_json_string "${METADATA_PATH}" 'tagline')"
home_url="$(read_json_string "${METADATA_PATH}" 'homeUrl')"
docs_url="$(read_json_string "${METADATA_PATH}" 'docsUrl')"
support_url="$(read_json_string "${METADATA_PATH}" 'supportUrl')"
issues_url="$(read_json_string "${METADATA_PATH}" 'issuesUrl')"
pulls_url="$(read_json_string "${METADATA_PATH}" 'pullsUrl')"
local_docs_path="$(read_json_string "${METADATA_PATH}" 'localDocsPath')"
local_support_path="$(read_json_string "${METADATA_PATH}" 'localSupportPath')"
local_contributing_path="$(
    read_json_string "${METADATA_PATH}" 'localContributingPath'
)"
start_command="$(read_json_string "${METADATA_PATH}" 'startCommand')"
short_start_command="$(read_json_string "${METADATA_PATH}" 'shortStartCommand')"
start_agent_id="$(read_json_string "${METADATA_PATH}" 'startAgentId')"
banner_asset_path="$(read_json_string "${METADATA_PATH}" 'bannerAssetPath')"
version="$(read_json_string "${PLUGIN_MANIFEST_PATH}" 'version')"
banner_path="${PLUGIN_ROOT}/${banner_asset_path}"

[[ -f "${banner_path}" ]] || fail "banner file not found: ${banner_path}"
banner_width="$(banner_display_width)"

setup_help_phrases=()
while IFS= read -r phrase; do
    setup_help_phrases+=("${phrase}")
done < <(read_json_string_array "${METADATA_PATH}" 'setupHelpPhrases')

[[ ${#setup_help_phrases[@]} -ge 3 ]] ||
    fail "setupHelpPhrases must contain help, status, and explain scopes"

help_phrase="${setup_help_phrases[0]}"
status_phrase="${setup_help_phrases[1]}"
explain_scopes_phrase="${setup_help_phrases[2]}"

if [[ "${mode}" == "progress" ]]; then
    if launcher_started_immediately; then
        printf '{"type":"progress","message":"%s"}\n' \
            "$(json_escape "$(review_plaque)")"
        exit 0
    fi
    progress_message="${display_name} v${version} loaded — type ${start_command} to start."
    printf '{"type":"progress","message":"%s"}\n' \
        "$(json_escape "${progress_message}")"
    exit 0
fi

if [[ "${mode}" == "prompt-plaque" ]]; then
    hook_input="$(cat)"
    if launcher_started_immediately; then
        exit 0
    fi
    if prompt_requests_review_start "${hook_input}"; then
        printf '{"type":"progress","message":"%s"}\n' \
            "$(json_escape "$(review_plaque)")"
    fi
    exit 0
fi

cat "${banner_path}"
version_line
printf '%s\n' "${tagline}"
printf '\n'
printf 'Stage: Setup\n'
printf 'Scope: NOT SELECTED\n'
printf '\n'
printf 'Start: Type %s to begin guided setup.\n' "${start_command}"
printf 'Shorthand: Type %s when extension commands are available.\n' \
    "${short_start_command}"
printf 'Agent fallback: Type /agent %s, then type start.\n' \
    "${start_agent_id}"
printf 'Commands: /rhyolite:help | /rhyolite:status | /rhyolite:version\n'
printf 'Rhyolite help: Type %s without a leading slash to re-show setup guidance.\n' \
    "${help_phrase}"
printf 'Rhyolite status: Type %s without a leading slash to see current selections.\n' \
    "${status_phrase}"
printf 'Explain scopes: Type %s without a leading slash for scope 1/2/3 setup differences.\n' \
    "${explain_scopes_phrase}"
printf '\n'
if public_repository_urls_resolved; then
    printf 'Docs: %s\n' "${docs_url}"
    printf 'Support: %s\n' "${support_url}"
else
    printf 'Docs: %s (local distribution documentation)\n' \
        "${local_docs_path}"
    printf 'Support: %s (local source/distribution documentation)\n' \
        "${local_support_path}"
fi
