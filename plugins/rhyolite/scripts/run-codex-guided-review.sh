#!/usr/bin/env bash

set -euo pipefail
umask 077

plugin_root=''
working_directory=''
session_directory=''
model=''
reasoning_effort=''
context_tier=''
initial_output=''
commit=''
auto_defaults=0
declare -a repositories=()

fail_controller() {
    printf 'Codex guided review controller failed: %s\n' "$1" >&2
    exit 1
}

while (($# > 0)); do
    case "$1" in
        --plugin-root)
            [[ $# -ge 2 && -z "${plugin_root}" ]] || fail_controller arguments
            plugin_root="$2"
            shift 2
            ;;
        --working-directory)
            [[ $# -ge 2 && -z "${working_directory}" ]] || fail_controller arguments
            working_directory="$2"
            shift 2
            ;;
        --session-directory)
            [[ $# -ge 2 && -z "${session_directory}" ]] || fail_controller arguments
            session_directory="$2"
            shift 2
            ;;
        --model)
            [[ $# -ge 2 && -z "${model}" ]] || fail_controller arguments
            model="$2"
            shift 2
            ;;
        --reasoning-effort)
            [[ $# -ge 2 && -z "${reasoning_effort}" ]] || fail_controller arguments
            reasoning_effort="$2"
            shift 2
            ;;
        --context)
            [[ $# -ge 2 && -z "${context_tier}" ]] || fail_controller arguments
            context_tier="$2"
            shift 2
            ;;
        --output-root)
            [[ $# -ge 2 && -z "${initial_output}" ]] || fail_controller arguments
            initial_output="$2"
            shift 2
            ;;
        --repo)
            [[ $# -ge 2 && -n "$2" ]] || fail_controller arguments
            repositories+=("$2")
            shift 2
            ;;
        --commit)
            [[ $# -ge 2 && -z "${commit}" &&
                "$2" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]] ||
                fail_controller arguments
            commit="$2"
            shift 2
            ;;
        --auto-defaults)
            ((auto_defaults == 0)) || fail_controller arguments
            auto_defaults=1
            shift
            ;;
        *)
            fail_controller arguments
            ;;
    esac
done

[[ "${plugin_root}" == /* && -d "${plugin_root}" && ! -L "${plugin_root}" &&
    "${working_directory}" == /* && -d "${working_directory}" &&
    ! -L "${working_directory}" &&
    "${session_directory}" == /* && -d "${session_directory}" &&
    ! -L "${session_directory}" &&
    "${model}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ &&
    "${reasoning_effort}" =~ ^[a-z]{1,32}$ &&
    ${#repositories[@]} -gt 0 ]] || fail_controller validation
[[ -z "${commit}" || ${#repositories[@]} -eq 1 ]] ||
    fail_controller validation
# Only a person at the terminal answers these questions; piped or redirected
# input never approves a plan.
if [[ ! -t 0 || ! -t 2 ]]; then
    printf '%s\n' \
        'The Codex setup and approval questions need an interactive terminal on standard input and standard error.' >&2
    fail_controller terminal
fi

runner="${plugin_root}/skills/readonly-repository-review/scripts/run-parallel-reviews.sh"
[[ -x "${runner}" ]] || fail_controller assets

current_output="${initial_output:-NOT SELECTED}"
current_scope='NOT SELECTED'
current_lookback='NOT SELECTED'
current_cookies='NOT SELECTED'
setup_sequence=0
approval_sequence=0
# full asks every setup question, scope asks only the scope and its follow-up
# questions, auto takes the --auto-defaults answers, and reuse keeps the
# answers after a plan mismatch so that only the plan and approval repeat.
next_setup=full
if ((auto_defaults)); then
    next_setup=auto
fi

print_scope_explanation() {
    printf '%s\n' \
        'Scope 1 covers source, history, architecture, quality, and the full dedicated security pass with the fewest AI credits and only anonymous Git network access.' \
        'Scope 2 adds public prior-art/community research, public network requests, and materially higher resource use.' \
        'Scope 3 adds whole-repository provenance evidence gathering, uses the most AI credits and network requests, and requires human review before sharing.' \
        'Every scope runs the same full security pass with the same approved model, reasoning effort, context tier, and session time limit.' \
        'All timing ranges are rough and can increase substantially for large repositories or broad topics.' >&2
}

# The setup and approval questions use the launcher's numbered prompts on
# stderr. End of input, or exact stop or cancel, at any question leaves
# without starting a review.
stop_without_review() {
    printf '%s\n' 'Rhyolite stopped without starting a review.' >&2
    exit 0
}

# Read one answer into prompt_answer.
#   ask <prompt>
ask() {
    printf '%s' "$1" >&2
    prompt_answer=''
    if ! IFS= read -r prompt_answer; then
        printf '\n' >&2
        stop_without_review
    fi
    case "${prompt_answer}" in
        stop|cancel) stop_without_review ;;
    esac
}

valid_output_root() {
    [[ "$1" == /* && "$1" != *[[:cntrl:]]* &&
        "$(printf '%s' "$1" | wc -c)" -le 4096 ]]
}

ask_output() {
    local current_choice="${working_directory%/}/rhyolite-output/repo-review"
    local home_choice="${HOME%/}/rhyolite-output/repo-review"
    local -a paths=() labels=()
    local index other

    if [[ "${current_choice}" == "${home_choice}" ]]; then
        paths=("${current_choice}")
        labels=("Current directory - ${current_choice}")
    elif [[ "${current_output}" == "${home_choice}" ]]; then
        paths=("${home_choice}" "${current_choice}")
        labels=(
            "Home directory - ${home_choice}"
            "Current directory - ${current_choice}"
        )
    else
        paths=("${current_choice}" "${home_choice}")
        labels=(
            "Current directory - ${current_choice}"
            "Home directory - ${home_choice}"
        )
    fi
    # Another path chosen earlier stays the default, as a remembered choice
    # does in the launcher.
    if [[ "${current_output}" != 'NOT SELECTED' &&
        "${current_output}" != "${current_choice}" &&
        "${current_output}" != "${home_choice}" ]]; then
        paths=("${current_output}" "${paths[@]}")
        labels=("Keep current output - ${current_output}" "${labels[@]}")
    fi
    other=$((${#paths[@]} + 1))
    while true; do
        printf '\nOutput location\n' >&2
        for index in "${!labels[@]}"; do
            printf '  %d. %s\n' "$((index + 1))" "${labels[index]}" >&2
        done
        printf '  %d. Enter another absolute path\n' "${other}" >&2
        ask 'Select output [1]: '
        prompt_answer="${prompt_answer:-1}"
        if [[ "${prompt_answer}" =~ ^[1-9][0-9]{0,2}$ ]] &&
            ((prompt_answer <= ${#paths[@]})); then
            current_output="${paths[prompt_answer - 1]}"
            return
        fi
        if [[ "${prompt_answer}" == "${other}" ]]; then
            ask 'Absolute output path: '
            if valid_output_root "${prompt_answer}"; then
                current_output="${prompt_answer}"
                return
            fi
            printf '%s\n' \
                'Enter an absolute path without control characters.' >&2
            continue
        fi
        printf '%s\n' 'Enter one of the displayed choice numbers.' >&2
    done
}

ask_lookback() {
    local -a months=(6 3 12 24)
    local -a labels=(
        '6 months (Recommended)'
        '3 months'
        '12 months'
        '24 months'
    )
    local index other

    if [[ "${current_lookback}" =~ ^[1-9][0-9]?$ &&
        " ${months[*]} " != *" ${current_lookback} "* ]]; then
        months=("${current_lookback}" "${months[@]}")
        labels=("Keep current lookback - ${current_lookback} months" "${labels[@]}")
    fi
    other=$((${#months[@]} + 1))
    while true; do
        printf '\nProvenance lookback\n' >&2
        for index in "${!labels[@]}"; do
            printf '  %d. %s\n' "$((index + 1))" "${labels[index]}" >&2
        done
        printf '  %d. Enter another number of months from 1 through 60\n' \
            "${other}" >&2
        ask 'Select lookback [1]: '
        prompt_answer="${prompt_answer:-1}"
        if [[ "${prompt_answer}" =~ ^[1-9][0-9]{0,2}$ ]] &&
            ((prompt_answer <= ${#months[@]})); then
            current_lookback="${months[prompt_answer - 1]}"
            return
        fi
        if [[ "${prompt_answer}" == "${other}" ]]; then
            ask 'Months (1-60): '
            if [[ "${prompt_answer}" =~ ^[1-9][0-9]?$ ]] &&
                ((prompt_answer <= 60)); then
                current_lookback="${prompt_answer}"
                return
            fi
            printf '%s\n' 'Enter a whole number from 1 through 60.' >&2
            continue
        fi
        printf '%s\n' 'Enter one of the displayed choice numbers.' >&2
    done
}

ask_cookies() {
    local default=1

    [[ "${current_cookies}" != ephemeral ]] || default=2
    printf '\n%s\n' \
        'Raw Set-Cookie values from research stay only in a private per-repository ledger and never reach a model or rendered report.' >&2
    while true; do
        printf '\nResearch cookies\n' >&2
        printf '%s\n' \
            '  1. Do not replay research cookies (Recommended)' \
            '  2. Allow a fresh per-repository research cookie jar' >&2
        ask "Select cookies [${default}]: "
        case "${prompt_answer:-${default}}" in
            1) current_cookies=off; return ;;
            2) current_cookies=ephemeral; return ;;
        esac
        printf '%s\n' 'Enter one of the displayed choice numbers.' >&2
    done
}

# The scope question, then the lookback and cookie questions that the chosen
# scope needs.
ask_scope() {
    local default="${current_scope}"

    [[ "${default}" =~ ^[123]$ ]] || default=1
    printf '\n' >&2
    print_scope_explanation
    while true; do
        printf '\nReview scope\n' >&2
        printf '%s\n' \
            '  1. Scope 1 - Core repository review (Recommended) - 15-45 minutes' \
            '  2. Scope 2 - Core + public prior-art/community research - 30-90+ minutes' \
            '  3. Scope 3 - Full + generated-code provenance review - 60-120+ minutes' >&2
        ask "Select scope [${default}]: "
        case "${prompt_answer:-${default}}" in
            1|2|3)
                current_scope="${prompt_answer:-${default}}"
                break
                ;;
        esac
        printf '%s\n' 'Enter one of the displayed choice numbers.' >&2
    done
    if [[ "${current_scope}" == 3 ]]; then
        ask_lookback
    else
        current_lookback=NULL
    fi
    if [[ "${current_scope}" == 1 ]]; then
        current_cookies=NULL
    else
        ask_cookies
    fi
}

# Keep each answer in the private launcher session for later diagnosis.
#   write_session_record <path> <action> [approval hash]
write_session_record() {
    python3 -I - "$1" "$2" "${3-}" "${current_output}" "${current_scope}" \
        "${current_lookback}" "${current_cookies}" <<'PY'
import json
import os
import sys

path, action, approval_hash, output, scope, lookback, cookies = sys.argv[1:8]
if approval_hash:
    value = {"Action": action, "ApprovalHash": approval_hash}
else:
    value = {
        "Action": action,
        "OutputRoot": output,
        "Scope": int(scope),
        "ProvenanceLookbackMonths": int(lookback) if scope == "3" else None,
        "ResearchCookies": cookies if scope in {"2", "3"} else None,
    }
descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as stream:
    json.dump(value, stream, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    stream.write("\n")
PY
}

# Discard anything typed before the plan appeared, so that only an answer
# given after it can start a review.
discard_typed_ahead_input() {
    [[ -t 0 ]] || return 0
    python3 -I -c \
        'import sys, termios; termios.tcflush(sys.stdin.fileno(), termios.TCIFLUSH)' \
        2>/dev/null || true
}

# Starting a review needs an explicit answer, so this question has no
# default.
ask_approval() {
    discard_typed_ahead_input
    while true; do
        printf '\nEffective review plan\n' >&2
        printf '%s\n' \
            '  1. Run review' \
            '  2. Edit setup' \
            '  3. Explain scope' \
            'Type stop to leave without starting a review.' >&2
        ask 'Select action: '
        case "${prompt_answer}" in
            1|'Run review') approval_action=run; return ;;
            2|'Edit setup') approval_action=edit; return ;;
            3|'Explain scope') approval_action=explain; return ;;
            'Change scope') approval_action=change-scope; return ;;
        esac
        printf '%s\n' 'Enter 1, 2, or 3, or type stop.' >&2
    done
}

# The key choices of the authoritative plan, printed after its full JSON so
# that they sit directly above the approval question.
print_plan_summary() {
    local plan="$1"

    python3 -I - "${plan}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    plan = json.load(stream)


def text(value):
    value = "NOT SELECTED" if value in (None, "") else str(value)
    return "".join(character for character in value if character.isprintable())


print("PLAN SUMMARY (the full plan above is authoritative)")
for source in plan.get("Sources") or []:
    if isinstance(source, dict):
        commit = source.get("RequestedCommit") or "the default branch at clone time"
        print(f"  Source: {text(source.get('RemoteUrl'))} at {text(commit)}")
scope = plan.get("Scope")
if isinstance(scope, dict):
    # The scope name already starts with its number.
    scope = scope.get("Name") or scope.get("Number")
print(f"  Scope: {text(scope)}")
print(f"  Output: {text(plan.get('OutputRoot'))}")
print("  Runtime: " + ", ".join(text(plan.get(key)) for key in (
    "Harness", "Model", "ReasoningEffort", "ContextTier")))
scans = plan.get("SecurityScans") if isinstance(plan.get("SecurityScans"), dict) else {}
print(f"  Security scans: {text(scans.get('Count'))}")
research = plan.get("ResearchTransport") if isinstance(plan.get("ResearchTransport"), dict) else {}
print(f"  Public research: {'enabled' if research.get('Enabled') is True else 'disabled'}")
print(f"  Session time limit: {text(plan.get('SessionTimeoutMinutes'))} minutes")
print(f"  Approval hash: {text(plan.get('ApprovalHash'))}")
PY
}

# Report the live review: the runner writes the run's state.json only when it
# finishes, so the latest progress line from its output is the current stage.
#   print_run_status <run folder or empty> <runner stdout copy>
print_run_status() {
    local run_folder="$1"
    local runner_output="$2"
    local progress='' elapsed='UNAVAILABLE' seconds

    if [[ -f "${runner_output}" && ! -L "${runner_output}" ]]; then
        progress="$(
            sed -n 's/^RHYOLITE PROGRESS | //p' "${runner_output}" | tail -n 1
        )"
    fi
    if [[ -n "${run_started_epoch-}" ]]; then
        seconds=$(($(date +%s) - run_started_epoch))
        elapsed="$((seconds / 60))m $((seconds % 60))s"
    fi
    python3 -I - "${run_folder}" "${progress}" "${elapsed}" "${model}" \
        "${reasoning_effort}" "${context_tier}" "${current_scope}" \
        "${repositories[@]}" <<'PY' || true
import json
import pathlib
import sys

(run_folder, progress, elapsed, model, effort, context, scope,
 *sources) = sys.argv[1:]


def text(value):
    return "".join(character for character in str(value) if character.isprintable())


state = {}
if run_folder:
    path = pathlib.Path(run_folder) / "state.json"
    if path.is_file() and not path.is_symlink():
        try:
            state = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            state = {}
    state = state if isinstance(state, dict) else {}
print("RHYOLITE STATUS")
print("Command: repo-review")
print(f"Stage: {text(progress) if progress else 'STARTING'}")
print(f"Elapsed: {text(elapsed)}")
print("Harness: codex")
print(f"Source: {text(', '.join(sources))}")
print(f"Model: {text(model)} ({text(effort)}, {text(context)})")
print(f"Scope: {text(scope)}")
print(f"Output: {text(run_folder) if run_folder else 'NOT AVAILABLE YET'}")
if run_folder:
    run_id = state.get("RunId") or pathlib.Path(run_folder).name
    print(f"Review run: {text(run_id)} ({text(state.get('Status') or 'Running')})")
else:
    print("Review run: NOT STARTED")
repositories = state.get("Repositories")
if isinstance(repositories, list):
    counts = {}
    for repository in repositories:
        if isinstance(repository, dict):
            status = text(repository.get("Status", "UNKNOWN"))
            counts[status] = counts.get(status, 0) + 1
    if counts:
        print("Repositories: " + ", ".join(f"{key}={counts[key]}" for key in sorted(counts)))
PY
}

# The approved review writes its output to private session files, and the
# controller shows that output as a live review view, so the review stays in
# the same interactive screen as the questions. Progress becomes readable
# milestone lines; the runner's text copy of the plan that was just approved
# and its heartbeats stay only in the files. At a capable terminal, a status
# line kept at the bottom shows a spinner, the elapsed time, the current
# stage, and the command being typed, and the terminal stays in character
# mode until the review ends. A dumb terminal gets the same lines without the
# status line.

review_measure_terminal() {
    local size columns

    size="$(stty size 2>/dev/null)" || size=''
    columns="${size##* }"
    if [[ "${columns}" =~ ^[0-9]+$ ]] && ((columns > 0)); then
        review_columns="${columns}"
    elif [[ "${COLUMNS-}" =~ ^[0-9]+$ ]] && ((COLUMNS > 0)); then
        review_columns="${COLUMNS}"
    else
        review_columns=80
    fi
}

review_erase_footer() {
    ((review_footer_visible)) || return 0
    printf '\r\033[K' >&2
    review_footer_visible=0
}

# Print one line in place of the status line, which the loop draws again.
#   review_emit <out|err> <line>
review_emit() {
    review_erase_footer
    if [[ "$1" == err ]]; then
        printf '%s\n' "$2" >&2
    else
        printf '%s\n' "$2"
    fi
}

# The status line never wraps: the placeholder goes first, then the stage
# text shortens, and a long command keeps its end visible.
review_draw_footer() {
    local now seconds elapsed spinner left text placeholder='' stage room width line

    ((review_live)) || return 0
    if ((review_columns < 30)); then
        review_erase_footer
        return 0
    fi
    now="${EPOCHSECONDS:-$(date +%s)}"
    seconds=$((now - run_started_epoch))
    ((seconds >= 0)) || seconds=0
    elapsed="$((seconds / 60))m $((seconds % 60))s"
    spinner="${review_spinner[review_frame % ${#review_spinner[@]}]}"
    width=$((review_columns - 1))
    left="${spinner} ${elapsed}"
    text="${review_input}"
    [[ -n "${text}" ]] || placeholder='type stop, cancel, or /rhyolite:status'
    # Two spaces, the prompt mark, and a space follow the elapsed time.
    room=$((width - ${#left} - 4))
    if ((${#text} > room)); then
        text="${review_ellipsis}${text: -$((room - ${#review_ellipsis}))}"
    fi
    # At a narrow terminal the stage matters more than the placeholder, whose
    # commands the header above already names.
    if [[ -n "${placeholder}" ]] &&
        ((width - ${#left} - ${#review_separator} - 4 - ${#placeholder} < 24)); then
        placeholder=''
    fi
    stage="${review_stage}"
    room=$((width - ${#left} - ${#review_separator} - 4 - ${#text} - ${#placeholder}))
    if ((room < 8)); then
        stage=''
    elif ((${#stage} > room)); then
        stage="${stage:0:$((room - ${#review_ellipsis}))}${review_ellipsis}"
    fi
    line="${review_accent}${spinner}${review_reset} ${elapsed}"
    [[ -z "${stage}" ]] ||
        line+="${review_dim}${review_separator}${review_reset}${stage}"
    line+="  ${review_accent}${review_prompt_mark}${review_reset} ${text}"
    printf '\r\033[K%s' "${line}" >&2
    if [[ -n "${placeholder}" ]]; then
        # Keep the cursor where the command will appear.
        printf '%s\033[%dD' "${review_dim}${placeholder}${review_reset}" \
            "${#placeholder}" >&2
    fi
    review_footer_visible=1
}

#   review_handle_progress <subject> <stage> <detail>
review_handle_progress() {
    local subject="$1" stage="$2" detail="$3" name label='' text time padded

    if [[ "${subject}" == run && "${stage}" == started &&
        "${detail}" == *' repositories; output '* && -z "${active_run_folder}" ]]; then
        active_run_folder="${detail#*'; output '}"
    fi
    if [[ "${subject}" == run && "${stage}" == completed ]]; then
        review_final_status="${detail%%; *}"
    fi
    name="${stage//-/ }"
    name="${name^}"
    if [[ "${subject}" != run ]] &&
        { ((${#repositories[@]} > 1)) || [[ "${subject}" == */* ]]; }; then
        label="${subject}: "
    fi
    text="${label}${detail}"
    # A heartbeat only confirms that a stage is still running, which the
    # status line's spinner and elapsed time already show.
    if [[ "${detail}" == *'still running; elapsed '* ]]; then
        ((review_live == 0)) || return 0
    else
        review_stage="${name}${text:+: ${text}}"
    fi
    printf -v time '%(%H:%M:%S)T' -1
    printf -v padded '%-14s' "${name}"
    review_emit out \
        "  ${review_dim}${time}${review_reset}  ${review_accent}${padded}${review_reset} ${text}"
}

review_handle_stdout_line() {
    local line="$1" rest subject stage detail

    # The runner first prints a text copy of the effective plan between
    # delimiter lines; it is the plan just shown and approved.
    case "${review_plan_state}" in
        held)
            if [[ "${line}" == 'EFFECTIVE REVIEW PLAN' ]]; then
                review_plan_state=title
                return 0
            fi
            review_plan_state=none
            review_emit out "${review_held_line}"
            ;;
        title)
            [[ ! "${line}" =~ ^={80,}$ ]] || review_plan_state=body
            return 0
            ;;
        body)
            [[ ! "${line}" =~ ^={80,}$ ]] || review_plan_state=none
            return 0
            ;;
    esac
    if [[ "${line}" =~ ^={80,}$ ]]; then
        review_plan_state=held
        review_held_line="${line}"
        return 0
    fi
    if [[ "${line}" == 'RHYOLITE PROGRESS | '* ]]; then
        rest="${line#'RHYOLITE PROGRESS | '}"
        subject="${rest%%' | '*}"
        rest="${rest:${#subject}}"
        rest="${rest#' | '}"
        stage="${rest%%' | '*}"
        detail="${rest:${#stage}}"
        detail="${detail#' | '}"
        review_handle_progress "${subject}" "${stage}" "${detail}"
        return 0
    fi
    review_emit out "${line}"
}

review_handle_stderr_line() {
    # Bash reports the sleep that the runner's own stop handling ended.
    [[ ! "$1" =~ ^Terminated\ +sleep\ [0-9.]+$ ]] || return 0
    review_emit err "$1"
}

# Show every complete line that the runner has written since the last call.
review_pump_output() {
    local chunk

    while true; do
        chunk=''
        if IFS= read -r -u "${review_out_fd}" chunk; then
            review_handle_stdout_line "${review_out_partial}${chunk}"
            review_out_partial=''
        else
            review_out_partial+="${chunk}"
            break
        fi
    done
    while true; do
        chunk=''
        if IFS= read -r -u "${review_err_fd}" chunk; then
            review_handle_stderr_line "${review_err_partial}${chunk}"
            review_err_partial=''
        else
            review_err_partial+="${chunk}"
            break
        fi
    done
}

review_flush_output() {
    review_pump_output
    if [[ "${review_plan_state}" == held ]]; then
        review_plan_state=none
        review_emit out "${review_held_line}"
    fi
    if [[ -n "${review_out_partial}" ]]; then
        review_handle_stdout_line "${review_out_partial}"
        review_out_partial=''
    fi
    if [[ -n "${review_err_partial}" ]]; then
        review_handle_stderr_line "${review_err_partial}"
        review_err_partial=''
    fi
}

review_run_command() {
    case "$1" in
        stop|cancel)
            stop_active_runner "$1"
            ;;
        /rhyolite:status)
            review_erase_footer
            print_run_status "${active_run_folder}" "${execution_stdout}"
            ;;
        '')
            ;;
        *)
            review_emit err \
                'During review execution, enter exact stop, cancel, or /rhyolite:status.'
            ;;
    esac
}

