#!/usr/bin/env bash

redact_emails() {
    sed -E \
        's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[email omitted]/g'
}

redact_credentials() {
    sed -E \
        -e 's#(https?://)[^/@[:space:]]+:[^/@[:space:]]+@#\1[credentials omitted]@#g' \
        -e 's/((Authorization|authorization|Proxy-Authorization|proxy-authorization):[[:space:]]*)((Bearer|bearer|Basic|basic)[[:space:]]+)?[^[:space:]]+/\1[credential omitted]/g' \
        -e 's/((access[_-]?token|ACCESS[_-]?TOKEN|api[_-]?key|API[_-]?KEY|password|PASSWORD|secret|SECRET|token|TOKEN)[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[credential omitted]/g' \
        -e 's/(github_pat_|gh[pousr]_)[A-Za-z0-9_]{20,}/[credential omitted]/g'
}

strip_terminal_controls() {
    LC_ALL=C awk '
        BEGIN {
            esc = sprintf("%c", 27)
            bel = sprintf("%c", 7)
            osc_bel = esc "\\][^" bel "]*" bel
            osc_st = esc "\\][^" esc "]*" esc "\\\\"
            csi = esc "\\[[0-?]*[ -/]*[@-~]"
            single_escape = esc "[@-_]"
        }
        {
            while (match($0, osc_bel)) {
                $0 = substr($0, 1, RSTART - 1) \
                    substr($0, RSTART + RLENGTH)
            }
            while (match($0, osc_st)) {
                $0 = substr($0, 1, RSTART - 1) \
                    substr($0, RSTART + RLENGTH)
            }
            gsub(csi, "")
            gsub(single_escape, "")
            gsub(/[\001-\010\013-\037\177]/, "")
            print
        }
    '
}

bound_repository_metadata() {
    awk '{
        print substr($0, 1, 512)
    }' |
        LC_ALL=C awk '
            BEGIN {
                total_limit = 65536
                section_limit = 12288
                section_marker_reserve = 160
                commit_marker_reserve = 192
                mode = "normal"
            }
            function line_bytes(value) {
                return length(value) + 1
            }
            function emit_line(value) {
                print value
                total_bytes += line_bytes(value)
            }
            function finish_bounded_section(kind, omitted, marker) {
                if (omitted == 0) {
                    return
                }
                marker = "[RHYOLITE metadata truncation: " omitted \
                    " additional " kind \
                    " records omitted after field sanitization and section bounds]"
                emit_line(marker)
            }
            $0 == "__RHYOLITE_TRACKED_METADATA_START__" {
                mode = "tracked"
                next
            }
            $0 == "__RHYOLITE_TRACKED_METADATA_END__" {
                finish_bounded_section("tracked-entry", tracked_omitted)
                mode = "normal"
                next
            }
            $0 == "__RHYOLITE_REF_METADATA_START__" {
                mode = "refs"
                next
            }
            $0 == "__RHYOLITE_REF_METADATA_END__" {
                finish_bounded_section("ref", refs_omitted)
                mode = "normal"
                next
            }
            $0 == "__RHYOLITE_COMMIT_RECORD_START__" {
                mode = "commit"
                commit_record = ""
                commit_record_bytes = 0
                next
            }
            $0 == "__RHYOLITE_COMMIT_RECORD_END__" {
                commit_records_seen++
                if (!commit_omission_started &&
                    total_bytes + commit_record_bytes + commit_marker_reserve <= total_limit) {
                    printf "%s", commit_record
                    total_bytes += commit_record_bytes
                } else {
                    commit_omission_started = 1
                    commit_records_omitted++
                }
                mode = "normal"
                next
            }
            mode == "tracked" {
                bytes = line_bytes($0)
                if (tracked_bytes + bytes + section_marker_reserve <= section_limit) {
                    emit_line($0)
                    tracked_bytes += bytes
                } else {
                    tracked_omitted++
                }
                next
            }
            mode == "refs" {
                bytes = line_bytes($0)
                if (refs_bytes + bytes + section_marker_reserve <= section_limit) {
                    emit_line($0)
                    refs_bytes += bytes
                } else {
                    refs_omitted++
                }
                next
            }
            mode == "commit" {
                commit_record = commit_record $0 "\n"
                commit_record_bytes += line_bytes($0)
                next
            }
            {
                emit_line($0)
            }
            END {
                if (commit_records_omitted > 0) {
                    marker = "[RHYOLITE metadata truncation: " \
                        commit_records_omitted \
                        " older commit records omitted after field sanitization " \
                        "and whole-record bounds]"
                    if (total_bytes + line_bytes(marker) <= total_limit) {
                        emit_line(marker)
                    } else {
                        print "[RHYOLITE metadata truncation: older commit records omitted]"
                    }
                }
            }
        '
}

