#!/usr/bin/env bash

set -euo pipefail

export LC_ALL=C.utf8

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
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

expect_status() {
    local expected_status="$1"
    local description="$2"
    local output_path="$3"
    shift 3
    local stderr_path="${FIXTURE_ROOT}/expect-status.stderr"
    local stdout_path="${FIXTURE_ROOT}/expect-status.stdout"
    local status

    rm -f -- "${output_path}" "${stderr_path}" "${stdout_path}"
    if "$@" > "${stdout_path}" 2> "${stderr_path}"; then
        status=0
    else
        status=$?
    fi
    [[ "${status}" -eq "${expected_status}" ]] ||
        fail "${description}: expected status ${expected_status}, got ${status}"
    [[ ! -e "${output_path}" ]] ||
        fail "${description}: unexpectedly created output"
    [[ -s "${stderr_path}" ]] ||
        fail "${description}: missing clear diagnostic"
}

capture_diagnostic() {
    local report="$1"
    local scope="$2"
    local diagnostic="$3"

    if validate_review_report_contract \
        "${report}" "${scope}" > /dev/null 2> "${diagnostic}"; then
        fail "scope ${scope} malformed report unexpectedly passed strict validation"
    fi
    [[ -s "${diagnostic}" ]] ||
        fail "scope ${scope} strict validation did not produce a diagnostic"
}

extract_descriptor() {
    local request="$1"

    awk '
        found {
            print
            exit
        }
        $0 == "EXPECTED CONFIDENCE EDIT" {
            found = 1
        }
    ' "${request}"
}

write_report() {
    local report="$1"
    local scope="$2"
    local target_section="$3"
    local target_value="$4"
    local target_prefix="$5"
    local duplicate_target="${6:-no}"
    local manipulation_value="Medium."
    local provenance_value="Low."

    if [[ "${target_section}" == "manipulation" ]]; then
        manipulation_value="${target_value}"
    elif [[ "${target_section}" == "provenance" ]]; then
        provenance_value="${target_value}"
    else
        fail "unknown synthetic target section: ${target_section}"
    fi

    {
        cat <<'EOF'
================================================================================
REPOSITORY REVIEW REPORT
REVIEW CONTEXT
Trusted synthetic report-repair fixture.

EXECUTIVE SUMMARY
The fixture exercises one bounded confidence grammar correction.

FINDINGS
No qualifying findings.

AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT
Prompt injection and reviewer-directed instructions: No supporting evidence.
Confidence: Low.
Evidence basis: Synthetic item-level evidence.
Source/docs/commit/ref metadata poisoning and dataset/benchmark poisoning:
No supporting evidence.
Encoded/invisible instructions and tool-call bait: No supporting evidence.
Recursive/resource-exhaustion tarpits: No supporting evidence.
Tracking pixels/callback beacons/trackers/sensors: No supporting evidence.
Limitations of available evidence: Trusted synthetic fixture only.
EOF
        printf '%sConfidence: %s\n' \
            "${target_prefix}" "${manipulation_value}"
        printf '%sEvidence basis: Synthetic section-level evidence.\n' \
            "${target_prefix}"
        if [[ "${duplicate_target}" == "manipulation" ]]; then
            printf 'Confidence: %s\n' "${manipulation_value}"
            printf '%s\n' 'Evidence basis: Deliberate ambiguous duplicate.'
        fi

        if [[ "${scope}" -ge 2 ]]; then
            cat <<'EOF'

RESEARCH SOURCE LANDSCAPE
No external sources are needed for this trusted fixture.

INACCESSIBLE RESOURCE REGISTER
None.

TOP USER RETRIEVAL PRIORITIES
None.

RESEARCH TRANSPORT OBSERVATIONS
No network activity occurred.
EOF
        fi

        if [[ "${scope}" -eq 3 ]]; then
            cat <<'EOF'

GENERATED-CODE PROVENANCE ASSESSMENT
Generation assessment: Indeterminate
Confidence: Low.
Evidence basis: Synthetic item-level provenance evidence.
Direct model attribution: No direct attribution.
Heuristic model candidates (not attribution): No candidate identified
Heuristic model confidence: Not applicable
Direct effort attribution: No direct attribution.
Direct harness attribution: No direct attribution.
Coverage/window: Trusted synthetic fixture only.
Alternative explanations: No directly bound generation evidence.
EOF
            printf '%sConfidence: %s\n' \
                "${target_prefix}" "${provenance_value}"
            printf '%sEvidence basis: Synthetic provenance evidence.\n' \
                "${target_prefix}"
            if [[ "${duplicate_target}" == "provenance" ]]; then
                printf 'Confidence: %s\n' "${provenance_value}"
                printf '%s\n' 'Evidence basis: Deliberate ambiguous duplicate.'
            fi
        fi

        cat <<'EOF'

AREAS REVIEWED WITHOUT QUALIFYING FINDINGS
Report repair helper behavior.

PRIORITIZED REMEDIATION
None.

OVERALL ASSESSMENT
Synthetic fixture complete.
================================================================================
EOF
    } > "${report}"
}

write_expected_candidate() {
    local initial="$1"
    local expected="$2"
    local prefix="$3"
    local original_value="$4"
    local conservative_level="$5"

    python3 - \
        "${initial}" \
        "${expected}" \
        "${prefix}" \
        "${original_value}" \
        "${conservative_level}" <<'PY'
import pathlib
import sys

initial, expected, prefix, original_value, conservative_level = sys.argv[1:]
data = pathlib.Path(initial).read_bytes()
needle = (
    f"{prefix}Confidence: {original_value}"
).encode("utf-8")
replacement = (
    f"{prefix}Confidence: {conservative_level} - "
    f"Original confidence detail: {original_value}"
).encode("utf-8")
if data.count(needle) != 1:
    raise SystemExit("expected exactly one target line in the synthetic report")
pathlib.Path(expected).write_bytes(data.replace(needle, replacement, 1))
PY
}

source "${OUTPUT_HELPER}"

