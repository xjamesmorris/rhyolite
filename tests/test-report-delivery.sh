#!/usr/bin/env bash

# Unit regressions for collect-mode report validation and the paged report
# delivery protocol (RHYOLITE_REPORT_DELIVERY_V1) that lets the trusted runner
# ask a review worker to resend only missing, truncated, or invalid sections,
# plus the deterministic failure analysis of a failed delivery.

set -euo pipefail
umask 077

export LC_ALL=C.utf8

ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_HELPER="${ROOT}/plugins/rhyolite/skills/readonly-repository-review/scripts/review-output.sh"
FIXTURE_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf -- "${FIXTURE_ROOT}"
}
trap cleanup EXIT

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local file="$1"
    local expected="$2"
    local description="$3"

    grep -Fq -- "${expected}" "${file}" ||
        fail "${description}: missing ${expected}"
}

assert_not_contains() {
    local file="$1"
    local unexpected="$2"
    local description="$3"

    if grep -Fq -- "${unexpected}" "${file}"; then
        fail "${description}: unexpectedly contained ${unexpected}"
    fi
}

expect_exit() {
    local expected="$1"
    local description="$2"
    shift 2
    local status=0

    "$@" > "${FIXTURE_ROOT}/last.stdout" 2> "${FIXTURE_ROOT}/last.stderr" ||
        status=$?
    [[ "${status}" -eq "${expected}" ]] ||
        fail "${description}: expected exit ${expected}, got ${status}: $(cat -- "${FIXTURE_ROOT}/last.stderr" "${FIXTURE_ROOT}/last.stdout")"
}

# shellcheck source=../plugins/rhyolite/skills/readonly-repository-review/scripts/review-output.sh
source "${OUTPUT_HELPER}"
RUNNER="${ROOT}/plugins/rhyolite/skills/readonly-repository-review/scripts/run-parallel-reviews.sh"
# Load the runner's exact strict finalization gate rather than a copy.
eval "$(grep -E '^REPORT_MARKDOWN_TABLE_DIAGNOSTIC=' "${RUNNER}")"
eval "$(awk '/^validate_final_review_report\(\) \{$/,/^}$/' "${RUNNER}")"
declare -F validate_final_review_report > /dev/null ||
    fail 'could not load the runner strict finalization gate'

DELIMITER='================================================================================'

write_section() {
    local section="$1"

    printf '%s\n' "${section}"
    case "${section}" in
        'AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT')
            cat <<'EOF'
Prompt injection and reviewer-directed instructions: No supporting evidence.
Source/docs/commit/ref metadata poisoning and dataset/benchmark poisoning:
No supporting evidence.
Encoded/invisible instructions and tool-call bait: No supporting evidence.
Recursive/resource-exhaustion tarpits: No supporting evidence.
Tracking pixels/callback beacons/trackers/sensors: No supporting evidence.
Limitations of available evidence: Synthetic delivery fixture only.
Confidence: Medium
Evidence basis: Synthetic manipulation evidence.
EOF
            ;;
        'CLAIMS AND REPUTATION INTEGRITY ASSESSMENT')
            cat <<'EOF'
Capability, maturity, and security claims versus implementation: None.
Roadmap and delivery commitments: None.
Conference, CFP, proposal, and paper submission indicators: None identified.
Media coverage, endorsement, award, and affiliation claims: None identified.
Adoption, popularity, and engagement authenticity: No adoption claim.
Reputation-building pattern indicators: No supporting evidence.
Supply-chain precursor indicators: No supporting evidence.
Limitations of available evidence: Synthetic claims fixture only.
Confidence: Medium
Evidence basis: Synthetic claims evidence.
EOF
            ;;
        'COMMUNITY HEALTH ASSESSMENT')
            cat <<'EOF'
Contributor and maintainer base: One synthetic author.
Activity and maintenance cadence: One synthetic commit.
Issue, pull request, and review practices: Not observable.
Governance, security policy, and release practices: None identified.
Independent adoption and engagement: No supporting evidence.
Limitations of available evidence: Synthetic community fixture only.
Confidence: Low
Evidence basis: Synthetic community evidence.
EOF
            ;;
        'PRIOR ART AND ORIGINALITY ASSESSMENT')
            cat <<'EOF'
