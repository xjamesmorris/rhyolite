#!/usr/bin/env bash

set -euo pipefail

original_arguments=("$@")
fixture_contract=''
session_name=''
session_id=''
model=''
reasoning_effort=''
context_tier=''
transcript_path=''

while (($# > 0)); do
    case "$1" in
        --fixture-contract)
            fixture_contract="${2-}"
            shift 2
            ;;
        --session-name)
            session_name="${2-}"
            shift 2
            ;;
        --session-id)
            session_id="${2-}"
            shift 2
            ;;
        --model)
            model="${2-}"
            shift 2
            ;;
        --reasoning-effort)
            reasoning_effort="${2-}"
            shift 2
            ;;
        --context)
            context_tier="${2-}"
            shift 2
            ;;
        --transcript)
            transcript_path="${2-}"
            shift 2
            ;;
        *)
            printf 'Unexpected no-op fixture argument: %s\n' "$1" >&2
            exit 64
            ;;
    esac
done

[[ "${fixture_contract}" == 2 ]]
[[ -n "${session_name}" && -n "${session_id}" ]]
[[ "${model}" == 'noop-fixture-model' ]]
[[ "${reasoning_effort}" == 'max' ]]
[[ "${context_tier}" == 'long_context' ]]
[[ -n "${transcript_path}" ]]
[[ -n "${NOOP_RUNTIME_HOME:-}" ]]
[[ -f "${NOOP_RUNTIME_HOME}/fixture-runtime.json" ]]
[[ "$(stat -c '%a' "${NOOP_RUNTIME_HOME}")" == 700 ]]
[[ "$(stat -c '%a' "${NOOP_RUNTIME_HOME}/fixture-runtime.json")" == 600 ]]

cat >/dev/null

mkdir -m 700 -- \
    "${NOOP_RUNTIME_HOME}/session-state" \
    "${NOOP_RUNTIME_HOME}/session-state/ephemeral"
printf '%s\n' '{"Persist":false,"Purpose":"cleanup-proof"}' \
    > "${NOOP_RUNTIME_HOME}/session-state/ephemeral/state.json"
chmod 600 -- \
    "${NOOP_RUNTIME_HOME}/session-state/ephemeral/state.json"

if [[ -n "${NOOP_CAPTURE_ROOT:-}" ]]; then
    mkdir -p -- "${NOOP_CAPTURE_ROOT}"
    printf '%s\0' "${original_arguments[@]}" \
        > "${NOOP_CAPTURE_ROOT}/argv"
    env | LC_ALL=C sort > "${NOOP_CAPTURE_ROOT}/environment.txt"
    pwd > "${NOOP_CAPTURE_ROOT}/cwd.txt"
    printf '%s\n' "${NOOP_RUNTIME_HOME}" \
        > "${NOOP_CAPTURE_ROOT}/runtime-home.txt"
    find "${NOOP_RUNTIME_HOME}" \
        -printf '%P\t%m\t%y\n' |
        LC_ALL=C sort > "${NOOP_CAPTURE_ROOT}/runtime-inventory.txt"
    printf '%s\n' 'started' > "${NOOP_CAPTURE_ROOT}/started"
fi

cat > "${transcript_path}" <<'EOF'
# Development-only no-op harness transcript

### NOOP FIXTURE FINAL RESPONSE

================================================================================
REPOSITORY REVIEW REPORT
REVIEW CONTEXT
DEVELOPMENT-ONLY NO-OP HARNESS DIAGNOSTIC.
Repository analysis performed: No.
Repository contents inspected: No.
Credentials requested or consumed: No.
This fixture ignored all repository inputs and produced fixed contract evidence.

EXECUTIVE SUMMARY
This is not a real repository review. The development-only no-op harness
completed a deterministic orchestration diagnostic and intentionally made no
claims about the selected repository.

FINDINGS
No repository findings were produced. Any interpretation of this report as
source analysis is invalid because the fixture did not inspect repository
contents.

AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT
Prompt injection and reviewer-directed instructions: Not assessed; repository content was not inspected.
Source/docs/commit/ref metadata poisoning and dataset/benchmark poisoning: Not assessed; repository content was not inspected.
Encoded/invisible instructions and tool-call bait: Not assessed; repository content was not inspected.
Recursive/resource-exhaustion tarpits: Not assessed; repository content was not inspected.
Tracking pixels/callback beacons/trackers/sensors: Not assessed; repository content was not inspected.
Limitations of available evidence: All repository evidence was intentionally ignored.
Confidence: High.
Evidence basis: The deterministic fixture worker receives no repository locator and emits this fixed diagnostic report.

AREAS REVIEWED WITHOUT QUALIFYING FINDINGS
None. The no-op fixture intentionally reviewed no repository areas.

PRIORITIZED REMEDIATION
Do not use this fixture as a review backend and do not treat this diagnostic as
evidence about a repository.

OVERALL ASSESSMENT
Development-only contract proof completed. Real repository assessment was not
performed.
================================================================================

### END NOOP FIXTURE FINAL RESPONSE
EOF

printf '%s\n' \
    'NOOP FIXTURE: repository analysis intentionally skipped.'
