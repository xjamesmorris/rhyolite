#!/usr/bin/env bash

# Source this from the trusted runner. It owns the offline grant manifest and
# broker lifecycle; adapters receive only paths, fixed tool names, and argv.

snapshot_transport_error() {
    printf '%s\n' "$1" >&2
    return 1
}

snapshot_transport_canonical_path() {
    local value="$1" kind="$2" resolved
    [[ "${value}" == /* && ! "${value}" =~ [[:cntrl:]] &&
        ! -L "${value}" ]] || return 1
    resolved="$(readlink -e -- "${value}")" || return 1
    [[ "${resolved}" == "${value}" ]] || return 1
    case "${kind}" in
        directory) [[ -d "${value}" ]] ;;
        file) [[ -f "${value}" ]] ;;
        *) return 1 ;;
    esac
}

snapshot_transport_overlap() {
    local first="${1%/}" second="${2%/}"
    [[ "${first}" == "${second}" || "${first}" == "${second}/"* ||
        "${second}" == "${first}/"* || -e "${first}" &&
        -e "${second}" && "${first}" -ef "${second}" ]]
}

snapshot_transport_json_string() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "${value}"
}

snapshot_transport_require_non_git() {
    local directory="$1" status=0 diagnostic
    diagnostic="$(
        env -u GIT_DIR -u GIT_WORK_TREE -u GIT_COMMON_DIR \
            -u GIT_CONFIG -u GIT_CONFIG_COUNT -u GIT_CONFIG_PARAMETERS \
            LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
            git -C "${directory}" rev-parse --git-dir 2>&1
    )" || status=$?
    [[ "${status}" == 128 && "${diagnostic}" == *'not a git repository'* ]] ||
        snapshot_transport_error 'Snapshot transport paths must be outside Git worktrees.'
}

snapshot_transport_validate_tree() {
    local tree="$1" inventory="$2" entry relative mode owner links type component
    local component_count=0 current_uid
    local -a components=()
    local entry_count=0
    local LC_ALL=C
    current_uid="$(id -u)"
    snapshot_transport_canonical_path "${tree}" directory ||
        { snapshot_transport_error 'Snapshot tree must be an existing canonical directory.'; return 1; }
    [[ "$(stat -c '%u' -- "${tree}")" == "${current_uid}" &&
        -r "${tree}" && -x "${tree}" ]] || return 1
    if ! (
        umask 077
        set -o noclobber
        find -P "${tree}" -printf '%y\0%U\0%m\0%n\0%p\0' > "${inventory}"
    ); then
        snapshot_transport_error 'Snapshot tree could not be completely enumerated.'
        return 1
    fi
    while IFS= read -r -d '' type &&
        IFS= read -r -d '' owner &&
        IFS= read -r -d '' mode &&
        IFS= read -r -d '' links &&
        IFS= read -r -d '' entry; do
        [[ "${type}" == f || "${type}" == d ]] ||
            { snapshot_transport_error 'Snapshot tree contains a symbolic link or special file.'; return 1; }
        relative="${entry#"${tree}/"}"
        if [[ "${entry}" == "${tree}" ]]; then
            relative=''
        else
            [[ ! "${relative}" =~ [[:cntrl:]] && "${relative}" != *'\'* &&
                ${#relative} -le 4096 ]] ||
                { snapshot_transport_error 'Snapshot tree contains an unsafe path.'; return 1; }
            IFS=/ read -r -a components <<< "${relative}"
            component_count="${#components[@]}"
            ((component_count <= 64)) || return 1
            for component in "${components[@]}"; do
                [[ "${component,,}" != .git ]] ||
                    { snapshot_transport_error 'Snapshot tree contains Git metadata.'; return 1; }
            done
        fi
        [[ "${owner}" == "${current_uid}" && "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
        (( (8#${mode} & 8#222) == 0 )) ||
            { snapshot_transport_error 'Snapshot tree must be read-only.'; return 1; }
        if [[ "${type}" == f ]]; then
            [[ "${links}" == 1 ]] ||
                { snapshot_transport_error 'Snapshot tree must not contain hard-linked files.'; return 1; }
        fi
        entry_count=$((entry_count + 1))
        ((entry_count <= 1000001)) ||
            { snapshot_transport_error 'Snapshot tree exceeds the approved entry budget.'; return 1; }
    done < "${inventory}"
    rm -f -- "${inventory}"
}

snapshot_transport_prepare() {
    local destination_name="$1" runtime_root="$2" phase="$3" snapshot="$4"
    local policy_digest="$5" workspace_root="$6" output_root="$7" harness_home="$8"
    local dossier="${9-}" summary="${10-}" grant_path grant_id size digest mode excluded index
    local manifest="${runtime_root}/snapshot-grants.json"
    local -a grants=() ids=()
    [[ "${destination_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ &&
        "${phase}" =~ ^(review|research)$ &&
        "${policy_digest}" =~ ^[0-9a-f]{64}$ ]] || return 1
    snapshot_transport_canonical_path "${runtime_root}" directory || return 1
    [[ "${runtime_root##*/}" == rhyolite-snapshot-read.* &&
        "$(stat -c '%u' -- "${runtime_root}")" == "$(id -u)" &&
        "$(stat -c '%a' -- "${runtime_root}")" == 700 ]] ||
        { snapshot_transport_error 'Snapshot transport runtime must be private and runner-created.'; return 1; }
    [[ -z "$(find -P "${runtime_root}" -mindepth 1 -print -quit)" ]] || return 1
    for grant_path in "${workspace_root}" "${output_root}" "${harness_home}" "${snapshot}"; do
        snapshot_transport_canonical_path "${grant_path}" directory || return 1
        if snapshot_transport_overlap "${runtime_root}" "${grant_path}"; then
            snapshot_transport_error 'Snapshot runtime must be disjoint from workspace, output, and harness homes.'
            return 1
        fi
    done
    local session_directory="${snapshot%/source}"
    [[ "${snapshot##*/}" == source &&
        "${session_directory%/*}" == "${workspace_root}" &&
        "${session_directory##*/}" == *-session ]] || {
        snapshot_transport_error 'Snapshot grants must name one runner-created session source directory.'
        return 1
    }
    if snapshot_transport_overlap "${snapshot}" "${output_root}" ||
        snapshot_transport_overlap "${snapshot}" "${harness_home}"; then
        snapshot_transport_error 'Snapshot reads must be disjoint from output and harness homes.'
        return 1
    fi
    snapshot_transport_require_non_git "${runtime_root}" || return 1
    snapshot_transport_require_non_git "${snapshot}" || return 1
    snapshot_transport_require_non_git "${harness_home}" || return 1
    snapshot_transport_validate_tree "${snapshot}" "${runtime_root}/.tree-inventory" || return 1
    if [[ -n "${dossier}" || -n "${summary}" ]]; then
        [[ "${phase}" == review && -n "${dossier}" && -n "${summary}" &&
            "${dossier##*/}" == research.txt && "${summary##*/}" == network-summary.json &&
            "${dossier%/*}" == "${summary%/*}" &&
            "${dossier%/*}" == "${session_directory}/research-evidence" ]] ||
            { snapshot_transport_error 'Only the complete runner-validated research file pair may be granted.'; return 1; }
        grants=("${dossier}" "${summary}")
        ids=(research-dossier research-network-summary)
    fi
    for grant_path in "${grants[@]}"; do
        snapshot_transport_canonical_path "${grant_path}" file || return 1
        for excluded in "${runtime_root}" "${snapshot}" "${output_root}" "${harness_home}"; do
            if snapshot_transport_overlap "${grant_path}" "${excluded}"; then
                snapshot_transport_error 'Additional snapshot file grants cross a forbidden boundary.'
                return 1
            fi
        done
        mode="$(stat -c '%a' -- "${grant_path}")" || return 1
        [[ "${mode}" =~ ^[0-7]{3,4}$ &&
            "$(stat -c '%u' -- "${grant_path}")" == "$(id -u)" &&
            "$(stat -c '%h' -- "${grant_path}")" == 1 ]] || return 1
        (( (8#${mode} & 8#222) == 0 )) || return 1
        size="$(stat -c '%s' -- "${grant_path}")" || return 1
        ((size <= 2097152)) || return 1
    done
    if ! (
        umask 077
        set -o noclobber
        {
            printf '{"SchemaVersion":1,"PolicyDigest":"%s","Phase":"%s","Grants":[' \
                "${policy_digest}" "${phase}"
            printf '{"Id":"snapshot","Kind":"tree","Path":%s}' \
                "$(snapshot_transport_json_string "${snapshot}")"
            for index in "${!grants[@]}"; do
                grant_path="${grants[index]}"
                grant_id="${ids[index]}"
                size="$(stat -c '%s' -- "${grant_path}")" || exit 1
                digest="$(sha256sum -- "${grant_path}")" || exit 1
                digest="${digest%% *}"
                [[ "${digest}" =~ ^[0-9a-f]{64}$ ]] || exit 1
                printf ',{"Id":"%s","Kind":"file","Path":%s,"SizeBytes":%s,"Sha256":"%s"}' \
                    "${grant_id}" "$(snapshot_transport_json_string "${grant_path}")" "${size}" "${digest}"
            done
            printf ']}\n'
        } > "${manifest}"
        chmod 600 -- "${manifest}"
    ); then
        snapshot_transport_error 'Could not write the runner-owned snapshot grant manifest.'
        return 1
    fi
    local -n snapshot_transport_arguments_ref="${destination_name}"
    snapshot_transport_arguments_ref=(
        --runtime-root "${runtime_root}"
        --grant-manifest "${manifest}"
        --expected-policy-digest "${policy_digest}"
    )
}

snapshot_transport_exit_record_clean() {
    local exit_file="$1" policy_digest="$2" phase="$3"
    python3 -I - "${exit_file}" "${policy_digest}" "${phase}" <<'PY'
import json
import os
import pathlib
import stat
import sys

path = pathlib.Path(sys.argv[1])
metadata = path.lstat()
if (not stat.S_ISREG(metadata.st_mode) or metadata.st_uid != os.getuid()
        or stat.S_IMODE(metadata.st_mode) != 0o600 or metadata.st_size > 4096):
    raise SystemExit(1)
value = json.loads(path.read_text(encoding="utf-8"))
if (not isinstance(value, dict) or set(value) != {
        "BrokerVersion", "CleanExit", "CompletedAt", "Phase", "PolicyDigest"}
        or value["BrokerVersion"] != "1.0" or value["CleanExit"] is not True
        or value["PolicyDigest"] != sys.argv[2] or value["Phase"] != sys.argv[3]):
    raise SystemExit(1)
PY
}

# A resumed worker session restarts the snapshot broker in its runtime root.
# Wait, within a bound, until the previous broker has finished, and require its
# recorded clean exit, so the next lifecycle can start in the same root.
snapshot_transport_wait_idle() {
    local runtime_root="$1" policy_digest="$2" phase="$3" limit="${4:-30}"
    local exit_file="${runtime_root}/snapshot-broker-exit.json"
    local pid_file="${runtime_root}/snapshot-broker.pid"
    local attempts

    [[ "${limit}" =~ ^[1-9][0-9]{0,2}$ ]] || return 1
    attempts=$((limit * 5))
    snapshot_transport_canonical_path "${runtime_root}" directory || return 1
    while [[ -e "${pid_file}" || -L "${pid_file}" ]]; do
        if ((attempts-- <= 0)); then
            snapshot_transport_error 'The previous snapshot broker did not finish in time.'
            return 1
        fi
        sleep 0.2
    done
    [[ -e "${exit_file}" || -L "${exit_file}" ||
        -e "${runtime_root}/snapshot-broker-process.txt" ]] || return 0
    snapshot_transport_exit_record_clean "${exit_file}" "${policy_digest}" "${phase}" || {
        snapshot_transport_error 'The previous snapshot broker did not record a clean exit.'
        return 1
    }
}

snapshot_transport_cleanup() {
    local runtime_root="$1" policy_digest="$2" phase="$3"
    local pid='' command_line='' attempt broker_path
    local process_file="${runtime_root}/snapshot-broker-process.txt"
    local exit_file="${runtime_root}/snapshot-broker-exit.json"
    local -a process_fields=() stat_fields=() command_fields=()
    [[ ! -e "${runtime_root}" && ! -L "${runtime_root}" ]] && return 0
    snapshot_transport_canonical_path "${runtime_root}" directory || return 1
    [[ "${runtime_root##*/}" == rhyolite-snapshot-read.* &&
        "$(stat -c '%u' -- "${runtime_root}")" == "$(id -u)" &&
        "$(stat -c '%a' -- "${runtime_root}")" == 700 ]] || return 1
    if [[ -e "${process_file}" ]]; then
        snapshot_transport_canonical_path "${process_file}" file || return 1
        [[ "$(stat -c '%u:%a:%h' -- "${process_file}")" == "$(id -u):600:1" ]] || return 1
        mapfile -t process_fields < "${process_file}"
        [[ ${#process_fields[@]} == 3 &&
            "${process_fields[0]}" =~ ^[0-9]{1,10}$ &&
            "${process_fields[1]}" =~ ^[0-9]{1,20}$ &&
            "${process_fields[2]}" == "$(id -u)" ]] || return 1
        pid="${process_fields[0]}"
        if kill -0 "${pid}" 2>/dev/null; then
            [[ -r "/proc/${pid}/stat" && -r "/proc/${pid}/cmdline" ]] || return 1
            read -r command_line < "/proc/${pid}/stat" || return 1
            command_line="${command_line##*) }"
            read -r -a stat_fields <<< "${command_line}"
            [[ "${stat_fields[19]-}" == "${process_fields[1]}" &&
                "$(stat -c '%u' -- "/proc/${pid}")" == "${process_fields[2]}" ]] || return 1
            broker_path="$(
                readlink -e -- "${BASH_SOURCE[0]%/*}/research-egress-broker.py"
            )" || return 1
            mapfile -d '' -t command_fields < "/proc/${pid}/cmdline"
            [[ ${#command_fields[@]} == 9 &&
                "${command_fields[0]}" == /usr/bin/python3 &&
                "${command_fields[1]}" == "${broker_path}" &&
                "${command_fields[2]}" == --snapshot-mode &&
                "${command_fields[3]}" == --runtime-root &&
                "${command_fields[4]}" == "${runtime_root}" &&
                "${command_fields[5]}" == --snapshot-grant-manifest &&
                "${command_fields[6]}" == "${runtime_root}/snapshot-grants.json" &&
                "${command_fields[7]}" == --expected-snapshot-policy-digest &&
                "${command_fields[8]}" == "${policy_digest}" ]] ||
                { snapshot_transport_error 'Snapshot cleanup refused an unverified broker process.'; return 1; }
            kill -TERM "${pid}" 2>/dev/null || true
            for attempt in 1 2 3 4 5; do
                kill -0 "${pid}" 2>/dev/null || break
                if [[ -r "/proc/${pid}/stat" ]]; then
                    read -r command_line < "/proc/${pid}/stat" || return 1
                    command_line="${command_line##*) }"
                    [[ "${command_line}" != Z\ * ]] || break
                fi
                sleep 1
            done
            if kill -0 "${pid}" 2>/dev/null && [[ "${command_line}" != Z\ * ]]; then
                snapshot_transport_error 'Snapshot broker did not stop gracefully.'
                return 1
            fi
        fi
        [[ -f "${exit_file}" && ! -L "${exit_file}" ]] || return 1
    fi
    if [[ -e "${exit_file}" ]]; then
        snapshot_transport_exit_record_clean "${exit_file}" "${policy_digest}" "${phase}" ||
            return 1
    fi
    [[ ! -L "${runtime_root}/snapshot-broker.pid" ]] || return 1
    if [[ -e "${runtime_root}/snapshot-broker.pid" && ! -e "${process_file}" ]]; then
        snapshot_transport_error 'Snapshot cleanup has a PID without a verified process identity.'
        return 1
    fi
    rm -rf -- "${runtime_root}"
    [[ ! -e "${runtime_root}" && ! -L "${runtime_root}" ]]
}