extract_report() {
    local timeline="$1"
    local report="$2"

    awk '
        function is_delimiter(value, trimmed) {
            trimmed = value
            sub(/^[[:space:]]+/, "", trimmed)
            sub(/[[:space:]]+$/, "", trimmed)
            return trimmed ~ /^=+$/ && length(trimmed) >= 80
        }
        { lines[NR] = $0 }
        END {
            start = 0
            last = NR
            candidate_finish = 0
            while (last > 0 && lines[last] ~ /^[[:space:]]*$/) {
                last--
            }
            for (i = 1; i <= last; i++) {
                if (is_delimiter(lines[i])) {
                    window = lines[i]
                    header = 0
                    for (j = 1; j <= 3 && i + j <= last; j++) {
                        window = window " " lines[i + j]
                        if (toupper(lines[i + j]) ~ /REPOSITORY.*REVIEW.*REPORT/) {
                            header = i + j
                        }
                    }
                    if (header > 0 &&
                        toupper(window) ~ /REPOSITORY.*REVIEW.*REPORT/) {
                        start = i
                        candidate_finish = 0
                        for (j = header + 1; j <= last; j++) {
                            if (is_delimiter(lines[j])) {
                                candidate_finish = j
                                break
                            }
                        }
                    }
                }
            }
            if (start == 0) {
                exit 42
            }
            finish = candidate_finish > 0 ? candidate_finish : last
            for (i = start; i <= finish; i++) {
                sub(/^ /, "", lines[i])
                print lines[i]
            }
        }
    ' "${timeline}" > "${report}"
}

extract_research_dossier() {
    local timeline="$1"
    local dossier="$2"

    awk '
        function is_delimiter(value, trimmed) {
            trimmed = value
            sub(/^[[:space:]]+/, "", trimmed)
            sub(/[[:space:]]+$/, "", trimmed)
            return trimmed ~ /^=+$/ && length(trimmed) >= 80
        }
        { lines[NR] = $0 }
        END {
            start = 0
            last = NR
            candidate_finish = 0
            while (last > 0 && lines[last] ~ /^[[:space:]]*$/) {
                last--
            }
            for (i = 1; i <= last; i++) {
                if (is_delimiter(lines[i])) {
                    header = 0
                    for (j = 1; j <= 3 && i + j <= last; j++) {
                        if (toupper(lines[i + j]) == "REPOSITORY RESEARCH DOSSIER") {
                            header = i + j
                        }
                    }
                    if (header > 0) {
                        start = i
                        candidate_finish = 0
                        for (j = header + 1; j <= last; j++) {
                            if (is_delimiter(lines[j])) {
                                candidate_finish = j
                                break
                            }
                        }
                    }
                }
            }
            if (start == 0) {
                exit 42
            }
            finish = candidate_finish > 0 ? candidate_finish : last
            for (i = start; i <= finish; i++) {
                sub(/^ /, "", lines[i])
                print lines[i]
            }
        }
    ' "${timeline}" > "${dossier}"
}

canonicalize_research_dossier_closing_delimiter() {
    local dossier="$1"

    python3 - "${dossier}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
lines = text.splitlines()
required_sections = [
    "RESEARCH CAPABILITY RECORD",
    "RESEARCH SOURCE LANDSCAPE",
    "INACCESSIBLE RESOURCE REGISTER",
    "TOP USER RETRIEVAL PRIORITIES",
    "RESEARCH LIMITATIONS",
    "RESEARCH TRANSPORT OBSERVATIONS",
]
if (
    len(lines) < 3
    or len(lines[0].strip()) < 80
    or set(lines[0].strip()) != {"="}
    or lines[1].strip() != "REPOSITORY RESEARCH DOSSIER"
    or any(lines.count(section) != 1 for section in required_sections)
):
    raise SystemExit(1)
if lines[-1].strip() and set(lines[-1].strip()) == {"="}:
    raise SystemExit(0)
path.write_text(text.rstrip() + "\n" + "=" * 80 + "\n", encoding="utf-8")
PY
}

report_has_closing_delimiter() {
    local report="$1"

    awk '
        NF { line = $0 }
        END {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            exit(line ~ /^=+$/ && length(line) >= 80 ? 0 : 1)
        }
    ' "${report}"
}

review_section_navigation_map() {
    cat <<'EOF'
REVIEW CONTEXT	review-context
EXECUTIVE SUMMARY	executive-summary
FINDINGS	findings
AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT	agent-targeting-and-review-manipulation-assessment
RESEARCH SOURCE LANDSCAPE	research-source-landscape
INACCESSIBLE RESOURCE REGISTER	inaccessible-resource-register
TOP USER RETRIEVAL PRIORITIES	top-user-retrieval-priorities
RESEARCH TRANSPORT OBSERVATIONS	research-transport-observations
GENERATED-CODE PROVENANCE ASSESSMENT	generated-code-provenance-assessment
AREAS REVIEWED WITHOUT QUALIFYING FINDINGS	areas-reviewed-without-qualifying-findings
PRIORITIZED REMEDIATION	prioritized-remediation
OVERALL ASSESSMENT	overall-assessment
EOF
}