observed_value='High for the two observed constructs; Medium for absence outside normalized text.'
single_high_value='High confidence based on the trusted synthetic fixture.'
single_medium_value='Medium confidence based on the trusted synthetic fixture.'
single_low_value='Low because the trusted synthetic fixture is intentionally bounded.'

for scope_specification in \
    "1|manipulation|${observed_value}|Medium|  7) " \
    "2|manipulation|${single_high_value}|High|  - " \
    "3|provenance|${single_low_value}|Low|  9. "; do
    IFS='|' read -r \
        scope target_section target_value conservative_level target_prefix \
        <<< "${scope_specification}"
    initial="${FIXTURE_ROOT}/scope-${scope}-initial.txt"
    diagnostic="${FIXTURE_ROOT}/scope-${scope}-diagnostic.txt"
    request="${FIXTURE_ROOT}/scope-${scope}-request.txt"
    reply="${FIXTURE_ROOT}/scope-${scope}-reply.txt"
    candidate="${FIXTURE_ROOT}/scope-${scope}-candidate.txt"
    expected="${FIXTURE_ROOT}/scope-${scope}-expected.txt"
    copied_initial="${FIXTURE_ROOT}/scope-${scope}-copied-initial.txt"
    copied_candidate="${FIXTURE_ROOT}/scope-${scope}-copied-candidate.txt"

    write_report \
        "${initial}" \
        "${scope}" \
        "${target_section}" \
        "${target_value}" \
        "${target_prefix}"
    capture_diagnostic "${initial}" "${scope}" "${diagnostic}"
    assert_contains \
        "${diagnostic}" \
        "has an invalid confidence level: ${target_value}" \
        "scope ${scope} strict diagnostic"

    prepare_review_report_repair \
        "${initial}" "${scope}" "${diagnostic}" "${request}" ||
        fail "scope ${scope} repair request preparation failed"
    descriptor="$(extract_descriptor "${request}")"
    [[ -n "${descriptor}" ]] ||
        fail "scope ${scope} request omitted the expected descriptor"
    printf '%s\n' "${descriptor}" > "${reply}"

    assert_contains \
        "${request}" \
        '"Field":"Confidence:"' \
        "scope ${scope} descriptor field"
    assert_contains \
        "${request}" \
        "\"ConservativeLevel\":\"${conservative_level}\"" \
        "scope ${scope} conservative level"
    assert_contains \
        "${request}" \
        "    ${target_prefix}Confidence: ${target_value}" \
        "scope ${scope} inert report"
    assert_not_contains \
        "${request}" \
        "${initial}" \
        "scope ${scope} prompt path isolation"

    if [[ "${scope}" -eq 2 ]]; then
        apply_review_report_repair \
            "${initial}" \
            "${scope}" \
            "${diagnostic}" \
            "${reply}" \
            "${candidate}" ||
            fail "scope ${scope} descriptor application failed"
    else
        apply_review_report_repair \
            "${initial}" \
            "${scope}" \
            "$(< "${diagnostic}")" \
            "${reply}" \
            "${candidate}" ||
            fail "scope ${scope} descriptor application failed"
    fi
    validate_review_report_contract "${candidate}" "${scope}" ||
        fail "scope ${scope} repaired candidate failed strict validation"

    write_expected_candidate \
        "${initial}" \
        "${expected}" \
        "${target_prefix}" \
        "${target_value}" \
        "${conservative_level}"
    cmp -s -- "${expected}" "${candidate}" ||
        fail "scope ${scope} changed bytes outside the target field"

    cp -- "${initial}" "${copied_initial}"
    apply_review_report_repair \
        "${copied_initial}" \
        "${scope}" \
        "$(< "${diagnostic}")" \
        "${reply}" \
        "${copied_candidate}" ||
        fail "scope ${scope} transcript-independent application failed"
    cmp -s -- "${candidate}" "${copied_candidate}" ||
        fail "scope ${scope} descriptor application depended on transcript state"
done

base_initial="${FIXTURE_ROOT}/scope-1-initial.txt"
base_diagnostic="${FIXTURE_ROOT}/scope-1-diagnostic.txt"
base_request="${FIXTURE_ROOT}/scope-1-request.txt"
base_reply="${FIXTURE_ROOT}/scope-1-reply.txt"
base_descriptor="$(extract_descriptor "${base_request}")"
base_diagnostic_text="$(< "${base_diagnostic}")"

assert_contains \
    "${FIXTURE_ROOT}/scope-1-candidate.txt" \
    "Confidence: Medium - Original confidence detail: ${observed_value}" \
    'observed compound-confidence correction'
assert_contains \
    "${FIXTURE_ROOT}/scope-2-candidate.txt" \
    "Confidence: High - Original confidence detail: ${single_high_value}" \
    'single-level missing-delimiter correction'

medium_initial="${FIXTURE_ROOT}/medium-initial.txt"
medium_diagnostic="${FIXTURE_ROOT}/medium-diagnostic.txt"
medium_request="${FIXTURE_ROOT}/medium-request.txt"
medium_reply="${FIXTURE_ROOT}/medium-reply.txt"
medium_candidate="${FIXTURE_ROOT}/medium-candidate.txt"
write_report \
    "${medium_initial}" \
    1 \
    manipulation \
    "${single_medium_value}" \
    '  + '
capture_diagnostic "${medium_initial}" 1 "${medium_diagnostic}"
prepare_review_report_repair \
    "${medium_initial}" 1 "${medium_diagnostic}" "${medium_request}" ||
    fail 'Medium single-level repair request preparation failed'
extract_descriptor "${medium_request}" > "${medium_reply}"
apply_review_report_repair \
    "${medium_initial}" \
    1 \
    "$(< "${medium_diagnostic}")" \
    "${medium_reply}" \
    "${medium_candidate}" ||
    fail 'Medium single-level descriptor application failed'
assert_contains \
    "${medium_candidate}" \
    "Confidence: Medium - Original confidence detail: ${single_medium_value}" \
    'Medium single-level missing-delimiter correction'
validate_review_report_contract "${medium_candidate}" 1 ||
    fail 'Medium single-level candidate failed strict validation'

