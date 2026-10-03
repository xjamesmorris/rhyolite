#!/usr/bin/env bash

rhyolite_ascii_lower() {
    printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'
}

rhyolite_launcher_home() {
    if [ -n "${XDG_STATE_HOME:-}" ]; then
        case "${XDG_STATE_HOME}" in
            /*)
                printf '%s/rhyolite/launcher\n' "${XDG_STATE_HOME%/}"
                return
                ;;
        esac
    fi

    case "$(uname -s 2>/dev/null || printf 'unknown')" in
        Darwin)
            printf '%s/Library/Application Support/Rhyolite/Launcher\n' \
                "${HOME%/}"
            ;;
        *)
            printf '%s/.local/state/rhyolite/launcher\n' "${HOME%/}"
            ;;
    esac
}

rhyolite_launcher_state_anchor() {
    if [ -n "${XDG_STATE_HOME:-}" ]; then
        case "${XDG_STATE_HOME}" in
            /*)
                printf '%s\n' "${XDG_STATE_HOME%/}"
                return
                ;;
        esac
    fi

    printf '%s\n' "${HOME%/}"
}

rhyolite_valid_harness_id() {
    [[ "$1" =~ ^[a-z][a-z0-9-]{0,31}$ ]]
}

rhyolite_valid_model_id() {
    [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]
}

rhyolite_path_has_no_symlink_components() {
    local path="$1"
    local remaining
    local component
    local current='/'

    case "${path}" in
        /*) ;;
        *) return 1 ;;
    esac
    while [[ "${path}" == */ && "${path}" != / ]]; do
        path="${path%/}"
    done
    remaining="${path#/}"
    [[ -n "${remaining}" ]] || return 0

    while true; do
        case "${remaining}" in
            */*)
                component="${remaining%%/*}"
                remaining="${remaining#*/}"
                ;;
            *)
                component="${remaining}"
                remaining=''
                ;;
        esac
        [[ -n "${component}" ]] || return 1
        case "${component}" in
            .|..) return 1 ;;
        esac
        if [[ "${current}" == / ]]; then
            current="/${component}"
        else
            current="${current}/${component}"
        fi
        [[ ! -L "${current}" ]] || return 1
        [[ -e "${current}" ]] || return 0
        [[ -n "${remaining}" ]] || return 0
    done
}

rhyolite_path_is_within_anchor() {
    local anchor="$1"
    local path="$2"

    while [[ "${anchor}" == */ && "${anchor}" != / ]]; do
        anchor="${anchor%/}"
    done
    while [[ "${path}" == */ && "${path}" != / ]]; do
        path="${path%/}"
    done
    case "${path}" in
        "${anchor}"|"${anchor}"/*) return 0 ;;
        *) return 1 ;;
    esac
}

rhyolite_secure_path_component() {
    local path="$1"
    local expected_uid="$2"
    local metadata
    local owner
    local mode
    local mode_value

    metadata="$(stat -c '%u %a' -- "${path}" 2>/dev/null)" || return 1
    owner="${metadata%% *}"
    mode="${metadata#* }"
    [[ "${owner}" == "${expected_uid}" ]] || return 1
    [[ "${mode}" =~ ^[0-7]{3,4}$ ]] || return 1
    mode_value=$((8#${mode}))
    (( (mode_value & 8#022) == 0 ))
}

rhyolite_secure_user_path() {
    local anchor="$1"
    local path="$2"
    local expected_uid
    local relative
    local remaining
    local component
    local current

    rhyolite_path_is_within_anchor "${anchor}" "${path}" || return 1
    rhyolite_path_has_no_symlink_components "${path}" || return 1
    [[ -e "${anchor}" && ! -L "${anchor}" ]] || return 1
    expected_uid="$(id -u 2>/dev/null)" || return 1
    [[ "${expected_uid}" =~ ^[0-9]+$ ]] || return 1
    rhyolite_secure_path_component "${anchor}" "${expected_uid}" || return 1

    while [[ "${anchor}" == */ && "${anchor}" != / ]]; do
        anchor="${anchor%/}"
    done
    while [[ "${path}" == */ && "${path}" != / ]]; do
        path="${path%/}"
    done
    [[ "${path}" != "${anchor}" ]] || return 0

    relative="${path#"${anchor}"}"
    relative="${relative#/}"
    current="${anchor}"
    remaining="${relative}"
    while [[ -n "${remaining}" ]]; do
        case "${remaining}" in
            */*)
                component="${remaining%%/*}"
                remaining="${remaining#*/}"
                ;;
            *)
                component="${remaining}"
                remaining=''
                ;;
        esac
        [[ -n "${component}" ]] || return 1
        current="${current%/}/${component}"
        [[ -e "${current}" && ! -L "${current}" ]] || return 1
        rhyolite_secure_path_component \
            "${current}" "${expected_uid}" || return 1
    done
}