normalize_report_utf8_for_finalization() {
    local report="$1"

    python3 - "${report}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    data = path.read_bytes()
except OSError as error:
    raise SystemExit(f"could not read the report: {error}")

try:
    data.decode("utf-8")
except UnicodeDecodeError as error:
    normalized = data.decode("utf-8", errors="replace").encode("utf-8")
    try:
        path.write_bytes(normalized)
    except OSError as write_error:
        raise SystemExit(
            f"could not replace invalid UTF-8 in the report: {write_error}"
        )
    print(
        f"invalid UTF-8 at byte offset {error.start}; "
        "invalid byte sequences were replaced with U+FFFD"
    )
    raise SystemExit(42)
PY
}

validate_review_report_contract() {
    local report="$1"
    local scope="$2"

    python3 - "${report}" "${scope}" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
scope = int(sys.argv[2])
try:
    lines = path.read_text(encoding="utf-8").splitlines()
except OSError as error:
    raise SystemExit(f"report could not be read: {error}")
except UnicodeDecodeError as error:
    raise SystemExit(
        f"report is not valid UTF-8 at byte offset {error.start}"
    )

ordered_sections = [
    "REVIEW CONTEXT",
    "EXECUTIVE SUMMARY",
    "FINDINGS",
    "AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT",
    "RESEARCH SOURCE LANDSCAPE",
    "INACCESSIBLE RESOURCE REGISTER",
    "TOP USER RETRIEVAL PRIORITIES",
    "RESEARCH TRANSPORT OBSERVATIONS",
    "GENERATED-CODE PROVENANCE ASSESSMENT",
    "AREAS REVIEWED WITHOUT QUALIFYING FINDINGS",
    "PRIORITIZED REMEDIATION",
    "OVERALL ASSESSMENT",
]
base_sections = [
    "REVIEW CONTEXT",
    "EXECUTIVE SUMMARY",
    "FINDINGS",
    "AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT",
    "AREAS REVIEWED WITHOUT QUALIFYING FINDINGS",
    "PRIORITIZED REMEDIATION",
    "OVERALL ASSESSMENT",
]
research_sections = [
    "RESEARCH SOURCE LANDSCAPE",
    "INACCESSIBLE RESOURCE REGISTER",
    "TOP USER RETRIEVAL PRIORITIES",
    "RESEARCH TRANSPORT OBSERVATIONS",
]
provenance_section = "GENERATED-CODE PROVENANCE ASSESSMENT"

if (
    len(lines) < 4
    or len(lines[0].strip()) < 80
    or set(lines[0].strip()) != {"="}
    or lines[1].strip() != "REPOSITORY REVIEW REPORT"
    or len(lines[-1].strip()) < 80
    or set(lines[-1].strip()) != {"="}
):
    raise SystemExit("report delimiters or heading are invalid")

required = list(base_sections)
if scope >= 2:
    required.extend(research_sections)
if scope == 3:
    required.append(provenance_section)

for section in ordered_sections:
    count = lines.count(section)
    if section in required and count != 1:
        raise SystemExit(
            f"required report section is missing or duplicated: {section}"
        )
    if section not in required and count != 0:
        raise SystemExit(
            f"scope {scope} report contains an unexpected section: {section}"
        )

positions = [lines.index(section) for section in ordered_sections if section in required]
if positions != sorted(positions):
    raise SystemExit("report sections are out of order")


def section_lines(name):
    start = lines.index(name) + 1
    later = [
        lines.index(section)
        for section in ordered_sections
        if section in required and lines.index(section) > start - 1
    ]
    end = min(later) if later else len(lines) - 1
    return lines[start:end]


list_marker = re.compile(r"^(?:(?:[-*+])|(?:\d+[.)]))[ \t]+")


def normalized_section_lines(section):
    return [
        list_marker.sub("", line.strip(), count=1)
        for line in section_lines(section)
    ]


def field_value(normalized, position, field, stop_fields):
    value_parts = [normalized[position][len(field):].strip()]
    for line in normalized[position + 1:]:
        if any(line.startswith(other_field) for other_field in stop_fields):
            break
        if not line:
            if any(value_parts):
                break
            continue
        value_parts.append(line)
    return " ".join(part for part in value_parts if part).strip()


def require_unique_fields(section, normalized, fields, stop_fields):
    values = {}
    for field in fields:
        positions = [
            index
            for index, line in enumerate(normalized)
            if line.startswith(field)
        ]
        if len(positions) != 1:
            raise SystemExit(
                f"{section} is missing or duplicates required field: {field}"
            )
        position = positions[0]
        value = field_value(normalized, position, field, stop_fields)
        if not value:
            raise SystemExit(
                f"{section} has an empty required field: {field}"
            )
        values[field] = value
    return values


def require_assessment_fields(section, fields):
    normalized = normalized_section_lines(section)
    assessment_fields = ("Confidence:", "Evidence basis:")
    stop_fields = tuple(fields) + assessment_fields
    values = require_unique_fields(
        section,
        normalized,
        fields,
        stop_fields,
    )

    confidence_positions = [
        index
        for index, line in enumerate(normalized)
        if line.startswith("Confidence:")
    ]
    evidence_positions = [
        index
        for index, line in enumerate(normalized)
        if line.startswith("Evidence basis:")
    ]
    if not confidence_positions:
        raise SystemExit(
            f"{section} is missing required assessment field: Confidence:"
        )

    inline_evidence_count = 0
    confidence_pattern = re.compile(r"^(High|Medium|Low)(.*)$")
    delimited_suffix_pattern = re.compile(
        r"^(?:[.,:;][ \t]+|[ \t]+-[ \t]+)(.+)$"
    )
    for position in confidence_positions:
        value = field_value(
            normalized,
            position,
            "Confidence:",
            stop_fields,
        )
        match = confidence_pattern.fullmatch(value)
        if match is None:
            raise SystemExit(
                f"{section} has an invalid confidence level: {value or '<empty>'}"
            )
        remainder = match.group(2)
        if remainder in ("", ".", ";"):
            continue
        suffix_match = delimited_suffix_pattern.fullmatch(remainder)
        if suffix_match is None:
            raise SystemExit(
                f"{section} has an invalid confidence level: {value or '<empty>'}"
            )
        inline_evidence = suffix_match.group(1).strip()
        if inline_evidence.startswith("Evidence basis:"):
            inline_evidence = inline_evidence[len("Evidence basis:"):].strip()
            if not inline_evidence:
                raise SystemExit(
                    f"{section} has an empty required field: Evidence basis:"
                )
        inline_evidence_count += 1

    for position in evidence_positions:
        value = field_value(
            normalized,
            position,
            "Evidence basis:",
            stop_fields,
        )
        if not value:
            raise SystemExit(
                f"{section} has an empty required field: Evidence basis:"
            )

    if not evidence_positions and inline_evidence_count == 0:
        raise SystemExit(
            f"{section} is missing required assessment field: Evidence basis:"
        )
    return values


require_assessment_fields(
    "AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT",
    [
        "Prompt injection and reviewer-directed instructions:",
        "Source/docs/commit/ref metadata poisoning and dataset/benchmark poisoning:",
        "Encoded/invisible instructions and tool-call bait:",
        "Recursive/resource-exhaustion tarpits:",
        "Tracking pixels/callback beacons/trackers/sensors:",
        "Limitations of available evidence:",
    ],
)

if scope == 3:
    provenance = require_assessment_fields(
        provenance_section,
        [
            "Generation assessment:",
            "Direct model attribution:",
            "Heuristic model candidates (not attribution):",
            "Heuristic model confidence:",
            "Direct effort attribution:",
            "Direct harness attribution:",
            "Coverage/window:",
            "Alternative explanations:",
        ],
    )
    assessment = provenance["Generation assessment:"]
    verdicts = (
        "Confirmed",
        "Evidence supports assisted generation",
        "Indeterminate",
        "No supporting evidence found",
    )
    valid_verdict = False
    verdict_suffix_pattern = re.compile(
        r"^(?:[.,:;][ \t]+|[ \t]+-[ \t]+)\S(?:.*\S)?$"
    )
    for verdict in verdicts:
        if assessment == verdict:
            valid_verdict = True
            break
        if assessment.startswith(verdict):
            suffix = assessment[len(verdict):]
            if verdict_suffix_pattern.fullmatch(suffix):
                valid_verdict = True
                break
    if not valid_verdict:
        raise SystemExit(
            "GENERATED-CODE PROVENANCE ASSESSMENT has an invalid generation verdict"
        )
    heuristic_candidates = provenance[
        "Heuristic model candidates (not attribution):"
    ]
    heuristic_confidence = provenance["Heuristic model confidence:"]
    allowed_heuristic_confidence = {
        "Not applicable",
        "Low",
        "Medium",
    }
    if heuristic_confidence not in allowed_heuristic_confidence:
        raise SystemExit(
            "GENERATED-CODE PROVENANCE ASSESSMENT has an invalid heuristic "
            "model confidence"
        )
    controlled_absence_values = {
        "No candidate identified",
        "Not appropriate",
    }
    if heuristic_candidates in controlled_absence_values:
        if heuristic_confidence != "Not applicable":
            raise SystemExit(
                "A controlled no-candidate value requires heuristic model "
                "confidence Not applicable"
            )
    elif heuristic_confidence == "Not applicable":
        raise SystemExit(
            "Heuristic model confidence Not applicable requires a controlled "
            "no-candidate value"
        )
PY
}

