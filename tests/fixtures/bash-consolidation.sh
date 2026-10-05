#!/usr/bin/env bash

set -euo pipefail

fail() {
    printf 'Bash consolidation regression: %s\n' "$1" >&2
    exit 1
}

[[ $# -ge 3 && $# -le 4 ]] ||
    fail 'expected output helper, preference helper, unused fixture directory, and optional baseline output helper'
output_helper="$1"
preference_helper="$2"
fixture_dir="$3"
baseline_output_helper="${4-}"
[[ ! -e "${fixture_dir}" && ! -L "${fixture_dir}" ]] ||
    fail 'fixture directory already exists'
mkdir -p -- "${fixture_dir}"
source "${output_helper}"
source "${preference_helper}"

timeline="${fixture_dir}/timeline with spaces.txt"
expected="${fixture_dir}/expected.txt"
checks=0
baseline_checks=0

assert_extraction() {
    local label="$1"
    local extractor="$2"
    local expected_status="$3"
    local input="${4:-${timeline}}"
    local actual="${fixture_dir}/${label}-${extractor}.txt"
    local status=0

    printf 'stale output\n' > "${actual}"
    "${extractor}" "${input}" "${actual}" \
        > "${actual}.stdout" 2> "${actual}.stderr" || status=$?
    [[ "${status}" -eq "${expected_status}" ]] ||
        fail "${label}: ${extractor} returned ${status}, expected ${expected_status}"
    cmp -s -- "${expected}" "${actual}" ||
        fail "${label}: ${extractor} changed extracted bytes"
    [[ ! -s "${actual}.stdout" ]] ||
        fail "${label}: ${extractor} wrote outside the output file"
    checks=$((checks + 1))

    if [[ -n "${baseline_output_helper}" ]]; then
        local baseline="${actual}.baseline"
        local baseline_status=0
        printf 'stale output\n' > "${baseline}"
        (
            source "${baseline_output_helper}"
            "${extractor}" "${input}" "${baseline}"
        ) > "${baseline}.stdout" 2> "${baseline}.stderr" ||
            baseline_status=$?
        [[ "${baseline_status}" -eq "${status}" ]] &&
            cmp -s -- "${actual}" "${baseline}" &&
            cmp -s -- "${actual}.stdout" "${baseline}.stdout" ||
            fail "${label}: ${extractor} differs from baseline bytes or status"
        baseline_checks=$((baseline_checks + 1))
    fi
}

delimiter='================================================================================'
for extractor in extract_report extract_research_dossier; do
    case "${extractor}" in
        extract_report)
            heading='REPOSITORY REVIEW REPORT'
            lower_heading='repository review report'
            ;;
        *)
            heading='REPOSITORY RESEARCH DOSSIER'
            lower_heading='repository research dossier'
            ;;
    esac

    printf '%s\n' \
        preamble "${delimiter}" "${heading}" 'old body' "${delimiter}" \
        progress progress progress \
        "  ${delimiter}  " progress '' "${lower_heading}" \
        '   retained indentation' "${delimiter}   " 'ignored after closing' '' \
        > "${timeline}"
    printf '%s\n' \
        " ${delimiter}  " progress '' "${lower_heading}" \
        '  retained indentation' "${delimiter}   " > "${expected}"
    assert_extraction latest-block "${extractor}" 0

    printf '%s\n' \
        "${delimiter}" "${heading}" 'complete old body' "${delimiter}" \
        progress progress progress \
        "${delimiter}" "${heading}" 'unfinished latest body' '   ' '' \
        > "${timeline}"
    printf '%s\n' "${delimiter}" "${heading}" 'unfinished latest body' \
        > "${expected}"
    assert_extraction incomplete-latest "${extractor}" 0

    printf '%s\n' \
        "${delimiter}" one two three "${heading}" body "${delimiter}" \
        > "${timeline}"
    : > "${expected}"
    assert_extraction outside-header-window "${extractor}" 42

    printf '%s\n' "${delimiter%?}" "${heading}" body "${delimiter%?}" \
        > "${timeline}"
    assert_extraction short-delimiter "${extractor}" 42

    printf '%s\n' \
        "${delimiter}" "${heading}" body "${delimiter}====" ignored \
        > "${timeline}"
    printf '%s\n' "${delimiter}" "${heading}" body "${delimiter}====" \
        > "${expected}"
    assert_extraction long-closing-delimiter "${extractor}" 0

    : > "${timeline}"
    : > "${expected}"
    assert_extraction empty-input "${extractor}" 42
    assert_extraction missing-input "${extractor}" 2 \
        "${fixture_dir}/missing-input.txt"
