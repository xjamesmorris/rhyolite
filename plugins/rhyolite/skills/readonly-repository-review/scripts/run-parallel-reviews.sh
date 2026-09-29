#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SKILL_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
PLUGIN_ROOT="$(cd -- "${SKILL_ROOT}/../.." && pwd)"
PROMPT_PATH="${SKILL_ROOT}/review-prompt.txt"
OUTPUT_HELPER="${SCRIPT_DIR}/review-output.sh"

if [[ ! -f "${OUTPUT_HELPER}" ]]; then
    printf 'Output processing helper not found: %s\n' "${OUTPUT_HELPER}" >&2
    exit 2
fi
# shellcheck source=review-output.sh
source "${OUTPUT_HELPER}"

THROTTLE_LIMIT=2
MAX_REPOSITORIES=5
SESSION_TIMEOUT_MINUTES=0
WORKSPACE_ROOT="${HOME}/.cache/rhyolite/repo-review/workspaces"
OUTPUT_ROOT=""
PLAN_SCHEMA_VERSION=1
SCOPE=0
SCOPE_SPECIFIED=0
MODEL="gpt-5.6-sol"
ENABLE_PUBLIC_RESEARCH=0
ENABLE_PROVENANCE_RESEARCH=0
DEFAULT_PRIOR_ART_LOOKBACK_MONTHS=6
DEFAULT_PROVENANCE_LOOKBACK_MONTHS=6
PROVENANCE_LOOKBACK_MONTHS=""
PROVENANCE_START_DATE=""
PROVENANCE_LOOKBACK_SPECIFIED=0
STATE_SCHEMA_VERSION=3
NON_INTERACTIVE=0
OPEN_HTML=0
NO_OPEN_HTML=0
VALIDATE_ONLY=0
PLAN_ONLY=0
REQUESTED_COMMIT=""
EXPECTED_PLAN_HASH=""
APPROVAL_HASH=""
RHYOLITE_SUPPORT_TEXT='SUPPORT.md and local documentation'
RHYOLITE_CONTRIBUTE_TEXT='CONTRIBUTING.md'

repositories=()
repository_file=""

usage() {
    cat <<'EOF'
Usage:
  run-parallel-reviews.sh --repo URL [--repo URL ...] [options]
  run-parallel-reviews.sh --repo-file FILE [options]

Options:
  --repo URL                       Anonymous public HTTPS Git repository URL
  --repo-path PATH                 Rejected; local repository paths are unsupported
  --repo-file FILE                 Public HTTPS Git repository URLs, one per line
  --throttle N                     Parallel session limit (default: 2)
  --max-repositories N             Maximum repositories per run (default: 5)
  --timeout-minutes N              Per-session timeout (default: scope-based)
  --workspace-root PATH            Clone workspace root
  --output-root PATH               Writable artifact root outside the checkout
  --result-root PATH               Deprecated alias for --output-root
  --scope 1|2|3                    1 core, 2 public research, 3 exact-commit provenance
  --commit SHA                     Exact 40-character commit for one repository
  --model MODEL                    Copilot model (default: gpt-5.6-sol)
  --enable-public-research         Permit arbitrary public URL access
  --enable-provenance-research     Enable whole-repository exact-commit provenance research
  --provenance-lookback-months N   Scope 3 calendar-month lookback (1-60, default: 6)
  --non-interactive                Use defaults without terminal prompts
  --open-html                      Open the HTML run index after completion
  --no-open-html                   Never open the HTML run index
  --validate-only                  Validate arguments without cloning or review
  --plan-only                      Resolve and print the effective plan as JSON
  --expected-plan-hash SHA256      Require the resolved plan approval hash
  --help                           Show this help
EOF
}

review_progress() {
    local subject="$1"
    local stage="$2"
    local detail="${3-}"

    if [[ -n "${detail}" ]]; then
        printf 'RHYOLITE PROGRESS | %s | %s | %s\n' \
            "${subject}" "${stage}" "${detail}"
    else
        printf 'RHYOLITE PROGRESS | %s | %s\n' "${subject}" "${stage}"
    fi
}

read_metadata_string() {
    local field="$1"
    local metadata_path="${PLUGIN_ROOT}/branding/welcome-metadata.json"

    [[ -f "${metadata_path}" ]] || return 0
    sed -nE \
        "s/^[[:space:]]*\"${field}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\"[[:space:]]*,?[[:space:]]*$/\\1/p" \
        "${metadata_path}" | head -n 1
}

load_repository_support_links() {
    local home_url docs_url support_url issues_url pulls_url value

    home_url="$(read_metadata_string 'homeUrl')"
    docs_url="$(read_metadata_string 'docsUrl')"
    support_url="$(read_metadata_string 'supportUrl')"
    issues_url="$(read_metadata_string 'issuesUrl')"
    pulls_url="$(read_metadata_string 'pullsUrl')"
    for value in \
        "${home_url}" \
        "${docs_url}" \
        "${support_url}" \
        "${issues_url}" \
        "${pulls_url}"; do
        case "${value}" in
            ''|*'<PUBLIC_'*'>'*) return ;;
        esac
    done
    RHYOLITE_SUPPORT_TEXT="${issues_url}"
    RHYOLITE_CONTRIBUTE_TEXT="${pulls_url}"
}

repository_failure_stage() {
    local status="$1"
    local errors_path="$2"

    case "${status}" in
        AccessPreflightFailed|PreflightBlocked)
            printf 'anonymous repository preflight'
            ;;
        CloneFailed)
            printf 'clone'
            ;;
        CommitResolutionFailed)
            printf 'commit resolution'
            ;;
        SnapshotFailed)
            printf 'read-only snapshot'
            ;;
        TimedOut)
            printf 'worker timeout'
            ;;
        ReviewFailed)
            if grep -Eq \
                'temporary Copilot runtime home|sanitize the temporary Copilot|cleanup' \
                "${errors_path}" 2>/dev/null; then
                printf 'cleanup'
            elif grep -Eq \
                'Incomplete report|Final report extraction failed|Final report header|Markdown table' \
                "${errors_path}" 2>/dev/null; then
                printf 'report validation'
            else
                printf 'worker analysis'
            fi
            ;;
        *)
            printf 'finalization'
            ;;
    esac
}

repository_failure_summary() {
    local status="$1"
    local stage="$2"

    case "${status}" in
        AccessPreflightFailed)
            printf 'Anonymous access to the selected public HTTPS repository could not be verified.'
            ;;
        PreflightBlocked)
            printf 'This repository was not started because another selected source failed the fail-closed anonymous preflight.'
            ;;
        CloneFailed)
            printf 'The anonymous public HTTPS clone failed.'
            ;;
        CommitResolutionFailed)
            printf 'The requested exact commit could not be fetched, checked out, or verified.'
            ;;
        SnapshotFailed)
            printf 'The trusted runner could not create the read-only, .git-free source snapshot.'
            ;;
        TimedOut)
            printf 'The repository-review worker exceeded its configured time limit.'
            ;;
        ReviewFailed)
            case "${stage}" in
                cleanup)
                    printf 'The review failed closed because temporary Copilot runtime cleanup did not complete safely.'
                    ;;
                'report validation')
                    printf 'The worker response did not satisfy the complete canonical report contract.'
                    ;;
                *)
                    printf 'The repository-review worker exited without a completed review.'
                    ;;
            esac
            ;;
        *)
            printf 'The repository review did not complete.'
            ;;
    esac
}

repository_failure_remediation() {
    local status="$1"
    local stage="$2"

    case "${status}" in
        AccessPreflightFailed)
            printf '%s' \
                'Supply an anonymously readable public HTTPS Git URL and retry. Rhyolite supports public sources only and intentionally does not attempt target authentication.'
            ;;
        PreflightBlocked)
            printf '%s' \
                'Remove or correct every source that failed anonymous preflight, regenerate the plan, and rerun the whole approved selection.'
            ;;
        CloneFailed)
            printf '%s' \
                'Verify the repository remains anonymously reachable over HTTPS, then retry; Rhyolite will not use target credentials.'
            ;;
        CommitResolutionFailed)
            printf '%s' \
                'Verify that the exact 40-character commit is publicly reachable from the selected repository, regenerate the plan if needed, and retry.'
            ;;
        SnapshotFailed)
            printf '%s' \
                'Check local Git/tar availability, free space, and workspace permissions, then retry without weakening snapshot isolation.'
            ;;
        TimedOut)
            printf '%s' \
                'Retry with a larger runner timeout or a narrower review scope.'
            ;;
        ReviewFailed)
            case "${stage}" in
                cleanup)
                    printf '%s' \
                        'Securely remove the reported temporary runtime path, correct local permissions or locks, and retry.'
                    ;;
                'report validation')
                    printf '%s' \
                        'Rerun the review; use the saved timeline and errors artifacts to diagnose repeated incomplete output.'
                    ;;
                *)
                    printf '%s' \
                        'Review the sanitized errors and timeline. If they show Copilot authentication failure, run copilot login from a clean non-Git directory, then retry.'
                    ;;
            esac
            ;;
        *)
            printf '%s' \
                'Inspect the returned state and errors artifacts, correct the reported local failure, and retry.'
            ;;
    esac
}

safe_error_details() {
    local errors_path="$1"

    if [[ ! -s "${errors_path}" ]]; then
        printf 'No additional safe detail was returned.'
        return
    fi
    tr -d '\r' < "${errors_path}" |
        strip_terminal_controls |
        redact_credentials |
        redact_emails |
        awk '
            NF {
                gsub(/^[[:space:]]+|[[:space:]]+$/, "")
                if (length(output) > 0) {
                    output = output " | "
                }
                output = output $0
            }
            END {
                if (length(output) == 0) {
                    output = "No additional safe detail was returned."
                }
                printf "%s", output
            }
        '
}

print_repository_error() {
    local result_file="$1"
    local result_directory="${result_file%/state.json}"
    local errors_path="${result_directory}/errors.txt"
    local timeline_path="${result_directory}/analysis-timeline.txt"
    local handoff_path="${result_directory}/handoff.md"
    local repository status exit_code stage summary remediation details

    repository="$(
        sed -n 's/^[[:space:]]*"Repository":[[:space:]]*"\(.*\)",[[:space:]]*$/\1/p' \
            "${result_file}" | head -n 1
    )"
    status="$(
        sed -n 's/^[[:space:]]*"Status":[[:space:]]*"\([^"]*\)",[[:space:]]*$/\1/p' \
            "${result_file}" | head -n 1
    )"
    exit_code="$(
        sed -n 's/^[[:space:]]*"ExitCode":[[:space:]]*\([0-9][0-9]*\),[[:space:]]*$/\1/p' \
            "${result_file}" | head -n 1
    )"
    [[ -n "${repository}" ]] || repository='UNAVAILABLE'
    [[ -n "${status}" ]] || status='UNAVAILABLE'
    [[ -n "${exit_code}" ]] || exit_code='UNAVAILABLE'
    stage="$(repository_failure_stage "${status}" "${errors_path}")"
    summary="$(repository_failure_summary "${status}" "${stage}")"
    remediation="$(repository_failure_remediation "${status}" "${stage}")"
    details="$(safe_error_details "${errors_path}")"

    printf '\n%s\n' 'RHYOLITE ERROR'
    printf '%s\n' \
        "Summary: ${summary}" \
        "Stage: ${stage}" \
        "Source: ${repository}" \
        "Details: Status ${status}; exit code ${exit_code}; ${details}" \
        'Consequence: This repository did not produce a completed review; the run state and artifacts remain truthful.' \
        "Remediation: ${remediation}" \
        "Artifacts: State ${result_file}; Errors ${errors_path}; Timeline ${timeline_path}; Handoff ${handoff_path}" \
        "Support: ${RHYOLITE_SUPPORT_TEXT}" \
        "Contribute: ${RHYOLITE_CONTRIBUTE_TEXT}"
}

load_repository_support_links

require_value() {
    local option="$1"
    local value="${2-}"
    if [[ -z "${value}" ]]; then
        printf 'Missing value for %s\n' "${option}" >&2
        exit 2
    fi
}

is_interactive_console() {
    ((NON_INTERACTIVE == 0)) && [[ -t 0 && -t 1 ]]
}

can_prompt_for_setup() {
    ((VALIDATE_ONLY == 0 && PLAN_ONLY == 0)) && is_interactive_console
}

days_in_month() {
    local year="$1"
    local month="$2"
    case "${month}" in
        1 | 3 | 5 | 7 | 8 | 10 | 12)
            printf '31\n'
            ;;
        4 | 6 | 9 | 11)
            printf '30\n'
            ;;
        2)
            if (((year % 4 == 0 && year % 100 != 0) || year % 400 == 0)); then
                printf '29\n'
            else
                printf '28\n'
            fi
            ;;
        *)
            printf 'Invalid month: %s\n' "${month}" >&2
            return 1
            ;;
    esac
}