extract_safe_https_references() {
    local report="$1"
    local scope="${2:-}"
    local contract_error=""

    [[ "${scope}" =~ ^[123]$ ]] || return 0
    if ! contract_error="$(
        validate_review_report_contract "${report}" "${scope}" 2>&1
    )"; then
        if [[ "${contract_error}" == \
            report\ is\ not\ valid\ UTF-8\ at\ byte\ offset* ]]; then
            printf '%s\n' \
                "URL extraction requires a valid UTF-8 report; ${contract_error}" \
                >&2
            return 1
        fi
        return 0
    fi

    python3 - "${report}" <<'PY'
import ipaddress
import pathlib
import re
import sys
from urllib.parse import unquote_to_bytes, urlsplit

path = pathlib.Path(sys.argv[1])
try:
    text = path.read_bytes().decode("utf-8")
except OSError as error:
    raise SystemExit(f"URL extraction could not read the report: {error}")
except UnicodeDecodeError as error:
    raise SystemExit(
        "URL extraction requires a valid UTF-8 report; "
        f"invalid byte sequence at byte offset {error.start}"
    )

ordered_sections = {
    "REVIEW CONTEXT",
    "EXECUTIVE SUMMARY",
    "FINDINGS",
    "AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT",
    "RESEARCH SOURCE LANDSCAPE",
    "INACCESSIBLE RESOURCE REGISTER",
    "TOP USER RETRIEVAL PRIORITIES",
    "RESEARCH TRANSPORT OBSERVATIONS",
    "GENERATED-CODE PROVENANCE ASSESSMENT",
    "AREAS REVIEWED WITHOUT QUALIFYING FINDINGS",
    "PRIORITIZED REMEDIATION",
    "OVERALL ASSESSMENT",
}
excluded_section = "AGENT-TARGETING AND REVIEW MANIPULATION ASSESSMENT"
reference_lines = []
excluded_lines = []
inside_excluded_section = False
for line in text.splitlines():
    if line == excluded_section:
        inside_excluded_section = True
        continue
    if inside_excluded_section and line in ordered_sections:
        inside_excluded_section = False
    if inside_excluded_section:
        excluded_lines.append(line)
    else:
        reference_lines.append(line)