Closest prior art and ecosystem: Synthetic established ecosystem.
Novelty and differentiation: No novelty claim.
Repackaging indicators: No supporting evidence.
Citation and attribution integrity: No citation present.
Limitations of available evidence: Synthetic prior-art fixture only.
Confidence: Medium
Evidence basis: Synthetic prior-art evidence.
EOF
            ;;
        'CODE AND ARCHITECTURE PROVENANCE ASSESSMENT')
            cat <<'EOF'
Code lineage and reuse: No upstream source identified.
Architecture lineage: Conventional synthetic layout.
License and attribution consistency: No inconsistency identified.
Chronology and submission timeline: One synthetic commit.
Coverage/window: Synthetic window only.
Alternative explanations: Synthetic lineage fixture only.
Confidence: Low
Evidence basis: Synthetic lineage evidence.
EOF
            ;;
        'GENERATED-CODE PROVENANCE ASSESSMENT')
            cat <<'EOF'
Generation assessment: Indeterminate
Direct model attribution: No direct attribution
Heuristic model candidates (not attribution): No candidate identified
Heuristic model confidence: Not applicable
Direct effort attribution: No direct attribution
Direct harness attribution: No direct attribution
Coverage/window: Synthetic window only.
Alternative explanations: No directly bound generation evidence.
Confidence: Low
Evidence basis: Synthetic provenance evidence.
EOF
            ;;
        'FINDINGS')
            printf '%s\n' \
                '1. Synthetic finding with path:line evidence (src/a.c:10).' \
                '   Severity: Medium. Confidence: High - direct evidence.'
            ;;
        *)
            printf 'Synthetic %s content.\n' "${section,,}"
            ;;
    esac
}

scope_sections() {
    local scope="$1"

    printf '%s\n' \
        'REVIEW CONTEXT' \
        'EXECUTIVE SUMMARY' \
        'FINDINGS' \
        'AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT' \
        'CLAIMS AND REPUTATION INTEGRITY ASSESSMENT' \
        'COMMUNITY HEALTH ASSESSMENT'
    if ((scope >= 2)); then
        printf '%s\n' \
            'RESEARCH SOURCE LANDSCAPE' \
            'INACCESSIBLE RESOURCE REGISTER' \
            'TOP USER RETRIEVAL PRIORITIES' \
            'RESEARCH TRANSPORT OBSERVATIONS' \
            'PRIOR ART AND ORIGINALITY ASSESSMENT'
    fi
    if ((scope == 3)); then
        printf '%s\n' \
            'CODE AND ARCHITECTURE PROVENANCE ASSESSMENT' \
            'GENERATED-CODE PROVENANCE ASSESSMENT'
    fi
    printf '%s\n' \
        'AREAS REVIEWED WITHOUT QUALIFYING FINDINGS' \
        'PRIORITIZED REMEDIATION' \
        'OVERALL ASSESSMENT'
}

write_valid_report() {
    local path="$1"
    local scope="$2"
    local section

    {
        printf '%s\n%s\n' "${DELIMITER}" 'REPOSITORY REVIEW REPORT'
        while IFS= read -r section; do
            printf '\n'
            write_section "${section}"
        done < <(scope_sections "${scope}")
        printf '\n%s\n' "${DELIMITER}"
    } > "${path}"
}

# Print a page reply for a request id and sections from a source report.
write_page_reply() {
    local path="$1"
    local page_id="$2"
    local terminal="$3"
    shift 3
    local section

    {
        printf 'Narration before the page is ignored.\n'
        printf 'RHYOLITE REPORT PAGE %s BEGIN\n' "${page_id}"
        for section in "$@"; do
            write_section "${section}"
            printf '\n'
        done
        printf 'RHYOLITE REPORT PAGE %s %s\n' "${page_id}" "${terminal}"
    } > "${path}"
}

request_id() {
    sed -n 's/^Request: \(R[0-9]*P[0-9]*\.[0-9]*\).*$/\1/p' "$1"
}

new_workdir() {
    local workdir
    workdir="$(mktemp -d "${FIXTURE_ROOT}/delivery.XXXXXX")"
    chmod 700 -- "${workdir}"
    printf '%s\n' "${workdir}"
}

