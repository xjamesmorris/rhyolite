#!/usr/bin/env bash

set -euo pipefail
umask 077

ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SUMMARY="${ROOT}/plugins/rhyolite/bin/rhyolite-summary"
ROOT_SUMMARY="${ROOT}/rhyolite-summary"
FIXTURE_ROOT="$(mktemp -d)"
OUTPUT_ROOT="${FIXTURE_ROOT}/output root/rhyolite-output"
MODULE_ROOT="${OUTPUT_ROOT}/repo-review"
SINGLE_RUN="${MODULE_ROOT}/run-single"
SINGLE_REPOSITORY="${SINGLE_RUN}/github--owner--one"
MULTI_RUN="${MODULE_ROOT}/run-multi"
MULTI_REPOSITORY_A="${MULTI_RUN}/github--owner--two"
MULTI_REPOSITORY_B="${MULTI_RUN}/github--owner--three"

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

mkdir -p -- \
    "${SINGLE_REPOSITORY}" \
    "${MULTI_REPOSITORY_A}" \
    "${MULTI_REPOSITORY_B}"

cat > "${SINGLE_RUN}/review-plan.json" <<'EOF'
{
  "SchemaVersion": 5,
  "RunId": "run-single",
  "GeneratedAt": "2026-10-08T14:00:00Z",
  "ReviewDate": "2026-10-08",
  "Harness": "copilot",
  "Model": "gpt-5.6-sol",
  "ModelCatalogMembership": "listed",
  "ReasoningEffort": "max",
  "ContextTier": "long_context",
  "RhyoliteVersion": "0.8.0",
  "Scope": {
    "Number": 1,
    "Name": "1 - Core repository review",
    "PublicResearch": false,
    "ProvenanceResearch": false
  }
}
EOF

cat > "${SINGLE_REPOSITORY}/review.txt" <<'EOF'
================================================================================
REPOSITORY REVIEW REPORT

REVIEW CONTEXT

Repository: https://github.com/owner/one
Review date: 2026-10-08
Scope: 1 - Core repository review

OVERALL ASSESSMENT

Suitable for limited use | with the documented controls. Runtime coverage
remains incomplete.
Confidence: High - direct source and test evidence support this assessment.
================================================================================
EOF

cat > "${SINGLE_REPOSITORY}/review.md" <<'EOF'
# Synthetic review one
EOF

cat > "${SINGLE_REPOSITORY}/review.html" <<'EOF'
<!doctype html><title>Synthetic review one</title>
EOF

cat > "${SINGLE_REPOSITORY}/state.json" <<EOF
{
  "SchemaVersion": 6,
  "Harness": "copilot",
  "Model": "gpt-5.6-sol",
  "ReasoningEffort": "max",
  "ContextTier": "long_context",
  "RhyoliteVersion": "0.8.0",
  "Slug": "github--owner--one",
  "Repository": "https://github.com/owner/one",
  "Source": {
    "Kind": "RemoteUrl",
    "RemoteUrl": "https://github.com/owner/one"
  },
  "Commit": "1111111111111111111111111111111111111111",
  "Status": "Completed",
  "StartedAt": "2026-10-08T14:01:00Z",
  "CompletedAt": "2026-10-08T14:10:00Z",
  "Scope": {
    "Name": "1 - Core repository review",
    "PublicResearch": false,
    "ProvenanceResearch": false
  },
  "Artifacts": {
    "PlainText": "/old-host/rhyolite-output/repo-review/run-single/github--owner--one/review.txt",
    "Markdown": "/old-host/rhyolite-output/repo-review/run-single/github--owner--one/review.md",
    "Html": "/old-host/rhyolite-output/repo-review/run-single/github--owner--one/review.html",
    "State": "/old-host/rhyolite-output/repo-review/run-single/github--owner--one/state.json"
  }
}
EOF

cat > "${SINGLE_RUN}/state.json" <<EOF
{
  "SchemaVersion": 6,
  "RunId": "run-single",
  "Status": "Completed",
  "Harness": "copilot",
  "Model": "gpt-5.6-sol",
  "ReasoningEffort": "max",
  "ContextTier": "long_context",
  "StartedAt": "2026-10-08T14:00:00Z",
  "CompletedAt": "2026-10-08T14:10:00Z",
  "Scope": {
    "Name": "1 - Core repository review",
    "PublicResearch": false,
    "ProvenanceResearch": false
  },
  "Repositories": [
    {
      "Repository": "https://github.com/owner/one",
      "Status": "Completed",
      "State": "${SINGLE_REPOSITORY}/state.json"
    }
  ]
}
EOF