text = "\n".join(reference_lines)
excluded_text = "\n".join(excluded_lines)

candidate_pattern = re.compile(
    r'''(?i)(?<![A-Za-z0-9])(?P<candidate>[<(\[{`"']*https://[^\s]+)'''
)
malformed_escape = re.compile(r"%(?![0-9A-Fa-f]{2})")
host_label = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")
unsafe_delimiters = set("<>\"'`{}|\\^[]")
sensitive_key = re.compile(
    r"(?:token|secret|password|passwd|api.?key|access.?key|auth|"
    r"authorization|credential|signature|session|cookie|jwt|code)",
    re.IGNORECASE,
)
credential_value = re.compile(
    r"(?i)(?:"
    r"^(?:bearer|basic)[ +]|"
    r"^(?:github_pat_|gh[pousr]_|sk-|rk-|AKIA|ASIA|AIza)|"
    r"^eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$|"
    r"-----BEGIN[ +][A-Z0-9 ]+PRIVATE[ +]KEY-----"
    r")"
)
blocked_exact = {
    "localhost",
    "localhost.localdomain",
}
blocked_helper_domains = ("localtest.me", "lvh.me", "nip.io", "sslip.io")
blocked_suffixes = (
    ".localhost",
    ".local",
    ".internal",
    ".localdomain",
    ".lan",
    ".home",
    ".home.arpa",
    ".corp",
    ".intranet",
    ".invalid",
    ".test",
    ".onion",
)


def normalize_candidate(candidate):
    value = candidate.lstrip("<([{`\"'")
    trailing_punctuation = ".,:;!?"
    closing_pairs = {")": "(", "]": "[", "}": "{", ">": "<"}
    quote_delimiters = {'"', "'", "`"}

    while value:
        normalized = value.rstrip(trailing_punctuation)
        if normalized != value:
            value = normalized
            continue
        final = value[-1]
        if (
            final in closing_pairs
            and value.count(final) > value.count(closing_pairs[final])
        ):
            value = value[:-1]
            continue
        if final in quote_delimiters and value.count(final) % 2:
            value = value[:-1]
            continue
        break
    return value


def has_balanced_parentheses(value):
    depth = 0
    for character in value:
        if character == "(":
            depth += 1
        elif character == ")":
            if depth == 0:
                return False
            depth -= 1
    return depth == 0


def decoded_ascii(value):
    try:
        decoded = unquote_to_bytes(value)
    except Exception:
        return None
    if any(byte < 0x21 or byte > 0x7E for byte in decoded):
        return None
    decoded_text = decoded.decode("ascii")
    if any(character in unsafe_delimiters for character in decoded_text):
        return None
    return decoded_text


def looks_credential_like(value):
    if credential_value.search(value):
        return True
    if (
        len(value) >= 32
        and re.fullmatch(r"[A-Za-z0-9_.~+/=-]+", value)
        and not re.fullmatch(r"[0-9A-Fa-f]+", value)
        and re.search(r"[A-Za-z]", value)
        and re.search(r"[0-9]", value)
    ):
        return True
    return False


