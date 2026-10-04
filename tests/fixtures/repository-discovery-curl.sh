#!/usr/bin/env bash

set -euo pipefail

mock_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
log_path="${mock_root}/curl.log"
map_path="${mock_root}/curl.map"
sequence_path="${mock_root}/curl.sequence"
counter_path="${mock_root}/curl.counter"

fail_mock() {
    printf 'mock repository discovery curl: %s\n' "$1" >&2
    exit 97
}

[[ "${HOME-}" == */.anonymous-git-home ]] ||
    fail_mock 'HOME is not the isolated anonymous Git home'
[[ "${USERPROFILE-}" == "${HOME}" ]] ||
    fail_mock 'USERPROFILE does not match the isolated home'
[[ "${XDG_CONFIG_HOME-}" == "${HOME}" ]] ||
    fail_mock 'XDG_CONFIG_HOME does not match the isolated home'
[[ "${CURL_HOME-}" == "${HOME}" ]] ||
    fail_mock 'CURL_HOME does not match the isolated home'
[[ "${LC_ALL-}" == C ]] ||
    fail_mock 'LC_ALL is not fixed to C'
[[ ! -e "${HOME}/.curlrc" && ! -e "${HOME}/.netrc" ]] ||
    fail_mock 'isolated curl or netrc configuration unexpectedly exists'

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
    -z "${NO_PROXY-}" &&
    -z "${CURL_CA_BUNDLE-}" &&
    -z "${CURL_SSL_BACKEND-}" &&
    -z "${CURL_TRACE-}" &&
    -z "${CURL_TRACE_ASCII-}" &&
    -z "${CURL_VERBOSE-}" &&
    -z "${SSL_CERT_FILE-}" &&
    -z "${SSL_CERT_DIR-}" &&
    -z "${SSLKEYLOGFILE-}" &&
    -z "${GIT_CONFIG_GLOBAL-}" &&
    -z "${GIT_CONFIG_SYSTEM-}" &&
    -z "${GIT_CURL_VERBOSE-}" &&
    -z "${GIT_SSL_NO_VERIFY-}" &&
    -z "${GIT_TRACE-}" &&
    -z "${GIT_TRACE_CURL-}" &&
    -z "${GIT_TRACE_CURL_NO_DATA-}" &&
    -z "${GIT_TRACE_PACKET-}" ]] ||
    fail_mock 'credential, proxy, TLS, or Git configuration leaked into curl'

(($# > 0)) || fail_mock 'no curl arguments were supplied'
[[ "${1}" == --disable ]] ||
    fail_mock '--disable must be the first actual curl argument'
request_url="${@: -1}"
[[ "${request_url}" == https://* ]] ||
    fail_mock "request URL is not HTTPS: ${request_url}"

call_number=1
if [[ -f "${counter_path}" ]]; then
    read -r call_number < "${counter_path}" ||
        fail_mock 'could not read the request counter'
    [[ "${call_number}" =~ ^[0-9]+$ ]] ||
        fail_mock 'request counter is malformed'
    call_number=$((call_number + 1))
fi
printf '%s\n' "${call_number}" > "${counter_path}"

{
    printf '%s\t' "${request_url}"
    printf '%q ' "$@"
    printf '\n'
} >> "${log_path}"

record=""
if [[ -s "${sequence_path}" ]]; then
    current_line=0
    while IFS= read -r candidate || [[ -n "${candidate}" ]]; do
        current_line=$((current_line + 1))
        if ((current_line == call_number)); then
            record="${candidate}"
            break
        fi
    done < "${sequence_path}"
    [[ -n "${record}" ]] ||
        fail_mock "unexpected request ${call_number}: ${request_url}"
else
    [[ -s "${map_path}" ]] ||
        fail_mock 'no offline response map or sequence is configured'
    while IFS= read -r candidate || [[ -n "${candidate}" ]]; do
        [[ -n "${candidate}" ]] || continue
        expected_url="${candidate%%|*}"
        if [[ "${expected_url}" == "${request_url}" ]]; then
            record="${candidate}"
            break
        fi
    done < "${map_path}"
    [[ -n "${record}" ]] ||
        fail_mock "request URL is not in the offline response map: ${request_url}"
fi

IFS='|' read -r expected_url status redirect_target expected_resolve extra \
    <<< "${record}"
[[ -z "${extra}" ]] ||
    fail_mock 'response record has too many fields'
[[ "${expected_url}" == "${request_url}" ]] ||
    fail_mock "expected ${expected_url}, received ${request_url}"
[[ -n "${status}" && -n "${expected_resolve}" ]] ||
    fail_mock 'response record is incomplete'

expected_arguments=(
    --disable
    --no-location
    --no-insecure
    --config /dev/null
    --silent
    --globoff
    --request GET
    --output /dev/null
    --write-out '%{http_code}\n%{redirect_url}\n'
    --connect-timeout 10
    --max-time 30
    --retry 0
    --max-redirs 0
    --proto '=https'
    --proto-redir '=https'
    --proxy ''
    --noproxy '*'
    --no-netrc
    --header 'Authorization:'
    --header 'Proxy-Authorization:'
    --header 'Cookie:'
    --resolve "${expected_resolve}"
    -- "${request_url}"
)
actual_arguments=("$@")
[[ ${#actual_arguments[@]} -eq ${#expected_arguments[@]} ]] ||
    fail_mock "unexpected argument count: $#"
for index in "${!expected_arguments[@]}"; do
    [[ "${actual_arguments[index]}" == "${expected_arguments[index]}" ]] ||
        fail_mock \
            "unexpected argument $((index + 1)): ${actual_arguments[index]}"
done

if [[ "${status}" == exit:* ]]; then
    exit_code="${status#exit:}"
    [[ "${exit_code}" =~ ^[1-9][0-9]*$ && "${exit_code}" -le 255 ]] ||
        fail_mock "invalid configured exit status: ${status}"
    printf '%s\n' \
        "${redirect_target:-mock repository discovery transport failure}" >&2
    exit "${exit_code}"
fi

if [[ "${redirect_target}" == //* ]]; then
    redirect_target="https:${redirect_target}"
elif [[ "${redirect_target}" == /* ]]; then
    authority="${request_url#https://}"
    authority="${authority%%/*}"
    redirect_target="https://${authority}${redirect_target}"
fi

printf '%s\n' "${status}"
if [[ -n "${redirect_target}" ]]; then
    printf '%s\n' "${redirect_target}"
fi