subtract_calendar_months() {
    local iso_date="$1"
    local months="$2"
    local year month day total_month_index target_month_index target_year
    local target_month max_day

    IFS='-' read -r year month day <<< "${iso_date}"
    year=$((10#${year}))
    month=$((10#${month}))
    day=$((10#${day}))
    months=$((10#${months}))
    total_month_index=$((year * 12 + month - 1))
    target_month_index=$((total_month_index - months))
    target_year=$((target_month_index / 12))
    target_month=$((target_month_index % 12 + 1))
    max_day="$(days_in_month "${target_year}" "${target_month}")" || return 1
    if ((day > max_day)); then
        day="${max_day}"
    fi
    printf '%04d-%02d-%02d\n' "${target_year}" "${target_month}" "${day}"
}

json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\b'/\\b}"
    value="${value//$'\f'/\\f}"
    value="${value//$'\t'/\\t}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    printf '%s' "${value}"
}

json_boolean() {
    local enabled="${1:-0}"
    if ((enabled)); then
        printf 'true'
    else
        printf 'false'
    fi
}

json_string_or_null() {
    local value="${1-}"
    if [[ -n "${value}" ]]; then
        printf '"%s"' "$(json_escape "${value}")"
    else
        printf 'null'
    fi
}

status_word() {
    local enabled="${1:-0}"
    if ((enabled)); then
        printf 'enabled'
    else
        printf 'disabled'
    fi
}

review_plan_open_html_policy() {
    if ((OPEN_HTML)); then
        printf 'always'
    elif ((NO_OPEN_HTML)); then
        printf 'never'
    else
        printf 'default'
    fi
}

base64_encode_utf8() {
    local value="$1"

    if command -v base64 >/dev/null 2>&1; then
        printf '%s' "${value}" | base64 | tr -d '\n'
        return
    fi
    if command -v openssl >/dev/null 2>&1; then
        printf '%s' "${value}" | openssl base64 -A
        return
    fi
    if command -v python3 >/dev/null 2>&1; then
        printf '%s' "${value}" |
            python3 -c 'import base64, sys; sys.stdout.write(base64.b64encode(sys.stdin.buffer.read()).decode("ascii"))'
        return
    fi

    printf '%s\n' \
        'A base64 encoder is required to compute the review plan approval hash.' >&2
    exit 2
}

approval_hash_string() {
    printf 'base64:%s' "$(base64_encode_utf8 "$1")"
}

approval_hash_string_or_null() {
    local value="${1-}"
    if [[ -n "${value}" ]]; then
        approval_hash_string "${value}"
    else
        printf 'null'
    fi
}

write_approval_hash_material() {
    local index

    for index in "${!canonical_urls[@]}"; do
        printf 'Source[%s].Kind=%s\n' \
            "${index}" "$(approval_hash_string "${source_kinds[index]}")"
        printf 'Source[%s].LocalPath=%s\n' \
            "${index}" "$(approval_hash_string_or_null "${source_paths[index]}")"
        printf 'Source[%s].RemoteUrl=%s\n' \
            "${index}" "$(approval_hash_string "${canonical_urls[index]}")"
        printf 'Source[%s].RequestedCommit=%s\n' \
            "${index}" "$(approval_hash_string_or_null "${requested_commits[index]}")"
        printf 'Source[%s].Slug=%s\n' \
            "${index}" "$(approval_hash_string "${slugs[index]}")"
    done
    printf 'ReviewDate=%s\n' "$(approval_hash_string "${REVIEW_DATE}")"
    printf 'WorkspaceRoot=%s\n' "$(approval_hash_string "${WORKSPACE_ROOT}")"
    printf 'OutputRoot=%s\n' "$(approval_hash_string "${OUTPUT_ROOT}")"
    printf 'Scope.Number=%s\n' "${SCOPE}"
    printf 'Scope.Name=%s\n' "$(approval_hash_string "${SCOPE_NAME}")"
    printf 'Scope.PublicResearch=%s\n' \
        "$(json_boolean "${ENABLE_PUBLIC_RESEARCH}")"
    printf 'Scope.ProvenanceResearch=%s\n' \
        "$(json_boolean "${ENABLE_PROVENANCE_RESEARCH}")"
    printf 'PriorArtWindow.Enabled=%s\n' \
        "$(json_boolean "${ENABLE_PUBLIC_RESEARCH}")"
    printf 'PriorArtWindow.LookbackMonths=%s\n' \
        "${DEFAULT_PRIOR_ART_LOOKBACK_MONTHS}"
    printf 'PriorArtWindow.StartDate=%s\n' \
        "$(approval_hash_string "${PRIOR_ART_START_DATE}")"
    printf 'PriorArtWindow.EndDate=%s\n' \
        "$(approval_hash_string "${REVIEW_DATE}")"
    if ((ENABLE_PROVENANCE_RESEARCH)); then
        printf 'ProvenanceWindow=present\n'
        printf 'ProvenanceWindow.LookbackMonths=%s\n' \
            "${PROVENANCE_LOOKBACK_MONTHS}"
        printf 'ProvenanceWindow.StartDate=%s\n' \
            "$(approval_hash_string "${PROVENANCE_START_DATE}")"
        printf 'ProvenanceWindow.EndDate=%s\n' \
            "$(approval_hash_string "${REVIEW_DATE}")"
    else
        printf 'ProvenanceWindow=null\n'
    fi
    printf 'SessionTimeoutMinutes=%s\n' "${SESSION_TIMEOUT_MINUTES}"
    printf 'ThrottleLimit=%s\n' "${THROTTLE_LIMIT}"
    printf 'MaxRepositories=%s\n' "${MAX_REPOSITORIES}"
    printf 'Model=%s\n' "$(approval_hash_string "${MODEL}")"
    printf 'OpenHtmlPolicy=%s\n' \
        "$(approval_hash_string "$(review_plan_open_html_policy)")"
}

sha256_hex() {
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
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import hashlib, sys; sys.stdout.write(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
        return
    fi

    printf '%s\n' \
        'A SHA-256 implementation is required to compute the review plan approval hash.' >&2
    exit 2
}

compute_approval_hash() {
    write_approval_hash_material | sha256_hex
}

prior_art_window_json() {
    cat <<EOF
{
  "Enabled": $(json_boolean "${ENABLE_PUBLIC_RESEARCH}"),
  "LookbackMonths": ${DEFAULT_PRIOR_ART_LOOKBACK_MONTHS},
  "StartDate": "$(json_escape "${PRIOR_ART_START_DATE}")",
  "EndDate": "$(json_escape "${REVIEW_DATE}")"
}
EOF
}

provenance_window_json() {
    local indent="$1"
    if ((ENABLE_PROVENANCE_RESEARCH)); then
        cat <<EOF
{
${indent}  "LookbackMonths": ${PROVENANCE_LOOKBACK_MONTHS},
${indent}  "StartDate": "$(json_escape "${PROVENANCE_START_DATE}")",
${indent}  "EndDate": "$(json_escape "${REVIEW_DATE}")"
${indent}}
EOF
    else
        printf 'null'
    fi
}

provenance_window_text() {
    if ((ENABLE_PROVENANCE_RESEARCH)); then
        printf 'Lookback months: %s\nStart date: %s\nEnd date: %s\n' \
            "${PROVENANCE_LOOKBACK_MONTHS}" "${PROVENANCE_START_DATE}" \
            "${REVIEW_DATE}"
    else
        printf 'Disabled\n'
    fi
}

write_review_plan_json() {
    local run_id="${1-}"
    local started_at="${2-}"
    local index

    printf '{\n'
    printf '  "SchemaVersion": %s,\n' "${PLAN_SCHEMA_VERSION}"
    printf '  "GeneratedAt": "%s",\n' "$(json_escape "${PLAN_GENERATED_AT}")"
    printf '  "ReviewDate": "%s",\n' "$(json_escape "${REVIEW_DATE}")"
    printf '  "ApprovalHash": "%s",\n' "$(json_escape "${APPROVAL_HASH}")"
    if [[ -n "${run_id}" ]]; then
        printf '  "RunId": "%s",\n' "$(json_escape "${run_id}")"
        printf '  "StartedAt": "%s",\n' "$(json_escape "${started_at}")"
    fi
    printf '  "Sources": [\n'
    for index in "${!canonical_urls[@]}"; do
        printf '    {\n'
        printf '      "Kind": "%s",\n' "$(json_escape "${source_kinds[index]}")"
        printf '      "LocalPath": '
        json_string_or_null "${source_paths[index]}"
        printf ',\n'
        printf '      "RemoteUrl": "%s",\n' \
            "$(json_escape "${canonical_urls[index]}")"
        printf '      "RequestedCommit": '
        json_string_or_null "${requested_commits[index]}"
        printf ',\n'
        printf '      "Slug": "%s"\n' "$(json_escape "${slugs[index]}")"
        printf '    }'
        if ((index + 1 < ${#canonical_urls[@]})); then
            printf ','
        fi
        printf '\n'
    done
    cat <<EOF
  ],
  "WorkspaceRoot": "$(json_escape "${WORKSPACE_ROOT}")",
  "OutputRoot": "$(json_escape "${OUTPUT_ROOT}")",
  "Scope": {
    "Number": ${SCOPE},
    "Name": "$(json_escape "${SCOPE_NAME}")",
    "PlanningEstimate": "$(json_escape "${SCOPE_ESTIMATE}")",
    "PublicResearch": $(json_boolean "${ENABLE_PUBLIC_RESEARCH}"),
    "ProvenanceResearch": $(json_boolean "${ENABLE_PROVENANCE_RESEARCH}")
  },
  "PriorArtWindow": $(prior_art_window_json),
  "ProvenanceWindow": $(provenance_window_json '  '),
  "SessionTimeoutMinutes": ${SESSION_TIMEOUT_MINUTES},
  "ThrottleLimit": ${THROTTLE_LIMIT},
  "MaxRepositories": ${MAX_REPOSITORIES},
  "Model": "$(json_escape "${MODEL}")",
  "OpenHtmlPolicy": "$(json_escape "$(review_plan_open_html_policy)")"
}
EOF
}

write_review_plan_text() {
    local run_id="${1-}"
    local started_at="${2-}"
    local index number requested_commit

    printf '================================================================================\n'
    printf 'EFFECTIVE REVIEW PLAN\n'
    printf '================================================================================\n'
    printf '%-30s %s\n' 'Generated at (UTC):' "${PLAN_GENERATED_AT}"
    printf '%-30s %s\n' 'Review date (local calendar):' "${REVIEW_DATE}"
    printf '%-20s %s\n' 'Approval hash:' "${APPROVAL_HASH}"
    if [[ -n "${run_id}" ]]; then
        printf '%-20s %s\n' 'Run ID:' "${run_id}"
        printf '%-20s %s\n' 'Started at:' "${started_at}"
    fi
    printf '%-20s %s\n' 'Workspace root:' "${WORKSPACE_ROOT}"
    printf '%-20s %s\n' 'Output root:' "${OUTPUT_ROOT}"
    printf '%-20s %s\n' 'Scope:' "${SCOPE_NAME}"
    printf '%-20s %s\n' 'Planning estimate:' "${SCOPE_ESTIMATE}"
    printf '%-20s %s\n' 'Public research:' \
        "$(status_word "${ENABLE_PUBLIC_RESEARCH}")"
    printf '%-20s %s\n' 'Provenance research:' \
        "$(status_word "${ENABLE_PROVENANCE_RESEARCH}")"
    if ((ENABLE_PUBLIC_RESEARCH)); then
        printf '%-20s %s months\n' \
            'Prior-art lookback:' "${DEFAULT_PRIOR_ART_LOOKBACK_MONTHS}"
        printf '%-30s %s through %s\n' \
            'Prior-art window (local calendar):' "${PRIOR_ART_START_DATE}" "${REVIEW_DATE}"
    else
        printf '%-30s %s\n' 'Prior-art window (local calendar):' 'disabled'
    fi
    if ((ENABLE_PROVENANCE_RESEARCH)); then
        printf '%-20s %s months\n' \
            'Provenance lookback:' "${PROVENANCE_LOOKBACK_MONTHS}"
        printf '%-30s %s through %s\n' \
            'Provenance window (local calendar):' "${PROVENANCE_START_DATE}" "${REVIEW_DATE}"
    else
        printf '%-30s %s\n' 'Provenance window (local calendar):' 'disabled'
    fi
    printf '%-20s %s minutes\n' 'Session timeout:' "${SESSION_TIMEOUT_MINUTES}"
    printf '%-20s %s\n' 'Throttle limit:' "${THROTTLE_LIMIT}"
    printf '%-20s %s\n' 'Maximum repositories:' "${MAX_REPOSITORIES}"
    printf '%-20s %s\n' 'Model:' "${MODEL}"
    printf '%-20s %s\n' 'Open HTML policy:' "$(review_plan_open_html_policy)"
    printf '%-20s %s\n' 'Sources:' "${#canonical_urls[@]}"
    number=1
    for index in "${!canonical_urls[@]}"; do
        requested_commit="${requested_commits[index]}"
        printf '  [%d] %s\n' "${number}" "${slugs[index]}"
        printf '      %-16s %s\n' 'Kind:' "${source_kinds[index]}"
        if [[ -n "${source_paths[index]}" ]]; then
            printf '      %-16s %s\n' 'Local path:' "${source_paths[index]}"
        fi
        printf '      %-16s %s\n' 'Remote URL:' "${canonical_urls[index]}"
        if [[ -n "${requested_commit}" ]]; then
            printf '      %-16s %s\n' 'Requested commit:' "${requested_commit}"
        else
            printf '      %-16s %s\n' 'Requested commit:' '(none)'
        fi
        number=$((number + 1))
    done
    printf '================================================================================\n'
}

while (($# > 0)); do
    case "$1" in
        --repo)
            require_value "$1" "${2-}"
            repositories+=("$2")
            shift 2
            ;;
        --repo-file)
            require_value "$1" "${2-}"
            repository_file="$2"
            shift 2
            ;;
        --repo-path)
            require_value "$1" "${2-}"
            printf '%s\n' \
                'Local repository paths are not supported. Supply only anonymously readable public HTTPS Git repository URLs.' >&2
            exit 2
            ;;
        --throttle)
            require_value "$1" "${2-}"
            THROTTLE_LIMIT="$2"
            shift 2
            ;;
        --max-repositories)
            require_value "$1" "${2-}"
            MAX_REPOSITORIES="$2"
            shift 2
            ;;
        --timeout-minutes)
            require_value "$1" "${2-}"
            SESSION_TIMEOUT_MINUTES="$2"
            shift 2
            ;;
        --workspace-root)
            require_value "$1" "${2-}"
            WORKSPACE_ROOT="$2"
            shift 2
            ;;
        --output-root|--result-root)
            require_value "$1" "${2-}"
            OUTPUT_ROOT="$2"
            shift 2
            ;;
        --scope)
            require_value "$1" "${2-}"
            SCOPE="$2"
            SCOPE_SPECIFIED=1
            shift 2
            ;;
        --commit)
            require_value "$1" "${2-}"
            REQUESTED_COMMIT="$2"
            shift 2
            ;;
        --model)
            require_value "$1" "${2-}"
            MODEL="$2"
            shift 2
            ;;
        --enable-public-research)
            ENABLE_PUBLIC_RESEARCH=1
            shift
            ;;
        --enable-provenance-research)
            ENABLE_PROVENANCE_RESEARCH=1
            shift
            ;;
        --provenance-lookback-months)
            require_value "$1" "${2-}"
            PROVENANCE_LOOKBACK_MONTHS="$2"
            PROVENANCE_LOOKBACK_SPECIFIED=1
            shift 2
            ;;
        --non-interactive)
            NON_INTERACTIVE=1
            shift
            ;;
        --open-html)
            OPEN_HTML=1
            shift
            ;;
        --no-open-html)
            NO_OPEN_HTML=1
            shift
            ;;
        --validate-only)
            VALIDATE_ONLY=1
            shift
            ;;
        --plan-only)
            PLAN_ONLY=1
            shift
            ;;
        --expected-plan-hash)
            require_value "$1" "${2-}"
            EXPECTED_PLAN_HASH="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ((VALIDATE_ONLY && PLAN_ONLY)); then
    printf '%s\n' \
        '--validate-only and --plan-only cannot be used together.' >&2
    exit 2