exercise_generic_level_case() {
    local name="$1"
    local scope="$2"
    local target_section="$3"
    local target_value="$4"
    local conservative_level="$5"
    local target_prefix="$6"
    local initial="${FIXTURE_ROOT}/${name}-initial.txt"
    local diagnostic="${FIXTURE_ROOT}/${name}-diagnostic.txt"
    local request="${FIXTURE_ROOT}/${name}-request.txt"
    local reply="${FIXTURE_ROOT}/${name}-reply.txt"
    local candidate="${FIXTURE_ROOT}/${name}-candidate.txt"
    local expected="${FIXTURE_ROOT}/${name}-expected.txt"

    write_report \
        "${initial}" \
        "${scope}" \
        "${target_section}" \
        "${target_value}" \
        "${target_prefix}"
    capture_diagnostic "${initial}" "${scope}" "${diagnostic}"
    prepare_review_report_repair \
        "${initial}" "${scope}" "${diagnostic}" "${request}" ||
        fail "${name} request preparation failed"
    extract_descriptor "${request}" > "${reply}"
    assert_contains \
        "${request}" \
        "\"ConservativeLevel\":\"${conservative_level}\"" \
        "${name} conservative level"
    apply_review_report_repair \
        "${initial}" \
        "${scope}" \
        "$(< "${diagnostic}")" \
        "${reply}" \
        "${candidate}" ||
        fail "${name} descriptor application failed"
    validate_review_report_contract "${candidate}" "${scope}" ||
        fail "${name} candidate failed strict validation"
    write_expected_candidate \
        "${initial}" \
        "${expected}" \
        "${target_prefix}" \
        "${target_value}" \
        "${conservative_level}"
    cmp -s -- "${expected}" "${candidate}" ||
        fail "${name} changed bytes outside the target field"
}

exercise_generic_level_case \
    'varied-scope-1' \
    1 \
    manipulation \
    'Observed paths are High confidence; absent paths are Medium confidence.' \
    Medium \
    '  7) '
exercise_generic_level_case \
    'varied-scope-2-high-low' \
    2 \
    manipulation \
    'High for direct source evidence; Low for inaccessible corroboration.' \
    Low \
    '  - '
exercise_generic_level_case \
    'varied-scope-3-all-levels' \
    3 \
    provenance \
    'High for direct metadata; Medium for aligned signals; Low for remaining uncertainty.' \
    Low \
    '  9. '
exercise_generic_level_case \
    'hyphenated-low-level' \
    1 \
    manipulation \
    'High for direct evidence; Low-confidence for unverified absence.' \
    Low \
    '  7) '
exercise_generic_level_case \
    'hyphenated-low-to-medium' \
    2 \
    manipulation \
    'High for direct evidence; Low-to-Medium for incomplete corroboration.' \
    Low \
    '  - '
exercise_generic_level_case \
    'underscored-low-markup' \
    3 \
    provenance \
    'High for direct evidence; _Low_ for unverified absence.' \
    Low \
    '  9. '
exercise_generic_level_case \
    'separate-very-low' \
    1 \
    manipulation \
    'High for direct evidence; Very Low for unverified absence.' \
    Low \
    '  7) '

repeated_valid_initial="${FIXTURE_ROOT}/repeated-valid-initial.txt"
repeated_valid_diagnostic="${FIXTURE_ROOT}/repeated-valid-diagnostic.txt"
repeated_valid_request="${FIXTURE_ROOT}/repeated-valid-request.txt"
repeated_valid_reply="${FIXTURE_ROOT}/repeated-valid-reply.txt"
repeated_valid_candidate="${FIXTURE_ROOT}/repeated-valid-candidate.txt"
repeated_valid_expected="${FIXTURE_ROOT}/repeated-valid-expected.txt"
repeated_valid_value='High for observed paths; Low for unavailable paths.'
write_report \
    "${FIXTURE_ROOT}/repeated-valid-base.txt" \
    1 \
    manipulation \
    "${repeated_valid_value}" \
    '  7) '
awk '
    { print }
    $0 == "Confidence: Low." {
        print "Confidence: High - repeated valid direct evidence."
        print "Confidence: Medium - repeated valid partial evidence."
    }
' "${FIXTURE_ROOT}/repeated-valid-base.txt" \
    > "${repeated_valid_initial}"
capture_diagnostic \
    "${repeated_valid_initial}" 1 "${repeated_valid_diagnostic}"
prepare_review_report_repair \
    "${repeated_valid_initial}" \
    1 \
    "${repeated_valid_diagnostic}" \
    "${repeated_valid_request}" ||
    fail 'repeated valid confidence request preparation failed'
assert_contains \
    "${repeated_valid_request}" \
    '"Occurrence":4' \
    'repeated valid confidence occurrence'
extract_descriptor "${repeated_valid_request}" > "${repeated_valid_reply}"
apply_review_report_repair \
    "${repeated_valid_initial}" \
    1 \
    "$(< "${repeated_valid_diagnostic}")" \
    "${repeated_valid_reply}" \
    "${repeated_valid_candidate}" ||
    fail 'repeated valid confidence descriptor application failed'
validate_review_report_contract "${repeated_valid_candidate}" 1 ||
    fail 'repeated valid confidence candidate failed strict validation'
write_expected_candidate \
    "${repeated_valid_initial}" \
    "${repeated_valid_expected}" \
    '  7) ' \
    "${repeated_valid_value}" \
    Low
cmp -s -- "${repeated_valid_expected}" "${repeated_valid_candidate}" ||
    fail 'repeated valid confidence repair changed non-target bytes'

multiline_initial="${FIXTURE_ROOT}/multiline-initial.txt"
multiline_diagnostic="${FIXTURE_ROOT}/multiline-diagnostic.txt"
multiline_request="${FIXTURE_ROOT}/multiline-request.txt"
multiline_reply="${FIXTURE_ROOT}/multiline-reply.txt"
multiline_candidate="${FIXTURE_ROOT}/multiline-candidate.txt"
multiline_expected="${FIXTURE_ROOT}/multiline-expected.txt"
multiline_first_value='High for directly observed paths;'
write_report \
    "${FIXTURE_ROOT}/multiline-base.txt" \
    2 \
    manipulation \
    "${multiline_first_value}" \
    '  7) '
