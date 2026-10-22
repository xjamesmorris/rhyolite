#!/usr/bin/env bash

set -euo pipefail
umask 077

launcher_path="$(readlink -f -- "${BASH_SOURCE[0]}")" || {
    printf '%s\n' 'Snapshot broker launcher path could not be resolved.' >&2
    exit 2
}
SCRIPT_DIR="$(cd -P -- "$(dirname -- "${launcher_path}")" && pwd)"
BROKER="${SCRIPT_DIR}/research-egress-broker.py"
SUPERVISOR="${SCRIPT_DIR}/stdio-broker-supervisor.sh"
runtime_root=''
grant_manifest=''
policy_digest=''

fail() {
    printf '%s\n' "$1" >&2
    exit 2
}

canonical_existing_path() {
    local value="$1"
    local expected_type="$2"
    local resolved

    [[ "${value}" == /* && ! "${value}" =~ [[:cntrl:]] && ! -L "${value}" ]] ||
        return 1
    resolved="$(readlink -e -- "${value}")" || return 1
    [[ "${resolved}" == "${value}" ]] || return 1
    case "${expected_type}" in
        directory)
            [[ -d "${value}" ]]
            ;;
        file)
            [[ -f "${value}" ]]
            ;;
        *)
            return 1
            ;;
    esac
}

while (($# > 0)); do
    case "$1" in
        --runtime-root)
            [[ -z "${runtime_root}" && -n "${2-}" ]] ||
                fail 'Snapshot broker runtime root is missing or duplicated.'
            runtime_root="$2"
            shift 2
            ;;
        --grant-manifest)
            [[ -z "${grant_manifest}" && -n "${2-}" ]] ||
                fail 'Snapshot grant manifest is missing or duplicated.'
            grant_manifest="$2"
            shift 2
            ;;
        --expected-policy-digest)
            [[ -z "${policy_digest}" && -n "${2-}" ]] ||
                fail 'Snapshot policy digest is missing or duplicated.'
            policy_digest="$2"
            shift 2
            ;;
        *)
            fail 'Snapshot broker launcher received an unknown argument.'
            ;;
    esac
done

[[ -f "${BROKER}" && ! -L "${BROKER}" ]] ||
    fail 'Snapshot broker implementation is unavailable.'
canonical_existing_path "${runtime_root}" directory ||
    fail 'Snapshot broker runtime root must be a canonical nonsymlink directory.'
canonical_existing_path "${grant_manifest}" file ||
    fail 'Snapshot grant manifest must be a canonical nonsymlink file.'
[[ "${policy_digest}" =~ ^[0-9a-f]{64}$ ]] ||
    fail 'Snapshot policy digest is invalid.'
[[ "$(stat -c '%u' -- "${runtime_root}")" == "$(id -u)" &&
    "$(stat -c '%a' -- "${runtime_root}")" == '700' ]] ||
    fail 'Snapshot broker runtime root must be current-user mode 0700.'
[[ "$(stat -c '%u' -- "${grant_manifest}")" == "$(id -u)" &&
    "$(stat -c '%a' -- "${grant_manifest}")" == '600' ]] ||
    fail 'Snapshot grant manifest must be current-user mode 0600.'
[[ -x /usr/bin/python3 ]] ||
    fail 'Python 3 is required for the snapshot broker.'

cd -- "${runtime_root}"
if [[ -n "${RHYOLITE_BROKER_OWNER_PID-}" ||
    -n "${RHYOLITE_BROKER_OWNER_START_TIME-}" ]]; then
    [[ -x "${SUPERVISOR}" &&
        "${RHYOLITE_BROKER_OWNER_PID-}" =~ ^[1-9][0-9]*$ &&
        "${RHYOLITE_BROKER_OWNER_START_TIME-}" =~ ^[1-9][0-9]*$ ]] ||
        fail 'Snapshot broker supervisor configuration is invalid.'
    exec /usr/bin/setsid --fork --wait \
        env -i \
        PATH='/usr/bin:/bin' \
        HOME="${runtime_root}" \
        TMPDIR="${runtime_root}" \
        XDG_CONFIG_HOME="${runtime_root}" \
        XDG_CACHE_HOME="${runtime_root}" \
        XDG_STATE_HOME="${runtime_root}" \
        LANG='C.UTF-8' \
        LC_ALL='C.UTF-8' \
        PYTHONDONTWRITEBYTECODE=1 \
        PYTHONHASHSEED=0 \
        PYTHONNOUSERSITE=1 \
        PYTHONSAFEPATH=1 \
        /usr/bin/bash "${SUPERVISOR}" \
        "${RHYOLITE_BROKER_OWNER_PID}" \
        "${RHYOLITE_BROKER_OWNER_START_TIME}" \
        -- \
        /usr/bin/python3 "${BROKER}" \
        --snapshot-mode \
        --runtime-root "${runtime_root}" \
        --snapshot-grant-manifest "${grant_manifest}" \
        --expected-snapshot-policy-digest "${policy_digest}"
fi
exec env -i \
    PATH='/usr/bin:/bin' \
    HOME="${runtime_root}" \
    TMPDIR="${runtime_root}" \
    XDG_CONFIG_HOME="${runtime_root}" \
    XDG_CACHE_HOME="${runtime_root}" \
    XDG_STATE_HOME="${runtime_root}" \
    LANG='C.UTF-8' \
    LC_ALL='C.UTF-8' \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONHASHSEED=0 \
    PYTHONNOUSERSITE=1 \
    PYTHONSAFEPATH=1 \
    /usr/bin/python3 "${BROKER}" \
    --snapshot-mode \
    --runtime-root "${runtime_root}" \
    --snapshot-grant-manifest "${grant_manifest}" \
    --expected-snapshot-policy-digest "${policy_digest}"