fi

if [[ -n "${EXPECTED_PLAN_HASH}" ]]; then
    if ! [[ "${EXPECTED_PLAN_HASH}" =~ ^[0-9A-Fa-f]{64}$ ]]; then
        printf '%s\n' \
            '--expected-plan-hash must be a 64-character hexadecimal SHA-256 value.' >&2
        exit 2
    fi
    EXPECTED_PLAN_HASH="${EXPECTED_PLAN_HASH,,}"
fi

if [[ -n "${repository_file}" ]]; then
    if [[ ! -f "${repository_file}" ]]; then
        printf 'Repository list not found: %s\n' "${repository_file}" >&2
        exit 2
    fi

    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ -n "${line}" && "${line}" != \#* ]]; then
            if [[ "${line}" =~ ^[A-Za-z][A-Za-z0-9+.-]*:// ]]; then
                repositories+=("${line}")
            else
                printf '%s\n' \
                    "Repository list contains an unsupported local path or non-URL entry: ${line}" \
                    'Supply only anonymously readable public HTTPS Git repository URLs.' >&2
                exit 2
            fi
        fi
    done < "${repository_file}"
fi

source_count=${#repositories[@]}
if ((source_count == 0)); then
    printf 'No repository URLs were provided.\n' >&2
    exit 2
fi

if ! [[ "${THROTTLE_LIMIT}" =~ ^[0-9]+$ ]] ||
    ((THROTTLE_LIMIT < 1 || THROTTLE_LIMIT > 8)); then
    printf 'Throttle must be an integer from 1 through 8.\n' >&2
    exit 2
fi

if ! [[ "${MAX_REPOSITORIES}" =~ ^[0-9]+$ ]] ||
    ((MAX_REPOSITORIES < 1 || MAX_REPOSITORIES > 10)); then
    printf 'Maximum repositories must be an integer from 1 through 10.\n' >&2
    exit 2
fi

if ! [[ "${SESSION_TIMEOUT_MINUTES}" =~ ^[0-9]+$ ]] ||
    ((SESSION_TIMEOUT_MINUTES > 720)); then
    printf 'Timeout must be 0 or an integer through 720 minutes.\n' >&2
    exit 2
fi

if ((source_count > MAX_REPOSITORIES)); then
    printf 'Received %d repositories; maximum is %d.\n' \
        "${source_count}" "${MAX_REPOSITORIES}" >&2
    exit 2
fi
if [[ -n "${REQUESTED_COMMIT}" ]] &&
    ! [[ "${REQUESTED_COMMIT}" =~ ^[0-9a-fA-F]{40}$ ]]; then
    printf '%s\n' '--commit must be a full 40-character hexadecimal SHA.' >&2
    exit 2
fi
if [[ -n "${REQUESTED_COMMIT}" ]] &&
    ((${#repositories[@]} != 1)); then
    printf '%s\n' '--commit can be used only with one remote repository URL.' >&2
    exit 2
fi

if [[ -n "${PROVENANCE_LOOKBACK_MONTHS}" ]]; then
    if ! [[ "${PROVENANCE_LOOKBACK_MONTHS}" =~ ^[0-9]+$ ]] ||
        ((10#${PROVENANCE_LOOKBACK_MONTHS} < 1 ||
            10#${PROVENANCE_LOOKBACK_MONTHS} > 60)); then
        printf '%s\n' \
            '--provenance-lookback-months must be a whole number from 1 through 60.' >&2
        exit 2
    fi
    PROVENANCE_LOOKBACK_MONTHS="$((10#${PROVENANCE_LOOKBACK_MONTHS}))"
fi

if ((OPEN_HTML && NO_OPEN_HTML)); then
    printf '%s\n' \
        '--open-html and --no-open-html cannot be used together.' >&2
    exit 2
fi

if ((SCOPE_SPECIFIED)) &&
    ! [[ "${SCOPE}" =~ ^[1-3]$ ]]; then
    printf '%s\n' '--scope must be a whole number from 1 through 3.' >&2
    exit 2
fi

if ((SCOPE_SPECIFIED && (ENABLE_PUBLIC_RESEARCH || ENABLE_PROVENANCE_RESEARCH))); then
    printf '%s\n' \
        'Use either --scope or the legacy research switches, not both.' >&2
    exit 2
fi

if ((!SCOPE_SPECIFIED)); then
    if ((ENABLE_PROVENANCE_RESEARCH && !ENABLE_PUBLIC_RESEARCH)); then
        printf '%s\n' \
            'Provenance research requires --enable-public-research.' >&2
        exit 2
    elif ((ENABLE_PROVENANCE_RESEARCH)); then
        SCOPE=3
    elif ((ENABLE_PUBLIC_RESEARCH)); then
        SCOPE=2
    elif can_prompt_for_setup; then
        cat <<'EOF'
Select review scope:
  1. Core review (recommended for a first run): source, history,
     architecture, quality, and a security specialist. Roughly 15-45
     minutes per repository; lowest AI-credit and network use.
  2. Core + public prior-art/community research: adds a research specialist
     and public web requests. Roughly 30-90+ minutes per repository and
     materially higher AI-credit/network use.
  3. Full + whole-repository exact-commit evidence-based provenance of
     agentically generated code: broadest scope, roughly 60-120+ minutes
     per repository, highest resource use, and mandatory human review before
     sharing.
Estimates are planning ranges and can increase substantially for large
repositories or broad research topics.
EOF
        read -r -p 'Scope [1]: ' scope_input
        scope_input="${scope_input:-1}"
        if [[ "${scope_input}" =~ ^[123]$ ]]; then
            SCOPE="${scope_input}"
        else
            printf 'Scope must be 1, 2, or 3.\n' >&2
            exit 2
        fi
    else
        SCOPE=1
    fi
fi

case "${SCOPE}" in
    1)
        SCOPE_NAME='1 - Core repository review'
        SCOPE_ESTIMATE='Roughly 15-45 minutes per repository; lowest resource use.'
        ENABLE_PUBLIC_RESEARCH=0
        ENABLE_PROVENANCE_RESEARCH=0
        ;;
    2)
        SCOPE_NAME='2 - Core plus public prior-art and community research'
        SCOPE_ESTIMATE='Roughly 30-90+ minutes per repository; additional research agent, public network requests, and AI credits.'
        ENABLE_PUBLIC_RESEARCH=1
        ENABLE_PROVENANCE_RESEARCH=0
        ;;
    3)
        SCOPE_NAME='3 - Full review plus whole-repository exact-commit evidence-based provenance of agentically generated code'
        SCOPE_ESTIMATE='Roughly 60-120+ minutes per repository; highest model, subagent, and network use; human review required.'
        ENABLE_PUBLIC_RESEARCH=1
        ENABLE_PROVENANCE_RESEARCH=1
        ;;
esac

if ((ENABLE_PROVENANCE_RESEARCH == 0)); then
    if ((PROVENANCE_LOOKBACK_SPECIFIED)); then
        printf '%s\n' \
            '--provenance-lookback-months can be used only with scope 3 provenance research.' >&2
        exit 2
    fi
    PROVENANCE_LOOKBACK_MONTHS=''
elif [[ -z "${PROVENANCE_LOOKBACK_MONTHS}" ]]; then
    if can_prompt_for_setup; then
        read -r -p "Provenance lookback months [${DEFAULT_PROVENANCE_LOOKBACK_MONTHS}]: " provenance_input
        provenance_input="${provenance_input:-${DEFAULT_PROVENANCE_LOOKBACK_MONTHS}}"
        if ! [[ "${provenance_input}" =~ ^[0-9]+$ ]] ||
            ((10#${provenance_input} < 1 ||
                10#${provenance_input} > 60)); then
            printf '%s\n' \
                'Provenance lookback months must be a whole number from 1 through 60.' >&2
            exit 2
        fi
        PROVENANCE_LOOKBACK_MONTHS="$((10#${provenance_input}))"
    else
        PROVENANCE_LOOKBACK_MONTHS="${DEFAULT_PROVENANCE_LOOKBACK_MONTHS}"
    fi
fi

if ((SESSION_TIMEOUT_MINUTES == 0)); then
    case "${SCOPE}" in
        1) SESSION_TIMEOUT_MINUTES=60 ;;
        2) SESSION_TIMEOUT_MINUTES=120 ;;
        3) SESSION_TIMEOUT_MINUTES=240 ;;
    esac
fi

default_output_root() {
    printf '%s/rhyolite-output/repo-review\n' "${HOME%/}"
}

canonicalize_directory_path() {
    local input="$1"
    local path cursor parent resolved

    if [[ "${input}" == /* ]]; then
        path="${input}"
    else
        path="${PWD}/${input}"
    fi

    resolved="$(realpath -m -- "${path}")" || {
        printf 'Cannot resolve directory path: %s\n' "${input}" >&2
        return 1
    }
    cursor="${resolved}"
    while [[ ! -e "${cursor}" ]]; do
        parent="$(dirname -- "${cursor}")"
        if [[ "${parent}" == "${cursor}" ]]; then
            printf 'Cannot resolve directory path: %s\n' "${input}" >&2
            return 1
        fi
        cursor="${parent}"
    done

    if [[ ! -d "${cursor}" ]]; then
        printf 'Directory path resolves through a file: %s\n' "${input}" >&2
        return 1
    fi

    printf '%s\n' "${resolved}"
}

path_contains() {
    local parent="${1%/}"
    local child="${2%/}"
    [[ "${child}" == "${parent}" || "${child}" == "${parent}/"* ]]
}

directory_contains_physical() {
    local parent="$1"
    local cursor="$2"
    local next

    while true; do
        if [[ "${cursor}" -ef "${parent}" ]]; then
            return 0
        fi
        next="$(dirname -- "${cursor}")"
        if [[ "${next}" == "${cursor}" ]]; then
            return 1
        fi
        cursor="${next}"
    done
}

require_control_free_paths() {
    local path
    for path in "$@"; do
        if [[ "${path}" =~ [[:cntrl:]] ]]; then
            printf '%s\n' \
                'Workspace and output paths must not contain control characters.' \
                >&2
            return 1
        fi
    done
}

nearest_existing_directory() {
    local cursor="$1"
    local parent
    while [[ ! -e "${cursor}" ]]; do
        parent="$(dirname -- "${cursor}")"
        if [[ "${parent}" == "${cursor}" ]]; then
            return 1
        fi
        cursor="${parent}"
    done
    [[ -d "${cursor}" ]] || return 1
    printf '%s\n' "${cursor}"
}

require_outside_git_repository() {
    local path="$1"
    local label="$2"
    local ancestor probe probe_exit

    ancestor="$(nearest_existing_directory "${path}")" || {
        printf 'Cannot find an existing directory ancestor for %s: %s\n' \
            "${label}" "${path}" >&2
        return 1
    }
    set +e
    probe="$(
        LC_ALL=C git -C "${ancestor}" rev-parse --git-dir 2>&1
    )"
    probe_exit=$?
    set -e
    if ((probe_exit == 0)); then
        printf '%s must not be inside a Git worktree or Git metadata directory.\n' \
            "${label}" >&2
        return 1
    fi
    if ((probe_exit != 128)) ||
        [[ "${probe}" != *"not a git repository"* ]]; then
        printf 'Could not verify Git isolation for %s at %s: %s\n' \
            "${label}" "${ancestor}" "${probe}" >&2
        return 1
    fi
}

if [[ -z "${OUTPUT_ROOT}" ]]; then
    OUTPUT_ROOT="$(default_output_root)"
    if can_prompt_for_setup; then
        printf '\nReview artifacts require a writable directory separate from '
        printf 'the read-only checkout.\n'
        read -r -p "Output root [${OUTPUT_ROOT}]: " output_input
        OUTPUT_ROOT="${output_input:-${OUTPUT_ROOT}}"
    fi
fi

require_control_free_paths "${WORKSPACE_ROOT}" "${OUTPUT_ROOT}" || exit 2

command -v realpath >/dev/null 2>&1 || {
    printf 'GNU realpath is required.\n' >&2
    exit 2
}
WORKSPACE_ROOT="$(canonicalize_directory_path "${WORKSPACE_ROOT}")"
OUTPUT_ROOT="$(canonicalize_directory_path "${OUTPUT_ROOT}")"
require_control_free_paths "${WORKSPACE_ROOT}" "${OUTPUT_ROOT}" || exit 2
if path_contains "${WORKSPACE_ROOT}" "${OUTPUT_ROOT}" ||
    path_contains "${OUTPUT_ROOT}" "${WORKSPACE_ROOT}" ||
    {
        [[ -d "${WORKSPACE_ROOT}" && -d "${OUTPUT_ROOT}" ]] &&
        {
            directory_contains_physical "${WORKSPACE_ROOT}" "${OUTPUT_ROOT}" ||
            directory_contains_physical "${OUTPUT_ROOT}" "${WORKSPACE_ROOT}"
        }
    }; then
    printf '%s\n' \
        'The writable output root and read-only checkout workspace must be disjoint.' \
        "Workspace: ${WORKSPACE_ROOT}" \
        "Output: ${OUTPUT_ROOT}" >&2
    exit 2
fi

if [[ ! -f "${PROMPT_PATH}" ]]; then
    printf 'Prompt template not found: %s\n' "${PROMPT_PATH}" >&2
    exit 2
fi

required_placeholders=(
    '{{REPOSITORY_URL}}'
    '{{REPOSITORY_PATH}}'
    '{{COMMIT}}'
    '{{REVIEW_DATE}}'
    '{{PRIOR_ART_START_DATE}}'
    '{{PROVENANCE_LOOKBACK_MONTHS}}'
    '{{PROVENANCE_START_DATE}}'
    '{{SCOPE_NAME}}'
    '{{OUTPUT_DIRECTORY}}'
    '{{REPOSITORY_METADATA}}'
    '{{PUBLIC_RESEARCH_INSTRUCTIONS}}'
    '{{PROVENANCE_INSTRUCTIONS}}'
)
for placeholder in "${required_placeholders[@]}"; do
    if ! grep -Fq -- "${placeholder}" "${PROMPT_PATH}"; then
        printf 'Prompt template is missing: %s\n' "${placeholder}" >&2
        exit 2
    fi
done

if ((PLAN_ONLY || !VALIDATE_ONLY)); then
    command -v git >/dev/null 2>&1 || {
        printf 'git is required.\n' >&2
        exit 2
    }
fi

if ((!VALIDATE_ONLY && !PLAN_ONLY)); then
    command -v copilot >/dev/null 2>&1 || {
        printf 'copilot is required.\n' >&2
        exit 2
    }
    command -v timeout >/dev/null 2>&1 || {
        printf 'GNU timeout is required.\n' >&2
        exit 2
    }
    command -v tar >/dev/null 2>&1 || {
        printf 'tar is required.\n' >&2
        exit 2
    }
    command -v python3 >/dev/null 2>&1 || {
        printf 'Python 3 is required for public DNS validation.\n' >&2
        exit 2
    }
fi

declare -a canonical_urls=()
declare -a slugs=()
declare -a source_kinds=()
declare -a source_paths=()
declare -a requested_commits=()
declare -a repository_hosts=()
declare -a repository_ports=()
declare -a curl_resolves=()
declare -A seen_slugs=()

decode_url_path() {
    local input="$1"
    local output=""
    local character hex byte
    local index=0

    while ((index < ${#input})); do
        character="${input:index:1}"
        if [[ "${character}" == '%' ]]; then
            if ((index + 2 >= ${#input})); then
                return 1
            fi
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

canonicalize_repository() {
    local input="$1"
    local value="${input%/}"
    local authority path host port decoded_path host_part path_part slug remainder
    local lower_value suffix label
    local -a host_labels

    lower_value="${value,,}"
    if [[ "${lower_value}" != https://* ]] ||
        [[ "${value}" == *'?'* ]] ||
        [[ "${value}" == *'#'* ]] ||
        [[ "${value}" =~ [[:cntrl:][:space:]] ]]; then
        printf '%s\n' \
            "Only anonymous public HTTPS Git repository URLs without embedded credentials, queries, or fragments are supported: ${input}" \
            >&2
        return 1
    fi

    if [[ "${lower_value}" =~ %0[0-9a-f]|%1[0-9a-f]|%7f|%2f|%5c ]]; then
        printf 'Repository URL contains unsupported characters: %s\n' \
            "${input}" >&2
        return 1
    fi

    remainder="${value:8}"
    authority="${remainder%%/*}"
    path="/${remainder#*/}"
    if [[ "${authority}" == "${remainder}" ]] ||
        [[ -z "${authority}" ]] ||
        [[ "${authority}" == *'@'* ]] ||
        [[ "${authority}" == *'['* || "${authority}" == *']'* ]]; then
        printf 'Repository URL must contain a public DNS host and Git path: %s\n' \
            "${input}" >&2
        return 1
    fi

    host="${authority}"
    port=""
    if [[ "${authority}" == *:* ]]; then
        host="${authority%%:*}"
        port="${authority#*:}"
        if [[ ! "${port}" =~ ^[0-9]+$ ]] ||
            ((10#${port} < 1 || 10#${port} > 65535)); then
            printf 'Repository URL contains an invalid HTTPS port: %s\n' \
                "${input}" >&2
            return 1
        fi
    fi
    host="${host,,}"
    if [[ "${host}" != *.* ]] ||
        [[ "${host}" == localhost ]] ||
        [[ "${host}" =~ ^[0-9.]+$ ]]; then
        printf 'Repository host must be a public DNS name: %s\n' \
            "${input}" >&2
        return 1
    fi
    for suffix in \
        .localhost .local .localdomain .internal .home .lan .corp \
        .test .invalid .example; do
        if [[ "${host}" == *"${suffix}" ]]; then
            printf 'Repository host must be a public DNS name: %s\n' \
                "${input}" >&2
            return 1
        fi
    done
    IFS='.' read -r -a host_labels <<< "${host}"
    for label in "${host_labels[@]}"; do
        if [[ ! "${label}" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] &&
            [[ ! "${label}" =~ ^[A-Za-z0-9]$ ]]; then
            printf 'Repository host contains an unsupported DNS label: %s\n' \
                "${input}" >&2
            return 1
        fi
    done

    path="${path%/}"
    if [[ "${path,,}" == *.git ]]; then
        path="${path:0:${#path}-4}"
    fi
    decoded_path="$(decode_url_path "${path}")" || {
        printf 'Repository URL contains malformed percent encoding: %s\n' \
            "${input}" >&2
        return 1
    }
    if [[ -z "${path#/}" ]] ||
        [[ "${decoded_path}" =~ [[:cntrl:][:space:]\\] ]]; then
        printf 'Repository URL must contain a safe non-empty Git path: %s\n' \
            "${input}" >&2
        return 1
    fi

    authority="${host}${port:+:${port}}"
    value="https://${authority}${path}"
    if [[ "${host}" == github.com ]]; then
        host_part='github'
    else
        host_part="$(printf '%s' "${host}" | sed -E 's/[^A-Za-z0-9]+/-/g')"
    fi
    path_part="$(
        printf '%s' "${decoded_path#/}" |
            sed -E 's/\.git$//I; s/[^A-Za-z0-9._-]+/--/g'
    )"
    slug="${host_part}--${path_part}"
    slug="${slug,,}"
    slug="${slug#-}"
    slug="${slug%-}"
    if [[ -z "${slug}" || ${#slug} -gt 120 ]]; then
        printf '%s\n' \
            'Repository host and path are too long for safe artifact naming.' >&2
        return 1
    fi
    if [[ -n "${seen_slugs[${slug}]+x}" ]]; then
        printf 'Duplicate repository: %s\n' "${input}" >&2
        return 1
    fi

    seen_slugs["${slug}"]=1
    canonical_urls+=("${value}")
    slugs+=("${slug}")
    source_kinds+=("RemoteUrl")
    source_paths+=("")
    requested_commits+=("${REQUESTED_COMMIT}")
    repository_hosts+=("${host}")
    repository_ports+=("${port:-443}")
    curl_resolves+=("")
}

clear_inherited_git_environment() {
    local variable_name
    while IFS= read -r variable_name; do
        unset "${variable_name}"
    done < <(compgen -A variable GIT_)
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_ATTR_NOSYSTEM=1
    export GIT_DISCOVERY_ACROSS_FILESYSTEM=1
    export GIT_LFS_SKIP_SMUDGE=1
    export GIT_NO_REPLACE_OBJECTS=1
    export GIT_OPTIONAL_LOCKS=0
    export GIT_TERMINAL_PROMPT=0
}

for repository in "${repositories[@]}"; do
    canonicalize_repository "${repository}"
done

if ((ENABLE_PUBLIC_RESEARCH)); then
    PUBLIC_RESEARCH_INSTRUCTIONS=$'ENABLED. Invoke a separate research specialist. Search only public sources.\nDo not include private code, internal names, internal URLs, credentials, or\nnon-public information in search queries.'
else
    PUBLIC_RESEARCH_INSTRUCTIONS=$'DISABLED. Do not perform public web research or invoke the research specialist.\nState that prior-art and community research were not requested.'
fi

if ((ENABLE_PROVENANCE_RESEARCH)); then
    PROVENANCE_INSTRUCTIONS=$'ENABLED. Assess whole-repository, exact-commit, evidence-based provenance of\nagentically generated code within the stated provenance window. Style, commit\nsize, quality, or similarity alone cannot prove AI generation, copying,\nplagiarism, intent, or misconduct. Require public evidence, chronology,\nsource lineage, alternative explanations, confidence, and human review.'
else
    PROVENANCE_INSTRUCTIONS=$'DISABLED. Do not analyze whether the repository contains agentically\ngenerated code or make unsupported claims about copying, plagiarism,\nintent, or misconduct.'
fi

if ((PLAN_ONLY || !VALIDATE_ONLY)); then
    clear_inherited_git_environment
    require_outside_git_repository \
        "${WORKSPACE_ROOT}" 'The checkout workspace root' || exit 2
    require_outside_git_repository \
        "${OUTPUT_ROOT}" 'The artifact output root' || exit 2
fi

PLAN_GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REVIEW_DATE="$(date +%Y-%m-%d)"
PRIOR_ART_START_DATE="$(
    subtract_calendar_months "${REVIEW_DATE}" \
        "${DEFAULT_PRIOR_ART_LOOKBACK_MONTHS}"
)"
if ((ENABLE_PROVENANCE_RESEARCH)); then
    PROVENANCE_START_DATE="$(
        subtract_calendar_months "${REVIEW_DATE}" \
            "${PROVENANCE_LOOKBACK_MONTHS}"
    )"
else
    PROVENANCE_START_DATE=''
fi
APPROVAL_HASH="$(compute_approval_hash)"

if ((VALIDATE_ONLY)); then
    for index in "${!canonical_urls[@]}"; do
        printf '%s  %s  %s  %s\n' \
            "${source_kinds[index]}" \
            "${slugs[index]}" \
            "${canonical_urls[index]}" \
            "${requested_commits[index]}"
    done
    printf '\nPrompt template:      %s\n' "${PROMPT_PATH}"
    printf 'Workspace root:       %s\n' "${WORKSPACE_ROOT}"
    printf 'Output root:          %s\n' "${OUTPUT_ROOT}"
    printf 'Scope:                %s\n' "${SCOPE_NAME}"
    printf 'Planning estimate:    %s\n' "${SCOPE_ESTIMATE}"
    printf 'Throttle limit:       %s\n' "${THROTTLE_LIMIT}"
    printf 'Maximum repositories: %s\n' "${MAX_REPOSITORIES}"
    printf 'Session timeout:      %s minutes\n' "${SESSION_TIMEOUT_MINUTES}"
    printf 'Public research:      %s\n' "${ENABLE_PUBLIC_RESEARCH}"
    printf 'Provenance research:  %s\n' "${ENABLE_PROVENANCE_RESEARCH}"
    if ((ENABLE_PROVENANCE_RESEARCH)); then
        printf 'Provenance lookback:  %s months\n' \
            "${PROVENANCE_LOOKBACK_MONTHS}"
        printf 'Provenance window:    pending review date\n'
    else
        printf 'Provenance window:    disabled\n'
    fi
    printf 'Model:                %s\n' "${MODEL}"
    exit 0
fi

if [[ -n "${EXPECTED_PLAN_HASH}" ]] &&
    [[ "${APPROVAL_HASH}" != "${EXPECTED_PLAN_HASH}" ]]; then
    printf '%s\n' 'approved plan changed; regenerate and reconfirm' >&2
    printf 'Expected approval hash: %s\n' "${EXPECTED_PLAN_HASH}" >&2
    printf 'Resolved approval hash: %s\n' "${APPROVAL_HASH}" >&2
    exit 2
fi

if ((PLAN_ONLY)); then
    write_review_plan_json
    exit 0
fi

write_review_plan_text
if is_interactive_console; then
    read -r -p 'Run this review plan? [y/N] ' confirm_input
    confirm_input="${confirm_input,,}"
    if [[ "${confirm_input}" != "y" && "${confirm_input}" != "yes" ]]; then
        printf '%s\n' 'Review plan cancelled.' >&2
        exit 1
    fi
fi
printf 'Starting %s; public research %s; provenance %s.\n' \
    "${SCOPE_NAME}" \
    "$(status_word "${ENABLE_PUBLIC_RESEARCH}")" \
    "$(status_word "${ENABLE_PROVENANCE_RESEARCH}")"

authentication_variables=(
    COPILOT_GITHUB_TOKEN
    GH_TOKEN
    GITHUB_TOKEN
    COPILOT_PROVIDER_API_KEY
    COPILOT_PROVIDER_BEARER_TOKEN
    ANTHROPIC_API_KEY
    AZURE_OPENAI_API_KEY
    OPENAI_API_KEY
    CAPI_HMAC_KEY
    COPILOT_HMAC_KEY
    GITHUB_COPILOT_API_TOKEN
)
source_copilot_home="${COPILOT_HOME:-${HOME}/.copilot}"
mapfile -t copilot_auth_bridge < <(
    python3 - "${source_copilot_home}/config.json" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
bridge = {}
if path.is_file():
    try:
        text = "\n".join(
            line for line in path.read_text(encoding="utf-8").splitlines()
            if not line.lstrip().startswith("//")
        )
        config = json.loads(text)
        for name in (
            "lastLoggedInUser",
            "loggedInUsers",
            "copilotTokens",
            "last_logged_in_user",
            "logged_in_users",
            "copilot_tokens",
        ):
            if name in config:
                bridge[name] = config[name]
    except (OSError, UnicodeError, json.JSONDecodeError):
        bridge = {}

has_plaintext_tokens = any(
    isinstance(bridge.get(name), dict) and bridge[name]
    for name in ("copilotTokens", "copilot_tokens")
)
print("1" if has_plaintext_tokens else "0")
print(json.dumps(bridge, separators=(",", ":")))
PY
)
COPILOT_AUTH_BRIDGE_HAS_PLAINTEXT="${copilot_auth_bridge[0]:-0}"
COPILOT_AUTH_BRIDGE_JSON="${copilot_auth_bridge[1]:-}"
[[ -n "${COPILOT_AUTH_BRIDGE_JSON}" ]] ||
    COPILOT_AUTH_BRIDGE_JSON='{}'
unset copilot_auth_bridge
printf '%s\n' \
    'Copilot authentication will be verified by the first isolated review session using the current environment, system credential store, GitHub CLI fallback, configured provider, or an ephemeral local auth bridge.'

git_version="$(git --version 2>/dev/null)" || {
    printf 'Could not determine the installed Git version.\n' >&2
    exit 2
}
git_version="${git_version#git version }"
git_version="${git_version%%[^0-9.]*}"
IFS='.' read -r git_major git_minor _ <<< "${git_version}"
if ! [[ "${git_major}" =~ ^[0-9]+$ && "${git_minor}" =~ ^[0-9]+$ ]] ||
    ((git_major < 2 || (git_major == 2 && git_minor < 41))); then
    printf '%s\n' \
        'Git 2.41 or newer is required for DNS-pinned public HTTPS clones.' >&2
    exit 2
fi

resolve_public_endpoint() {
    python3 - "$1" "$2" <<'PY'
import ipaddress
import socket
import sys
import time

host = sys.argv[1]
port = int(sys.argv[2])
last_error = None
for attempt in range(3):
    try:
        records = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
        break
    except OSError as error:
        last_error = error
        if attempt < 2:
            time.sleep(0.2 * (attempt + 1))
else:
    raise SystemExit(f"Could not resolve public repository host {host}: {last_error}")

addresses = sorted({
    ipaddress.ip_address(record[4][0].split("%", 1)[0])
    for record in records
}, key=lambda address: (address.version, int(address)))
if not addresses:
    raise SystemExit(f"Public repository host did not resolve: {host}")
if any(not address.is_global for address in addresses):
    raise SystemExit(
        f"Repository host must resolve only to public IP addresses: {host}"
    )

formatted = [
    f"[{address}]" if address.version == 6 else str(address)
    for address in addresses
]
print(f"{host}:{port}:{','.join(formatted)}")
PY
}

for index in "${!canonical_urls[@]}"; do
    curl_resolves[index]="$(
        resolve_public_endpoint \
            "${repository_hosts[index]}" \
            "${repository_ports[index]}"
    )" || exit 2
done

RUN_ID="$(
    printf '%s-' "$(date +%Y%m%d-%H%M%S)"
    od -An -N8 -tx1 /dev/urandom | tr -d '[:space:]'
)"
RUN_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
RUN_WORKSPACE="${WORKSPACE_ROOT}/${RUN_ID}"
RUN_RESULTS="${OUTPUT_ROOT}/${RUN_ID}"
require_outside_git_repository \
    "${WORKSPACE_ROOT}" 'The checkout workspace root' || exit 2
require_outside_git_repository \
    "${OUTPUT_ROOT}" 'The artifact output root' || exit 2
mkdir -p -- "${WORKSPACE_ROOT}" "${OUTPUT_ROOT}"
WORKSPACE_ROOT="$(canonicalize_directory_path "${WORKSPACE_ROOT}")"
OUTPUT_ROOT="$(canonicalize_directory_path "${OUTPUT_ROOT}")"
require_control_free_paths "${WORKSPACE_ROOT}" "${OUTPUT_ROOT}" || exit 2
if directory_contains_physical "${WORKSPACE_ROOT}" "${OUTPUT_ROOT}" ||
    directory_contains_physical "${OUTPUT_ROOT}" "${WORKSPACE_ROOT}"; then
    printf '%s\n' \
        'The writable output root and read-only checkout workspace became overlapping.' \
        "Workspace: ${WORKSPACE_ROOT}" \
        "Output: ${OUTPUT_ROOT}" >&2
    exit 2
fi
require_outside_git_repository \
    "${WORKSPACE_ROOT}" 'The checkout workspace root' || exit 2
require_outside_git_repository \
    "${OUTPUT_ROOT}" 'The artifact output root' || exit 2
RUN_WORKSPACE="${WORKSPACE_ROOT}/${RUN_ID}"
RUN_RESULTS="${OUTPUT_ROOT}/${RUN_ID}"
mkdir -- "${RUN_WORKSPACE}" "${RUN_RESULTS}"
RUN_WORKSPACE="$(canonicalize_directory_path "${RUN_WORKSPACE}")"
RUN_RESULTS="$(canonicalize_directory_path "${RUN_RESULTS}")"
require_control_free_paths "${RUN_WORKSPACE}" "${RUN_RESULTS}" || exit 2
if ! directory_contains_physical "${WORKSPACE_ROOT}" "${RUN_WORKSPACE}" ||
    ! directory_contains_physical "${OUTPUT_ROOT}" "${RUN_RESULTS}" ||
    directory_contains_physical "${RUN_WORKSPACE}" "${RUN_RESULTS}" ||
    directory_contains_physical "${RUN_RESULTS}" "${RUN_WORKSPACE}"; then
    printf '%s\n' \
        'Run-specific checkout and output directories are not safely disjoint.' >&2
    exit 2
fi
REVIEW_PLAN_JSON_PATH="${RUN_RESULTS}/review-plan.json"
REVIEW_PLAN_TEXT_PATH="${RUN_RESULTS}/review-plan.txt"
write_review_plan_json "${RUN_ID}" "${RUN_STARTED_AT}" > "${REVIEW_PLAN_JSON_PATH}"
write_review_plan_text "${RUN_ID}" "${RUN_STARTED_AT}" > "${REVIEW_PLAN_TEXT_PATH}"
review_progress \
    'run' \
    'started' \
    "${#canonical_urls[@]} repositories; output ${RUN_RESULTS}"
ANONYMOUS_GIT_HOME="${RUN_WORKSPACE}/.anonymous-git-home"
mkdir -m 700 -- "${ANONYMOUS_GIT_HOME}"

anonymous_git() {
    env \
        -u COPILOT_GITHUB_TOKEN \
        -u GH_TOKEN \
        -u GITHUB_TOKEN \
        -u GIT_ASKPASS \
        -u SSH_ASKPASS \
        -u SSH_AUTH_SOCK \
        -u GCM_INTERACTIVE \
        -u GCM_MODAL_PROMPT \
        -u NETRC \
        -u http_proxy \
        -u https_proxy \
        -u all_proxy \
        -u no_proxy \
        -u HTTP_PROXY \
        -u HTTPS_PROXY \
        -u ALL_PROXY \
        -u NO_PROXY \
        HOME="${ANONYMOUS_GIT_HOME}" \
        USERPROFILE="${ANONYMOUS_GIT_HOME}" \
        XDG_CONFIG_HOME="${ANONYMOUS_GIT_HOME}" \
        CURL_HOME="${ANONYMOUS_GIT_HOME}" \
        GIT_CONFIG_NOSYSTEM=1 \
        GIT_CONFIG_GLOBAL=/dev/null \
        GIT_ATTR_NOSYSTEM=1 \
        GIT_DISCOVERY_ACROSS_FILESYSTEM=1 \
        GIT_LFS_SKIP_SMUDGE=1 \
        GIT_NO_REPLACE_OBJECTS=1 \
        GIT_OPTIONAL_LOCKS=0 \
        GIT_TERMINAL_PROMPT=0 \
        git "$@"
}

anonymous_git_repository() {
    local curl_resolve="$1"
    shift

    anonymous_git \
        -c core.hooksPath=/dev/null \
        -c protocol.allow=never \
        -c protocol.https.allow=always \
        -c protocol.file.allow=never \
        -c protocol.ext.allow=never \
        -c credential.helper= \
        -c credential.interactive=false \
        -c http.extraHeader= \
        -c http.proxy= \
        -c http.sslVerify=true \
        -c http.followRedirects=false \
        -c "http.curloptResolve=${curl_resolve}" \
        "$@"
}

write_result() {
    local path="$1"
    local slug="$2"
    local repository="$3"
    local session="$4"
    local commit="$5"
    local status="$6"
    local exit_code="$7"
    local checkout="$8"
    local output_directory="$9"
    local report="${10}"
    local markdown="${11}"
    local html="${12}"
    local timeline="${13}"
    local transcript="${14}"
    local request="${15}"
    local errors="${16}"
    local handoff="${17}"
    local started_at="${18}"
    local completed_at="${19}"
    local session_id="${20}"
    local verification_clone="${21}"
    local requested_commit="${22}"
    local source_kind="${23}"
    local source_path="${24}"

    cat > "${path}" <<EOF
{
  "SchemaVersion": ${STATE_SCHEMA_VERSION},
  "Slug": "$(json_escape "${slug}")",
  "Repository": "$(json_escape "${repository}")",
  "Source": {
    "Kind": "$(json_escape "${source_kind}")",
    "LocalPath": "$(json_escape "${source_path}")",
    "RemoteUrl": "$(json_escape "${repository}")"
  },
  "RequestedCommit": "$(json_escape "${requested_commit}")",
  "Commit": "$(json_escape "${commit}")",
  "Status": "$(json_escape "${status}")",
  "ExitCode": ${exit_code},
  "StartedAt": "$(json_escape "${started_at}")",
  "CompletedAt": "$(json_escape "${completed_at}")",
  "Scope": {
    "Name": "$(json_escape "${SCOPE_NAME}")",
    "PlanningEstimate": "$(json_escape "${SCOPE_ESTIMATE}")",
    "PublicResearch": $([[ ${ENABLE_PUBLIC_RESEARCH} -eq 1 ]] && printf true || printf false),
    "ProvenanceResearch": $([[ ${ENABLE_PROVENANCE_RESEARCH} -eq 1 ]] && printf true || printf false)
  },
  "ProvenanceWindow": $(provenance_window_json '  '),
  "Session": {
    "Id": "$(json_escape "${session_id}")",
    "Name": "$(json_escape "${session}")",
    "ResumePolicy": "Continue only through the trusted Rhyolite repo-review runner; do not invoke copilot --resume directly."
  },
  "Paths": {
    "ReadOnlyCheckout": "$(json_escape "${checkout}")",
    "VerificationClone": "$(json_escape "${verification_clone}")",
    "WritableOutput": "$(json_escape "${output_directory}")"
  },
  "Artifacts": {
    "PlainText": "$(json_escape "${report}")",
    "Markdown": "$(json_escape "${markdown}")",
    "Html": "$(json_escape "${html}")",
    "Timeline": "$(json_escape "${timeline}")",
    "Transcript": "$(json_escape "${transcript}")",
    "Request": "$(json_escape "${request}")",
    "Errors": "$(json_escape "${errors}")",
    "State": "$(json_escape "${path}")",
    "Handoff": "$(json_escape "${handoff}")",
    "AgentState": "$(json_escape "${output_directory}/agent-state")"
  }
}
EOF
}

finalize_repository_artifacts() {
    local state_path="$1"
    local slug="$2"
    local repository="$3"
    local session="$4"
    local commit="$5"
    local status="$6"
    local exit_code="$7"
    local checkout="$8"
    local output_directory="$9"
    local report="${10}"
    local markdown="${11}"
    local html="${12}"
    local timeline="${13}"
    local transcript="${14}"
    local request="${15}"
    local errors="${16}"
    local handoff="${17}"
    local started_at="${18}"
    local completed_at="${19}"
    local active_session_id="${session_id:-}"
    local active_verification_clone="${verification_clone:-${checkout}}"
    local active_requested_commit="${requested_commit:-}"
    local active_source_kind="${source_kind:-RemoteUrl}"
    local active_source_path="${source_path:-}"

    mkdir -p -- "${output_directory}/agent-state"
    [[ -f "${timeline}" ]] || : > "${timeline}"
    if [[ ! -f "${transcript}" ]]; then
        printf '# Copilot session transcript\n\n%s\n' \
            'No completed session transcript is available.' > "${transcript}"
    fi
    if [[ ! -f "${request}" ]]; then
        printf '%s\n' \
            'No review request was generated because the session did not start.' \
            > "${request}"
    fi
    [[ -f "${errors}" ]] || : > "${errors}"
    if [[ -s "${errors}" ]]; then
        tr -d '\r' < "${errors}" |
            strip_terminal_controls |
            redact_credentials |
            redact_emails > "${errors}.tmp"
        mv -- "${errors}.tmp" "${errors}"
    fi

    write_markdown_report "${report}" "${markdown}"
    write_html_report \
        "${report}" "${html}" "${repository}" "${commit}" "${status}"
    write_review_handoff \
        "${handoff}" "${repository}" "${commit}" "${status}" "${session}" \
        "${checkout}" "${output_directory}" "${SCOPE_NAME}" \
        "${SCOPE_ESTIMATE}" "${active_session_id}" \
        "${active_source_kind}" "${active_source_path}" \
        "$(provenance_window_text)"
    write_result \
        "${state_path}" "${slug}" "${repository}" "${session}" "${commit}" \
        "${status}" "${exit_code}" "${checkout}" "${output_directory}" \
        "${report}" "${markdown}" "${html}" "${timeline}" "${transcript}" \
        "${request}" "${errors}" "${handoff}" "${started_at}" \
        "${completed_at}" "${active_session_id}" \
        "${active_verification_clone}" "${active_requested_commit}" \
        "${active_source_kind}" "${active_source_path}"
    printf '%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0%s\0' \
        "${repository}" "${active_source_kind}" "${active_source_path}" \
        "${active_requested_commit}" "${commit}" "${status}" \
        "${state_path}" "${handoff}" "${html}" \
        > "${output_directory}/.result-summary"
}

write_repository_failure_result() {
    local slug="$1"
    local repository="$2"
    local requested_commit="$3"
    local source_kind="$4"
    local source_path="$5"
    local status="$6"
    local summary="$7"
    local error_text="$8"
    local started_at="$9"
    local failure_exit_code="${10:-1}"
    local verification_clone="${11-}"
    local result_path="${RUN_RESULTS}/${slug}"
    local report_path="${result_path}/review.txt"
    local markdown_path="${result_path}/review.md"
    local html_path="${result_path}/review.html"
    local timeline_path="${result_path}/analysis-timeline.txt"
    local transcript_path="${result_path}/session.md"
    local request_path="${result_path}/request.txt"
    local error_path="${result_path}/errors.txt"
    local state_path="${result_path}/state.json"
    local handoff_path="${result_path}/handoff.md"
    local review_path=""
    local session_id=""

    mkdir -p -- "${result_path}"
    if [[ -n "${error_text}" ]]; then
        printf '%s\n' "${error_text}" > "${error_path}"
    else
        : > "${error_path}"
    fi
    cat > "${report_path}" <<EOF
================================================================================
REPOSITORY REVIEW REPORT
${summary}
================================================================================
EOF
    finalize_repository_artifacts \
        "${state_path}" "${slug}" "${repository}" "" "" "${status}" \
        "${failure_exit_code}" \
        "${review_path}" "${result_path}" "${report_path}" \
        "${markdown_path}" "${html_path}" "${timeline_path}" \
        "${transcript_path}" "${request_path}" "${error_path}" \
        "${handoff_path}" "${started_at}" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

PREFLIGHT_FAILURE_SUMMARY=""
PREFLIGHT_ERROR_DETAILS=""
PREFLIGHT_EXIT_CODE=1

preflight_repository_access() {
    local repository="$1"
    local slug="$2"
    local requested_commit="$3"
    local source_kind="$4"
    local source_path="$5"
    local curl_resolve="$6"
    local ls_remote_output=""
    local ls_remote_exit=0
    local init_output=""
    local init_exit=0
    local fetch_output=""
    local fetch_exit=0
    local verify_output=""
    local verify_exit=0
    local preflight_path="${RUN_WORKSPACE}/${slug}-preflight"

    PREFLIGHT_FAILURE_SUMMARY=""
    PREFLIGHT_ERROR_DETAILS=""
    PREFLIGHT_EXIT_CODE=1

    review_progress "${slug}" 'preflight' 'checking anonymous public access'

    ls_remote_output="$(
        anonymous_git_repository "${curl_resolve}" \
            ls-remote --symref --exit-code -- "${repository}" HEAD 2>&1
    )" || ls_remote_exit=$?
    if ((ls_remote_exit != 0)); then
        PREFLIGHT_EXIT_CODE="${ls_remote_exit}"
        PREFLIGHT_FAILURE_SUMMARY='Anonymous repository accessibility preflight failed. Rhyolite currently supports only publicly accessible repositories and does not attempt authentication. See errors.txt.'
        PREFLIGHT_ERROR_DETAILS="$(
            cat <<EOF
Anonymous repository accessibility preflight failed.
Rhyolite currently supports only publicly accessible repositories and does not attempt authentication.
Repository: ${repository}
Source kind: ${source_kind}
Selected source path: ${source_path:-NOT APPLICABLE}
Requested commit: ${requested_commit:-HEAD}
Git command: git ls-remote --symref --exit-code -- ${repository} HEAD
Exit code: ${ls_remote_exit}

${ls_remote_output}
EOF
        )"
        return 1
    fi

    if [[ -n "${requested_commit}" ]]; then
        rm -rf -- "${preflight_path}" 2>/dev/null || true

        init_output="$(
            anonymous_git init --quiet -- "${preflight_path}" 2>&1
        )" || init_exit=$?
        if ((init_exit != 0)); then
            PREFLIGHT_EXIT_CODE="${init_exit}"
            PREFLIGHT_FAILURE_SUMMARY='Anonymous repository accessibility preflight could not initialize exact-commit verification. See errors.txt.'
            PREFLIGHT_ERROR_DETAILS="$(
                cat <<EOF
Anonymous repository accessibility preflight could not initialize exact-commit verification.
Repository: ${repository}
Source kind: ${source_kind}
Selected source path: ${source_path:-NOT APPLICABLE}
Requested commit: ${requested_commit}
Git command: git init --quiet -- ${preflight_path}
Exit code: ${init_exit}

${init_output}
EOF
            )"
            rm -rf -- "${preflight_path}" 2>/dev/null || true
            return 1
        fi

        fetch_output="$(
            anonymous_git_repository "${curl_resolve}" \
                -C "${preflight_path}" \
                fetch --quiet --no-tags --depth=1 -- \
                "${repository}" "${requested_commit}" 2>&1
        )" || fetch_exit=$?
        if ((fetch_exit != 0)); then
            PREFLIGHT_EXIT_CODE="${fetch_exit}"
            PREFLIGHT_FAILURE_SUMMARY='Anonymous repository accessibility preflight could not verify the exact commit. Rhyolite currently supports only publicly accessible repositories and does not attempt authentication. See errors.txt.'
            PREFLIGHT_ERROR_DETAILS="$(
                cat <<EOF
Anonymous repository accessibility preflight could not verify the exact commit.
Rhyolite currently supports only publicly accessible repositories and does not attempt authentication.
Repository: ${repository}
Source kind: ${source_kind}
Selected source path: ${source_path:-NOT APPLICABLE}
Requested commit: ${requested_commit}
Git command: git fetch --quiet --no-tags --depth=1 -- ${repository} ${requested_commit}
Exit code: ${fetch_exit}

${fetch_output}
EOF
            )"
            rm -rf -- "${preflight_path}" 2>/dev/null || true
            return 1
        fi

        verify_output="$(
            git -C "${preflight_path}" rev-parse --verify FETCH_HEAD^{commit} 2>&1
        )" || verify_exit=$?
        if ((verify_exit != 0)); then
            PREFLIGHT_EXIT_CODE="${verify_exit}"
            PREFLIGHT_FAILURE_SUMMARY='Anonymous repository accessibility preflight could not verify the exact fetched commit. See errors.txt.'
            PREFLIGHT_ERROR_DETAILS="$(
                cat <<EOF
Anonymous repository accessibility preflight could not verify the exact fetched commit.
Repository: ${repository}
Source kind: ${source_kind}
Selected source path: ${source_path:-NOT APPLICABLE}
Requested commit: ${requested_commit}
Git command: git rev-parse --verify FETCH_HEAD^{commit}
Exit code: ${verify_exit}

${verify_output}
EOF
            )"
            rm -rf -- "${preflight_path}" 2>/dev/null || true
            return 1
        fi

        rm -rf -- "${preflight_path}" 2>/dev/null || true
        review_progress \
            "${slug}" \
            'preflight' \
            "anonymous access confirmed at ${requested_commit:0:12}"
        return 0
    fi

    review_progress "${slug}" 'preflight' 'anonymous access confirmed'
    return 0
}