rhyolite_prepare_secure_user_directory() {
    local anchor="$1"
    local directory="$2"
    local relative
    local remaining
    local component
    local current

    rhyolite_path_is_within_anchor "${anchor}" "${directory}" || return 1
    rhyolite_path_has_no_symlink_components "${directory}" || return 1
    if [[ -e "${anchor}" || -L "${anchor}" ]]; then
        [[ -d "${anchor}" && ! -L "${anchor}" ]] || return 1
        rhyolite_secure_user_path "${anchor}" "${anchor}" || return 1
        relative="${directory#"${anchor%/}"}"
        relative="${relative#/}"
        current="${anchor%/}"
        remaining="${relative}"
        while [[ -n "${remaining}" ]]; do
            case "${remaining}" in
                */*)
                    component="${remaining%%/*}"
                    remaining="${remaining#*/}"
                    ;;
                *)
                    component="${remaining}"
                    remaining=''
                    ;;
            esac
            [[ -n "${component}" ]] || return 1
            current="${current%/}/${component}"
            if [[ -e "${current}" || -L "${current}" ]]; then
                [[ -d "${current}" && ! -L "${current}" ]] || return 1
                rhyolite_secure_user_path \
                    "${anchor}" "${current}" || return 1
            else
                break
            fi
        done
    fi
    if [[ -e "${directory}" || -L "${directory}" ]]; then
        [[ -d "${directory}" && ! -L "${directory}" ]] || return 1
    else
        (
            umask 077
            mkdir -p -- "${directory}"
        ) || return 1
    fi
    rhyolite_path_has_no_symlink_components "${directory}" || return 1
    rhyolite_secure_user_path "${anchor}" "${directory}"
}

rhyolite_preference_anchor() {
    local launcher_home="$1"
    local default_launcher_home

    default_launcher_home="$(rhyolite_launcher_home)"
    if [[ "${launcher_home}" == "${default_launcher_home}" ]]; then
        rhyolite_launcher_state_anchor
    else
        printf '%s\n' "${launcher_home%/}"
    fi
}

