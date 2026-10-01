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
            gsub(bel, "")
            print
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

extract_final_copilot_report() {
    local transcript="$1"
    local report="$2"
    local final_message="${report}.final-message"
    local extraction_status=0

    if ! awk '
        { lines[NR] = $0 }
        END {
            start = 0
            for (i = 1; i <= NR; i++) {
                marker = lines[i]
                sub(/^[[:space:]]+/, "", marker)
                sub(/[[:space:]]+$/, "", marker)
                if (marker == "### Copilot") {
                    start = i + 1
                }
            }
            if (start == 0) {
                exit 42
            }
            for (i = start; i <= NR; i++) {
                print lines[i]
            }
        }
    ' "${transcript}" > "${final_message}"; then
        rm -f -- "${final_message}"
        return 42
    fi

    extract_report "${final_message}" "${report}" || extraction_status=$?
    rm -f -- "${final_message}"
    return "${extraction_status}"
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

write_markdown_report() {
    local report="$1"
    local markdown="$2"

    {
        printf '# Repository Review Report\n\n'
        sed 's/^/    /' "${report}"
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
    local encoded_repository encoded_commit encoded_status

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
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<title>Repository Review Report</title>
<style>
:root { color-scheme: light dark; }
body { margin: 0; font-family: system-ui, sans-serif; line-height: 1.45; }
main { max-width: 1000px; margin: 0 auto; padding: 2rem; }
h1 { margin-top: 0; }
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
        printf '<dl><dt>Repository</dt><dd>%s</dd>' "${encoded_repository}"
        printf '<dt>Commit</dt><dd>%s</dd>' "${encoded_commit}"
        printf '<dt>Status</dt><dd>%s</dd></dl>\n' "${encoded_status}"
        printf '<pre>'
        html_escape_file "${report}"
        printf '</pre>\n</main>\n</body>\n</html>\n'
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
    local continuation

    if [[ -n "${session_id}" ]]; then
        continuation="The saved Copilot session ID is \`${session_id}\`. Do not invoke \`copilot --resume\` directly: a direct resume does not reliably restore this review's path, tool, network, and environment restrictions. Start the \`repository-review\` agent and provide this handoff path so a trusted runner can establish a restricted continuation."
    else
        continuation='Setup did not reach a child Copilot session. Rerun `repository-review` using the repository URL, requested commit, scope, and output choices recorded in `state.json`. Do not analyze the verification clone directly.'
    fi

    {
        printf '# Repository review handoff\n\n'
        printf 'Repository:\n\n    %s\n\n' "${repository}"
        printf 'Source kind:\n\n    %s\n\n' "${source_kind}"
        printf 'Selected source path:\n\n    %s\n\n' "${source_path}"
        printf 'Commit:\n\n    %s\n\n' "${commit}"
        printf 'Status:\n\n    %s\n\n' "${status}"
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
        printf 'Copilot session:\n\n    %s\n\n' "${session}"
        printf 'Copilot session ID:\n\n    %s\n\n' "${session_id}"
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