{
    printf '[\n'
    cat -- "${SINGLE_REPOSITORY}/state.json"
    printf '\n]\n'
} > "${SINGLE_RUN}/manifest.json"

cat > "${MULTI_RUN}/review-plan.json" <<'EOF'
{
  "SchemaVersion": 5,
  "RunId": "run-multi",
  "GeneratedAt": "2026-10-09T15:00:00Z",
  "ReviewDate": "2026-10-09",
  "Harness": "copilot",
  "Model": "claude-opus-5.5",
  "ReasoningEffort": "max",
  "ContextTier": "long_context",
  "Scope": {
    "Number": 3,
    "Name": "3 - Full review, public research, and whole-repository provenance",
    "PublicResearch": true,
    "ProvenanceResearch": true
  }
}
EOF

cat > "${MULTI_REPOSITORY_A}/review.txt" <<'EOF'
================================================================================
REPOSITORY REVIEW REPORT

REVIEW CONTEXT

Repository: https://github.com/owner/two
Review date: 2026-10-09
Scope: 3 - Full review, public research, and whole-repository provenance

OVERALL ASSESSMENT

Overall grade: <strong>Conditional pass</strong>
The repository is suitable only after the listed remediations.
Confidence: Medium - public evidence is useful but incomplete.
Confidence: Low - deployment conditions were not available.
================================================================================
EOF

cat > "${MULTI_REPOSITORY_A}/review.md" <<'EOF'
# Synthetic review two
EOF

cat > "${MULTI_REPOSITORY_A}/review.html" <<'EOF'
<!doctype html><title>Synthetic review two</title>
EOF

cat > "${MULTI_REPOSITORY_A}/state.json" <<EOF
{
  "SchemaVersion": 6,
  "Harness": "copilot",
  "Model": "claude-opus-5.5",
  "ReasoningEffort": "max",
  "ContextTier": "long_context",
  "RhyoliteVersion": "0.8.1",
  "Slug": "github--owner--two",
  "Repository": "https://github.com/owner/two",
  "Source": {
    "Kind": "RemoteUrl",
    "RemoteUrl": "https://github.com/owner/two"
  },
  "Commit": "2222222222222222222222222222222222222222",
  "Status": "Completed",
  "StartedAt": "2026-10-09T15:01:00Z",
  "CompletedAt": "2026-10-09T15:20:00Z",
  "Scope": {
    "Name": "3 - Full review, public research, and whole-repository provenance",
    "PublicResearch": true,
    "ProvenanceResearch": true
  },
  "Artifacts": {
    "PlainText": "${MULTI_REPOSITORY_A}/review.txt",
    "Markdown": "${MULTI_REPOSITORY_A}/review.md",
    "Html": "${MULTI_REPOSITORY_A}/review.html",
    "State": "${MULTI_REPOSITORY_A}/state.json"
  }
}
EOF

cat > "${MULTI_REPOSITORY_B}/review.txt" <<'EOF'
Repository review did not complete.
EOF

cat > "${MULTI_REPOSITORY_B}/review.md" <<'EOF'
# Synthetic failed review
EOF

cat > "${MULTI_REPOSITORY_B}/review.html" <<'EOF'
<!doctype html><title>Synthetic failed review</title>
EOF

cat > "${MULTI_REPOSITORY_B}/state.json" <<EOF
{
  "SchemaVersion": 6,
  "Harness": "copilot",
  "Model": "gpt-5.6-sol",
  "ReasoningEffort": "max",
  "ContextTier": "long_context",
  "Slug": "github--owner--three",
  "Repository": "https://github.com/owner/three",
  "Source": {
    "Kind": "RemoteUrl",
    "RemoteUrl": "https://github.com/owner/three"
  },
  "Commit": "3333333333333333333333333333333333333333",
  "Status": "Failed",
  "StartedAt": "2026-10-09T15:02:00Z",
  "CompletedAt": "2026-10-09T15:04:00Z",
  "Scope": {
    "Name": "3 - Full review, public research, and whole-repository provenance",
    "PublicResearch": true,
    "ProvenanceResearch": true
  },
  "Artifacts": {
    "PlainText": "${MULTI_REPOSITORY_B}/review.txt",
    "Markdown": "${MULTI_REPOSITORY_B}/review.md",
    "Html": "${MULTI_REPOSITORY_B}/review.html",
    "State": "${MULTI_REPOSITORY_B}/state.json"
  }
}
EOF

