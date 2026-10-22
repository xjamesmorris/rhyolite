#!/usr/bin/env bash

set -euo pipefail
umask 077

owner_pid="${1-}"
owner_start_time="${2-}"
shift 2
[[ "${1-}" == -- ]] || {
    printf '%s\n' 'Broker supervisor command separator is missing.' >&2
    exit 2
}
shift
[[ "${owner_pid}" =~ ^[1-9][0-9]*$ &&
    "${owner_start_time}" =~ ^[1-9][0-9]*$ &&
    $# -gt 0 ]] || {
    printf '%s\n' 'Broker supervisor owner identity is invalid.' >&2
    exit 2
}

owner_is_current() {
    local stat_line stat_fields owner_uid
    [[ -r "/proc/${owner_pid}/stat" &&
        -r "/proc/${owner_pid}/status" ]] || return 1
    stat_line="$(< "/proc/${owner_pid}/stat")" || return 1
    stat_fields="${stat_line##*) }"
    read -r -a stat_values <<< "${stat_fields}"
    ((${#stat_values[@]} > 19)) || return 1
    [[ "${stat_values[19]}" == "${owner_start_time}" ]] || return 1
    owner_uid="$(
        awk '/^Uid:/ { print $2; exit }' "/proc/${owner_pid}/status"
    )" || return 1
    [[ "${owner_uid}" == "$(id -u)" ]]
}

owner_is_current || {
    printf '%s\n' 'Broker supervisor owner process is unavailable.' >&2
    exit 2
}

exec 3<&0 4>&1 5>&2
"$@" <&3 >&4 2>&5 &
broker_pid=$!
owner_lost=0

stop_broker() {
    local attempt
    kill "${broker_pid}" 2>/dev/null || true
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        kill -0 "${broker_pid}" 2>/dev/null || return 0
        sleep 0.1
    done
    kill -KILL "${broker_pid}" 2>/dev/null || true
}

trap 'stop_broker' INT TERM HUP
while kill -0 "${broker_pid}" 2>/dev/null; do
    if ! owner_is_current; then
        owner_lost=1
        stop_broker
        break
    fi
    sleep 0.1
done

set +e
wait "${broker_pid}"
broker_status=$?
set -e
trap - INT TERM HUP
if ((owner_lost)) && ((broker_status != 0)); then
    printf '%s\n' \
        'Broker supervisor stopped the broker after its trusted owner exited.' >&2
fi
exit "${broker_status}"