awk '
    { print }
    $0 == "  7) Confidence: High for directly observed paths;" {
        print "      Medium for partially observed paths;"
        print "      Low for unavailable paths."
    }
' "${FIXTURE_ROOT}/multiline-base.txt" > "${multiline_initial}"
capture_diagnostic "${multiline_initial}" 2 "${multiline_diagnostic}"
assert_contains \
    "${multiline_diagnostic}" \
    'High for directly observed paths; Medium for partially observed paths; Low for unavailable paths.' \
    'multiline logical confidence value'
prepare_review_report_repair \
    "${multiline_initial}" 2 "${multiline_diagnostic}" "${multiline_request}" ||
    fail 'multiline confidence request preparation failed'
assert_contains \
    "${multiline_request}" \
    '"ConservativeLevel":"Low"' \
    'multiline conservative level'
extract_descriptor "${multiline_request}" > "${multiline_reply}"
apply_review_report_repair \
    "${multiline_initial}" \
    2 \
    "$(< "${multiline_diagnostic}")" \
    "${multiline_reply}" \
    "${multiline_candidate}" ||
    fail 'multiline confidence descriptor application failed'
validate_review_report_contract "${multiline_candidate}" 2 ||
    fail 'multiline confidence candidate failed strict validation'
write_expected_candidate \
    "${multiline_initial}" \
    "${multiline_expected}" \
    '  7) ' \
    "${multiline_first_value}" \
    Low
cmp -s -- "${multiline_expected}" "${multiline_candidate}" ||
    fail 'multiline confidence repair changed continuation or non-target bytes'

continued_value_initial="${FIXTURE_ROOT}/continued-value-initial.txt"
continued_value_diagnostic="${FIXTURE_ROOT}/continued-value-diagnostic.txt"
continued_value_request="${FIXTURE_ROOT}/continued-value-request.txt"
continued_value_reply="${FIXTURE_ROOT}/continued-value-reply.txt"
continued_value_candidate="${FIXTURE_ROOT}/continued-value-candidate.txt"
continued_value_expected="${FIXTURE_ROOT}/continued-value-expected.txt"
write_report \
    "${FIXTURE_ROOT}/continued-value-base.txt" \
    3 \
    provenance \
    'High for direct metadata; Low for unattributed files.' \
    '  9. '
awk '
    $0 == "  9. Confidence: High for direct metadata; Low for unattributed files." {
        print "  9. Confidence:"
        print "      High for direct metadata;"
        print "      Low for unattributed files."
        next
    }
    { print }
' "${FIXTURE_ROOT}/continued-value-base.txt" \
    > "${continued_value_initial}"
capture_diagnostic \
    "${continued_value_initial}" 3 "${continued_value_diagnostic}"
assert_contains \
    "${continued_value_diagnostic}" \
    'High for direct metadata; Low for unattributed files.' \
    'continued-line logical confidence value'
prepare_review_report_repair \
    "${continued_value_initial}" \
    3 \
    "${continued_value_diagnostic}" \
    "${continued_value_request}" ||
    fail 'continued-line confidence request preparation failed'
assert_contains \
    "${continued_value_request}" \
    '"ConservativeLevel":"Low"' \
    'continued-line conservative level'
extract_descriptor "${continued_value_request}" > "${continued_value_reply}"
apply_review_report_repair \
    "${continued_value_initial}" \
    3 \
    "$(< "${continued_value_diagnostic}")" \
    "${continued_value_reply}" \
    "${continued_value_candidate}" ||
    fail 'continued-line confidence descriptor application failed'
sed \
    's/^  9\. Confidence:$/  9. Confidence: Low - Original confidence detail:/' \
    "${continued_value_initial}" > "${continued_value_expected}"
cmp -s -- "${continued_value_expected}" "${continued_value_candidate}" ||
    fail 'continued-line confidence repair changed continuation or non-target bytes'
validate_review_report_contract "${continued_value_candidate}" 3 ||
    fail 'continued-line confidence candidate failed strict validation'

write_reply_variant() {
    local path="$1"
    local content="$2"

    printf '%s\n' "${content}" > "${path}"
}

wrong_high="${FIXTURE_ROOT}/wrong-high.json"
write_reply_variant \
    "${wrong_high}" \
    "${base_descriptor/\"ConservativeLevel\":\"Medium\"/\"ConservativeLevel\":\"High\"}"
expect_status \
    1 \
    'inflated conservative level' \
    "${FIXTURE_ROOT}/wrong-high-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${wrong_high}" \
    "${FIXTURE_ROOT}/wrong-high-candidate.txt"

wrong_low="${FIXTURE_ROOT}/wrong-low.json"
write_reply_variant \
    "${wrong_low}" \
    "${base_descriptor/\"ConservativeLevel\":\"Medium\"/\"ConservativeLevel\":\"Low\"}"
expect_status \
    1 \
    'wrong conservative level' \
    "${FIXTURE_ROOT}/wrong-low-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${wrong_low}" \
    "${FIXTURE_ROOT}/wrong-low-candidate.txt"

extra_key="${FIXTURE_ROOT}/extra-key.json"
write_reply_variant \
    "${extra_key}" \
    "${base_descriptor%\}},\"ReplacementText\":\"substantive edit\"}"
expect_status \
    1 \
    'extra descriptor key' \
    "${FIXTURE_ROOT}/extra-key-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${extra_key}" \
    "${FIXTURE_ROOT}/extra-key-candidate.txt"

duplicate_key="${FIXTURE_ROOT}/duplicate-key.json"
write_reply_variant \
    "${duplicate_key}" \
    "${base_descriptor/\{\"ProtocolVersion\":1/\{\"ProtocolVersion\":1,\"ProtocolVersion\":1}"
expect_status \
    1 \
    'duplicate descriptor key' \
    "${FIXTURE_ROOT}/duplicate-key-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${duplicate_key}" \
    "${FIXTURE_ROOT}/duplicate-key-candidate.txt"