done

write_failure_output="${fixture_dir}/output-directory"
mkdir -- "${write_failure_output}"
for extractor in extract_report extract_research_dossier; do
    status=0
    "${extractor}" "${timeline}" "${write_failure_output}" \
        > "${write_failure_output}.stdout" 2> "${write_failure_output}.stderr" ||
        status=$?
    [[ "${status}" -eq 1 && ! -s "${write_failure_output}.stdout" &&
        -s "${write_failure_output}.stderr" ]] ||
        fail "${extractor} lost the output-write failure"
    checks=$((checks + 1))
    if [[ -n "${baseline_output_helper}" ]]; then
        baseline_status=0
        (
            source "${baseline_output_helper}"
            "${extractor}" "${timeline}" "${write_failure_output}"
        ) > "${write_failure_output}.baseline.stdout" \
            2> "${write_failure_output}.baseline.stderr" ||
            baseline_status=$?
        [[ "${baseline_status}" -eq "${status}" ]] &&
            cmp -s -- "${write_failure_output}.stdout" \
                "${write_failure_output}.baseline.stdout" ||
            fail "${extractor} differs from the baseline output-write failure"
        baseline_checks=$((baseline_checks + 1))
    fi
done

printf '%s\n' \
    "${delimiter}" \
    'prefix repository extended review detailed report suffix' \
    body "${delimiter}" > "${timeline}"
cp -- "${timeline}" "${expected}"
assert_extraction permissive-report-heading extract_report 0
: > "${expected}"
assert_extraction report-is-not-dossier extract_research_dossier 42

printf '%s\n' \
    "${delimiter}" ' REPOSITORY RESEARCH DOSSIER' \
    body "${delimiter}" > "${timeline}"
assert_extraction indented-dossier-heading extract_research_dossier 42
printf '%s\n' \
    "${delimiter}" 'REPOSITORY RESEARCH DOSSIER suffix' \
    body "${delimiter}" > "${timeline}"
assert_extraction suffixed-dossier-heading extract_research_dossier 42

printf '%s\r\n' \
    "${delimiter}" 'REPOSITORY REVIEW REPORT' body "${delimiter}" \
    > "${timeline}"
cp -- "${timeline}" "${expected}"
assert_extraction report-carriage-returns extract_report 0
printf '%s\r\n' \
    "${delimiter}" 'REPOSITORY RESEARCH DOSSIER' body "${delimiter}" \
    > "${timeline}"
: > "${expected}"
assert_extraction exact-dossier-carriage-returns extract_research_dossier 42

invalid_output="${fixture_dir}/invalid-kind.txt"
printf 'unchanged\n' > "${invalid_output}"
cp -- "${invalid_output}" "${expected}"
for kind in '' unknown '../report' 'report;false'; do
    status=0
    extract_delimited_review_output "${timeline}" "${invalid_output}" "${kind}" \
        > "${invalid_output}.stdout" 2> "${invalid_output}.stderr" ||
        status=$?
    [[ "${status}" -eq 2 && ! -s "${invalid_output}.stdout" ]] &&
        cmp -s -- "${expected}" "${invalid_output}" ||
        fail 'invalid output kind was accepted or mutated the output'
    checks=$((checks + 1))
done