# Edit the command on the status line, one key at a time.
review_handle_key() {
    local key="$1" code command

    [[ -n "${key}" ]] || return 0
    printf -v code '%d' "'${key}"
    case "${code}" in
        10|13)
            command="${review_input}"
            review_input=''
            [[ -z "${command}" ]] ||
                review_emit err \
                    "${review_dim}${review_prompt_mark} ${command}${review_reset}"
            review_run_command "${command}"
            ;;
        8|127)
            review_input="${review_input%?}"
            ;;
        21)
            review_input=''
            ;;
        27)
            # Discard the rest of an escape sequence, such as an arrow key.
            while IFS= read -rsn1 -d '' -t 0.02 key; do :; done
            ;;
        *)
            if ((code >= 32 && code <= 126 && ${#review_input} < 200)); then
                review_input+="${key}"
            fi
            ;;
    esac
}

stop_active_runner() {
    local reason="$1"

    ((stop_requested == 0)) || return 0
    stop_requested=1
    review_stage='Stopping the review'
    review_emit err "Stopping Rhyolite review (${reason})..."
    if [[ -n "${active_run_folder}" ]]; then
        # The verified stop request returns after the runner finalizes; the
        # live view keeps running meanwhile.
        /usr/bin/bash "${runner}" \
            --harness codex \
            --request-stop "${active_run_folder}" \
            < /dev/null > "${review_stop_output}" 2>&1 \
            {review_out_fd}<&- {review_err_fd}<&- &
        stop_pid=$!
    elif [[ -n "${runner_pid}" ]] && kill -0 "${runner_pid}" 2>/dev/null; then
        kill -TERM "${runner_pid}" 2>/dev/null || true
    fi
}

# When the verified stop request failed while the runner still runs, show
# why and end the runner, which this controller started.
review_check_stop_request() {
    local status line

    [[ -n "${stop_pid}" ]] || return 0
    ! kill -0 "${stop_pid}" 2>/dev/null || return 0
    wait "${stop_pid}"
    status=$?
    stop_pid=''
    ((status != 0)) && kill -0 "${runner_pid}" 2>/dev/null || return 0
    while IFS= read -r line; do
        review_emit err "${line}"
    done < "${review_stop_output}"
    kill -TERM "${runner_pid}" 2>/dev/null || true
}

review_restore_terminal() {
    review_erase_footer
    if [[ -n "${review_saved_tty}" ]]; then
        stty "${review_saved_tty}" 2>/dev/null || true
        review_saved_tty=''
    fi
}

# Ctrl-Z stops this controller with the rest of the job, and a job-control
# shell then restores its own terminal settings; take character mode again
# when the job continues. Where no job-control shell runs, the process group
# is orphaned and the kernel discards Ctrl-Z, so the review simply goes on.
review_resume() {
    stty -icanon -echo min 1 time 0 2>/dev/null
    review_resized=1
}

review_begin() {
    review_live=0
    review_columns=80
    review_saved_tty=''
    review_footer_visible=0
    review_resized=0
    review_input=''
    review_frame=0
    review_stage='Starting'
    review_final_status=''
    review_plan_state=none
    review_held_line=''
    review_out_partial=''
    review_err_partial=''
    review_stop_output="${session_directory}/codex-stop.out"
    review_accent=''
    review_dim=''
    review_reset=''
    stop_requested=0
    stop_pid=''
    runner_pid=''
    active_run_folder=''
    controller_input=1
    if [[ -z "${NO_COLOR+x}" && "${COPILOT_NO_COLOR-}" != 1 &&
        "${FORCE_COLOR-}" != 0 && "${TERM-}" != dumb ]]; then
        review_accent=$'\033[38;2;66;203;255m'
        review_dim=$'\033[2m'
        review_reset=$'\033[0m'
    fi
    # Bash counts characters, not bytes, only in a UTF-8 locale.
    if [[ "$(locale charmap 2>/dev/null)" == UTF-8 ]]; then
        review_spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        review_separator=' · '
        review_prompt_mark='›'
        review_ellipsis='…'
    else
        review_spinner=('|' '/' '-' '\')
        review_separator=' - '
        review_prompt_mark='>'
        review_ellipsis='...'
    fi
    case "${TERM-}" in
        '' | dumb | unknown)
            ;;
        *)
            review_saved_tty="$(stty -g 2>/dev/null)" || review_saved_tty=''
            if [[ -n "${review_saved_tty}" ]] &&
                stty -icanon -echo min 1 time 0 2>/dev/null; then
                review_live=1
                trap 'review_restore_terminal' EXIT
                trap 'review_resized=1' WINCH
                trap 'review_resume' CONT
                review_measure_terminal
            else
                review_saved_tty=''
            fi
            ;;
    esac
}

review_print_header() {
    local sources='' repository

    for repository in "${repositories[@]}"; do
        sources+="${sources:+, }${repository}"
    done
    printf '\n%s\n' "${review_accent}Review running${review_reset}"
    printf '  Source: %s\n' "${sources}"
    printf '  Runtime: codex, %s, %s, %s; scope %s\n' \
        "${model}" "${reasoning_effort}" "${context_tier}" "${current_scope}"
    printf '  Full runner output: %s\n' "${execution_stdout}"
    printf '  %s\n\n' \
        'Type stop or cancel to stop the review, or /rhyolite:status for its current state. Ctrl-C also stops it.'
}

review_report_finish() {
    local index="${active_run_folder}/index.html"

    [[ -n "${review_final_status}" ]] || return 0
    if [[ -n "${active_run_folder}" && -f "${index}" ]]; then
        printf '\nReview finished: %s. Open %s to read the results.\n' \
            "${review_final_status}" "${index}"
    else
        printf '\nReview finished: %s.\n' "${review_final_status}"
    fi
}

# Run the approved review with its live view and set execution_status.
run_approved_review() {
    local key read_status attempt

    set +e
    execution_stdout="${session_directory}/codex-run.stdout"
    execution_stderr="${session_directory}/codex-run.stderr"
    : > "${execution_stdout}"
    : > "${execution_stderr}"
    review_begin
    run_started_epoch="${EPOCHSECONDS:-$(date +%s)}"
    review_print_header
    exec {review_out_fd}<"${execution_stdout}" {review_err_fd}<"${execution_stderr}"
    trap 'stop_active_runner signal' INT TERM HUP
    # The runner never reads the terminal, which the live view owns, and
    # inherits none of the live view's descriptors.
    /usr/bin/bash "${runner}" \
        "${runner_arguments[@]}" \
        --expected-plan-hash "${approval_hash}" \
        < /dev/null > "${execution_stdout}" 2> "${execution_stderr}" \
        {review_out_fd}<&- {review_err_fd}<&- &
    runner_pid=$!
    while kill -0 "${runner_pid}" 2>/dev/null; do
        review_pump_output
        review_check_stop_request
        if ((review_resized)); then
            review_resized=0
            review_measure_terminal
        fi
        if ((review_live)); then
            review_frame=$((review_frame + 1))
            review_draw_footer
            if ((controller_input)); then
                key=''
                IFS= read -rsn1 -d '' -t 0.25 key
                read_status=$?
                if ((read_status == 0)); then
                    review_handle_key "${key}"
                elif ((read_status == 1)); then
                    controller_input=0
                fi
            else
                sleep 0.25
            fi
        elif ((controller_input)); then
            key=''
            IFS= read -r -t 1 key
            read_status=$?
            if ((read_status == 0)); then
                review_run_command "${key}"
            elif ((read_status == 1)); then
                controller_input=0
            fi
        else
            sleep 1
        fi
    done
    wait "${runner_pid}"
    execution_status=$?
    for ((attempt = 0; attempt < 120; attempt++)); do
        [[ -n "${stop_pid}" ]] && kill -0 "${stop_pid}" 2>/dev/null || break
        sleep 0.25
    done
    review_check_stop_request
    review_flush_output
    review_restore_terminal
    trap - INT TERM HUP EXIT WINCH CONT
    exec {review_out_fd}<&- {review_err_fd}<&-
    review_report_finish
    set -e
}

while true; do
    setup_sequence=$((setup_sequence + 1))
    case "${next_setup}" in
        auto)
            # --auto-defaults accepts the home output and scope 1 without a
            # setup question; the effective plan still needs explicit approval.
            current_output="${HOME%/}/rhyolite-output/repo-review"
            current_scope=1
            current_lookback=NULL
            current_cookies=NULL
            ;;
        full)
            ask_output
            ask_scope
            write_session_record \
                "${session_directory}/codex-setup-${setup_sequence}.json" \
                continue || fail_controller session-record
            ;;
        scope)
            ask_scope
            write_session_record \
                "${session_directory}/codex-setup-${setup_sequence}.json" \
                continue || fail_controller session-record
            ;;
        reuse)
            ;;
        *)
            fail_controller setup-mode
            ;;
    esac

    # The offline snapshot transport keeps the integrated security pass.
    declare -a runner_arguments=(
        --harness codex
        --security-scans 1
        --model "${model}"
        --reasoning-effort "${reasoning_effort}"
        --context "${context_tier}"
        --output-root "${current_output}"
        --scope "${current_scope}"
        --remember-preferences
        --non-interactive
        --no-open-html
    )
    for repository in "${repositories[@]}"; do
        runner_arguments+=(--repo "${repository}")
    done
    if [[ -n "${commit}" ]]; then
        runner_arguments+=(--commit "${commit}")
    fi
    if [[ "${current_scope}" == 3 ]]; then
        runner_arguments+=(--provenance-lookback-months "${current_lookback}")
    fi
    if [[ "${current_scope}" == 2 || "${current_scope}" == 3 ]]; then
        runner_arguments+=(--research-cookies "${current_cookies}")
    fi

    plan_path="${session_directory}/codex-plan-${setup_sequence}.json"
    plan_error="${session_directory}/codex-plan-${setup_sequence}.stderr"
    if ! /usr/bin/bash "${runner}" \
        "${runner_arguments[@]}" \
        --plan-only > "${plan_path}" 2> "${plan_error}"; then
        cat -- "${plan_error}" >&2
        fail_controller plan
    fi
    chmod 600 -- "${plan_path}" "${plan_error}"
    approval_hash="$(
        python3 -I - "${plan_path}" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