# ---------------------------------------------------------------------------
# 1. Strict validation keeps its first-error behavior; collect mode reports
#    every attributable violation with its section.
# ---------------------------------------------------------------------------
for scope in 1 2 3; do
    write_valid_report "${FIXTURE_ROOT}/valid-${scope}.txt" "${scope}"
    validate_review_report_contract "${FIXTURE_ROOT}/valid-${scope}.txt" "${scope}" ||
        fail "scope ${scope} synthetic report failed strict validation"
    validate_final_review_report_collect_fixture="$(
        validate_review_report_contract \
            "${FIXTURE_ROOT}/valid-${scope}.txt" "${scope}" collect
    )"
    [[ "${validate_final_review_report_collect_fixture}" == '{"errors": []}' ]] ||
        fail "scope ${scope} collect mode reported errors for a valid report"
done

expect_exit 2 'unsupported validation mode is rejected' \
    validate_review_report_contract "${FIXTURE_ROOT}/valid-1.txt" 1 lenient

multi_invalid="${FIXTURE_ROOT}/multi-invalid.txt"
python3 - "${FIXTURE_ROOT}/valid-3.txt" "${multi_invalid}" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
text = text.replace(
    "Roadmap and delivery commitments: None.\n", "", 1
).replace(
    "Confidence: Medium\nEvidence basis: Synthetic claims evidence.",
    "Confidence: High for counts and Medium for interpretation.\n"
    "Evidence basis: Synthetic claims evidence.",
    1,
).replace(
    "1. Synthetic finding",
    "| Severity | Finding |\n| --- | --- |\n1. Synthetic finding",
    1,
).replace(
    "Heuristic model confidence: Not applicable",
    "Heuristic model confidence: High",
    1,
)
pathlib.Path(sys.argv[2]).write_text(text, encoding="utf-8")
PY
strict_message="$(
    validate_review_report_contract "${multi_invalid}" 3 2>&1
)" && fail 'multi-invalid report unexpectedly passed strict validation'
[[ "${strict_message}" == 'CLAIMS AND REPUTATION INTEGRITY ASSESSMENT is missing or duplicates required field: Roadmap and delivery commitments:' ]] ||
    fail "strict mode changed its first diagnostic: ${strict_message}"
validate_review_report_contract "${multi_invalid}" 3 collect \
    > "${FIXTURE_ROOT}/collect.json"
python3 - "${FIXTURE_ROOT}/collect.json" <<'PY'
import json
import sys

errors = json.load(open(sys.argv[1], encoding="utf-8"))["errors"]
expected = [
    ("CLAIMS AND REPUTATION INTEGRITY ASSESSMENT",
     "CLAIMS AND REPUTATION INTEGRITY ASSESSMENT is missing or duplicates "
     "required field: Roadmap and delivery commitments:"),
    ("CLAIMS AND REPUTATION INTEGRITY ASSESSMENT",
     "CLAIMS AND REPUTATION INTEGRITY ASSESSMENT has an invalid confidence "
     "level: High for counts and Medium for interpretation."),
    ("GENERATED-CODE PROVENANCE ASSESSMENT",
     "GENERATED-CODE PROVENANCE ASSESSMENT has an invalid heuristic model "
     "confidence"),
    ("FINDINGS", "Final report contains a Markdown table."),
]
found = [(e["section"], e["message"]) for e in errors]
for item in expected:
    if item not in found:
        raise SystemExit(f"collect mode missed {item}; found {found}")
PY

truncated_3="${FIXTURE_ROOT}/truncated-3.txt"
awk '/^RESEARCH TRANSPORT OBSERVATIONS$/ { print; print "Partial transport obs"; exit } { print }' \
    "${FIXTURE_ROOT}/valid-3.txt" > "${truncated_3}"
validate_review_report_contract "${truncated_3}" 3 collect \
    > "${FIXTURE_ROOT}/collect-truncated.json"
grep -Fq '"section": "RESEARCH TRANSPORT OBSERVATIONS", "message": "Incomplete report: final closing delimiter was missing."' \
    "${FIXTURE_ROOT}/collect-truncated.json" ||
    fail 'collect mode did not attribute truncation to the cut section'