new_session_id() {
    local value hex
    if [[ -r /proc/sys/kernel/random/uuid ]]; then
        read -r value < /proc/sys/kernel/random/uuid
        printf '%s\n' "${value}"
        return
    fi
    if command -v uuidgen >/dev/null 2>&1; then
        uuidgen | tr '[:upper:]' '[:lower:]'
        return
    fi

    hex="$(od -An -N16 -tx1 /dev/urandom | tr -d '[:space:]')"
    printf '%s-%s-%s-%s-%s\n' \
        "${hex:0:8}" "${hex:8:4}" "${hex:12:4}" \
        "${hex:16:4}" "${hex:20:12}"
}

sanitize_and_remove_runtime_copilot_home() {
    local runtime_home="$1"
    local attempt

    [[ -n "${runtime_home}" && -e "${runtime_home}" ]] || return 0
    if [[ -f "${runtime_home}/config.json" ]]; then
        if ! rm -f -- "${runtime_home}/config.json"; then
            {
                printf '%s\n' \
                    '// User settings belong in settings.json.' \
                    '// This file is managed automatically.' \
                    '{}'
            } > "${runtime_home}/config.json" 2>/dev/null || true
            chmod 600 -- "${runtime_home}/config.json" 2>/dev/null || true
        fi
    fi

    for attempt in 1 2 3; do
        rm -rf -- "${runtime_home}" 2>/dev/null || true
        [[ ! -e "${runtime_home}" ]] && return 0
        sleep 1
    done
    return 1
}