rhyolite_decode_url_path() {
    local input="$1"
    local output=""
    local character hex byte
    local index=0

    while ((index < ${#input})); do
        character="${input:index:1}"
        if [[ "${character}" == '%' ]]; then
            ((index + 2 < ${#input})) || return 1
            hex="${input:index+1:2}"
            [[ "${hex}" =~ ^[0-9A-Fa-f]{2}$ ]] || return 1
            printf -v byte '%b' "\\x${hex}"
            output+="${byte}"
            index=$((index + 3))
        else
            output+="${character}"
            index=$((index + 1))
        fi
    done

    printf '%s' "${output}"
}

rhyolite_canonicalize_repository() {
    local input="$1"
    local value="${input}"
    local lower_value remainder authority path host port decoded_path
    local lower_path suffix label
    local -a host_labels

    while [[ "${value}" == */ ]]; do
        value="${value%/}"
    done
    lower_value="$(rhyolite_ascii_lower "${value}")"
    case "${lower_value}" in
        https://*) ;;
        *) return 1 ;;
    esac
    case "${value}" in
        *'?'*|*'#'*|*[$'\001'$'\002'$'\003'$'\004'$'\005'$'\006'$'\007'$'\010'$'\011'$'\012'$'\013'$'\014'$'\015'$'\016'$'\017'$'\020'$'\021'$'\022'$'\023'$'\024'$'\025'$'\026'$'\027'$'\030'$'\031'$'\032'$'\033'$'\034'$'\035'$'\036'$'\037'$'\040'$'\177']*)
            return 1
            ;;
    esac
    if printf '%s' "${lower_value}" |
        grep -Eq '%0[0-9a-f]|%1[0-9a-f]|%7f|%2f|%5c'; then
        return 1
    fi

    remainder="${value:8}"
    authority="${remainder%%/*}"
    path="/${remainder#*/}"
    if [[ "${authority}" == "${remainder}" ]] ||
        [[ -z "${authority}" ]] ||
        [[ "${authority}" == *'@'* ]] ||
        [[ "${authority}" == *'['* || "${authority}" == *']'* ]]; then
        return 1
    fi

    host="${authority}"
    port=""
    if [[ "${authority}" == *:* ]]; then
        host="${authority%%:*}"
        port="${authority#*:}"
        [[ "${port}" =~ ^[0-9]+$ ]] || return 1
        ((10#${port} >= 1 && 10#${port} <= 65535)) || return 1
        if ((10#${port} == 443)); then
            port=""
        fi
    fi
    host="$(rhyolite_ascii_lower "${host}")"
    [[ "${host}" == *.* ]] || return 1
    [[ "${host}" != localhost ]] || return 1
    [[ ! "${host}" =~ ^[0-9.]+$ ]] || return 1
    for suffix in \
        .localhost .local .localdomain .internal .home .lan .corp \
        .test .invalid .example; do
        [[ "${host}" != *"${suffix}" ]] || return 1
    done
    IFS='.' read -r -a host_labels <<< "${host}"
    for label in "${host_labels[@]}"; do
        if [[ ! "${label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] &&
            [[ ! "${label}" =~ ^[A-Za-z0-9]$ ]]; then
            return 1
        fi
    done

    path="${path%/}"
    lower_path="$(rhyolite_ascii_lower "${path}")"
    if [[ "${lower_path}" == *.git ]]; then
        path="${path:0:${#path}-4}"
    fi
    decoded_path="$(rhyolite_decode_url_path "${path}")" || return 1
    if [[ -z "${path#/}" ]] ||
        [[ "${decoded_path}" =~ [[:cntrl:][:space:]\\] ]]; then
        return 1
    fi

    RHYOLITE_CANONICAL_REPOSITORY="https://${host}${port:+:${port}}${path}"
    return 0
}

rhyolite_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
        return
    fi
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
        return
    fi
    if command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 -r | awk '{print $1}'
        return
    fi
    return 1
}

rhyolite_json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "${value}"
}

rhyolite_json_unescape() {
    local value="$1"
    value="${value//\\\//\/}"
    value="${value//\\n/$'\n'}"
    value="${value//\\r/$'\r'}"
    value="${value//\\t/$'\t'}"
    value="${value//\\\"/\"}"
    value="${value//\\\\/\\}"
    printf '%s' "${value}"
}

rhyolite_read_json_string() {
    local file="$1"
    local field="$2"
    local value

    value="$(
        sed -nE \
            "s/^[[:space:]]*\"${field}\"[[:space:]]*:[[:space:]]*\"(([^\"\\\\]|\\\\.)*)\"[[:space:]]*,?[[:space:]]*$/\\1/p" \
            "${file}" | head -n 1
    )"
    [[ -n "${value}" ]] || return 1
    rhyolite_json_unescape "${value}"
}

rhyolite_preference_path() {
    local canonical_repository="$1"
    local launcher_home="${2:-$(rhyolite_launcher_home)}"
    local repository_key

    repository_key="$(
        printf '%s' "${canonical_repository}" | rhyolite_sha256
    )" || return 1
    printf '%s/preferences/%s.json\n' \
        "${launcher_home%/}" "${repository_key}"
}

rhyolite_read_preference() {
    local canonical_repository="$1"
    local selected_harness="$2"
    local launcher_home="${3:-$(rhyolite_launcher_home)}"
    local preference_path
    local preference_anchor
    local schema
    local stored_repository
    local stored_harness
    local fleet_mode
    local model

    RHYOLITE_PREFERENCE_STATUS='missing'
    RHYOLITE_PREFERENCE_HARNESS=''
    RHYOLITE_PREFERENCE_FLEET_MODE=''
    RHYOLITE_PREFERENCE_MODEL=''
    if ! rhyolite_valid_harness_id "${selected_harness}"; then
        RHYOLITE_PREFERENCE_STATUS='invalid'
        return 1
    fi
    preference_path="$(
        rhyolite_preference_path "${canonical_repository}" "${launcher_home}"
    )" || {
        RHYOLITE_PREFERENCE_STATUS='invalid'
        return 1
    }
    if ! rhyolite_path_has_no_symlink_components "${preference_path}"; then
        RHYOLITE_PREFERENCE_STATUS='invalid'
        return 1
    fi
    if [[ ! -e "${preference_path}" && ! -L "${preference_path}" ]]; then
        return 1
    fi
    preference_anchor="$(rhyolite_preference_anchor "${launcher_home}")"
    if [[ ! -f "${preference_path}" || -L "${preference_path}" ]] ||
        ! rhyolite_secure_user_path \
            "${preference_anchor}" "${preference_path}"; then
        RHYOLITE_PREFERENCE_STATUS='invalid'
        return 1
    fi
    if (( $(wc -c < "${preference_path}") > 8192 )); then
        RHYOLITE_PREFERENCE_STATUS='invalid'
        return 1
    fi

    schema="$(
        sed -nE \
            's/^[[:space:]]*"schemaVersion"[[:space:]]*:[[:space:]]*([0-9]+)[[:space:]]*,?[[:space:]]*$/\1/p' \
            "${preference_path}" | head -n 1
    )"
    case "${schema}" in
        1)
            awk '
                function trim(value) {
                    sub(/^[[:space:]]+/, "", value)
                    sub(/[[:space:]]+$/, "", value)
                    return value
                }
                function starts_with(value, prefix) {
                    return substr(value, 1, length(prefix)) == prefix
                }
                function ends_with(value, suffix) {
                    return substr(value, length(value) - length(suffix) + 1) == suffix
                }
                NF {
                    count++
                    lines[count] = trim($0)
                }
                END {
                    if (count != 7 ||
                        lines[1] != "{" ||
                        lines[2] !~ /^"schemaVersion":[[:space:]]*1,$/ ||
                        !starts_with(lines[3], "\"canonicalRepository\": \"") ||
                        !ends_with(lines[3], "\",") ||
                        !starts_with(lines[4], "\"fleetMode\": \"") ||
                        !ends_with(lines[4], "\",") ||
                        !starts_with(lines[5], "\"model\": \"") ||
                        !ends_with(lines[5], "\",") ||
                        !starts_with(lines[6], "\"updatedAt\": \"") ||
                        !ends_with(lines[6], "\"") ||
                        lines[7] != "}") {
                        exit 1
                    }
                }
            ' "${preference_path}" || {
                RHYOLITE_PREFERENCE_STATUS='invalid'
                return 1
            }
            stored_harness='copilot'
            ;;
        2)
            awk '
            function trim(value) {
                sub(/^[[:space:]]+/, "", value)
                sub(/[[:space:]]+$/, "", value)
                return value
            }
            function starts_with(value, prefix) {
                return substr(value, 1, length(prefix)) == prefix
            }
            function ends_with(value, suffix) {
                return substr(value, length(value) - length(suffix) + 1) == suffix
            }
            NF {
                count++
                lines[count] = trim($0)
            }
            END {
                if (count != 8 ||
                    lines[1] != "{" ||
                    lines[2] !~ /^"schemaVersion":[[:space:]]*2,$/ ||
                    !starts_with(lines[3], "\"canonicalRepository\": \"") ||
                    !ends_with(lines[3], "\",") ||
                    !starts_with(lines[4], "\"harness\": \"") ||
                    !ends_with(lines[4], "\",") ||
                    !starts_with(lines[5], "\"fleetMode\": \"") ||
                    !ends_with(lines[5], "\",") ||
                    !starts_with(lines[6], "\"model\": \"") ||
                    !ends_with(lines[6], "\",") ||
                    !starts_with(lines[7], "\"updatedAt\": \"") ||
                    !ends_with(lines[7], "\"") ||
                    lines[8] != "}") {
                    exit 1
                }
            }
        ' "${preference_path}" || {
                RHYOLITE_PREFERENCE_STATUS='invalid'
                return 1
            }
            stored_harness="$(
                rhyolite_read_json_string "${preference_path}" harness
            )" || stored_harness=''
            ;;
        *)
            RHYOLITE_PREFERENCE_STATUS='invalid'
            return 1
            ;;
    esac

    stored_repository="$(
        rhyolite_read_json_string "${preference_path}" canonicalRepository
    )" || stored_repository=''
    fleet_mode="$(
        rhyolite_read_json_string "${preference_path}" fleetMode
    )" || fleet_mode=''
    model="$(
        rhyolite_read_json_string "${preference_path}" model
    )" || model=''

    if [[ "${stored_repository}" != "${canonical_repository}" ]] ||
        ! rhyolite_valid_harness_id "${stored_harness}" ||
        [[ "${fleet_mode}" != native && "${fleet_mode}" != standard ]] ||
        ! rhyolite_valid_model_id "${model}"; then
        RHYOLITE_PREFERENCE_STATUS='invalid'
        return 1
    fi
    if [[ "${stored_harness}" != "${selected_harness}" ]]; then
        RHYOLITE_PREFERENCE_STATUS='mismatch'
        return 1
    fi

    RHYOLITE_PREFERENCE_STATUS='valid'
    RHYOLITE_PREFERENCE_HARNESS="${stored_harness}"
    RHYOLITE_PREFERENCE_FLEET_MODE="${fleet_mode}"
    RHYOLITE_PREFERENCE_MODEL="${model}"
    return 0
}