# ---------------------------------------------------------------------------
# 2. Page plan is deterministic, bounded, and isolates FINDINGS.
# ---------------------------------------------------------------------------
review_report_delivery plan 3 > "${FIXTURE_ROOT}/plan-3.json"
python3 - "${FIXTURE_ROOT}/plan-3.json" <<'PY'
import json
import sys

plan = json.load(open(sys.argv[1], encoding="utf-8"))
assert plan["Protocol"] == "RHYOLITE_REPORT_DELIVERY_V1", plan
assert plan["RoundLimit"] == 2 and plan["PageLineBudget"] == 250, plan
assert plan["PartLimit"] == 4 and plan["PageSectionLimit"] == 3, plan
pages = plan["FirstRoundPages"]
assert ["FINDINGS"] in pages, pages
assert all(len(page) <= 3 for page in pages), pages
assert [s for page in pages for s in page] == plan["Required"], pages
assert len(plan["Required"]) == 16, plan
PY
expect_exit 2 'invalid plan scope is rejected' review_report_delivery plan 4

# ---------------------------------------------------------------------------
# 3. A truncated scope-3 report keeps every complete valid section verbatim
#    and requests only the cut and missing sections.
# ---------------------------------------------------------------------------
workdir="$(new_workdir)"
review_report_delivery assess "${truncated_3}" 3 "${workdir}" truncated \
    > "${FIXTURE_ROOT}/assess.json"
python3 - "${FIXTURE_ROOT}/assess.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["Accepted"] == [
    "REVIEW CONTEXT", "EXECUTIVE SUMMARY", "FINDINGS",
    "AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT",
    "CLAIMS AND REPUTATION INTEGRITY ASSESSMENT",
    "COMMUNITY HEALTH ASSESSMENT", "RESEARCH SOURCE LANDSCAPE",
    "INACCESSIBLE RESOURCE REGISTER", "TOP USER RETRIEVAL PRIORITIES",
], result
assert result["Needed"][0] == "RESEARCH TRANSPORT OBSERVATIONS", result
assert len(result["Needed"]) == 7, result
PY
[[ "$(stat -c '%a' "${workdir}/delivery.json")" == 600 ]] ||
    fail 'delivery state is not private'

request="${FIXTURE_ROOT}/request-1.txt"
review_report_delivery request "${workdir}" "${request}"
page_id="$(request_id "${request}")"
[[ "${page_id}" == R1P1.1 ]] || fail "unexpected first page id: ${page_id}"
assert_contains "${request}" 'Protocol: RHYOLITE_REPORT_DELIVERY_V1' 'request protocol'
assert_contains "${request}" 'Round: 1 of 2' 'request round'
assert_contains "${request}" 'most likely because it reached the per-response output token limit' 'truncation reason'
assert_contains "${request}" '- RESEARCH TRANSPORT OBSERVATIONS: This section was cut off before its end, most likely by the per-response output token limit.' 'cut section diagnostic'
assert_contains "${request}" 'RHYOLITE REPORT PAGE R1P1.1 BEGIN' 'begin marker'
assert_contains "${request}" 'RHYOLITE REPORT PAGE R1P1.1 CONTINUES' 'continuation marker'
assert_contains "${request}" 'RHYOLITE REPORT PAGE R1P1.1 END' 'end marker'
assert_contains "${request}" 'at or under 250' 'line budget'
assert_not_contains "${request}" '- REVIEW CONTEXT' 'accepted section was re-requested'
mapfile -t page_sections < <(sed -n '/^Requested sections, in this exact order:$/,/^$/ { s/^- //p }' "${request}")
[[ "${#page_sections[@]}" -eq 3 ]] ||
    fail "first page should request 3 sections, got ${#page_sections[@]}"

# Stale marker, missing terminal marker, extra text, foreign sections, and
# delimiters are all rejected with exact diagnostics and no state change.
reply="${FIXTURE_ROOT}/reply.txt"
write_page_reply "${reply}" R9P9.1 END "${page_sections[@]}"
expect_exit 20 'stale page id is rejected' review_report_delivery accept "${workdir}" "${reply}"
assert_contains "${FIXTURE_ROOT}/last.stdout" 'it used a marker from another request' 'stale marker diagnostic'
review_report_delivery request "${workdir}" "${request}"
page_id="$(request_id "${request}")"
[[ "${page_id}" == R1P2.1 ]] ||
    fail "a rejected page must be re-requested later in the round, got ${page_id}"