process_repository() {
    local repository="$1"
    local slug="$2"
    local requested_commit="$3"
    local source_kind="$4"
    local source_path="$5"
    local curl_resolve="$6"
    local started_at
    started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local clone_path="${RUN_WORKSPACE}/${slug}-readonly"
    local verification_clone="${clone_path}"
    local session_root="${RUN_WORKSPACE}/${slug}-session"
    local snapshot_path="${session_root}/source"
    local review_path=""
    local result_path="${RUN_RESULTS}/${slug}"
    local report_path="${result_path}/review.txt"
    local markdown_path="${result_path}/review.md"
    local html_path="${result_path}/review.html"
    local timeline_path="${result_path}/analysis-timeline.txt"
    local transcript_path="${result_path}/session.md"
    local request_path="${result_path}/request.txt"
    local error_path="${result_path}/errors.txt"
    local state_path="${result_path}/state.json"
    local handoff_path="${result_path}/handoff.md"
    local agent_state_path="${result_path}/agent-state"
    local copilot_home_path="${agent_state_path}/copilot-home"
    local raw_output="${result_path}/copilot-output.raw"
    local session_id=""
    local session_name=""
    local commit=""
    local status="ReviewFailed"
    local exit_code=1
    local post_process_failure=0
    local runtime_copilot_home=""

    mkdir -p -- "${result_path}"
    : > "${error_path}"
    review_progress "${slug}" 'clone' 'anonymous public HTTPS clone started'

    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_LFS_SKIP_SMUDGE=1
    export GIT_TERMINAL_PROMPT=0

    set +e
    anonymous_git_repository "${curl_resolve}" \
        clone \
        --quiet \
        --filter=blob:none \
        --no-recurse-submodules \
        -- \
        "${repository}" \
        "${clone_path}" 2> "${error_path}"
    local clone_exit_code=$?
    set -e
    if ((clone_exit_code != 0)); then
        cat > "${report_path}" <<'EOF'
================================================================================
REPOSITORY REVIEW REPORT
Repository clone failed. See errors.txt.
================================================================================
EOF
        finalize_repository_artifacts \
            "${state_path}" "${slug}" "${repository}" "" "" "CloneFailed" \
            "${clone_exit_code}" \
            "${review_path}" "${result_path}" "${report_path}" \
            "${markdown_path}" "${html_path}" "${timeline_path}" \
            "${transcript_path}" "${request_path}" "${error_path}" \
            "${handoff_path}" "${started_at}" \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        return 1
    fi

    if [[ -n "${requested_commit}" ]]; then
        local commit_setup_exit_code=0
        set +e
        git -C "${clone_path}" \
            cat-file -e "${requested_commit}^{commit}" 2>> "${error_path}"
        commit_setup_exit_code=$?
        set -e
        if ((commit_setup_exit_code != 0)); then
            set +e
            anonymous_git_repository "${curl_resolve}" \
                -C "${clone_path}" \
                fetch \
                --quiet \
                --no-tags \
                origin \
                "${requested_commit}" 2>> "${error_path}"
            commit_setup_exit_code=$?
            set -e
            if ((commit_setup_exit_code != 0)); then
                cat > "${report_path}" <<'EOF'
================================================================================
REPOSITORY REVIEW REPORT
Requested commit could not be fetched. See errors.txt.
================================================================================
EOF
                finalize_repository_artifacts \
                    "${state_path}" "${slug}" "${repository}" "" \
                    "" "CommitResolutionFailed" \
                    "${commit_setup_exit_code}" \
                    "${review_path}" "${result_path}" "${report_path}" \
                    "${markdown_path}" "${html_path}" "${timeline_path}" \
                    "${transcript_path}" "${request_path}" "${error_path}" \
                    "${handoff_path}" "${started_at}" \
                    "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
                return 1
            fi
        fi
        set +e
        git \
            -C "${clone_path}" \
            -c core.hooksPath=/dev/null \
            checkout \
            --quiet \
            --detach \
            "${requested_commit}" 2>> "${error_path}"
        commit_setup_exit_code=$?
        set -e
        if ((commit_setup_exit_code != 0)); then
            cat > "${report_path}" <<'EOF'
================================================================================
REPOSITORY REVIEW REPORT
Requested commit could not be checked out. See errors.txt.
================================================================================
EOF
            finalize_repository_artifacts \
                "${state_path}" "${slug}" "${repository}" "" \
                "" "CommitResolutionFailed" "${commit_setup_exit_code}" \
                "${review_path}" "${result_path}" "${report_path}" \
                "${markdown_path}" "${html_path}" "${timeline_path}" \
                "${transcript_path}" "${request_path}" "${error_path}" \
                "${handoff_path}" "${started_at}" \
                "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            return 1
        fi
    fi

    local commit_resolution_exit_code=0
    set +e
    commit="$(git -C "${clone_path}" rev-parse HEAD 2>> "${error_path}")"
    commit_resolution_exit_code=$?
    set -e
    if ((commit_resolution_exit_code != 0)); then
        cat > "${report_path}" <<'EOF'
================================================================================
REPOSITORY REVIEW REPORT
Commit resolution failed. See errors.txt.
================================================================================
EOF
        finalize_repository_artifacts \
            "${state_path}" "${slug}" "${repository}" "" "" \
            "CommitResolutionFailed" "${commit_resolution_exit_code}" \
            "${review_path}" "${result_path}" \
            "${report_path}" "${markdown_path}" "${html_path}" \
            "${timeline_path}" "${transcript_path}" "${request_path}" \
            "${error_path}" "${handoff_path}" "${started_at}" \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        return 1
    fi
    if [[ -n "${requested_commit}" &&
        "${commit}" != "${requested_commit,,}" ]]; then
        printf 'Resolved commit %s does not match requested commit %s.\n' \
            "${commit}" "${requested_commit}" >> "${error_path}"
        cat > "${report_path}" <<'EOF'
================================================================================
REPOSITORY REVIEW REPORT
Requested commit did not resolve exactly. See errors.txt.
================================================================================
EOF
        finalize_repository_artifacts \
            "${state_path}" "${slug}" "${repository}" "" "${commit}" \
            "CommitResolutionFailed" 1 "${review_path}" "${result_path}" \
            "${report_path}" "${markdown_path}" "${html_path}" \
            "${timeline_path}" "${transcript_path}" "${request_path}" \
            "${error_path}" "${handoff_path}" "${started_at}" \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        return 1
    fi
    review_progress "${slug}" 'clone' "exact commit ${commit:0:12} resolved"

    local tracked_file_count repository_metadata
    tracked_file_count="$(
        git -C "${clone_path}" ls-files | wc -l | tr -d '[:space:]'
    )"
    repository_metadata="$(
        set +o pipefail
        {
            cat <<EOF
TRUSTED WRAPPER-SUPPLIED GIT METADATA
The child sees a read-only, .git-free source snapshot archived from a pristine
clone detached at the exact commit below. Direct shell and Git tools are
intentionally unavailable to the child agent.

Source type: ${source_kind}
Remote URL: ${repository}
HEAD: ${commit}
Tracked file count: ${tracked_file_count}

Top-level tracked entries (maximum 200):
EOF
            git -C "${clone_path}" ls-tree --name-only HEAD |
                awk 'NR <= 200 { print substr($0, 1, 512) }'
            printf '\nRefs (maximum 200):\n'
            git -C "${clone_path}" for-each-ref \
                '--format=%(refname)%09%(objectname)' \
                refs/heads refs/remotes refs/tags |
                awk 'NR <= 200 { print substr($0, 1, 512) }'
            printf '\nRecent commit history (maximum 100; author email addresses omitted):\n'
            git -C "${clone_path}" log \
                --no-show-signature \
                -n 100 \
                --date=iso-strict \
                '--pretty=format:%H%x09%ad%x09%<(128,trunc)%an%x09%<(256,trunc)%s' |
                awk '{ print substr($0, 1, 512) }'
            printf '\n'
        } |
            strip_terminal_controls |
            redact_credentials |
            redact_emails |
            head -c 65536
    )"
    if ((${#repository_metadata} > 65536)); then
        repository_metadata="${repository_metadata:0:65536}"$'\n[trusted metadata truncated by wrapper]'
    fi

    mkdir -- "${session_root}" "${snapshot_path}"
    local archive_path="${session_root}/source.tar"
    local attribute_path
    attribute_path="$(
        git -C "${clone_path}" rev-parse --git-path info/attributes
    )"
    if [[ "${attribute_path}" != /* ]]; then
        attribute_path="${clone_path}/${attribute_path}"
    fi
    mkdir -p -- "$(dirname -- "${attribute_path}")"
    local attribute_backup="${session_root}/info-attributes.backup"
    local had_attribute_file=0
    if [[ -f "${attribute_path}" ]]; then
        cp -- "${attribute_path}" "${attribute_backup}"
        had_attribute_file=1
    fi
    printf '%s\n' '* -export-ignore -export-subst' > "${attribute_path}"
    local snapshot_exit_code=0
    set +e
    git \
        -C "${clone_path}" \
        -c core.hooksPath=/dev/null \
        archive \
        --format=tar \
        --output="${archive_path}" \
        "${commit}" 2>> "${error_path}"
    local archive_exit_code=$?
    set -e
    snapshot_exit_code="${archive_exit_code}"
    if ((had_attribute_file)); then
        mv -- "${attribute_backup}" "${attribute_path}"
    else
        rm -f -- "${attribute_path}"
    fi
    if ((snapshot_exit_code == 0)); then
        set +e
        tar -xf "${archive_path}" -C "${snapshot_path}" \
            2>> "${error_path}"
        snapshot_exit_code=$?
        set -e
    fi
    if ((snapshot_exit_code != 0)); then
        rm -f -- "${archive_path}"
        cat > "${report_path}" <<'EOF'
================================================================================
REPOSITORY REVIEW REPORT
Read-only source snapshot failed. See errors.txt.
================================================================================
EOF
        finalize_repository_artifacts \
            "${state_path}" "${slug}" "${repository}" "" "${commit}" \
            "SnapshotFailed" "${snapshot_exit_code}" \
            "${review_path}" "${result_path}" \
            "${report_path}" "${markdown_path}" "${html_path}" \
            "${timeline_path}" "${transcript_path}" "${request_path}" \
            "${error_path}" "${handoff_path}" "${started_at}" \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        return 1
    fi
    rm -f -- "${archive_path}"
    while IFS= read -r -d '' link_path; do
        link_target="$(readlink -- "${link_path}" || true)"
        rm -f -- "${link_path}"
        printf 'Symbolic link target (not followed): %s\n' "${link_target}" \
            > "${link_path}"
    done < <(find "${snapshot_path}" -type l -print0)
    chmod -R a-w -- "${snapshot_path}"
    review_path="${snapshot_path}"
    review_progress "${slug}" 'snapshot' 'read-only source snapshot prepared'

    while IFS= read -r template_line || [[ -n "${template_line}" ]]; do
        case "${template_line}" in
            'Repository URL: {{REPOSITORY_URL}}')
                printf 'Repository URL: %s\n' "${repository}"
                ;;
            'Read-only source snapshot: {{REPOSITORY_PATH}}')
                printf 'Read-only source snapshot: %s\n' "${review_path}"
                ;;
            'Exact commit to review: {{COMMIT}}')
                printf 'Exact commit to review: %s\n' "${commit}"
                ;;
            'Review date: {{REVIEW_DATE}}')
                printf 'Review date: %s\n' "${REVIEW_DATE}"
                ;;
            'Recent-prior-art window: {{PRIOR_ART_START_DATE}} through {{REVIEW_DATE}}')
                printf 'Recent-prior-art window: %s through %s\n' \
                    "${PRIOR_ART_START_DATE}" "${REVIEW_DATE}"
                ;;
            'Provenance lookback months: {{PROVENANCE_LOOKBACK_MONTHS}}')
                if ((ENABLE_PROVENANCE_RESEARCH)); then
                    printf 'Provenance lookback months: %s\n' \
                        "${PROVENANCE_LOOKBACK_MONTHS}"
                else
                    printf 'Provenance lookback months: disabled\n'
                fi
                ;;
            'Provenance start date: {{PROVENANCE_START_DATE}}')
                if ((ENABLE_PROVENANCE_RESEARCH)); then
                    printf 'Provenance start date: %s\n' \
                        "${PROVENANCE_START_DATE}"
                else
                    printf 'Provenance start date: disabled\n'
                fi
                ;;
            'Selected scope: {{SCOPE_NAME}}')
                printf 'Selected scope: %s\n' "${SCOPE_NAME}"
                ;;
            'Trusted wrapper artifact directory: {{OUTPUT_DIRECTORY}}')
                printf 'Trusted wrapper artifact directory: %s\n' \
                    "${result_path}"
                ;;
            '{{REPOSITORY_METADATA}}')
                printf '%s\n' "${repository_metadata}"
                ;;
            '{{PUBLIC_RESEARCH_INSTRUCTIONS}}')
                printf '%s\n' "${PUBLIC_RESEARCH_INSTRUCTIONS}"
                ;;
            '{{PROVENANCE_INSTRUCTIONS}}')
                printf '%s\n' "${PROVENANCE_INSTRUCTIONS}"
                ;;
            *)
                printf '%s\n' "${template_line}"
                ;;
        esac
    done < "${PROMPT_PATH}" > "${request_path}"

    session_id="$(new_session_id)"
    local session_prefix='review-'
    local session_suffix="-${RUN_ID}"
    local maximum_slug_length=$((96 - ${#session_prefix} - ${#session_suffix}))
    local session_slug="${slug:0:maximum_slug_length}"
    session_name="${session_prefix}${session_slug}${session_suffix}"

    local available_tools
    available_tools='view,glob,rg,skill,task,list_agents,read_agent'
    if ((ENABLE_PUBLIC_RESEARCH)); then
        available_tools+=',web_fetch'
    fi

    local -a copilot_arguments=(
        -C "${session_root}"
        --plugin-dir "${PLUGIN_ROOT}"
        --name "${session_name}"
        --session-id "${session_id}"
        --agent rhyolite:repo-review-worker
        --model "${MODEL}"
        --context long_context
        --no-ask-user
        --no-color
        --no-custom-instructions
        --disable-builtin-mcps
        --disallow-temp-dir
        --no-remote-export
        --secret-env-vars "$(IFS=,; printf '%s' "${authentication_variables[*]}")"
        --available-tools "${available_tools}"
        --allow-tool read
        --deny-tool write
        --deny-tool shell
        --stream off
        --share "${transcript_path}"
        --silent
    )
    if ((ENABLE_PUBLIC_RESEARCH)); then
        copilot_arguments+=(--allow-all-urls)
    fi

    runtime_copilot_home="$(
        mktemp -d "${TMPDIR:-/tmp}/rhyolite-repo-review-copilot.XXXXXXXX"
    )"
    chmod 700 -- "${runtime_copilot_home}"
    REPO_REVIEWER_RUNTIME_HOME_TO_CLEAN="${runtime_copilot_home}"
    trap '
        if [[ -n "${REPO_REVIEWER_RUNTIME_HOME_TO_CLEAN-}" ]]; then
            sanitize_and_remove_runtime_copilot_home \
                "${REPO_REVIEWER_RUNTIME_HOME_TO_CLEAN}" \
                >/dev/null 2>&1 || true
        fi
    ' EXIT
    if ((COPILOT_AUTH_BRIDGE_HAS_PLAINTEXT)); then
        cat > "${runtime_copilot_home}/settings.json" <<'EOF'
{
  "storeTokenPlaintext": true,
  "disableAllHooks": true,
  "customAgents": {
    "defaultLocalOnly": true
  }
}
EOF
    else
        cat > "${runtime_copilot_home}/settings.json" <<'EOF'
{
  "disableAllHooks": true,
  "customAgents": {
    "defaultLocalOnly": true
  }
}
EOF
    fi
    {
        printf '%s\n' \
            '// User settings belong in settings.json.' \
            '// This file is managed automatically.'
        printf '%s\n' "${COPILOT_AUTH_BRIDGE_JSON}"
    } > "${runtime_copilot_home}/config.json"
    chmod 600 -- \
        "${runtime_copilot_home}/settings.json" \
        "${runtime_copilot_home}/config.json"

    review_progress \
        "${slug}" \
        'analysis' \
        "${MODEL} review started; scope ${SCOPE}"
    set +e
    timeout \
        --signal=TERM \
        --kill-after=30s \
        "${SESSION_TIMEOUT_MINUTES}m" \
        env \
        -u COPILOT_ALLOW_ALL \
        -u COPILOT_SKILLS_DIRS \
        -u COPILOT_CUSTOM_INSTRUCTIONS_DIRS \
        -u COPILOT_DYNAMIC_RETRIEVAL_SKILLS \
        -u COPILOT_EMBEDDING_ONLY_SKILLS \
        COPILOT_HOME="${runtime_copilot_home}" \
        copilot "${copilot_arguments[@]}" \
        < "${request_path}" \
        > "${raw_output}" \
        2> "${error_path}" &
    local review_process_id=$!
    local analysis_started_epoch
    analysis_started_epoch="$(date +%s)"
    while kill -0 "${review_process_id}" 2>/dev/null; do
        sleep 30
        if kill -0 "${review_process_id}" 2>/dev/null; then
            local elapsed_seconds=$(( $(date +%s) - analysis_started_epoch ))
            review_progress \
                "${slug}" \
                'analysis' \
                "still running; elapsed $((elapsed_seconds / 60))m $((elapsed_seconds % 60))s"
        fi
    done
    wait "${review_process_id}"
    exit_code=$?
    set -e

    mkdir -p -- "${copilot_home_path}"
    chmod 700 -- "${copilot_home_path}"
    cat > "${copilot_home_path}/settings.json" <<'EOF'
{
  "disableAllHooks": true,
  "customAgents": {
    "defaultLocalOnly": true
  }
}
EOF
    cat > "${copilot_home_path}/config.json" <<'EOF'
// User settings belong in settings.json.
// This file is managed automatically.
{}
EOF
    chmod 600 -- \
        "${copilot_home_path}/settings.json" \
        "${copilot_home_path}/config.json"
    local state_entry source_entry destination_entry state_file
    local relative_state_file destination_state_file
    for state_entry in session-state session-store; do
        source_entry="${runtime_copilot_home}/${state_entry}"
        [[ -d "${source_entry}" ]] || continue
        destination_entry="${copilot_home_path}/${state_entry}"
        mkdir -p -- "${destination_entry}"
        while IFS= read -r -d '' state_file; do
            relative_state_file="${state_file#"${source_entry}/"}"
            destination_state_file="${destination_entry}/${relative_state_file}"
            mkdir -p -- "$(dirname -- "${destination_state_file}")"
            cp -- "${state_file}" "${destination_state_file}"
        done < <(find "${source_entry}" -type f -print0)
    done
    find "${copilot_home_path}" -type d -exec chmod 700 -- {} +
    find "${copilot_home_path}" -type f -exec chmod 600 -- {} +
    if sanitize_and_remove_runtime_copilot_home "${runtime_copilot_home}"; then
        runtime_copilot_home=""
        REPO_REVIEWER_RUNTIME_HOME_TO_CLEAN=""
        trap - EXIT
    else
        printf '%s\n' \
            "Could not remove the temporary Copilot runtime home after three attempts: ${runtime_copilot_home}" \
            >> "${error_path}"
        post_process_failure=1
    fi

    tr -d '\r' < "${raw_output}" |
        strip_terminal_controls |
        redact_credentials |
        redact_emails > "${timeline_path}"
    rm -f -- "${raw_output}"
    if [[ -s "${error_path}" ]]; then
        tr -d '\r' < "${error_path}" |
            strip_terminal_controls |
            redact_credentials |
            redact_emails > "${error_path}.tmp"
        mv -- "${error_path}.tmp" "${error_path}"
    fi

    if ((exit_code == 0)); then
        review_progress "${slug}" 'analysis' 'agent response received'
        if extract_report "${timeline_path}" "${report_path}"; then
            if ! awk '
                NF { line = $0 }
                END {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
                    exit(line ~ /^=+$/ && length(line) >= 80 ? 0 : 1)
                }
            ' "${report_path}"; then
                printf '%s\n' \
                    'Incomplete report: final closing delimiter was missing; recovered text was saved through end of agent output.' \
                    >> "${error_path}"
                exit_code=1
            fi
            if grep -Eq '^[[:space:]]*\|.*\|[[:space:]]*$' "${report_path}"; then
                printf '%s\n' \
                    'Final report contains a Markdown table.' >> "${error_path}"
                exit_code=1
            fi
        else
            printf '%s\n' \
                'Final report extraction failed. See analysis-timeline.txt.' \
                > "${report_path}"
            printf '%s\n' \
                'Final report header or end marker was not found.' \
                >> "${error_path}"
            exit_code=1
        fi
    elif ((exit_code == 124)); then
        printf '%s\n' \
            'Repository review timed out. See analysis-timeline.txt.' \
            > "${report_path}"
        printf 'Session exceeded %s minutes.\n' \
            "${SESSION_TIMEOUT_MINUTES}" >> "${error_path}"
    else
        printf '%s\n' \
            'Repository review failed. See errors.txt and analysis-timeline.txt.' \
            > "${report_path}"
    fi
    if ((post_process_failure)); then
        exit_code=1
    fi

    local checkout_changed=0
    if [[ -n "$(
        git -C "${clone_path}" status \
            --porcelain --untracked-files=all 2>> "${error_path}"
    )" ]]; then
        checkout_changed=1
    fi
    if [[ "$(
        git -C "${clone_path}" rev-parse HEAD 2>> "${error_path}"
    )" != "${commit}" ]]; then
        checkout_changed=1
    fi
    if ! git -C "${clone_path}" diff --quiet --no-ext-diff ||
        ! git -C "${clone_path}" diff --cached --quiet --no-ext-diff; then
        checkout_changed=1
    fi
    if ((checkout_changed)); then
        printf '%s\n' \
            'Policy violation: reviewed checkout is not clean.' >> "${error_path}"
        exit_code=1
    fi

    if [[ -f "${transcript_path}" ]]; then
        tr -d '\r' < "${transcript_path}" |
            strip_terminal_controls |
            redact_credentials |
            redact_emails > "${transcript_path}.plain"
        write_safe_markdown_document \
            'Copilot Session Transcript' \
            "${transcript_path}.plain" \
            "${transcript_path}.tmp"
        mv -- "${transcript_path}.tmp" "${transcript_path}"
        rm -f -- "${transcript_path}.plain"
    fi

    if ((exit_code == 0)); then
        status="Completed"
    elif ((exit_code == 124)); then
        status="TimedOut"
    else
        status="ReviewFailed"
    fi

    finalize_repository_artifacts \
        "${state_path}" "${slug}" "${repository}" "${session_name}" \
        "${commit}" "${status}" "${exit_code}" "${review_path}" \
        "${result_path}" "${report_path}" "${markdown_path}" "${html_path}" \
        "${timeline_path}" "${transcript_path}" "${request_path}" \
        "${error_path}" "${handoff_path}" "${started_at}" \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    review_progress "${slug}" 'artifacts' "${status}; ${result_path}"

    ((exit_code == 0))
}

declare -a preflight_passed=()
declare -a preflight_failure_summaries=()
declare -a preflight_error_details=()
declare -a preflight_exit_codes=()
declare -a preflight_started_ats=()
pids=()
failure=0
preflight_failed=0

review_progress \
    'run' \
    'preflight' \
    'verifying anonymous public access before clone or worker start'

for index in "${!canonical_urls[@]}"; do
    preflight_started_ats[index]="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    if preflight_repository_access \
        "${canonical_urls[index]}" \
        "${slugs[index]}" \
        "${requested_commits[index]}" \
        "${source_kinds[index]}" \
        "${source_paths[index]}" \
        "${curl_resolves[index]}"; then
        preflight_passed[index]=1
        preflight_failure_summaries[index]=''
        preflight_error_details[index]=''
        preflight_exit_codes[index]=0
    else
        preflight_passed[index]=0
        preflight_failure_summaries[index]="${PREFLIGHT_FAILURE_SUMMARY}"
        preflight_error_details[index]="${PREFLIGHT_ERROR_DETAILS}"
        preflight_exit_codes[index]="${PREFLIGHT_EXIT_CODE}"
        preflight_failed=1
    fi
done

if ((preflight_failed)); then
    failing_repositories_text='Failing repositories:'
    for index in "${!canonical_urls[@]}"; do
        if ((preflight_passed[index] == 0)); then
            failing_repositories_text+=$'\n'"- ${canonical_urls[index]}"
        fi
    done

    review_progress \
        'run' \
        'preflight' \
        'approved plan failed closed; no clones or workers started'

    for index in "${!canonical_urls[@]}"; do
        if ((preflight_passed[index] == 0)); then
            write_repository_failure_result \
                "${slugs[index]}" \
                "${canonical_urls[index]}" \
                "${requested_commits[index]}" \
                "${source_kinds[index]}" \
                "${source_paths[index]}" \
                'AccessPreflightFailed' \
                "${preflight_failure_summaries[index]}" \
                "${preflight_error_details[index]}" \
                "${preflight_started_ats[index]}" \
                "${preflight_exit_codes[index]}"
        else
            write_repository_failure_result \
                "${slugs[index]}" \
                "${canonical_urls[index]}" \
                "${requested_commits[index]}" \
                "${source_kinds[index]}" \
                "${source_paths[index]}" \
                'PreflightBlocked' \
                'Repository review did not start because another selected repository failed anonymous repository accessibility preflight. Rhyolite currently supports only publicly accessible repositories and does not attempt authentication. See errors.txt.' \
                "$(cat <<EOF
Repository review did not start because another selected repository failed anonymous repository accessibility preflight.
Rhyolite currently supports only publicly accessible repositories and does not attempt authentication.
Fail-closed policy: one inaccessible or anonymously unreadable source stops the whole approved plan before clone or worker start.
${failing_repositories_text}
EOF
)" \
                "${preflight_started_ats[index]}" \
                1
        fi
    done
    failure=1
else
    review_progress \
        'run' \
        'preflight' \
        'all selected repositories anonymously accessible'

    for index in "${!canonical_urls[@]}"; do
        process_repository \
            "${canonical_urls[index]}" \
            "${slugs[index]}" \
            "${requested_commits[index]}" \
            "${source_kinds[index]}" \
            "${source_paths[index]}" \
            "${curl_resolves[index]}" &
        pids+=("$!")

        if ((${#pids[@]} >= THROTTLE_LIMIT)); then
            if ! wait "${pids[0]}"; then
                failure=1
            fi
            pids=("${pids[@]:1}")
        fi
    done

    for pid in "${pids[@]}"; do
        if ! wait "${pid}"; then
            failure=1
        fi
    done
fi

review_progress \
    'run' \
    'finalizing' \
    'building manifest, state, handoff, and HTML index'

shopt -s nullglob
result_files=("${RUN_RESULTS}"/*/state.json)
read_result_summary() {
    local summary_path="$1"
    exec 9< "${summary_path}"
    IFS= read -r -d '' repository <&9
    IFS= read -r -d '' source_kind <&9
    IFS= read -r -d '' source_path <&9
    IFS= read -r -d '' requested_commit <&9
    IFS= read -r -d '' commit <&9
    IFS= read -r -d '' status <&9
    IFS= read -r -d '' state <&9
    IFS= read -r -d '' handoff <&9
    IFS= read -r -d '' html <&9
    exec 9<&-
}
MANIFEST_PATH="${RUN_RESULTS}/manifest.json"
{
    printf '[\n'
    for index in "${!result_files[@]}"; do
        cat "${result_files[index]}"
        if ((index + 1 < ${#result_files[@]})); then
            printf ',\n'
        else
            printf '\n'
        fi
    done
    printf ']\n'
} > "${MANIFEST_PATH}"

for result_file in "${result_files[@]}"; do
    summary_file="${result_file%/state.json}/.result-summary"
    read_result_summary "${summary_file}"
    printf '%-70s %s\n' "${repository}" "${status}"
done

RUN_COMPLETED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if ((failure == 0)); then
    RUN_STATUS='Completed'
elif grep -q '"Status": "Completed"' "${result_files[@]}"; then
    RUN_STATUS='Partial'
else
    RUN_STATUS='Failed'
fi

RUN_STATE_PATH="${RUN_RESULTS}/state.json"
RUN_HANDOFF_PATH="${RUN_RESULTS}/handoff.md"
INDEX_PATH="${RUN_RESULTS}/index.html"

{
    cat <<EOF
{
  "SchemaVersion": ${STATE_SCHEMA_VERSION},
  "RunId": "$(json_escape "${RUN_ID}")",
  "Status": "$(json_escape "${RUN_STATUS}")",
  "StartedAt": "$(json_escape "${RUN_STARTED_AT}")",
  "CompletedAt": "$(json_escape "${RUN_COMPLETED_AT}")",
  "Scope": {
    "Name": "$(json_escape "${SCOPE_NAME}")",
    "PlanningEstimate": "$(json_escape "${SCOPE_ESTIMATE}")",
    "PublicResearch": $([[ ${ENABLE_PUBLIC_RESEARCH} -eq 1 ]] && printf true || printf false),
    "ProvenanceResearch": $([[ ${ENABLE_PROVENANCE_RESEARCH} -eq 1 ]] && printf true || printf false)
  },
  "ProvenanceWindow": $(provenance_window_json '  '),
  "Paths": {
    "ReadOnlyWorkspace": "$(json_escape "${RUN_WORKSPACE}")",
    "WritableOutput": "$(json_escape "${RUN_RESULTS}")"
  },
  "Artifacts": {
    "ReviewPlanJson": "$(json_escape "${REVIEW_PLAN_JSON_PATH}")",
    "ReviewPlanText": "$(json_escape "${REVIEW_PLAN_TEXT_PATH}")",
    "Manifest": "$(json_escape "${MANIFEST_PATH}")",
    "Handoff": "$(json_escape "${RUN_HANDOFF_PATH}")",
    "HtmlIndex": "$(json_escape "${INDEX_PATH}")"
  },
  "Repositories": [
EOF
    for index in "${!result_files[@]}"; do
        summary_file="${result_files[index]%/state.json}/.result-summary"
        read_result_summary "${summary_file}"
        cat <<EOF
    {
      "Repository": "$(json_escape "${repository}")",
      "Source": {
        "Kind": "$(json_escape "${source_kind}")",
        "LocalPath": "$(json_escape "${source_path}")",
        "RemoteUrl": "$(json_escape "${repository}")"
      },
      "RequestedCommit": "$(json_escape "${requested_commit}")",
      "Commit": "$(json_escape "${commit}")",
      "Status": "$(json_escape "${status}")",
      "ProvenanceWindow": $(provenance_window_json '      '),
      "State": "$(json_escape "${state}")",
      "Handoff": "$(json_escape "${handoff}")",
      "Html": "$(json_escape "${html}")"
    }
EOF
        if ((index + 1 < ${#result_files[@]})); then
            printf ','
        fi
        printf '\n'
    done
    printf '  ]\n}\n'
} > "${RUN_STATE_PATH}"

{
    provenance_window="$(provenance_window_text)"
    printf '# Repository review run handoff\n\n'
    printf 'Run ID:\n\n    %s\n\n' "${RUN_ID}"
    printf 'Status:\n\n    %s\n\n' "${RUN_STATUS}"
    printf 'Scope:\n\n    %s\n\n' "${SCOPE_NAME}"
    printf 'Planning estimate:\n\n    %s\n\n' "${SCOPE_ESTIMATE}"
    printf 'Provenance window:\n\n'
    while IFS= read -r line || [[ -n "${line}" ]]; do
        printf '    %s\n' "${line}"
    done <<< "${provenance_window}"
    printf '\n'
    printf 'Read-only workspace:\n\n    %s\n\n' "${RUN_WORKSPACE}"
    printf 'Writable output:\n\n    %s\n\n' "${RUN_RESULTS}"
    printf '## Continue safely\n\n'
    printf '%s\n\n' \
        'Open each repository handoff for its saved session identifiers and state. Do not invoke `copilot --resume` directly; continue through the trusted Rhyolite `repo-review` runner so all restrictions are re-established.'
    printf '## Repository sessions\n\n'
    for result_file in "${result_files[@]}"; do
        summary_file="${result_file%/state.json}/.result-summary"
        read_result_summary "${summary_file}"
        printf 'Repository:\n\n    %s\n\n' "${repository}"
        printf 'Source kind:\n\n    %s\n\n' "${source_kind}"
        printf 'Selected source path:\n\n    %s\n\n' "${source_path}"
        printf 'Status:\n\n    %s\n\n' "${status}"
        printf 'Handoff:\n\n    %s\n\n' "${handoff}"
    done
    printf '\n## Run artifacts\n\n'
    printf 'Review plan JSON:\n\n    %s\n\n' "${REVIEW_PLAN_JSON_PATH}"
    printf 'Review plan text:\n\n    %s\n\n' "${REVIEW_PLAN_TEXT_PATH}"
    printf 'Manifest:\n\n    %s\n\n' "${MANIFEST_PATH}"
    printf 'State:\n\n    %s\n\n' "${RUN_STATE_PATH}"
    printf 'HTML index:\n\n    %s\n' "${INDEX_PATH}"
} > "${RUN_HANDOFF_PATH}"

{
    cat <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>Repository Review Run</title>
<style>
:root { color-scheme: light dark; }
body { margin: 0; font-family: system-ui, sans-serif; line-height: 1.45; }
main { max-width: 1200px; margin: 0 auto; padding: 2rem; }
table { width: 100%; border-collapse: collapse; }
th, td { padding: .6rem; border: 1px solid currentColor; text-align: left; vertical-align: top; }
a { color: inherit; }
code { overflow-wrap: anywhere; }
</style>
</head>
<body>
<main>
<h1>Repository Review Run</h1>
EOF
    printf '<p>Run <code>%s</code>; status <strong>%s</strong>; scope <strong>%s</strong>; public research <strong>%s</strong>; provenance <strong>%s</strong>.</p>\n' \
        "$(html_escape_value "${RUN_ID}")" \
        "$(html_escape_value "${RUN_STATUS}")" \
        "$(html_escape_value "${SCOPE_NAME}")" \
        "$(html_escape_value "$(status_word "${ENABLE_PUBLIC_RESEARCH}")")" \
        "$(html_escape_value "$(status_word "${ENABLE_PROVENANCE_RESEARCH}")")"
    printf '<p><a href="review-plan.txt">Review plan (text)</a> · <a href="review-plan.json">Review plan (JSON)</a> · <a href="handoff.md">Run handoff</a> · <a href="state.json">Run state</a> · <a href="manifest.json">Manifest</a></p>\n'
    printf '<table><thead><tr><th>Repository</th><th>Source</th><th>Status</th><th>Commit</th><th>Artifacts</th></tr></thead><tbody>\n'
    for result_file in "${result_files[@]}"; do
        summary_file="${result_file%/state.json}/.result-summary"
        read_result_summary "${summary_file}"
        slug="$(basename -- "$(dirname -- "${result_file}")")"
        printf '<tr><td>%s</td><td>%s</td><td>%s</td><td><code>%s</code></td>' \
            "$(html_escape_value "${repository}")" \
            "$(html_escape_value "${source_kind}")" \
            "$(html_escape_value "${status}")" \
            "$(html_escape_value "${commit}")"
        printf '<td><a href="%s/review.html">HTML</a> ' "${slug}"
        printf '<a href="%s/review.md">Markdown</a> ' "${slug}"
        printf '<a href="%s/review.txt">Plain text</a> ' "${slug}"
        printf '<a href="%s/handoff.md">Handoff</a></td></tr>\n' "${slug}"
    done
    printf '</tbody></table>\n</main>\n</body>\n</html>\n'
} > "${INDEX_PATH}"

for result_file in "${result_files[@]}"; do
    rm -f -- "${result_file%/state.json}/.result-summary"
done

printf '\nRun workspace: %s\n' "${RUN_WORKSPACE}"
printf 'Run output:    %s\n' "${RUN_RESULTS}"
printf 'Review plan JSON: %s\n' "${REVIEW_PLAN_JSON_PATH}"
printf 'Review plan text: %s\n' "${REVIEW_PLAN_TEXT_PATH}"
printf 'Manifest:      %s\n' "${MANIFEST_PATH}"
printf 'State:         %s\n' "${RUN_STATE_PATH}"
printf 'Handoff:       %s\n' "${RUN_HANDOFF_PATH}"
printf 'HTML index:    %s\n' "${INDEX_PATH}"
review_progress 'run' 'completed' "${RUN_STATUS}; ${RUN_RESULTS}"

if ((failure)); then
    for result_file in "${result_files[@]}"; do
        if ! grep -q '"Status": "Completed"' "${result_file}"; then
            print_repository_error "${result_file}"
        fi
    done
fi

allow_all="${COPILOT_ALLOW_ALL:-false}"
allow_all="${allow_all,,}"
should_open=0
if ((OPEN_HTML)); then
    should_open=1
elif ((!NO_OPEN_HTML)) &&
    [[ "${allow_all}" == "true" || "${allow_all}" == "1" ||
        "${allow_all}" == "yes" ]]; then
    should_open=1
elif ((!NO_OPEN_HTML)) && is_interactive_console; then
    read -r -p 'Open the local HTML report index now? [y/N]: ' open_input
    open_input="${open_input,,}"
    if [[ "${open_input}" == "y" || "${open_input}" == "yes" ]]; then
        should_open=1
    fi
fi

if ((should_open)); then
    if command -v xdg-open >/dev/null 2>&1; then
        nohup xdg-open -- "${INDEX_PATH}" >/dev/null 2>&1 &
    elif command -v open >/dev/null 2>&1; then
        nohup open -- "${INDEX_PATH}" >/dev/null 2>&1 &
    else
        printf 'No supported browser opener was found; open %s manually.\n' \
            "${INDEX_PATH}" >&2
    fi
fi

exit "${failure}"
