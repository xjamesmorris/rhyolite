#!/usr/bin/env bash

set -euo pipefail

ROOT="${PWD}"

while (($#)); do
    case "$1" in
        --root)
            (($# >= 2)) || exit 2
            ROOT="$2"
            shift 2
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            exit 2
            ;;
    esac
done

if [[ ! -d "${ROOT}" ]]; then
    printf 'Discovery root is not a directory: %s\n' "${ROOT}" >&2
    exit 2
fi
ROOT="$(cd -- "${ROOT}" && pwd -P)"
if [[ "${ROOT}" =~ [[:cntrl:]] ]]; then
    printf 'Repository discovery path contains control characters.\n' >&2
    exit 2
fi

cursor="${ROOT}"
while true; do
    if [[ -e "${cursor}/.git" ]]; then
        printf 'current\t%s\n' "${cursor}"
        exit 0
    fi
    parent="$(dirname -- "${cursor}")"
    [[ "${parent}" != "${cursor}" ]] || break
    cursor="${parent}"
done

shopt -s nullglob
children=(
    "${ROOT}"/*
    "${ROOT}"/.[!.]*
    "${ROOT}"/..?*
)
for child in "${children[@]}"; do
    [[ -d "${child}" ]] || continue
    [[ ! -L "${child}" && -e "${child}/.git" ]] || continue
    child="$(cd -- "${child}" && pwd -P)"
    if [[ "${child}" =~ [[:cntrl:]] ]]; then
        printf 'Repository discovery path contains control characters.\n' >&2
        exit 2
    fi
    printf 'child\t%s\n' "${child}"
done