mapfile -t page_sections < <(sed -n '/^Requested sections, in this exact order:$/,/^$/ { s/^- //p }' "${request}")
{
    printf 'RHYOLITE REPORT PAGE %s BEGIN\n' "${page_id}"
    write_section "${page_sections[0]}"
} > "${reply}"
expect_exit 20 'cut page is rejected' review_report_delivery accept "${workdir}" "${reply}"
assert_contains "${FIXTURE_ROOT}/last.stdout" 'probably cut off by the per-response output token limit' 'cut page diagnostic'

review_report_delivery request "${workdir}" "${request}"
page_id="$(request_id "${request}")"
mapfile -t page_sections < <(sed -n '/^Requested sections, in this exact order:$/,/^$/ { s/^- //p }' "${request}")
write_page_reply "${reply}" "${page_id}" END "${page_sections[@]}"
printf 'Would you like me to fix this?\n' >> "${reply}"
expect_exit 20 'text after the final marker is rejected' \
    review_report_delivery accept "${workdir}" "${reply}"
assert_contains "${FIXTURE_ROOT}/last.stdout" 'contained text after' 'trailing text diagnostic'

# Round 1 is now exhausted with every page rejected; round 2 requests one
# section per page with the latest diagnostics.
review_report_delivery request "${workdir}" "${request}"
assert_contains "${request}" 'Round: 2 of 2' 'second round starts'
assert_contains "${request}" 'Reason: The trusted runner rejected your previous page reply.' 'second round reason'
mapfile -t page_sections < <(sed -n '/^Requested sections, in this exact order:$/,/^$/ { s/^- //p }' "${request}")
[[ "${#page_sections[@]}" -eq 1 ]] ||
    fail 'round 2 must request exactly one section per page'

# Deliver every remaining round-2 page, the first one in two parts.
first=1
while :; do
    page_id="$(request_id "${request}")"
    mapfile -t page_sections < <(sed -n '/^Requested sections, in this exact order:$/,/^$/ { s/^- //p }' "${request}")
    if ((first)); then
        first=0
        {
            printf 'RHYOLITE REPORT PAGE %s BEGIN\n' "${page_id}"
            write_section "${page_sections[0]}" | sed -n '1,2p'
            printf 'RHYOLITE REPORT PAGE %s CONTINUES\n' "${page_id}"
        } > "${reply}"
        expect_exit 10 'continuation part is accepted' \
            review_report_delivery accept "${workdir}" "${reply}"
        review_report_delivery request "${workdir}" "${request}"
        part_id="$(request_id "${request}")"
        [[ "${part_id}" == "${page_id%.*}.2" ]] ||
            fail "continuation part id mismatch: ${part_id}"
        assert_contains "${request}" "Continue exactly from the line after the last line of part ${page_id}" 'continuation instruction'
        {
            printf 'RHYOLITE REPORT PAGE %s BEGIN\n' "${part_id}"
            write_section "${page_sections[0]}" | sed -n '3,$p'
            printf 'RHYOLITE REPORT PAGE %s END\n' "${part_id}"
        } > "${reply}"
    else
        write_page_reply "${reply}" "${page_id}" END "${page_sections[@]}"
    fi
    expect_exit 0 "page ${page_id} is accepted" \
        review_report_delivery accept "${workdir}" "${reply}"
    status=0
    review_report_delivery request "${workdir}" "${request}" || status=$?
    ((status == 0)) || break
done
[[ "${status}" -eq 3 ]] || fail "all pages accepted but request returned ${status}"

assembled="${FIXTURE_ROOT}/assembled-3.txt"
review_report_delivery assemble "${workdir}" "${assembled}"
validate_final_review_report "${assembled}" 3 ||
    fail 'assembled scope-3 report failed strict finalization'