sanitization_input="${fixture_dir}/sanitization-input.txt"
sanitization_actual="${fixture_dir}/sanitization-actual.txt"
fixture_email="$(printf '%s@%s' author docs.example.org)"
fixture_userinfo_url="$(
    printf '%s://%s:%s@%s/path' https reader fixture docs.example.org
)"
fixture_token="$(printf '%s%s' ghp_ 123456789012345678901234567890)"
{
    printf '\033[31mColor\033[0m\n'
    printf 'OSC: \033]8;;https://docs.example.org/path\aVisible\033]8;;\a\n'
    printf 'Contact: %s\nUserinfo: %s\n' \
        "${fixture_email}" "${fixture_userinfo_url}"
    printf '%s\n' \
        'Authorization: Bearer fixture-auth' \
        'Proxy-Authorization: Basic fixture-proxy'
    printf 'access_token=%s API_KEY:%s password = %s SECRET=%s TOKEN: %s\n' \
        fixture-access fixture-api fixture-password fixture-secret fixture-token
    printf 'Git token: %s\n' "${fixture_token}"
    printf 'Controls:\001\007\013\014\037\177carriage\rreturn\ttab\n'
    printf 'unterminated line'
} > "${sanitization_input}"
sanitize_review_text < "${sanitization_input}" > "${sanitization_actual}"
{
    printf '%s\n' \
        Color 'OSC: Visible' \
        'Contact: [email omitted]' \
        'Userinfo: https://[credentials omitted]@docs.example.org/path' \
        'Authorization: [credential omitted]' \
        'Proxy-Authorization: [credential omitted]' \
        'access_token=[credential omitted] API_KEY:[credential omitted] password = [credential omitted] SECRET=[credential omitted] TOKEN: [credential omitted]' \
        'Git token: [credential omitted]'
    printf 'Controls:carriagereturn\ttab\n'
    printf 'unterminated line\n'
} > "${expected}"
cmp -s -- "${expected}" "${sanitization_actual}" ||
    fail 'shared stream sanitization changed control handling or redaction'
checks=$((checks + 1))
if [[ -n "${baseline_output_helper}" ]]; then
    (
        source "${baseline_output_helper}"
        strip_terminal_controls | redact_credentials | redact_emails
    ) < "${sanitization_input}" > "${sanitization_actual}.baseline"
    cmp -s -- "${sanitization_actual}" "${sanitization_actual}.baseline" ||
        fail 'shared stream sanitization differs from baseline bytes'
    baseline_checks=$((baseline_checks + 1))
fi

for failed_filter in strip_terminal_controls redact_credentials redact_emails; do
    status=0
    (
        case "${failed_filter}" in
            strip_terminal_controls) strip_terminal_controls() { return 29; } ;;
            redact_credentials) redact_credentials() { return 29; } ;;
            redact_emails) redact_emails() { return 29; } ;;
        esac
        sanitize_review_text < "${sanitization_input}" > /dev/null
    ) || status=$?
    [[ "${status}" -eq 29 ]] ||
        fail "shared stream sanitization lost ${failed_filter} failure"
    checks=$((checks + 1))
done

fixture_home="${fixture_dir}/home with spaces"
for xdg_state in '' relative/state "${fixture_dir}/state with spaces/"; do
    case "${xdg_state}" in
        /*) expected_home="${xdg_state%/}/rhyolite/launcher" ;;
        *) expected_home="${fixture_home}/.local/state/rhyolite/launcher" ;;
    esac
    actual_home="$(
        HOME="${fixture_home}/" XDG_STATE_HOME="${xdg_state}" \
            rhyolite_launcher_home
    )"
    [[ "${actual_home}" == "${expected_home}" ]] ||
        fail 'canonical launcher state-home resolution changed'
    checks=$((checks + 1))
done
actual_home="$(
    unset XDG_STATE_HOME
    HOME="${fixture_home}/" rhyolite_launcher_home
)"
[[ "${actual_home}" == "${fixture_home}/.local/state/rhyolite/launcher" ]] ||
    fail 'unset XDG state-home fallback changed'
checks=$((checks + 1))

printf 'Bash consolidation regressions: %s passed.\n' "${checks}"
if [[ -n "${baseline_output_helper}" ]]; then
    printf 'Baseline byte/status comparisons: %s passed.\n' "${baseline_checks}"
fi