multiple_edits="${FIXTURE_ROOT}/multiple-edits.json"
write_reply_variant \
    "${multiple_edits}" \
    "[${base_descriptor},${base_descriptor}]"
expect_status \
    1 \
    'multiple edit descriptors' \
    "${FIXTURE_ROOT}/multiple-edits-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${multiple_edits}" \
    "${FIXTURE_ROOT}/multiple-edits-candidate.txt"

multiple_objects="${FIXTURE_ROOT}/multiple-objects.json"
printf '%s\n%s\n' "${base_descriptor}" "${base_descriptor}" \
    > "${multiple_objects}"
expect_status \
    1 \
    'multiple JSON objects' \
    "${FIXTURE_ROOT}/multiple-objects-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${multiple_objects}" \
    "${FIXTURE_ROOT}/multiple-objects-candidate.txt"

wrong_hash="${FIXTURE_ROOT}/wrong-hash.json"
python3 - "${base_reply}" "${wrong_hash}" <<'PY'
import json
import pathlib
import sys

source, destination = sys.argv[1:]
value = json.loads(pathlib.Path(source).read_text(encoding="utf-8"))
value["OriginalValueSha256"] = "0" * 64
pathlib.Path(destination).write_text(
    json.dumps(value, separators=(",", ":")) + "\n",
    encoding="utf-8",
)
PY
expect_status \
    1 \
    'wrong original value hash' \
    "${FIXTURE_ROOT}/wrong-hash-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${wrong_hash}" \
    "${FIXTURE_ROOT}/wrong-hash-candidate.txt"

wrong_occurrence="${FIXTURE_ROOT}/wrong-occurrence.json"
write_reply_variant \
    "${wrong_occurrence}" \
    "${base_descriptor/\"Occurrence\":2/\"Occurrence\":1}"
expect_status \
    1 \
    'wrong confidence occurrence' \
    "${FIXTURE_ROOT}/wrong-occurrence-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${wrong_occurrence}" \
    "${FIXTURE_ROOT}/wrong-occurrence-candidate.txt"

unknown_section="${FIXTURE_ROOT}/unknown-section.json"
write_reply_variant \
    "${unknown_section}" \
    "${base_descriptor/AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT/FINDINGS}"
expect_status \
    1 \
    'unknown descriptor section' \
    "${FIXTURE_ROOT}/unknown-section-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${unknown_section}" \
    "${FIXTURE_ROOT}/unknown-section-candidate.txt"

unknown_field="${FIXTURE_ROOT}/unknown-field.json"
write_reply_variant \
    "${unknown_field}" \
    "${base_descriptor/\"Field\":\"Confidence:\"/\"Field\":\"Finding:\"}"
expect_status \
    1 \
    'unknown descriptor field' \
    "${FIXTURE_ROOT}/unknown-field-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${unknown_field}" \
    "${FIXTURE_ROOT}/unknown-field-candidate.txt"

boolean_version="${FIXTURE_ROOT}/boolean-version.json"
write_reply_variant \
    "${boolean_version}" \
    "${base_descriptor/\"ProtocolVersion\":1/\"ProtocolVersion\":true}"
expect_status \
    1 \
    'boolean protocol version' \
    "${FIXTURE_ROOT}/boolean-version-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${boolean_version}" \
    "${FIXTURE_ROOT}/boolean-version-candidate.txt"

boolean_occurrence="${FIXTURE_ROOT}/boolean-occurrence.json"
write_reply_variant \
    "${boolean_occurrence}" \
    "${base_descriptor/\"Occurrence\":2/\"Occurrence\":true}"
expect_status \
    1 \
    'boolean confidence occurrence' \
    "${FIXTURE_ROOT}/boolean-occurrence-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${boolean_occurrence}" \
    "${FIXTURE_ROOT}/boolean-occurrence-candidate.txt"

incomplete_reply="${FIXTURE_ROOT}/incomplete.json"
printf '{\n' > "${incomplete_reply}"
expect_status \
    1 \
    'incomplete descriptor' \
    "${FIXTURE_ROOT}/incomplete-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${incomplete_reply}" \
    "${FIXTURE_ROOT}/incomplete-candidate.txt"

code_fence_reply="${FIXTURE_ROOT}/code-fence.txt"
printf '```json\n%s\n```\n' "${base_descriptor}" > "${code_fence_reply}"
expect_status \
    1 \
    'code-fenced descriptor' \
    "${FIXTURE_ROOT}/code-fence-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${code_fence_reply}" \
    "${FIXTURE_ROOT}/code-fence-candidate.txt"

full_report_reply="${FIXTURE_ROOT}/full-report-reply.txt"
cp -- "${base_initial}" "${full_report_reply}"
expect_status \
    1 \
    'full report replacement reply' \
    "${FIXTURE_ROOT}/full-report-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${full_report_reply}" \
    "${FIXTURE_ROOT}/full-report-candidate.txt"

invalid_utf8_reply="${FIXTURE_ROOT}/invalid-utf8-reply.txt"
printf '\377\n' > "${invalid_utf8_reply}"
expect_status \
    1 \
    'invalid UTF-8 repair reply' \
    "${FIXTURE_ROOT}/invalid-utf8-reply-candidate.txt" \
    apply_review_report_repair \
    "${base_initial}" 1 "${base_diagnostic_text}" "${invalid_utf8_reply}" \
    "${FIXTURE_ROOT}/invalid-utf8-reply-candidate.txt"

changed_initial="${FIXTURE_ROOT}/changed-initial.txt"
write_report \
    "${changed_initial}" \
    1 \
    manipulation \
    "${single_high_value}" \
    '  7) '
expect_status \
    42 \
    'changed target with stale diagnostic' \
    "${FIXTURE_ROOT}/changed-target-candidate.txt" \
    apply_review_report_repair \
    "${changed_initial}" 1 "${base_diagnostic_text}" "${base_reply}" \
    "${FIXTURE_ROOT}/changed-target-candidate.txt"

valid_initial="${FIXTURE_ROOT}/valid-initial.txt"
write_report \
    "${valid_initial}" \
    1 \
    manipulation \
    'High - already valid synthetic evidence.' \
    '  7) '