[[ "$(stat -c '%a' "${assembled}")" == 600 ]] || fail 'assembled report is not private'
cmp -s "${assembled}" "${FIXTURE_ROOT}/valid-3.txt" ||
    fail 'assembled report did not reproduce the canonical report byte for byte'
review_report_delivery status "${workdir}" > "${FIXTURE_ROOT}/status.json"
python3 - "${FIXTURE_ROOT}/status.json" <<'PY'
import json
import sys

status = json.load(open(sys.argv[1], encoding="utf-8"))
assert status["Needed"] == [] and status["Round"] == 2, status
assert status["PagesRejected"] == 3 and status["PartsAccepted"] == 1, status
assert status["PagesAccepted"] == 7, status
PY

# ---------------------------------------------------------------------------
# 4. Section-level validation rejects only the invalid section of a page and
#    reports the exact strict-validator diagnostic.
# ---------------------------------------------------------------------------
workdir="$(new_workdir)"
review_report_delivery assess "${multi_invalid}" 3 "${workdir}" invalid > /dev/null
review_report_delivery request "${workdir}" "${request}"
assert_contains "${request}" '- FINDINGS: Final report contains a Markdown table.' 'table diagnostic in request'
assert_contains "${request}" 'Reason: Your previous reply did not pass the trusted runner' 'invalid reason'
page_id="$(request_id "${request}")"
mapfile -t page_sections < <(sed -n '/^Requested sections, in this exact order:$/,/^$/ { s/^- //p }' "${request}")
[[ "${page_sections[*]}" == FINDINGS ]] ||
    fail "FINDINGS must be delivered alone, got ${page_sections[*]}"
{
    printf 'RHYOLITE REPORT PAGE %s BEGIN\n' "${page_id}"
    write_section FINDINGS
    printf '\nOVERALL ASSESSMENT\nNot requested.\n'
    printf 'RHYOLITE REPORT PAGE %s END\n' "${page_id}"
} > "${reply}"
expect_exit 20 'an unrequested section is rejected' \
    review_report_delivery accept "${workdir}" "${reply}"
assert_contains "${FIXTURE_ROOT}/last.stdout" 'sections that were not requested: OVERALL ASSESSMENT' 'foreign section diagnostic'
review_report_delivery request "${workdir}" "${request}"
page_id="$(request_id "${request}")"
mapfile -t page_sections < <(sed -n '/^Requested sections, in this exact order:$/,/^$/ { s/^- //p }' "${request}")
[[ "${page_sections[0]}" == 'CLAIMS AND REPUTATION INTEGRITY ASSESSMENT' ]] ||
    fail "unexpected second page: ${page_sections[*]}"
assert_contains "${request}" '- CLAIMS AND REPUTATION INTEGRITY ASSESSMENT: CLAIMS AND REPUTATION INTEGRITY ASSESSMENT has an invalid confidence level: High for counts and Medium for interpretation.' 'exact diagnostic in request'
assert_contains "${request}" '- CLAIMS AND REPUTATION INTEGRITY ASSESSMENT: CLAIMS AND REPUTATION INTEGRITY ASSESSMENT is missing or duplicates required field: Roadmap and delivery commitments:' 'every diagnostic in request'
{
    printf 'RHYOLITE REPORT PAGE %s BEGIN\n' "${page_id}"
    for section in "${page_sections[@]}"; do
        if [[ "${section}" == 'CLAIMS AND REPUTATION INTEGRITY ASSESSMENT' ]]; then
            write_section "${section}" |
                sed 's/^Confidence: Medium$/Confidence: High for counts; Low otherwise/'
        else
            write_section "${section}"
        fi
    done
    printf 'RHYOLITE REPORT PAGE %s END\n' "${page_id}"
} > "${reply}"
expect_exit 20 'invalid section inside a page is rejected' \
    review_report_delivery accept "${workdir}" "${reply}"
assert_contains "${FIXTURE_ROOT}/last.stdout" 'has an invalid confidence level: High for counts; Low otherwise' 'page diagnostic'
review_report_delivery status "${workdir}" > "${FIXTURE_ROOT}/status.json"
python3 - "${FIXTURE_ROOT}/status.json" <<'PY'
import json
import sys