def safe_reference(candidate):
    if (
        len(candidate) > 2048
        or not candidate.isascii()
        or any(character.isspace() or ord(character) < 0x20 for character in candidate)
        or any(character in unsafe_delimiters for character in candidate)
        or malformed_escape.search(candidate)
        or not has_balanced_parentheses(candidate)
    ):
        return False

    try:
        parsed = urlsplit(candidate)
        port = parsed.port
    except ValueError:
        return False
    if (
        parsed.scheme.lower() != "https"
        or not parsed.netloc
        or parsed.username is not None
        or parsed.password is not None
        or "@" in parsed.netloc
        or "%" in parsed.netloc
    ):
        return False
    if port is not None and not 1 <= port <= 65535:
        return False

    host = parsed.hostname
    if not host:
        return False
    host = host.lower()
    if (
        host.endswith(".")
        or host in blocked_exact
        or host.endswith(blocked_suffixes)
        or any(
            host == domain or host.endswith("." + domain)
            for domain in blocked_helper_domains
        )
    ):
        return False
    try:
        ipaddress.ip_address(host)
        return False
    except ValueError:
        pass

    labels = host.split(".")
    if len(labels) < 2 or any(not host_label.fullmatch(label) for label in labels):
        return False
    if labels[-1].isdigit() or len(labels[-1]) < 2:
        return False

    decoded_path = decoded_ascii(parsed.path)
    decoded_query = decoded_ascii(parsed.query)
    decoded_fragment = decoded_ascii(parsed.fragment)
    if decoded_path is None or decoded_query is None or decoded_fragment is None:
        return False
    if not all(
        has_balanced_parentheses(value)
        for value in (decoded_path, decoded_query, decoded_fragment)
    ):
        return False

    if parsed.query:
        fields = re.split(r"[&;]", parsed.query)
        if len(fields) > 50:
            return False
        for field in fields:
            key, separator, value = field.partition("=")
            decoded_key = decoded_ascii(key)
            decoded_value = decoded_ascii(value if separator else "")
            if decoded_key is None or decoded_value is None:
                return False
            normalized_key = re.sub(r"[^a-z0-9]", "", decoded_key.lower())
            if sensitive_key.search(normalized_key) or looks_credential_like(decoded_value):
                return False
    if looks_credential_like(decoded_fragment):
        return False
    return True


def suppression_key(candidate):
    try:
        parsed = urlsplit(candidate)
        port = parsed.port
    except ValueError:
        return None
    if (
        parsed.scheme.lower() != "https"
        or not parsed.netloc
        or parsed.username is not None
        or parsed.password is not None
        or "@" in parsed.netloc
    ):
        return None
    host = parsed.hostname
    if not host:
        return None
    host = host.lower()
    normalized_port = None if port in (None, 443) else port
    normalized_path = parsed.path or "/"
    if normalized_path != "/":
        normalized_path = normalized_path.rstrip("/") or "/"
    return host, normalized_port, normalized_path


excluded_endpoint_keys = set()
for match in candidate_pattern.finditer(excluded_text):
    candidate = normalize_candidate(match.group("candidate"))
    endpoint_key = suppression_key(candidate)
    if endpoint_key is not None:
        excluded_endpoint_keys.add(endpoint_key)

seen = set()
for match in candidate_pattern.finditer(text):
    candidate = normalize_candidate(match.group("candidate"))
    endpoint_key = suppression_key(candidate)
    if (
        endpoint_key in excluded_endpoint_keys
        or candidate in seen
        or not safe_reference(candidate)
    ):
        continue
    seen.add(candidate)
    print(candidate)
    if len(seen) >= 200:
        break
PY
}

write_markdown_navigation() {
    local report="$1"
    local heading anchor

    printf '## Navigation\n\n'
    while IFS=$'\t' read -r heading anchor; do
        if grep -Fxq -- "${heading}" "${report}"; then
            printf -- '- [%s](#%s)\n' "${heading}" "${anchor}"
        fi
    done < <(review_section_navigation_map)
    printf '\n'
}

write_markdown_external_references() {
    local report="$1"
    local scope="$2"
    local references reference

    references="$(extract_safe_https_references "${report}" "${scope}")"
    printf '## External references\n\n'
    if [[ -z "${references}" ]]; then
        printf 'None identified.\n\n'
        return
    fi
    while IFS= read -r reference || [[ -n "${reference}" ]]; do
        printf -- '- [%s](%s)\n' "${reference}" "${reference}"
    done <<< "${references}"
    printf '\n'
}

write_markdown_report() {
    local report="$1"
    local markdown="$2"
    local scope="${3:-}"

    {
        printf '# Repository Review Report\n\n'
        printf '[Plain text](review.txt) | [HTML](review.html) | '
        printf '[Run index](../index.html)\n\n'
        write_markdown_navigation "${report}"
        write_markdown_external_references "${report}" "${scope}"
        printf '## Canonical report\n\n'
        awk '
            NR == FNR {
                separator = index($0, "\t")
                heading = substr($0, 1, separator - 1)
                anchors[heading] = substr($0, separator + 1)
                next
            }
            {
                if ($0 in anchors) {
                    printf "\n<a id=\"%s\"></a>\n## %s\n\n", \
                        anchors[$0], $0
                    next
                }
                print "    " $0
            }
        ' <(review_section_navigation_map) "${report}"
    } > "${markdown}"
}

write_safe_markdown_document() {
    local title="$1"
    local source="$2"
    local destination="$3"

    {
        printf '# %s\n\n' "${title//$'\n'/ }"
        sed 's/^/    /' "${source}"
    } > "${destination}"
}

html_escape_file() {
    local source="$1"

    sed \
        -e 's/&/\&amp;/g' \
        -e 's/</\&lt;/g' \
        -e 's/>/\&gt;/g' \
        -e 's/"/\&quot;/g' \
        -e "s/'/\&#39;/g" \
        "${source}"
}