rhyolite_write_preference() {
    local canonical_repository="$1"
    local harness="$2"
    local fleet_mode="$3"
    local model="$4"
    local launcher_home="${5:-$(rhyolite_launcher_home)}"
    local preference_anchor
    local preference_path
    local preference_dir
    local temporary_path
    local updated_at

    rhyolite_valid_harness_id "${harness}" || return 1
    [[ "${fleet_mode}" == native || "${fleet_mode}" == standard ]] ||
        return 1
    rhyolite_valid_model_id "${model}" || return 1
    preference_path="$(
        rhyolite_preference_path "${canonical_repository}" "${launcher_home}"
    )" || return 1
    preference_anchor="$(rhyolite_preference_anchor "${launcher_home}")"
    preference_dir="$(dirname "${preference_path}")"
    rhyolite_prepare_secure_user_directory \
        "${preference_anchor}" "${preference_dir}" || return 1
    chmod 700 -- "${launcher_home}" "${preference_dir}" 2>/dev/null ||
        return 1
    rhyolite_secure_user_path \
        "${preference_anchor}" "${preference_dir}" || return 1
    if [[ -e "${preference_path}" || -L "${preference_path}" ]]; then
        [[ -f "${preference_path}" && ! -L "${preference_path}" ]] ||
            return 1
        rhyolite_secure_user_path \
            "${preference_anchor}" "${preference_path}" || return 1
    fi
    temporary_path="${preference_path}.tmp.$$"
    [[ ! -e "${temporary_path}" && ! -L "${temporary_path}" ]] || return 1
    updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    (
        umask 077
        cat <<EOF
{
  "schemaVersion": 2,
  "canonicalRepository": "$(rhyolite_json_escape "${canonical_repository}")",
  "harness": "$(rhyolite_json_escape "${harness}")",
  "fleetMode": "$(rhyolite_json_escape "${fleet_mode}")",
  "model": "$(rhyolite_json_escape "${model}")",
  "updatedAt": "$(rhyolite_json_escape "${updated_at}")"
}
EOF
    ) > "${temporary_path}" || {
        rm -f -- "${temporary_path}"
        return 1
    }
    chmod 600 -- "${temporary_path}" || {
        rm -f -- "${temporary_path}"
        return 1
    }
    mv -f -- "${temporary_path}" "${preference_path}" || {
        rm -f -- "${temporary_path}"
        return 1
    }
    [[ -f "${preference_path}" && ! -L "${preference_path}" ]] ||
        return 1
    chmod 600 -- "${preference_path}" || return 1
    rhyolite_secure_user_path \
        "${preference_anchor}" "${preference_path}"
}