status = json.load(open(sys.argv[1], encoding="utf-8"))
assert status["Needed"] == [
    "FINDINGS",
    "CLAIMS AND REPUTATION INTEGRITY ASSESSMENT",
], status
PY
review_report_delivery request "${workdir}" "${request}"
page_id="$(request_id "${request}")"
assert_contains "${request}" 'Round: 2 of 2' 'round 2 retries rejected sections'
{
    printf 'RHYOLITE REPORT PAGE %s BEGIN\n' "${page_id}"
    write_section FINDINGS
    printf '%s\n' "${DELIMITER}"
    printf 'RHYOLITE REPORT PAGE %s END\n' "${page_id}"
} > "${reply}"
expect_exit 20 'a delimiter inside a page is rejected' \
    review_report_delivery accept "${workdir}" "${reply}"
assert_contains "${FIXTURE_ROOT}/last.stdout" 'report delimiters or the REPOSITORY REVIEW REPORT heading' 'delimiter diagnostic'

# ---------------------------------------------------------------------------
# 5. A missing report (only a continuation tail, or an interrupted session)
#    requests every section that is not already complete; rounds are bounded.
# ---------------------------------------------------------------------------
tail_only="${FIXTURE_ROOT}/tail-only.txt"
{
    printf '   to kernel text and the hypercall page, mapped read-only\n'
    sed -n '/^AREAS REVIEWED WITHOUT QUALIFYING FINDINGS$/,$p' "${FIXTURE_ROOT}/valid-1.txt"
} > "${tail_only}"
workdir="$(new_workdir)"
review_report_delivery assess "${tail_only}" 1 "${workdir}" missing \
    > "${FIXTURE_ROOT}/assess.json"
python3 - "${FIXTURE_ROOT}/assess.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["Accepted"] == [
    "AREAS REVIEWED WITHOUT QUALIFYING FINDINGS",
    "PRIORITIZED REMEDIATION",
    "OVERALL ASSESSMENT",
], result
assert len(result["Needed"]) == 6, result
PY

workdir="$(new_workdir)"
printf 'The previous request was interrupted.\n' > "${FIXTURE_ROOT}/preface.txt"
review_report_delivery assess '' 1 "${workdir}" interrupted > /dev/null
review_report_delivery request "${workdir}" "${request}" "${FIXTURE_ROOT}/preface.txt"
assert_contains "${request}" 'The previous request was interrupted.' 'preface'
assert_contains "${request}" "- REVIEW CONTEXT: Deliver this section; the runner has no copy of it yet." 'interrupted diagnostic'
for _ in $(seq 1 20); do
    status=0
    review_report_delivery request "${workdir}" "${request}" || status=$?
    if ((status != 0)); then
        break
    fi
    page_id="$(request_id "${request}")"
    printf 'no markers\n' > "${reply}"
    review_report_delivery accept "${workdir}" "${reply}" > /dev/null || true
done
[[ "${status}" -eq 4 ]] || fail "rejected rounds must exhaust with exit 4, got ${status}"
expect_exit 3 'premature assembly is refused' \
    review_report_delivery assemble "${workdir}" "${FIXTURE_ROOT}/never.txt"
[[ ! -e "${FIXTURE_ROOT}/never.txt" ]] || fail 'premature assembly wrote a report'

# ---------------------------------------------------------------------------
# 6. Invalid UTF-8 is never accepted or silently replaced: the section is
#    resent, and a page containing invalid bytes is rejected.
# ---------------------------------------------------------------------------
invalid_utf8="${FIXTURE_ROOT}/invalid-utf8.txt"
awk '{ print } /^FINDINGS$/ { printf "\377 invalid byte\n" }' \
    "${FIXTURE_ROOT}/valid-1.txt" > "${invalid_utf8}"
workdir="$(new_workdir)"
review_report_delivery assess "${invalid_utf8}" 1 "${workdir}" invalid \
    > "${FIXTURE_ROOT}/assess.json"