validate_review_report_contract "${valid_initial}" 1 ||
    fail 'strict validator rejected the valid control report'
expect_status \
    42 \
    'valid original confidence field' \
    "${FIXTURE_ROOT}/valid-target-candidate.txt" \
    apply_review_report_repair \
    "${valid_initial}" 1 "${base_diagnostic_text}" "${base_reply}" \
    "${FIXTURE_ROOT}/valid-target-candidate.txt"

unsupported_value_report="${FIXTURE_ROOT}/unsupported-value.txt"
unsupported_value_diagnostic="${FIXTURE_ROOT}/unsupported-value-diagnostic.txt"
write_report \
    "${unsupported_value_report}" \
    1 \
    manipulation \
    'Certain based on unknown confidence text.' \
    '  7) '
capture_diagnostic \
    "${unsupported_value_report}" 1 "${unsupported_value_diagnostic}"
expect_status \
    42 \
    'unsupported confidence value' \
    "${FIXTURE_ROOT}/unsupported-value-request.txt" \
    prepare_review_report_repair \
    "${unsupported_value_report}" \
    1 \
    "${unsupported_value_diagnostic}" \
    "${FIXTURE_ROOT}/unsupported-value-request.txt"

unknown_diagnostic="${FIXTURE_ROOT}/unknown-diagnostic.txt"
printf '%s\n' 'FINDINGS has an invalid confidence level: High confidence.' \
    > "${unknown_diagnostic}"
expect_status \
    42 \
    'unknown validator diagnostic' \
    "${FIXTURE_ROOT}/unknown-diagnostic-request.txt" \
    prepare_review_report_repair \
    "${base_initial}" \
    1 \
    "${unknown_diagnostic}" \
    "${FIXTURE_ROOT}/unknown-diagnostic-request.txt"

unsupported_class_report="${FIXTURE_ROOT}/unsupported-class-report.txt"
unsupported_class_diagnostic="${FIXTURE_ROOT}/unsupported-class-diagnostic.txt"
head -n -1 "${base_initial}" > "${unsupported_class_report}"
capture_diagnostic \
    "${unsupported_class_report}" 1 "${unsupported_class_diagnostic}"
expect_status \
    42 \
    'unsupported validator diagnostic class' \
    "${FIXTURE_ROOT}/unsupported-class-request.txt" \
    prepare_review_report_repair \
    "${unsupported_class_report}" \
    1 \
    "${unsupported_class_diagnostic}" \
    "${FIXTURE_ROOT}/unsupported-class-request.txt"

ambiguous_report="${FIXTURE_ROOT}/ambiguous-report.txt"
ambiguous_diagnostic="${FIXTURE_ROOT}/ambiguous-diagnostic.txt"
write_report \
    "${ambiguous_report}" \
    1 \
    manipulation \
    "${observed_value}" \
    '  7) ' \
    manipulation
capture_diagnostic "${ambiguous_report}" 1 "${ambiguous_diagnostic}"
expect_status \
    42 \
    'ambiguous confidence target' \
    "${FIXTURE_ROOT}/ambiguous-request.txt" \
    prepare_review_report_repair \
    "${ambiguous_report}" \
    1 \
    "${ambiguous_diagnostic}" \
    "${FIXTURE_ROOT}/ambiguous-request.txt"

multiple_invalid_report="${FIXTURE_ROOT}/multiple-invalid-report.txt"
multiple_invalid_diagnostic="${FIXTURE_ROOT}/multiple-invalid-diagnostic.txt"
sed '0,/^Confidence: Low\.$/s//Confidence: Low confidence on the first item./' \
    "${base_initial}" > "${multiple_invalid_report}"
capture_diagnostic \
    "${multiple_invalid_report}" 1 "${multiple_invalid_diagnostic}"
expect_status \
    42 \
    'multiple distinct invalid confidence fields' \
    "${FIXTURE_ROOT}/multiple-invalid-request.txt" \
    prepare_review_report_repair \
    "${multiple_invalid_report}" \
    1 \
    "${multiple_invalid_diagnostic}" \
    "${FIXTURE_ROOT}/multiple-invalid-request.txt"

missing_evidence_report="${FIXTURE_ROOT}/missing-evidence-report.txt"
missing_evidence_diagnostic="${FIXTURE_ROOT}/missing-evidence-diagnostic.txt"
grep -Fv 'Evidence basis:' "${base_initial}" \
    > "${missing_evidence_report}"
capture_diagnostic \
    "${missing_evidence_report}" 1 "${missing_evidence_diagnostic}"
expect_status \
    42 \
    'missing independent evidence basis' \
    "${FIXTURE_ROOT}/missing-evidence-request.txt" \
    prepare_review_report_repair \
    "${missing_evidence_report}" \
    1 \
    "${missing_evidence_diagnostic}" \
    "${FIXTURE_ROOT}/missing-evidence-request.txt"

lowercase_level_report="${FIXTURE_ROOT}/lowercase-level-report.txt"
lowercase_level_diagnostic="${FIXTURE_ROOT}/lowercase-level-diagnostic.txt"
lowercase_level_value='High for observed text; low-confidence for absent context.'
write_report \
    "${lowercase_level_report}" \
    1 \
    manipulation \
    "${lowercase_level_value}" \
    '  7) '
capture_diagnostic \
    "${lowercase_level_report}" 1 "${lowercase_level_diagnostic}"
expect_status \
    42 \
    'case-insensitive ambiguous level text' \
    "${FIXTURE_ROOT}/lowercase-level-request.txt" \
    prepare_review_report_repair \
    "${lowercase_level_report}" \
    1 \
    "${lowercase_level_diagnostic}" \
    "${FIXTURE_ROOT}/lowercase-level-request.txt"

lowercase_underscore_report="${FIXTURE_ROOT}/lowercase-underscore-report.txt"
lowercase_underscore_diagnostic="${FIXTURE_ROOT}/lowercase-underscore-diagnostic.txt"
lowercase_underscore_value='High for observed text; low_confidence for absent context.'
write_report \
    "${lowercase_underscore_report}" \
    1 \
    manipulation \
    "${lowercase_underscore_value}" \
    '  7) '