html_escape_value() {
    printf '%s' "$1" |
        sed \
            -e 's/&/\&amp;/g' \
            -e 's/</\&lt;/g' \
            -e 's/>/\&gt;/g' \
            -e 's/"/\&quot;/g' \
            -e "s/'/\&#39;/g"
}

write_html_report() {
    local report="$1"
    local html="$2"
    local repository="$3"
    local commit="$4"
    local status="$5"
    local scope="${6:-}"
    local encoded_repository encoded_commit encoded_status
    local heading anchor references reference encoded_reference

    encoded_repository="$(html_escape_value "${repository}")"
    encoded_commit="$(html_escape_value "${commit}")"
    encoded_status="$(html_escape_value "${status}")"

    {
        cat <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src 'none'; media-src 'none'; connect-src 'none'; font-src 'none'; object-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'">
<title>Repository Review Report</title>
<style>
:root { color-scheme: light dark; }
body { margin: 0; font-family: system-ui, sans-serif; line-height: 1.45; }
main { max-width: 1000px; margin: 0 auto; padding: 2rem; }
h1 { margin-top: 0; }
nav, section { margin-block: 1.5rem; }
ul { padding-inline-start: 1.5rem; }
a { color: inherit; overflow-wrap: anywhere; }
dl { display: grid; grid-template-columns: max-content 1fr; gap: .25rem 1rem; }
dt { font-weight: 700; }
dd { margin: 0; overflow-wrap: anywhere; }
pre { padding: 1rem; border: 1px solid currentColor; overflow: auto; white-space: pre-wrap; overflow-wrap: anywhere; font: 14px/1.45 ui-monospace, monospace; }
</style>
</head>
<body>
<main>
<h1>Repository Review Report</h1>
EOF
        printf '%s\n' \
            '<nav aria-label="Report formats"><a href="review.txt" rel="noopener noreferrer nofollow external" referrerpolicy="no-referrer">Plain text</a> | <a href="review.md" rel="noopener noreferrer nofollow external" referrerpolicy="no-referrer">Markdown</a> | <a href="../index.html" rel="noopener noreferrer nofollow external" referrerpolicy="no-referrer">Run index</a></nav>'
        printf '<dl><dt>Repository</dt><dd>%s</dd>' "${encoded_repository}"
        printf '<dt>Commit</dt><dd>%s</dd>' "${encoded_commit}"
        printf '<dt>Status</dt><dd>%s</dd></dl>\n' "${encoded_status}"
        printf '<nav aria-label="Report sections"><h2>Navigation</h2><ul>\n'
        while IFS=$'\t' read -r heading anchor; do
            if grep -Fxq -- "${heading}" "${report}"; then
                printf '<li><a href="#%s" rel="noopener noreferrer nofollow external" referrerpolicy="no-referrer">%s</a></li>\n' \
                    "${anchor}" "$(html_escape_value "${heading}")"
            fi
        done < <(review_section_navigation_map)
        printf '</ul></nav>\n'
        printf '<section aria-labelledby="external-references"><h2 id="external-references">External references</h2>\n'
        references="$(extract_safe_https_references "${report}" "${scope}")"
        if [[ -z "${references}" ]]; then
            printf '<p>None identified.</p>\n'
        else
            printf '<ul>\n'
            while IFS= read -r reference || [[ -n "${reference}" ]]; do
                encoded_reference="$(html_escape_value "${reference}")"
                printf '<li><a href="%s" rel="noopener noreferrer nofollow external" referrerpolicy="no-referrer">%s</a></li>\n' \
                    "${encoded_reference}" "${encoded_reference}"
            done <<< "${references}"
            printf '</ul>\n'
        fi
        printf '</section>\n'
        printf '<div aria-label="Canonical report body"><pre>'
        awk '
            function escape_html(value) {
                gsub(/&/, "\\&amp;", value)
                gsub(/</, "\\&lt;", value)
                gsub(/>/, "\\&gt;", value)
                gsub(/"/, "\\&quot;", value)
                gsub(/\047/, "\\&#39;", value)
                return value
            }
            NR == FNR {
                separator = index($0, "\t")
                heading = substr($0, 1, separator - 1)
                anchors[heading] = substr($0, separator + 1)
                next
            }
            {
                if ($0 in anchors) {
                    if (in_section) {
                        print "</pre></section>"
                    } else {
                        print "</pre>"
                    }
                    printf "<section id=\"%s\"><h2>%s</h2><pre>", \
                        anchors[$0], escape_html($0)
                    in_section = 1
                    next
                }
                print escape_html($0)
            }
            END {
                if (in_section) {
                    print "</pre></section>"
                } else {
                    print "</pre>"
                }
            }
        ' <(review_section_navigation_map) "${report}"
        printf '</div>\n</main>\n</body>\n</html>\n'
    } > "${html}"
}

write_review_handoff() {
    local handoff="$1"
    local repository="$2"
    local commit="$3"
    local status="$4"
    local session="$5"
    local checkout="$6"
    local output_directory="$7"
    local scope="$8"
    local scope_estimate="$9"
    local session_id="${10}"
    local source_kind="${11:-RemoteUrl}"
    local source_path="${12:-}"
    local provenance_window="${13:-Disabled}"
    local research_transport="${14:-Disabled}"
    local research_status="${15:-Disabled}"
    local research_directory="${16:-}"
    local research_dossier="${17:-}"
    local research_network_summary="${18:-}"
    local research_private_directory="${19:-}"
    local harness="${20:-}"
    local harness_display_name="${21:-}"
    local reasoning_effort="${22:-}"
    local provider_id="${23:-}"
    local provider_host="${24:-}"
    local provider_env_names="${25:-(none)}"
    local resume_policy="${26:-}"
    local continuation

    if [[ -n "${session_id}" ]]; then
        continuation="The saved ${harness_display_name} session ID is \`${session_id}\`. ${resume_policy} Start the \`repository-review\` agent and provide this handoff path so a trusted runner can establish a restricted continuation."
    else
        continuation="Setup did not reach a child ${harness_display_name} session. Rerun \`repository-review\` using the repository URL, requested commit, scope, and output choices recorded in \`state.json\`. Do not analyze the verification clone directly."
    fi

    {
        printf '# Repository review handoff\n\n'
        printf 'Repository:\n\n    %s\n\n' "${repository}"
        printf 'Source kind:\n\n    %s\n\n' "${source_kind}"
        printf 'Selected source path:\n\n    %s\n\n' "${source_path}"
        printf 'Commit:\n\n    %s\n\n' "${commit}"
        printf 'Status:\n\n    %s\n\n' "${status}"
        printf 'Harness:\n\n    %s (%s)\n\n' \
            "${harness_display_name}" "${harness}"
        printf 'Reasoning effort:\n\n    %s\n\n' "${reasoning_effort}"
        printf 'Provider:\n\n'
        printf '    ID: %s\n' "${provider_id}"
        printf '    Host: %s\n' "${provider_host}"
        printf '    Forwarded environment variable names: %s\n\n' \
            "${provider_env_names}"
        printf 'Scope:\n\n    %s\n\n' "${scope}"
        printf 'Planning estimate:\n\n    %s\n\n' "${scope_estimate}"
        printf 'Provenance window:\n\n'
        while IFS= read -r line || [[ -n "${line}" ]]; do
            printf '    %s\n' "${line}"
        done <<< "${provenance_window}"
        printf '\n'
        printf 'Research transport:\n\n'
        while IFS= read -r line || [[ -n "${line}" ]]; do
            printf '    %s\n' "${line}"
        done <<< "${research_transport}"
        printf '\n'
        printf 'Research status:\n\n    %s\n\n' "${research_status}"
        if [[ -n "${research_directory}" ]]; then
            printf 'Research artifact directory:\n\n    %s\n\n' \
                "${research_directory}"
            printf '%s\n\n' \
                'The research network/private directory may contain sensitive tracking identifiers and hostile unsupported bytes. Keep it local and do not render or execute private evidence.'
        fi
        printf 'Read-only checkout:\n\n    %s\n\n' "${checkout}"
        printf 'Writable output directory:\n\n    %s\n\n' "${output_directory}"
        printf 'Harness session:\n\n    %s\n\n' "${session}"
        printf 'Harness session ID:\n\n    %s\n\n' "${session_id}"
        printf 'Resume policy:\n\n    %s\n\n' "${resume_policy}"
        printf '## Continue safely\n\n%s\n\n' "${continuation}"
        printf '%s\n%s\n\n' \
            'Read `state.json`, `request.txt`, and `errors.txt` before continuing.' \
            'The checkout must remain read-only; only the trusted wrapper writes artifacts.'
        printf '## Artifacts\n\n'
        printf 'PlainText:\n\n    %s/review.txt\n\n' "${output_directory}"
        printf 'Markdown:\n\n    %s/review.md\n\n' "${output_directory}"
        printf 'Html:\n\n    %s/review.html\n\n' "${output_directory}"
        printf 'Timeline:\n\n    %s/analysis-timeline.txt\n\n' "${output_directory}"
        printf 'Transcript:\n\n    %s/session.md\n\n' "${output_directory}"
        printf 'Request:\n\n    %s/request.txt\n\n' "${output_directory}"
        printf 'Errors:\n\n    %s/errors.txt\n\n' "${output_directory}"
        printf 'State:\n\n    %s/state.json\n\n' "${output_directory}"
        if [[ -n "${research_dossier}" ]]; then
            printf 'ResearchDossier:\n\n    %s\n\n' "${research_dossier}"
        fi
        if [[ -n "${research_network_summary}" ]]; then
            printf 'ResearchNetworkSummary:\n\n    %s\n\n' \
                "${research_network_summary}"
        fi
        if [[ -n "${research_private_directory}" ]]; then
            printf 'ResearchPrivateEvidence:\n\n    %s\n\n' \
                "${research_private_directory}"
        fi
        printf 'AgentState:\n\n    %s/agent-state\n' "${output_directory}"
    } > "${handoff}"
}