python3 - "${FIXTURE_ROOT}/assess.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["Needed"] == ["FINDINGS"], result
PY
review_report_delivery request "${workdir}" "${request}"
assert_contains "${request}" '- FINDINGS: This section contained bytes that are not valid UTF-8.' 'invalid UTF-8 diagnostic'
page_id="$(request_id "${request}")"
{
    printf 'RHYOLITE REPORT PAGE %s BEGIN\n' "${page_id}"
    printf 'FINDINGS\n\377 still invalid\n'
    printf 'RHYOLITE REPORT PAGE %s END\n' "${page_id}"
} > "${reply}"
expect_exit 20 'a page with invalid UTF-8 is rejected' \
    review_report_delivery accept "${workdir}" "${reply}"
assert_contains "${FIXTURE_ROOT}/last.stdout" 'not valid UTF-8' 'page UTF-8 diagnostic'
grep -rqa $'\xef\xbf\xbd' "${workdir}/sections" &&
    fail 'a stored section contains a replacement character'

expect_exit 2 'unknown delivery command' review_report_delivery explode
expect_exit 2 'invalid assess reason' \
    review_report_delivery assess '' 1 "${workdir}" whatever

# ---------------------------------------------------------------------------
# 7. Failure analysis of a failed delivery: when the harness CLI rejects the
#    continuation's options (the 2026-10-13 run, Copilot CLI 1.0.98-2), the
#    class is harness-invocation rather than the output-limit trigger, and a
#    rerun is not recommended. Without that rejection the same artifacts keep
#    the output-limit class.
# ---------------------------------------------------------------------------
analysis_rejected="${FIXTURE_ROOT}/analysis-rejected"
analysis_cut="${FIXTURE_ROOT}/analysis-cut"
mkdir -p -- "${analysis_rejected}/worker-recovery"
cat > "${analysis_rejected}/state.json" <<'EOF'
{"Status": "ReviewFailed", "Repository": "https://github.com/octocat/Hello-World", "Harness": "copilot", "WorkerRecovery": {"Status": "Failed", "Trigger": "missing"}, "ReportRepair": {"Status": "NotReached"}}
EOF
cat > "${analysis_rejected}/worker-recovery/initial-outcome.json" <<'EOF'
{"ExitCode": 0, "FallbackModel": "", "FinalReplyAtOutputLimit": false, "ModelCallFailures": 0, "Outcome": "completed", "OutputLimitHits": 3, "OutputTokenLimit": 32000, "Phase": "review", "Retryable": false, "Schema": 1, "SessionErrors": [], "TurnRetries": 0}
EOF
cat > "${analysis_rejected}/errors.txt" <<'EOF'
Final report header or end marker was not found.
error: option '-n, --name <name>' cannot be used with option '--session-id <id>' when it resolves to an existing or remote session or task.
--name only names a brand-new session created by --session-id=<new-uuid>; the resolved session was not renamed.
Worker responses that reached the per-response output token limit of 32000 tokens: 3.
Worker recovery Failed: The worker continuation ended without an acceptable reply (outcome unknown).
EOF
cp -R -- "${analysis_rejected}" "${analysis_cut}"
grep -v -e '^error: option ' -e '^--name only ' "${analysis_rejected}/errors.txt" \
    > "${analysis_cut}/errors.txt"
write_failure_analysis "${analysis_rejected}" 'worker recovery' ||
    fail 'failure analysis of a rejected continuation was not written'
write_failure_analysis "${analysis_cut}" 'worker recovery' ||
    fail 'failure analysis of a cut report was not written'
python3 - "${analysis_rejected}/failure-analysis.json" \
    "${analysis_cut}/failure-analysis.json" <<'PY'
import json
import sys

rejected = json.load(open(sys.argv[1], encoding="utf-8"))
cut = json.load(open(sys.argv[2], encoding="utf-8"))
assert rejected["FailureClass"] == "harness-invocation", rejected
assert "error: option '-n, --name <name>' cannot be used" in rejected["RootCause"], rejected
assert rejected["RecommendedActions"][0].startswith("Do not rerun"), rejected
assert rejected["OutputLimitHits"] == 3 and rejected["OutputTokenLimit"] == 32000, rejected
assert cut["FailureClass"] == "output-limit", cut
PY
assert_contains "${analysis_rejected}/failure-analysis.md" \
    '- Failure class: harness-invocation' 'rejected continuation analysis'

printf 'Report delivery regressions passed.\n'