approval = value.get("ApprovalHash")
if not isinstance(approval, str) or not re.fullmatch(r"[0-9a-f]{64}", approval):
    raise SystemExit(1)
print(approval)
PY
    )" || fail_controller plan-hash
    printf '\nEFFECTIVE REVIEW PLAN\n'
    python3 -I - "${plan_path}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
print(json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True))
PY
    printf '\n'
    print_plan_summary "${plan_path}" || fail_controller plan-summary
    printf 'The full plan is also saved at %s.\n' "${plan_path}"

    while true; do
        approval_sequence=$((approval_sequence + 1))
        ask_approval
        write_session_record \
            "${session_directory}/codex-approval-${approval_sequence}.json" \
            "${approval_action}" \
            "${approval_hash}" || fail_controller session-record
        case "${approval_action}" in
            run)
                run_approved_review
                # The runner reported this review's outcome, including any
                # RHYOLITE ERROR block, so the launcher adds no second one.
                if [[ -n "${review_final_status}" ]]; then
                    : > "${session_directory}/codex-review-reported"
                fi
                if ((execution_status == 0)); then
                    exit 0
                fi
                if ((stop_requested)); then
                    printf '%s\n' 'Rhyolite review stopped.' >&2
                    exit 0
                fi
                if grep -Fq \
                    'approved plan changed; regenerate and reconfirm' \
                    "${execution_stderr}"; then
                    printf '%s\n' \
                        'The approved effective plan changed; regenerating it with the preserved setup.' >&2
                    next_setup=reuse
                    break
                fi
                exit "${execution_status}"
                ;;
            edit)
                next_setup=full
                break
                ;;
            change-scope)
                next_setup=scope
                break
                ;;
            explain)
                print_scope_explanation
                continue
                ;;
            *)
                fail_controller approval-action
                ;;
        esac
        break
    done
done