cat > "${MULTI_RUN}/state.json" <<EOF
{
  "SchemaVersion": 6,
  "RunId": "run-multi",
  "Status": "Partial",
  "Harness": "copilot",
  "Model": "claude-opus-5.5",
  "ReasoningEffort": "max",
  "ContextTier": "long_context",
  "StartedAt": "2026-10-09T15:00:00Z",
  "CompletedAt": "2026-10-09T15:20:00Z",
  "Scope": {
    "Name": "3 - Full review, public research, and whole-repository provenance",
    "PublicResearch": true,
    "ProvenanceResearch": true
  },
  "Repositories": [
    {
      "Repository": "https://github.com/owner/two",
      "Status": "Completed",
      "State": "${MULTI_REPOSITORY_A}/state.json"
    },
    {
      "Repository": "https://github.com/owner/three",
      "Status": "Failed",
      "State": "${MULTI_REPOSITORY_B}/state.json"
    }
  ]
}
EOF

{
    printf '[\n'
    cat -- "${MULTI_REPOSITORY_A}/state.json"
    printf ',\n'
    cat -- "${MULTI_REPOSITORY_B}/state.json"
    printf '\n]\n'
} > "${MULTI_RUN}/manifest.json"

json_summary="${FIXTURE_ROOT}/summary.json"
"${SUMMARY}" --output-root "${OUTPUT_ROOT}" --format json > "${json_summary}"

python3 - "${json_summary}" "${OUTPUT_ROOT}" <<'PY'
import json
import pathlib
import sys

summary_path = pathlib.Path(sys.argv[1])
output_root = str(pathlib.Path(sys.argv[2]).resolve())
data = json.loads(summary_path.read_text(encoding="utf-8"))

assert data["schema_version"] == 1
assert data["summary_id"].startswith("summary-")
assert data["current_date"]
assert data["generated_at"].endswith("Z")
assert data["host"]["hostname"]
assert data["source"]["rhyolite_output_root"] == output_root
assert data["output"] == {"format": "json", "path": None}
assert data["inventory"]["run_count"] == 2
assert data["inventory"]["review_count"] == 3
assert data["inventory"]["run_kinds"] == {
    "multi-repository": 1,
    "single-repository": 1,
}
assert data["inventory"]["review_statuses"] == {
    "Completed": 2,
    "Failed": 1,
}
assert data["rhyolite_versions"]["recorded_for_reviews"] == ["0.8.1", "0.8.0"]
assert data["rhyolite_versions"]["reviews_without_recorded_version"] == 1

reviews = {review["review_id"]: review for review in data["reviews"]}
one = reviews["run-single/github--owner--one"]
assert one["source_repository"] == "https://github.com/owner/one"
assert one["scope"]["number"] == 1
assert [model["id"] for model in one["models"]] == ["gpt-5.6-sol"]
assert one["overall_grading"]["value"] == (
    "Suitable for limited use | with the documented controls."
)
assert one["overall_grading"]["source"] == "overall-assessment-first-sentence"
assert one["overall_grading"]["confidence_levels"] == ["High"]
assert one["paths"]["reports"]["plain_text"]["path"] == (
    "repo-review/run-single/github--owner--one/review.txt"
)

two = reviews["run-multi/github--owner--two"]
assert two["overall_grading"]["value"] == "<strong>Conditional pass</strong>"
assert two["overall_grading"]["source"] == "explicit-grade-or-verdict-field"
assert two["overall_grading"]["confidence_levels"] == ["Medium", "Low"]
assert two["scope"]["number"] == 3

three = reviews["run-multi/github--owner--three"]
assert [model["id"] for model in three["models"]] == [
    "gpt-5.6-sol",
    "claude-opus-5.5",
]
assert three["overall_grading"]["value"] is None
assert three["overall_grading"]["confidence"] == []

absolute_strings = []