capture_diagnostic \
    "${lowercase_underscore_report}" 1 "${lowercase_underscore_diagnostic}"
expect_status \
    42 \
    'underscored lowercase level text' \
    "${FIXTURE_ROOT}/lowercase-underscore-request.txt" \
    prepare_review_report_repair \
    "${lowercase_underscore_report}" \
    1 \
    "${lowercase_underscore_diagnostic}" \
    "${FIXTURE_ROOT}/lowercase-underscore-request.txt"

for invented_level_value in \
    'High for direct evidence; lower for inferred absence.' \
    'High for direct evidence; Lowest for inferred absence.' \
    'High for direct evidence; highest for observed paths.' \
    'High for direct evidence; Medium2 for inferred absence.' \
    'High for direct evidence; veryLow for inferred absence.' \
    'High for direct evidence; VERYLOW for inferred absence.' \
    'High for direct evidence; subMedium for inferred absence.' \
    'Highé for direct evidence.' \
    'High for below-average coverage that may allow uncertainty.'; do
    invented_level_slug="$(
        printf '%s' "${invented_level_value}" |
            tr -c 'A-Za-z0-9' '-' |
            tr '[:upper:]' '[:lower:]'
    )"
    invented_level_report="${FIXTURE_ROOT}/${invented_level_slug}-report.txt"
    invented_level_diagnostic="${FIXTURE_ROOT}/${invented_level_slug}-diagnostic.txt"
    invented_level_request="${FIXTURE_ROOT}/${invented_level_slug}-request.txt"
    write_report \
        "${invented_level_report}" \
        1 \
        manipulation \
        "${invented_level_value}" \
        '  7) '
    capture_diagnostic \
        "${invented_level_report}" 1 "${invented_level_diagnostic}"
    expect_status \
        42 \
        'invented or suffixed confidence level text' \
        "${invented_level_request}" \
        prepare_review_report_repair \
        "${invented_level_report}" \
        1 \
        "${invented_level_diagnostic}" \
        "${invented_level_request}"
done

invisible_level_index=0
for invisible_level_value in \
    $'High for direct evidence; sub\u2060Medium for inferred absence.' \
    $'High for direct evidence; very\u200dLow for inferred absence.' \
    $'High\u00adest for direct evidence.' \
    $'High\u0301 for direct evidence.' \
    $'High for direct evidence; Lo\u2065w for inferred absence.' \
    $'High for direct evidence; \uFF2C\uFF4F\uFF57 for inferred absence.' \
    $'High for direct evidence; L\u03BFw for inferred absence.' \
    $'High for direct evidence; \U0001D40B\U0001D428\U0001D430 for inferred absence.' \
    $'High for direct evidence; \u24C1\u24C4\u24CC for inferred absence.' \
    $'High for direct evidence; \U0001F13B\U0001F13E\U0001F146 for inferred absence.' \
    $'Medium for direct evidence; \U0001F1F1\U0001F1F4\U0001F1FC for inferred absence.'; do
    invisible_level_index=$((invisible_level_index + 1))
    invisible_level_report="${FIXTURE_ROOT}/invisible-level-${invisible_level_index}-report.txt"
    invisible_level_diagnostic="${FIXTURE_ROOT}/invisible-level-${invisible_level_index}-diagnostic.txt"
    invisible_level_request="${FIXTURE_ROOT}/invisible-level-${invisible_level_index}-request.txt"
    write_report \
        "${invisible_level_report}" \
        1 \
        manipulation \
        "${invisible_level_value}" \
        '  7) '
    capture_diagnostic \
        "${invisible_level_report}" 1 "${invisible_level_diagnostic}"
    expect_status \
        42 \
        'invisible or combining confidence level text' \
        "${invisible_level_request}" \
        prepare_review_report_repair \
        "${invisible_level_report}" \
        1 \
        "${invisible_level_diagnostic}" \
        "${invisible_level_request}"
done

cross_section_invalid_report="${FIXTURE_ROOT}/cross-section-invalid-report.txt"
cross_section_invalid_diagnostic="${FIXTURE_ROOT}/cross-section-invalid-diagnostic.txt"
write_report \
    "${FIXTURE_ROOT}/cross-section-invalid-base.txt" \
    3 \
    manipulation \
    'High for direct evidence; Low for missing corroboration.' \
    '  7) '
sed \
    's/^  7) Confidence: Low\.$/  7) Confidence: Medium for observed provenance; Low for unattributed files./' \
    "${FIXTURE_ROOT}/cross-section-invalid-base.txt" \
    > "${cross_section_invalid_report}"
capture_diagnostic \
    "${cross_section_invalid_report}" 3 "${cross_section_invalid_diagnostic}"
expect_status \
    42 \
    'second invalid confidence in another assessment section' \
    "${FIXTURE_ROOT}/cross-section-invalid-request.txt" \
    prepare_review_report_repair \
    "${cross_section_invalid_report}" \
    3 \
    "${cross_section_invalid_diagnostic}" \
    "${FIXTURE_ROOT}/cross-section-invalid-request.txt"

cross_section_missing_evidence_report="${FIXTURE_ROOT}/cross-section-missing-evidence-report.txt"
cross_section_missing_evidence_diagnostic="${FIXTURE_ROOT}/cross-section-missing-evidence-diagnostic.txt"
awk '
    $0 == "GENERATED-CODE PROVENANCE ASSESSMENT" {
        in_provenance = 1
    }
    $0 == "AREAS REVIEWED WITHOUT QUALIFYING FINDINGS" {
        in_provenance = 0
    }
    in_provenance && $0 ~ /Evidence basis:/ {
        next
    }
    { print }
' "${FIXTURE_ROOT}/cross-section-invalid-base.txt" \
    > "${cross_section_missing_evidence_report}"
capture_diagnostic \
    "${cross_section_missing_evidence_report}" \
    3 \
    "${cross_section_missing_evidence_diagnostic}"
