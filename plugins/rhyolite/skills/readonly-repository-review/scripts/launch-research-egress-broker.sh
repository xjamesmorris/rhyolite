#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BROKER="${SCRIPT_DIR}/research-egress-broker.py"
runtime_root=""
arguments=()

while (($# > 0)); do
    case "$1" in
        --runtime-root)
            [[ -n "${2-}" ]] || {
                printf '%s\n' 'Missing value for --runtime-root.' >&2
                exit 2
            }
            runtime_root="$2"
            arguments+=("$1" "$2")
            shift 2
            ;;
        *)
            arguments+=("$1")
            shift
            ;;
    esac
done

[[ -f "${BROKER}" ]] || {
    printf 'Research egress broker not found: %s\n' "${BROKER}" >&2
    exit 2
}
[[ -n "${runtime_root}" && -d "${runtime_root}" ]] || {
    printf '%s\n' 'Research broker runtime root is missing or invalid.' >&2
    exit 2
}
[[ "$(stat -c '%a' "${runtime_root}")" == "700" ]] || {
    printf '%s\n' 'Research broker runtime root must be mode 0700.' >&2
    exit 2
}

python_path="$(command -v python3)" || {
    printf '%s\n' 'Python 3 is required for the research egress broker.' >&2
    exit 2
}

exec env -i \
    PATH="/usr/bin:/bin" \
    HOME="${runtime_root}" \
    XDG_CONFIG_HOME="${runtime_root}" \
    XDG_CACHE_HOME="${runtime_root}" \
    XDG_STATE_HOME="${runtime_root}" \
    LANG="C.UTF-8" \
    LC_ALL="C.UTF-8" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONNOUSERSITE=1 \
    "${python_path}" "${BROKER}" "${arguments[@]}"