def walk(value, path=()):
    if isinstance(value, dict):
        for key, child in value.items():
            walk(child, path + (key,))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            walk(child, path + (str(index),))
    elif isinstance(value, str) and value.startswith("/"):
        absolute_strings.append((path, value))

walk(data)
assert absolute_strings == [
    (("source", "rhyolite_output_root"), output_root)
], absolute_strings
PY

single_summary="${FIXTURE_ROOT}/single.json"
"${SUMMARY}" "${SINGLE_RUN}" --format json > "${single_summary}"
python3 - "${single_summary}" "${SINGLE_RUN}" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert data["source"]["rhyolite_output_root"] == str(pathlib.Path(sys.argv[2]).resolve())
assert data["inventory"]["run_count"] == 1
assert data["inventory"]["review_count"] == 1
assert data["runs"][0]["kind"] == "single-repository"
PY

repository_summary="${FIXTURE_ROOT}/repository.json"
"${SUMMARY}" "${SINGLE_REPOSITORY}" --format json > "${repository_summary}"
python3 - "${repository_summary}" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert data["inventory"]["run_count"] == 1
assert data["inventory"]["review_count"] == 1
assert data["runs"][0]["kind"] == "single-repository"
assert data["reviews"][0]["paths"]["reports"]["plain_text"]["path"] == "review.txt"
PY

markdown_summary="${FIXTURE_ROOT}/summary.md"
"${SUMMARY}" "${OUTPUT_ROOT}" --format md > "${markdown_summary}"
assert_contains "${markdown_summary}" \
    '| Review ID | Source repository | Model(s) | Scope | Overall grading | Status |' \
    'Markdown summary table'
[[ "$(grep -c '^---$' "${markdown_summary}")" -eq 2 ]] ||
    fail 'Markdown summary does not contain two horizontal separators.'
if grep -Fq 'Confidence' "${markdown_summary}"; then
    fail 'Markdown summary still exposes confidence levels.'
fi
assert_contains "${markdown_summary}" \
    'Suitable for limited use \| with the documented controls.' \
    'Markdown table escaping'
assert_contains "${markdown_summary}" \
    '&lt;strong&gt;Conditional pass&lt;/strong&gt;' \
    'Markdown HTML escaping'
if grep -Fq '<strong>Conditional pass</strong>' "${markdown_summary}"; then
    fail 'Markdown summary retained unescaped review HTML.'
fi

text_summary="${FIXTURE_ROOT}/summary.txt"
"${SUMMARY}" "${OUTPUT_ROOT}" --format text > "${text_summary}"
assert_contains "${text_summary}" \
    'RHYOLITE REVIEW SUMMARY' \
    'Text summary heading'
assert_contains "${text_summary}" \
    'run-multi/github--owner--two' \
    'Text summary multi-repository row'
[[ "$(grep -Ec '^={40,}$' "${text_summary}")" -eq 2 ]] ||
    fail 'Text summary does not contain two horizontal separators.'
if grep -Fq 'Confidence' "${text_summary}"; then
    fail 'Text summary still exposes confidence levels.'
fi

html_summary="${FIXTURE_ROOT}/summary.html"
"${SUMMARY}" "${OUTPUT_ROOT}" --format html > "${html_summary}"
assert_contains "${html_summary}" \
    "default-src 'none'" \
    'HTML summary CSP'
assert_contains "${html_summary}" \
    '&lt;strong&gt;Conditional pass&lt;/strong&gt;' \
    'HTML summary escaping'
[[ "$(grep -o '<hr>' "${html_summary}" | wc -l)" -eq 2 ]] ||
    fail 'HTML summary does not contain two horizontal separators.'
if grep -Fq '>Confidence<' "${html_summary}"; then
    fail 'HTML summary still exposes a confidence column.'
fi
if grep -Fq '<strong>Conditional pass</strong>' "${html_summary}"; then
    fail 'HTML summary rendered unescaped review content.'
fi

written_path="$(
    "${SUMMARY}" "${OUTPUT_ROOT}" --format md --write-file
)"
[[ "${written_path}" == "${OUTPUT_ROOT}/summaries/"*.md ]] ||
    fail 'Default file output was not placed under rhyolite-output/summaries.'
[[ -f "${written_path}" ]] ||
    fail 'Default file output was not created.'