expect_status \
    42 \
    'missing evidence in another assessment section' \
    "${FIXTURE_ROOT}/cross-section-missing-evidence-request.txt" \
    prepare_review_report_repair \
    "${cross_section_missing_evidence_report}" \
    3 \
    "${cross_section_missing_evidence_diagnostic}" \
    "${FIXTURE_ROOT}/cross-section-missing-evidence-request.txt"

invalid_provenance_verdict_report="${FIXTURE_ROOT}/invalid-provenance-verdict-report.txt"
invalid_provenance_verdict_diagnostic="${FIXTURE_ROOT}/invalid-provenance-verdict-diagnostic.txt"
write_report \
    "${FIXTURE_ROOT}/invalid-provenance-verdict-base.txt" \
    3 \
    provenance \
    'High for direct provenance; Low for unattributed files.' \
    '  9. '
sed \
    's/^Generation assessment: Indeterminate$/Generation assessment: Probably generated/' \
    "${FIXTURE_ROOT}/invalid-provenance-verdict-base.txt" \
    > "${invalid_provenance_verdict_report}"
capture_diagnostic \
    "${invalid_provenance_verdict_report}" \
    3 \
    "${invalid_provenance_verdict_diagnostic}"
expect_status \
    42 \
    'invalid provenance verdict after confidence repair' \
    "${FIXTURE_ROOT}/invalid-provenance-verdict-request.txt" \
    prepare_review_report_repair \
    "${invalid_provenance_verdict_report}" \
    3 \
    "${invalid_provenance_verdict_diagnostic}" \
    "${FIXTURE_ROOT}/invalid-provenance-verdict-request.txt"

invalid_utf8_report="${FIXTURE_ROOT}/invalid-utf8-report.txt"
cp -- "${base_initial}" "${invalid_utf8_report}"
printf '\377' >> "${invalid_utf8_report}"
expect_status \
    1 \
    'invalid UTF-8 initial report' \
    "${FIXTURE_ROOT}/invalid-utf8-request.txt" \
    prepare_review_report_repair \
    "${invalid_utf8_report}" \
    1 \
    "${base_diagnostic}" \
    "${FIXTURE_ROOT}/invalid-utf8-request.txt"

invalid_utf8_diagnostic="${FIXTURE_ROOT}/invalid-utf8-diagnostic.txt"
printf '\377\n' > "${invalid_utf8_diagnostic}"
expect_status \
    1 \
    'invalid UTF-8 initial diagnostic' \
    "${FIXTURE_ROOT}/invalid-diagnostic-request.txt" \
    prepare_review_report_repair \
    "${base_initial}" \
    1 \
    "${invalid_utf8_diagnostic}" \
    "${FIXTURE_ROOT}/invalid-diagnostic-request.txt"

scope_three_descriptor="$(extract_descriptor "${FIXTURE_ROOT}/scope-3-request.txt")"
changed_known_section="${FIXTURE_ROOT}/changed-known-section.json"
write_reply_variant \
    "${changed_known_section}" \
    "${scope_three_descriptor/GENERATED-CODE PROVENANCE ASSESSMENT/AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT}"
expect_status \
    1 \
    'changed known descriptor target' \
    "${FIXTURE_ROOT}/changed-known-section-candidate.txt" \
    apply_review_report_repair \
    "${FIXTURE_ROOT}/scope-3-initial.txt" \
    3 \
    "$(< "${FIXTURE_ROOT}/scope-3-diagnostic.txt")" \
    "${changed_known_section}" \
    "${FIXTURE_ROOT}/changed-known-section-candidate.txt"

handoff_with_summary="${FIXTURE_ROOT}/handoff-with-summary.md"
handoff_without_summary="${FIXTURE_ROOT}/handoff-without-summary.md"
repair_summary=$'Applied one bounded confidence grammar correction.\n# raw diagnostic heading remains inert'
write_review_handoff \
    "${handoff_with_summary}" \
    'https://github.com/octocat/Hello-World.git' \
    '0123456789abcdef' \
    'Completed' \
    "${FIXTURE_ROOT}/session.md" \
    "${FIXTURE_ROOT}/checkout" \
    "${FIXTURE_ROOT}/output" \
    'Local code review' \
    'Synthetic estimate' \
    'session-id' \
    'RemoteUrl' \
    'https://github.com/octocat/Hello-World.git' \
    'Disabled' \
    'Disabled' \
    'Disabled' \
    '' \
    '' \
    '' \
    '' \
    'copilot' \
    'Copilot' \
    'gpt-5.6-sol' \
    'max' \
    'long_context' \
    'github' \
    'github.com' \
    '(none)' \
    'Use only the trusted runner.' \
    "${repair_summary}"
assert_contains \
    "${handoff_with_summary}" \
    'Report repair summary:' \
    'handoff repair summary heading'
assert_contains \
    "${handoff_with_summary}" \
    '    Applied one bounded confidence grammar correction.' \
    'handoff controlled repair summary'
assert_contains \
    "${handoff_with_summary}" \
    '    # raw diagnostic heading remains inert' \
    'handoff inert diagnostic-shaped line'
if grep -Fxq '# raw diagnostic heading remains inert' \
    "${handoff_with_summary}"; then
    fail 'handoff rendered a diagnostic-shaped line as active markup'
fi

write_review_handoff \
    "${handoff_without_summary}" \
    'https://github.com/octocat/Hello-World.git' \
    '0123456789abcdef' \
    'Completed' \
    "${FIXTURE_ROOT}/session.md" \
    "${FIXTURE_ROOT}/checkout" \
    "${FIXTURE_ROOT}/output" \
    'Local code review' \
    'Synthetic estimate' \
    'session-id' \
    'RemoteUrl' \
    'https://github.com/octocat/Hello-World.git' \
    'Disabled' \
    'Disabled' \
    'Disabled' \
    '' \
    '' \
    '' \
    '' \
    'copilot' \
    'Copilot' \
    'gpt-5.6-sol' \
    'max' \
    'long_context' \
    'github' \
    'github.com' \
    '(none)' \
    'Use only the trusted runner.'
assert_not_contains \
    "${handoff_without_summary}" \
    'Report repair summary:' \
    'default handoff behavior'

printf '%s\n' 'Report repair helper tests passed.'
