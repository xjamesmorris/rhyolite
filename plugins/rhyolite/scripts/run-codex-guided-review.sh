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
                execution_stdout="${session_directory}/codex-run.stdout"
                execution_stderr="${session_directory}/codex-run.stderr"
                : > "${execution_stdout}"
                : > "${execution_stderr}"
                active_run_folder=''
                stop_requested=0
                runner_pid=''
                controller_input=1
                stop_active_runner() {
                    local reason="$1"

                    ((stop_requested == 0)) || return 0
                    stop_requested=1
                    if [[ -n "${active_run_folder}" ]]; then
                        printf 'Stopping Rhyolite review (%s)...\n' "${reason}" >&2
                        /usr/bin/bash "${runner}" \
                            --harness codex \
                            --request-stop "${active_run_folder}" ||
                            true
                    elif [[ -n "${runner_pid}" ]] &&
                        kill -0 "${runner_pid}" 2>/dev/null; then
                        kill -TERM "${runner_pid}" 2>/dev/null || true
                    fi
                }
                run_started_epoch="$(date +%s)"
                trap 'stop_active_runner signal' INT TERM HUP
                if [[ -t 0 ]]; then
                    printf '%s\n' \
                        'Review started. Type exact stop or cancel to interrupt, or /rhyolite:status for current state.' >&2
                fi
                set +e
                /usr/bin/bash "${runner}" \
                    "${runner_arguments[@]}" \
                    --expected-plan-hash "${approval_hash}" \
                    > >(tee "${execution_stdout}") \
                    2> >(tee "${execution_stderr}" >&2) &
                runner_pid=$!
                # The runner names its run output folder when the run starts.
                refresh_active_run_folder() {
                    [[ -z "${active_run_folder}" ]] || return 0
                    active_run_folder="$(
                        sed -n \
                            's/^RHYOLITE PROGRESS | run | started | .* output //p' \
                            "${execution_stdout}" |
                            tail -n 1
                    )"
                }
                while kill -0 "${runner_pid}" 2>/dev/null; do
                    refresh_active_run_folder
                    if ((controller_input)); then
                        command=''
                        IFS= read -r -t 1 command
                        read_status=$?
                        if ((read_status == 0)); then
                            case "${command}" in
                                stop|cancel)
                                    refresh_active_run_folder
                                    stop_active_runner "${command}"
                                    ;;
                                /rhyolite:status)
                                    refresh_active_run_folder
                                    print_run_status \
                                        "${active_run_folder}" \
                                        "${execution_stdout}"
                                    ;;
                                '')
                                    ;;
                                *)
                                    printf '%s\n' \
                                        'During review execution, enter exact stop, cancel, or /rhyolite:status.' >&2
                                    ;;
                            esac
                        elif ((read_status == 1)); then
                            controller_input=0
                        fi
                    else
                        sleep 1
                    fi
                done
                wait "${runner_pid}"
                execution_status=$?
                set -e
                trap - INT TERM HUP
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