[[ "$(stat -c '%a' "${written_path}")" == 600 ]] ||
    fail 'Default file output permissions are not 0600.'

explicit_path="$(
    "${SUMMARY}" "${OUTPUT_ROOT}" \
        --format json \
        --output summaries/fixed-summary.json
)"
[[ "${explicit_path}" == "${OUTPUT_ROOT}/summaries/fixed-summary.json" ]] ||
    fail 'Relative explicit output did not resolve under the selected root.'
python3 - "${explicit_path}" <<'PY'
import json
import pathlib
import sys

data = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert data["output"] == {
    "format": "json",
    "path": "summaries/fixed-summary.json",
}
PY

if "${SUMMARY}" "${OUTPUT_ROOT}" \
    --format json \
    --output summaries/fixed-summary.json \
    > "${FIXTURE_ROOT}/replace.stdout" \
    2> "${FIXTURE_ROOT}/replace.stderr"; then
    fail 'Existing explicit output was replaced without --force.'
fi
assert_contains "${FIXTURE_ROOT}/replace.stderr" \
    'already exists' \
    'Existing-output diagnostic'
"${SUMMARY}" "${OUTPUT_ROOT}" \
    --format json \
    --output summaries/fixed-summary.json \
    --force > /dev/null

mkdir -- "${FIXTURE_ROOT}/empty"
if "${SUMMARY}" "${FIXTURE_ROOT}/empty" \
    --format json \
    > "${FIXTURE_ROOT}/empty.stdout" \
    2> "${FIXTURE_ROOT}/empty.stderr"; then
    fail 'Empty output directory unexpectedly produced a summary.'
fi
assert_contains "${FIXTURE_ROOT}/empty.stderr" \
    'No Rhyolite run or repository state was found.' \
    'Empty-directory diagnostic'

mkdir -- "${FIXTURE_ROOT}/no-candidate"
if (
    cd -- "${FIXTURE_ROOT}/no-candidate" &&
        "${SUMMARY}" --non-interactive \
            > "${FIXTURE_ROOT}/noninteractive.stdout" \
            2> "${FIXTURE_ROOT}/noninteractive.stderr"
); then
    fail 'Non-interactive invocation without a root unexpectedly succeeded.'
fi
assert_contains "${FIXTURE_ROOT}/noninteractive.stderr" \
    'Pass --output-root PATH' \
    'Non-interactive missing-root diagnostic'

python3 - "${SUMMARY}" "$(dirname -- "${OUTPUT_ROOT}")" <<'PY'
import errno
import os
import pathlib
import pty
import select
import subprocess
import sys
import time

summary, working_directory = sys.argv[1:]
master, slave = pty.openpty()
process = subprocess.Popen(
    [summary],
    cwd=working_directory,
    stdin=slave,
    stdout=slave,
    stderr=slave,
    close_fds=True,
)
os.close(slave)
output = bytearray()
selection_sent = False
deadline = time.monotonic() + 15

while time.monotonic() < deadline:
    readable, _, _ = select.select([master], [], [], 0.1)
    if readable:
        try:
            chunk = os.read(master, 65536)
        except OSError as error:
            if error.errno == errno.EIO:
                break
            raise
        if not chunk:
            break
        output.extend(chunk)
        if not selection_sent and b"Selection [1]:" in output:
            os.write(master, b"\n")
            selection_sent = True
    if process.poll() is not None and not readable:
        break

if process.poll() is None:
    process.kill()
    process.wait()
    raise SystemExit("interactive default-selection test timed out")
status = process.wait()
os.close(master)
text = output.decode("utf-8", errors="replace")
if status != 0:
    raise SystemExit(f"interactive default selection failed ({status}): {text}")
if not selection_sent:
    raise SystemExit("interactive default-selection prompt was not observed")
if '"review_count": 3' not in text:
    raise SystemExit("bare Enter did not select the first discovered output root")
PY

expected_version="$(tr -d '\r\n' < "${ROOT}/VERSION")"
root_version="$("${ROOT_SUMMARY}" --version)"
[[ "${root_version}" == \
    "Rhyolite review summary utility v${expected_version} (schema 1)" ]] ||
    fail 'Repository-root summary wrapper did not delegate version output.'

printf 'Review summary utility tests passed.\n'
