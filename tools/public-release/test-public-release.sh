#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "${SCRIPT_DIR}/../.." && pwd)"
REAL_BASH="$(command -v bash)"
REAL_NODE="$(command -v node)"
REAL_GIT="$(command -v git)"
REAL_TAR="$(command -v tar)"
REAL_DIRNAME="$(command -v dirname)"
WORK_ROOT="$(cd -- "${ROOT}/.." && pwd)/rhyolite-public-release-test-work"
SANDBOX="${WORK_ROOT}/sandbox"
TREES_ROOT="${WORK_ROOT}/trees"
REPORTS_ROOT="${WORK_ROOT}/reports"
FAILED_PARENT="${WORK_ROOT}/failed-parent"
FAILED_DEST="${FAILED_PARENT}/export-destination"
FAKE_BIN="${WORK_ROOT}/fake-bin"
PRIVATE_DENY_SOURCE="${ROOT}/tools/public-release/private-deny-patterns.json"
PRIVATE_DENY_SANDBOX="${SANDBOX}/tools/public-release/private-deny-patterns.json"
VALIDATION_FULL_BIN="${WORK_ROOT}/validation-full-bin"
VALIDATION_BASH_ONLY_BIN="${WORK_ROOT}/validation-bash-only-bin"
VALIDATION_NO_BASH_BIN="${WORK_ROOT}/validation-no-bash-bin"
VALIDATION_LOG="${REPORTS_ROOT}/validation.log"

cleanup() {
    rm -rf -- "${WORK_ROOT}"
}
trap cleanup EXIT

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

join_runtime_fragments() {
    local fragment
    for fragment in "$@"; do
        printf '%s' "${fragment}"
    done
}

expect_failure() {
    local output_path="$1"
    shift
    set +e
    "$@" >"${output_path}" 2>&1
    local status=$?
    set -e
    if [[ "${status}" -eq 0 ]]; then
        cat "${output_path}" >&2
        fail "Expected command to fail: $*"
    fi
}

expect_success() {
    local output_path="$1"
    shift
    if ! "$@" >"${output_path}" 2>&1; then
        cat "${output_path}" >&2
        fail "Expected command to succeed: $*"
    fi
}

require_grep() {
    local pattern="$1"
    local file="$2"
    grep -Fq -- "${pattern}" "${file}" || {
        cat "${file}" >&2
        fail "Missing pattern in ${file}: ${pattern}"
    }
}

reject_grep() {
    local pattern="$1"
    local file="$2"
    if grep -Fq -- "${pattern}" "${file}"; then
        cat "${file}" >&2
        fail "Unexpected pattern in ${file}: ${pattern}"
    fi
}

commit_all() {
    local repo_path="$1"
    local message="$2"
    local sandbox_email
    sandbox_email="$(build_nonpublic_email_fixture)"
    git -C "${repo_path}" add .
    git -C "${repo_path}" \
        -c user.name='Sandbox' \
        -c user.email="${sandbox_email}" \
        commit -qm "${message}"
}

run_in_directory() {
    local working_directory="$1"
    shift
    (
        cd -- "${working_directory}"
        "$@"
    )
}

build_nonpublic_email_fixture() {
    join_runtime_fragments 'sandbox' '@' 'example' '.' 'invalid'
}

build_dev_azure_host_fixture() {
    join_runtime_fragments 'dev' '.az' 'ure.com/' 'org/project'
}

build_dev_azure_https_fixture() {
    join_runtime_fragments 'https://' "$(build_dev_azure_host_fixture)"
}

build_visualstudio_host_fixture() {
    join_runtime_fragments 'example' '.visual' 'studio.com/' 'project'
}

build_visualstudio_https_fixture() {
    join_runtime_fragments 'https://' "$(build_visualstudio_host_fixture)"
}

build_public_github_host_fixture() {
    join_runtime_fragments 'github.com/' 'octocat/Hello-World'
}

build_public_github_https_fixture() {
    join_runtime_fragments 'https://' "$(build_public_github_host_fixture)"
}

build_public_placeholder_fixture() {
    local suffix="${1:-TOKEN}"
    join_runtime_fragments '<' 'PUBLIC_' "${suffix}" '>'
}

write_private_url_fixture_file() {
    local target_path="$1"
    cat > "${target_path}" <<EOF_URLS
$(build_dev_azure_https_fixture)
$(build_dev_azure_host_fixture)
$(build_visualstudio_https_fixture)
$(build_visualstudio_host_fixture)
$(build_public_github_https_fixture)
$(build_public_github_host_fixture)
EOF_URLS
}

prepare_source_repository() {
    local repo_path="$1"
    rm -rf -- "${repo_path}"
    mkdir -p -- "${repo_path}" "${repo_path}/tools"
    git -C "${ROOT}" archive --format=tar HEAD | tar -xf - -C "${repo_path}"
    rm -rf -- "${repo_path}/tools/public-release"
    cp -R -- "${ROOT}/tools/public-release" "${repo_path}/tools/"
    git -C "${repo_path}" init -q
    commit_all "${repo_path}" 'sandbox'
}

ensure_release_gate_files() {
    local target_path="$1"
    mkdir -p -- "${target_path}/.github"
    [[ -f "${target_path}/CODE_OF_CONDUCT.md" ]] || printf 'Public code of conduct\n' > "${target_path}/CODE_OF_CONDUCT.md"
    [[ -f "${target_path}/SUPPORT.md" ]] || printf 'Public support guidance\n' > "${target_path}/SUPPORT.md"
    [[ -f "${target_path}/LICENSE" ]] || printf 'Sample public license terms.\n' > "${target_path}/LICENSE"
    [[ -f "${target_path}/.github/CODEOWNERS" ]] || printf '* @public-owner\n' > "${target_path}/.github/CODEOWNERS"
}

write_mock_validator_scripts() {
    local target_path="$1"
    mkdir -p -- "${target_path}/tests"
    cat <<EOF_SH > "${target_path}/tests/validate-plugin.sh"
#!${REAL_BASH}
set -euo pipefail
if [[ -n "\${PUBLIC_RELEASE_VALIDATION_LOG:-}" ]]; then
    printf 'validator-script-sh %s\n' "\$PWD" >> "\${PUBLIC_RELEASE_VALIDATION_LOG}"
fi
if [[ -n "\${MOCK_VALIDATE_BASH_OUTPUT:-}" ]]; then
    printf '%s\n' "\${MOCK_VALIDATE_BASH_OUTPUT}" >&2
fi
exit "\${MOCK_VALIDATE_BASH_EXIT:-0}"
EOF_SH
    chmod +x "${target_path}/tests/validate-plugin.sh"

    cat <<'EOF_PS1' > "${target_path}/tests/validate-plugin.ps1"
[CmdletBinding()]
param()

if ($env:MOCK_VALIDATE_PWSH_OUTPUT) {
    Write-Error $env:MOCK_VALIDATE_PWSH_OUTPUT
}

$exitCode = 0
if ($env:MOCK_VALIDATE_PWSH_EXIT) {
    $parsed = 0
    if ([int]::TryParse($env:MOCK_VALIDATE_PWSH_EXIT, [ref] $parsed)) {
        $exitCode = $parsed
    }
}

exit $exitCode
EOF_PS1
}

prepare_validation_tree() {
    local tree_path="$1"
    rm -rf -- "${tree_path}"
    mkdir -p -- "${tree_path}"
    git -C "${SANDBOX}" archive --format=tar HEAD | tar -xf - -C "${tree_path}"
    ensure_release_gate_files "${tree_path}"
    write_mock_validator_scripts "${tree_path}"
}

prepare_clean_release_source_repository() {
    local repo_path="$1"
    rm -rf -- "${repo_path}"
    mkdir -p -- \
        "${repo_path}/tools" \
        "${repo_path}/.github/workflows" \
        "${repo_path}/.github/plugin" \
        "${repo_path}/plugins/demo"
    cp -R -- "${ROOT}/tools/public-release" "${repo_path}/tools/"

    cat <<'EOF_README' > "${repo_path}/README.md"
Public release overview.
EOF_README
    cat <<'EOF_CONTRIBUTING' > "${repo_path}/CONTRIBUTING.md"
Public contribution guidance.
EOF_CONTRIBUTING
    cat <<'EOF_SECURITY' > "${repo_path}/SECURITY.md"
Public security reporting guidance.
EOF_SECURITY
    cat <<'EOF_PRIVACY' > "${repo_path}/PRIVACY.md"
Public privacy guidance.
EOF_PRIVACY
    cat <<'EOF_VERSION' > "${repo_path}/VERSION"
1.0.0
EOF_VERSION
    cat <<'EOF_CHANGELOG' > "${repo_path}/CHANGELOG.md"
# Changelog

- Initial public release.
EOF_CHANGELOG
    cat <<'EOF_LAUNCHER' > "${repo_path}/rhyolite"
#!/usr/bin/env bash
printf 'public checkout launcher\n'
EOF_LAUNCHER
    chmod +x "${repo_path}/rhyolite"
    cat <<'EOF_PLUGIN' > "${repo_path}/plugins/demo/plugin.json"
{
  "name": "public-demo",
  "displayName": "Public Demo Plugin",
  "version": "1.0.0"
}
EOF_PLUGIN
    cat <<'EOF_MARKETPLACE' > "${repo_path}/.github/plugin/marketplace.json"
{
  "plugins": [
    "public-demo"
  ]
}
EOF_MARKETPLACE
    cat <<'EOF_WORKFLOW' > "${repo_path}/.github/workflows/release.yml"
name: release
on:
  workflow_dispatch:
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - run: echo public release validation
EOF_WORKFLOW

    ensure_release_gate_files "${repo_path}"
    write_mock_validator_scripts "${repo_path}"

    if [[ -f "${repo_path}/tools/public-release/private-deny-patterns.json" ]]; then
        printf 'tools/public-release/private-deny-patterns.json export-ignore\n' > "${repo_path}/.gitattributes"
    fi

    git -C "${repo_path}" init -q
    commit_all "${repo_path}" 'clean-release'
}

prepare_clean_release_tree() {
    local source_repo_path="$1"
    local tree_path="$2"
    rm -rf -- "${tree_path}"
    mkdir -p -- "${tree_path}"
    git -C "${source_repo_path}" archive --format=tar HEAD | tar -xf - -C "${tree_path}"
}

write_validation_runtime_bins() {
    rm -rf -- "${VALIDATION_FULL_BIN}" "${VALIDATION_BASH_ONLY_BIN}" "${VALIDATION_NO_BASH_BIN}"
    mkdir -p -- "${VALIDATION_FULL_BIN}" "${VALIDATION_BASH_ONLY_BIN}" "${VALIDATION_NO_BASH_BIN}"

    for bin_path in \
        "${VALIDATION_FULL_BIN}" \
        "${VALIDATION_BASH_ONLY_BIN}" \
        "${VALIDATION_NO_BASH_BIN}"; do
        ln -s "${REAL_NODE}" "${bin_path}/node"
        ln -s "${REAL_GIT}" "${bin_path}/git"
        ln -s "${REAL_TAR}" "${bin_path}/tar"
        ln -s "${REAL_DIRNAME}" "${bin_path}/dirname"
    done

    cat <<EOF_BASH > "${VALIDATION_FULL_BIN}/bash"
#!${REAL_BASH}
set -euo pipefail
if [[ -n "\${PUBLIC_RELEASE_VALIDATION_LOG:-}" ]]; then
    printf 'bash %s\n' "\$*" >> "\${PUBLIC_RELEASE_VALIDATION_LOG}"
fi
exec "${REAL_BASH}" "\$@"
EOF_BASH
    chmod +x "${VALIDATION_FULL_BIN}/bash"
    cp -- "${VALIDATION_FULL_BIN}/bash" "${VALIDATION_BASH_ONLY_BIN}/bash"

    cat <<EOF_PWSH > "${VALIDATION_FULL_BIN}/pwsh"
#!${REAL_BASH}
set -euo pipefail
if [[ -n "\${PUBLIC_RELEASE_VALIDATION_LOG:-}" ]]; then
    printf 'pwsh %s\n' "\$*" >> "\${PUBLIC_RELEASE_VALIDATION_LOG}"
fi
if [[ -n "\${MOCK_VALIDATE_PWSH_OUTPUT:-}" ]]; then
    printf '%s\n' "\${MOCK_VALIDATE_PWSH_OUTPUT}" >&2
fi
exit "\${MOCK_VALIDATE_PWSH_EXIT:-0}"
EOF_PWSH
    chmod +x "${VALIDATION_FULL_BIN}/pwsh"
    cp -- "${VALIDATION_FULL_BIN}/pwsh" "${VALIDATION_NO_BASH_BIN}/pwsh"
}

assert_public_tool_has_no_private_literals() {
    [[ -f "${PRIVATE_DENY_SOURCE}" ]] || return 0

    mapfile -t private_literals < <(node - <<'EOF_NODE' "${PRIVATE_DENY_SOURCE}"
const fs = require('fs');
const doc = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
for (const section of ['path', 'content']) {
  for (const entry of doc[section] ?? []) {
    for (const literal of entry.testLiterals ?? []) {
      console.log(String(literal));
    }
  }
}
EOF_NODE
)

    for literal in "${private_literals[@]}"; do
        [[ -n "${literal}" ]] || continue
        if grep -R -F --exclude='private-deny-patterns.json' -- "${literal}" "${ROOT}/tools/public-release" >/dev/null; then
            fail "Public tool files still contain a private literal from the private deny overlay."
        fi
    done
}

assert_public_tool_has_no_private_literals
write_validation_runtime_bins
mkdir -p -- "${WORK_ROOT}" "${TREES_ROOT}" "${REPORTS_ROOT}" "${FAILED_PARENT}" "${FAKE_BIN}"
prepare_source_repository "${SANDBOX}"
rm -f -- "${PRIVATE_DENY_SANDBOX}"
commit_all "${SANDBOX}" 'public-sandbox'
SANDBOX_COMMIT="$(git -C "${SANDBOX}" rev-parse HEAD)"
CLEAN_RELEASE_SOURCE="${WORK_ROOT}/clean-release-source"
prepare_clean_release_source_repository "${CLEAN_RELEASE_SOURCE}"
CLEAN_RELEASE_COMMIT="$(git -C "${CLEAN_RELEASE_SOURCE}" rev-parse HEAD)"

# Symlink rejection: symlinks must be findings and must not satisfy required files.
SYMLINK_TREE="${TREES_ROOT}/symlink-tree"
mkdir -p -- "${SYMLINK_TREE}"
git -C "${SANDBOX}" archive --format=tar HEAD | tar -xf - -C "${SYMLINK_TREE}"
rm -f -- "${SYMLINK_TREE}/README.md"
ln -s CHANGELOG.md "${SYMLINK_TREE}/README.md"
expect_failure "${REPORTS_ROOT}/symlink.stdout.txt" \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${SYMLINK_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --skip-validation \
    --audit-report "${REPORTS_ROOT}/symlink.audit.txt"
require_grep '[symlink|symlink-entry] README.md Symbolic links are not allowed in exported trees.' \
    "${REPORTS_ROOT}/symlink.audit.txt"
require_grep '[required|required-readme] Missing required public file: README.' \
    "${REPORTS_ROOT}/symlink.audit.txt"

# Source-private deny overlay loads automatically and merges with --deny-file rules.
PRIVATE_TREE="${TREES_ROOT}/private-overlay-tree"
PRIVATE_USER_DENY="${REPORTS_ROOT}/private-overlay-user-deny.json"
PRIVATE_ALLOWLIST="${REPORTS_ROOT}/private-overlay-allowlist.json"
mkdir -p -- "${PRIVATE_TREE}"
git -C "${SANDBOX}" archive --format=tar HEAD | tar -xf - -C "${PRIVATE_TREE}"
mkdir -p -- "${PRIVATE_TREE}/docs"
cat <<'PRIVATE_TEXT' > "${PRIVATE_TREE}/docs/merged-deny.txt"
AUTO-PRIVATE-DENY-MARKER
USER-DENY-MARKER
PRIVATE_TEXT
cat <<'PRIVATE_OVERLAY' > "${PRIVATE_DENY_SANDBOX}"
{
  "content": [
    {
      "id": "content-auto-private-overlay",
      "pattern": "AUTO-PRIVATE-DENY-MARKER",
      "description": "Reject auto-loaded private overlay marker."
    }
  ]
}
PRIVATE_OVERLAY
cat <<'PRIVATE_USER_RULES' > "${PRIVATE_USER_DENY}"
{
  "content": [
    {
      "id": "content-user-deny-marker",
      "pattern": "USER-DENY-MARKER",
      "description": "Reject user-supplied deny marker."
    }
  ]
}
PRIVATE_USER_RULES
expect_failure "${REPORTS_ROOT}/private-overlay.stdout.txt" \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${PRIVATE_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --skip-validation \
    --deny-file "${PRIVATE_USER_DENY}" \
    --audit-report "${REPORTS_ROOT}/private-overlay.audit.txt"
require_grep '[content|content-auto-private-overlay] docs/merged-deny.txt:1:1 match_hash=' \
    "${REPORTS_ROOT}/private-overlay.audit.txt"
require_grep '[content|content-user-deny-marker] docs/merged-deny.txt:2:1 match_hash=' \
    "${REPORTS_ROOT}/private-overlay.audit.txt"
PRIVATE_OVERLAY_HASH="$(node - <<'EOF_NODE' "${REPORTS_ROOT}/private-overlay.audit.txt"
const fs = require('fs');
const report = fs.readFileSync(process.argv[2], 'utf8');
const match = report.match(/\[content\|content-auto-private-overlay\] docs\/merged-deny\.txt:1:1 match_hash=([0-9a-f]+)/);
if (!match) {
  throw new Error('Expected private overlay finding.');
}
console.log(match[1]);
EOF_NODE
)"
cat <<EOF_PRIVATE_ALLOWLIST > "${PRIVATE_ALLOWLIST}"
{
  "entries": [
    {
      "kind": "content",
      "path": "docs/merged-deny.txt",
      "ruleId": "content-auto-private-overlay",
      "line": 1,
      "matchHash": "${PRIVATE_OVERLAY_HASH}",
      "reviewedBy": "release-reviewer",
      "reason": "Attempting to waive a hard private overlay rule."
    }
  ]
}
EOF_PRIVATE_ALLOWLIST
expect_failure "${REPORTS_ROOT}/private-overlay-allowlist.stdout.txt" \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${PRIVATE_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --skip-validation \
    --deny-file "${PRIVATE_USER_DENY}" \
    --allowlist-file "${PRIVATE_ALLOWLIST}" \
    --audit-report "${REPORTS_ROOT}/private-overlay-allowlist.audit.txt"
require_grep "[content|content-auto-private-overlay] docs/merged-deny.txt:1:1 match_hash=${PRIVATE_OVERLAY_HASH} Reject auto-loaded private overlay marker." \
    "${REPORTS_ROOT}/private-overlay-allowlist.audit.txt"
require_grep "[content|content-auto-private-overlay] docs/merged-deny.txt:1 match_hash=${PRIVATE_OVERLAY_HASH} reviewedBy=release-reviewer" \
    "${REPORTS_ROOT}/private-overlay-allowlist.audit.txt"
rm -f -- "${PRIVATE_DENY_SANDBOX}"

# Generic private URL detection must catch Azure DevOps-style URLs without
# flagging ordinary public repository URLs.
URL_TREE="${TREES_ROOT}/url-tree"
URL_ALLOWLIST="${REPORTS_ROOT}/url-allowlist.json"
mkdir -p -- "${URL_TREE}"
git -C "${SANDBOX}" archive --format=tar HEAD | tar -xf - -C "${URL_TREE}"
mkdir -p -- "${URL_TREE}/docs"
write_private_url_fixture_file "${URL_TREE}/docs/url-patterns.txt"
expect_failure "${REPORTS_ROOT}/url-patterns.stdout.txt" \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${URL_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --skip-validation \
    --audit-report "${REPORTS_ROOT}/url-patterns.audit.txt"
require_grep '[content|content-private-repository-url] docs/url-patterns.txt:1:1 match_hash=' \
    "${REPORTS_ROOT}/url-patterns.audit.txt"
require_grep '[content|content-private-repository-url] docs/url-patterns.txt:2:1 match_hash=' \
    "${REPORTS_ROOT}/url-patterns.audit.txt"
require_grep '[content|content-private-repository-url] docs/url-patterns.txt:3:1 match_hash=' \
    "${REPORTS_ROOT}/url-patterns.audit.txt"
require_grep '[content|content-private-repository-url] docs/url-patterns.txt:4:1 match_hash=' \
    "${REPORTS_ROOT}/url-patterns.audit.txt"
reject_grep '[content|content-private-repository-url] docs/url-patterns.txt:5:1 match_hash=' \
    "${REPORTS_ROOT}/url-patterns.audit.txt"
reject_grep '[content|content-private-repository-url] docs/url-patterns.txt:6:1 match_hash=' \
    "${REPORTS_ROOT}/url-patterns.audit.txt"
URL_PRIVATE_HASH="$(node - <<'EOF_NODE' "${REPORTS_ROOT}/url-patterns.audit.txt"
const fs = require('fs');
const report = fs.readFileSync(process.argv[2], 'utf8');
const match = report.match(/\[content\|content-private-repository-url\] docs\/url-patterns\.txt:1:1 match_hash=([0-9a-f]+)/);
if (!match) {
  throw new Error('Expected hard private URL finding.');
}
console.log(match[1]);
EOF_NODE
)"
cat <<EOF_URL_ALLOWLIST > "${URL_ALLOWLIST}"
{
  "entries": [
    {
      "kind": "content",
      "path": "docs/url-patterns.txt",
      "ruleId": "content-private-repository-url",
      "line": 1,
      "matchHash": "${URL_PRIVATE_HASH}",
      "reviewedBy": "release-reviewer",
      "reason": "Attempting to waive a hard private URL rule."
    }
  ]
}
EOF_URL_ALLOWLIST
expect_failure "${REPORTS_ROOT}/url-allowlist.stdout.txt" \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${URL_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --skip-validation \
    --allowlist-file "${URL_ALLOWLIST}" \
    --audit-report "${REPORTS_ROOT}/url-allowlist.audit.txt"
require_grep "[content|content-private-repository-url] docs/url-patterns.txt:1:1 match_hash=${URL_PRIVATE_HASH} Likely private repository references must not appear in exported content." \
    "${REPORTS_ROOT}/url-allowlist.audit.txt"
require_grep "[content|content-private-repository-url] docs/url-patterns.txt:1 match_hash=${URL_PRIVATE_HASH} reviewedBy=release-reviewer" \
    "${REPORTS_ROOT}/url-allowlist.audit.txt"

# Preflight must be self-contained for standalone exported trees with no source
# Git repo.
STANDALONE_PREFLIGHT_TREE="${TREES_ROOT}/standalone-preflight-tree"
prepare_validation_tree "${STANDALONE_PREFLIGHT_TREE}"
: > "${VALIDATION_LOG}"
expect_success "${REPORTS_ROOT}/standalone-preflight.stdout.txt" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "${STANDALONE_PREFLIGHT_TREE}/tools/public-release/public-preflight.sh" \
    --destination "${STANDALONE_PREFLIGHT_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --audit-report "${REPORTS_ROOT}/standalone-preflight.audit.txt"
require_grep 'preflight: passed' "${REPORTS_ROOT}/standalone-preflight.audit.txt"
require_grep 'validation: passed' "${REPORTS_ROOT}/standalone-preflight.audit.txt"
reject_grep 'Unable to locate the source repository' "${REPORTS_ROOT}/standalone-preflight.stdout.txt"

# Standalone exported trees with no Git metadata must still scan all entries
# and reject nested .git content.
NO_GIT_NESTED_GIT_TREE="${TREES_ROOT}/no-git-nested-git-tree"
prepare_validation_tree "${NO_GIT_NESTED_GIT_TREE}"
mkdir -p -- "${NO_GIT_NESTED_GIT_TREE}/nested/repository/.git"
printf '[core]\n\trepositoryformatversion = 0\n' > "${NO_GIT_NESTED_GIT_TREE}/nested/repository/.git/config"
: > "${VALIDATION_LOG}"
expect_failure "${REPORTS_ROOT}/no-git-nested-git.stdout.txt" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "${NO_GIT_NESTED_GIT_TREE}/tools/public-release/public-preflight.sh" \
    --destination "${NO_GIT_NESTED_GIT_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --audit-report "${REPORTS_ROOT}/no-git-nested-git.audit.txt"
require_grep '[path|path-dot-git-metadata] nested/repository/.git/config .git metadata must never appear in the public export.' \
    "${REPORTS_ROOT}/no-git-nested-git.audit.txt"

# Preflight must support --destination . from a public checkout, scan only
# tracked non-export-ignore entries, and ignore untracked or ignored local
# artifacts.
PUBLIC_CHECKOUT_TREE="${TREES_ROOT}/public-checkout-tree"
prepare_validation_tree "${PUBLIC_CHECKOUT_TREE}"
mkdir -p -- "${PUBLIC_CHECKOUT_TREE}/docs"
printf '%s\n' "$(build_dev_azure_https_fixture)" > "${PUBLIC_CHECKOUT_TREE}/docs/tracked-private-url.txt"
printf 'Private handoff reference: %s\n' "$(build_nonpublic_email_fixture)" > "${PUBLIC_CHECKOUT_TREE}/HANDOFF.md"
if [[ -f "${PRIVATE_DENY_SOURCE}" ]]; then
    cp -- "${PRIVATE_DENY_SOURCE}" "${PUBLIC_CHECKOUT_TREE}/tools/public-release/private-deny-patterns.json"
fi
PRIVATE_OVERLAY_EXPORT_IGNORE_URL="$(build_dev_azure_https_fixture)"
node - <<'EOF_NODE' "${PUBLIC_CHECKOUT_TREE}/tools/public-release/private-deny-patterns.json" "${PRIVATE_OVERLAY_EXPORT_IGNORE_URL}"
const fs = require('fs');
const filePath = process.argv[2];
const exportIgnoreUrl = process.argv[3];
const document = JSON.parse(fs.readFileSync(filePath, 'utf8'));
document.exportIgnoreFixture = exportIgnoreUrl;
fs.writeFileSync(filePath, `${JSON.stringify(document, null, 2)}\n`, 'utf8');
EOF_NODE
cat <<'PUBLIC_CHECKOUT_GITIGNORE' > "${PUBLIC_CHECKOUT_TREE}/.gitignore"
/.test-output/
/.claude/
PUBLIC_CHECKOUT_GITIGNORE
printf '\nHANDOFF.md export-ignore\ntools/public-release/private-deny-patterns.json export-ignore\n' >> "${PUBLIC_CHECKOUT_TREE}/.gitattributes"
git -C "${PUBLIC_CHECKOUT_TREE}" init -q
git -C "${PUBLIC_CHECKOUT_TREE}" add .
mkdir -p -- "${PUBLIC_CHECKOUT_TREE}/.test-output" "${PUBLIC_CHECKOUT_TREE}/.claude"
printf 'Ignored local password artifact.\n' > "${PUBLIC_CHECKOUT_TREE}/.test-output/session-password.txt"
printf '%s\n' "$(build_nonpublic_email_fixture)" > "${PUBLIC_CHECKOUT_TREE}/.claude/session-notes.txt"
printf 'Untracked local token artifact.\n' > "${PUBLIC_CHECKOUT_TREE}/local-token.txt"
: > "${VALIDATION_LOG}"
expect_failure "${REPORTS_ROOT}/public-checkout.stdout.txt" \
    run_in_directory "${PUBLIC_CHECKOUT_TREE}" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "tools/public-release/public-preflight.sh" \
    --destination . \
    --source-commit "${SANDBOX_COMMIT}" \
    --audit-report "${REPORTS_ROOT}/public-checkout.audit.txt"
require_grep '[content|content-private-repository-url] docs/tracked-private-url.txt:1:1 match_hash=' \
    "${REPORTS_ROOT}/public-checkout.audit.txt"
reject_grep '[path|path-dot-git-metadata]' "${REPORTS_ROOT}/public-checkout.audit.txt"
reject_grep '.test-output/' "${REPORTS_ROOT}/public-checkout.audit.txt"
reject_grep '.claude/' "${REPORTS_ROOT}/public-checkout.audit.txt"
reject_grep 'local-token.txt' "${REPORTS_ROOT}/public-checkout.audit.txt"
reject_grep 'HANDOFF.md' "${REPORTS_ROOT}/public-checkout.audit.txt"
reject_grep 'tools/public-release/private-deny-patterns.json' "${REPORTS_ROOT}/public-checkout.audit.txt"
reject_grep '[content|content-private-repository-url] tools/public-release/test-public-release.sh:' \
    "${REPORTS_ROOT}/public-checkout.audit.txt"
reject_grep '[content|content-corporate-email] tools/public-release/test-public-release.sh:' \
    "${REPORTS_ROOT}/public-checkout.audit.txt"

# CODEOWNERS and LICENSE gates must block missing files without duplicate
# generic required-file findings.
GATE_MISSING_TREE="${TREES_ROOT}/gate-missing-tree"
prepare_clean_release_tree "${CLEAN_RELEASE_SOURCE}" "${GATE_MISSING_TREE}"
rm -f -- "${GATE_MISSING_TREE}/.github/CODEOWNERS" "${GATE_MISSING_TREE}/LICENSE"
: > "${VALIDATION_LOG}"
expect_failure "${REPORTS_ROOT}/gate-missing.stdout.txt" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "${GATE_MISSING_TREE}/tools/public-release/public-preflight.sh" \
    --destination "${GATE_MISSING_TREE}" \
    --source-commit "${CLEAN_RELEASE_COMMIT}" \
    --audit-report "${REPORTS_ROOT}/gate-missing.audit.txt"
require_grep '[gate|required-codeowners-gate] .github/CODEOWNERS Public release requires a regular .github/CODEOWNERS file with at least one concrete non-comment ownership rule.' \
    "${REPORTS_ROOT}/gate-missing.audit.txt"
require_grep '[gate|required-license-gate] LICENSE Public release requires a regular LICENSE* file with substantive non-whitespace content.' \
    "${REPORTS_ROOT}/gate-missing.audit.txt"
reject_grep '[required|required-codeowners]' "${REPORTS_ROOT}/gate-missing.audit.txt"
reject_grep '[required|required-license]' "${REPORTS_ROOT}/gate-missing.audit.txt"

# Comment-only CODEOWNERS and whitespace-only LICENSE content must remain
# blocking gate failures.
GATE_INVALID_TREE="${TREES_ROOT}/gate-invalid-tree"
prepare_clean_release_tree "${CLEAN_RELEASE_SOURCE}" "${GATE_INVALID_TREE}"
cat <<'EOF_INVALID_CODEOWNERS' > "${GATE_INVALID_TREE}/.github/CODEOWNERS"
# pending public owners
   # still pending
EOF_INVALID_CODEOWNERS
printf ' \n\t\n' > "${GATE_INVALID_TREE}/LICENSE"
: > "${VALIDATION_LOG}"
expect_failure "${REPORTS_ROOT}/gate-invalid.stdout.txt" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "${GATE_INVALID_TREE}/tools/public-release/public-preflight.sh" \
    --destination "${GATE_INVALID_TREE}" \
    --source-commit "${CLEAN_RELEASE_COMMIT}" \
    --audit-report "${REPORTS_ROOT}/gate-invalid.audit.txt"
require_grep '[gate|required-codeowners-gate] .github/CODEOWNERS Public release requires a regular .github/CODEOWNERS file with at least one concrete non-comment ownership rule.' \
    "${REPORTS_ROOT}/gate-invalid.audit.txt"
require_grep '[gate|required-license-gate] LICENSE Public release requires a regular LICENSE* file with substantive non-whitespace content.' \
    "${REPORTS_ROOT}/gate-invalid.audit.txt"

# Placeholder CODEOWNERS and LICENSE files must be blocked by hard placeholder
# findings without duplicate gate findings.
GATE_PLACEHOLDER_TREE="${TREES_ROOT}/gate-placeholder-tree"
prepare_clean_release_tree "${CLEAN_RELEASE_SOURCE}" "${GATE_PLACEHOLDER_TREE}"
printf '* %s\n' "$(build_public_placeholder_fixture 'CODEOWNERS_OWNER')" > "${GATE_PLACEHOLDER_TREE}/.github/CODEOWNERS"
printf '%s\n' "$(build_public_placeholder_fixture 'LICENSE_TEXT')" > "${GATE_PLACEHOLDER_TREE}/LICENSE"
: > "${VALIDATION_LOG}"
expect_failure "${REPORTS_ROOT}/gate-placeholder.stdout.txt" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "${GATE_PLACEHOLDER_TREE}/tools/public-release/public-preflight.sh" \
    --destination "${GATE_PLACEHOLDER_TREE}" \
    --source-commit "${CLEAN_RELEASE_COMMIT}" \
    --audit-report "${REPORTS_ROOT}/gate-placeholder.audit.txt"
require_grep '[content|content-public-placeholder] .github/CODEOWNERS:1:3 match_hash=' \
    "${REPORTS_ROOT}/gate-placeholder.audit.txt"
require_grep '[content|content-public-placeholder] LICENSE:1:1 match_hash=' \
    "${REPORTS_ROOT}/gate-placeholder.audit.txt"
reject_grep '[gate|required-codeowners-gate]' "${REPORTS_ROOT}/gate-placeholder.audit.txt"
reject_grep '[gate|required-license-gate]' "${REPORTS_ROOT}/gate-placeholder.audit.txt"

# Fully resolved gate files must allow both export and preflight to succeed
# with both validators passing and no findings.
CLEAN_EXPORT_DEST="${WORK_ROOT}/clean-release-export"
: > "${VALIDATION_LOG}"
expect_success "${REPORTS_ROOT}/clean-export.stdout.txt" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "${CLEAN_RELEASE_SOURCE}/tools/public-release/public-export.sh" \
    --source-ref HEAD \
    --destination "${CLEAN_EXPORT_DEST}" \
    --audit-report "${REPORTS_ROOT}/clean-export.audit.txt"
require_grep 'preflight: passed' "${REPORTS_ROOT}/clean-export.audit.txt"
require_grep 'validation: passed' "${REPORTS_ROOT}/clean-export.audit.txt"
require_grep 'finding_count: 0' "${REPORTS_ROOT}/clean-export.audit.txt"
require_grep '[bash] status=passed command=bash tests/validate-plugin.sh exit_code=0' \
    "${REPORTS_ROOT}/clean-export.audit.txt"
require_grep '[pwsh] status=passed command=pwsh -NoLogo -NoProfile -File tests/validate-plugin.ps1 exit_code=0' \
    "${REPORTS_ROOT}/clean-export.audit.txt"
[[ -x "${CLEAN_EXPORT_DEST}/rhyolite" ]] ||
    fail 'Public export did not preserve the root launcher executable.'
require_grep 'public checkout launcher' "${CLEAN_EXPORT_DEST}/rhyolite"

: > "${VALIDATION_LOG}"
expect_success "${REPORTS_ROOT}/clean-preflight.stdout.txt" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "${CLEAN_EXPORT_DEST}/tools/public-release/public-preflight.sh" \
    --destination "${CLEAN_EXPORT_DEST}" \
    --source-commit "${CLEAN_RELEASE_COMMIT}" \
    --audit-report "${REPORTS_ROOT}/clean-preflight.audit.txt"
require_grep 'preflight: passed' "${REPORTS_ROOT}/clean-preflight.audit.txt"
require_grep 'validation: passed' "${REPORTS_ROOT}/clean-preflight.audit.txt"
require_grep 'finding_count: 0' "${REPORTS_ROOT}/clean-preflight.audit.txt"
require_grep "bash ${CLEAN_EXPORT_DEST}/tests/validate-plugin.sh" "${VALIDATION_LOG}"
require_grep "pwsh -NoLogo -NoProfile -File ${CLEAN_EXPORT_DEST}/tests/validate-plugin.ps1" "${VALIDATION_LOG}"

# Full validation matrix: both bash and pwsh validators run and are recorded.
VALIDATION_TREE="${TREES_ROOT}/validation-tree"
prepare_validation_tree "${VALIDATION_TREE}"
: > "${VALIDATION_LOG}"
expect_success "${REPORTS_ROOT}/validation-pass.stdout.txt" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${VALIDATION_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --audit-report "${REPORTS_ROOT}/validation-pass.audit.txt"
require_grep 'preflight: passed' "${REPORTS_ROOT}/validation-pass.audit.txt"
require_grep 'validation: passed' "${REPORTS_ROOT}/validation-pass.audit.txt"
require_grep 'finding_count: 0' "${REPORTS_ROOT}/validation-pass.audit.txt"
require_grep '[bash] status=passed command=bash tests/validate-plugin.sh exit_code=0' \
    "${REPORTS_ROOT}/validation-pass.audit.txt"
require_grep '[pwsh] status=passed command=pwsh -NoLogo -NoProfile -File tests/validate-plugin.ps1 exit_code=0' \
    "${REPORTS_ROOT}/validation-pass.audit.txt"
require_grep "bash ${VALIDATION_TREE}/tests/validate-plugin.sh" "${VALIDATION_LOG}"
require_grep "pwsh -NoLogo -NoProfile -File ${VALIDATION_TREE}/tests/validate-plugin.ps1" "${VALIDATION_LOG}"

# Skipping validation must still block release and record both validators as skipped.
: > "${VALIDATION_LOG}"
expect_failure "${REPORTS_ROOT}/validation-skip.stdout.txt" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${VALIDATION_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --skip-validation \
    --audit-report "${REPORTS_ROOT}/validation-skip.audit.txt"
require_grep 'validation: skipped' "${REPORTS_ROOT}/validation-skip.audit.txt"
require_grep '[validation|validation-skipped] Validation was skipped by option; public release requires both bash tests/validate-plugin.sh and pwsh -NoLogo -NoProfile -File tests/validate-plugin.ps1.' \
    "${REPORTS_ROOT}/validation-skip.audit.txt"
require_grep '[bash] status=skipped command=bash tests/validate-plugin.sh' \
    "${REPORTS_ROOT}/validation-skip.audit.txt"
require_grep '[pwsh] status=skipped command=pwsh -NoLogo -NoProfile -File tests/validate-plugin.ps1' \
    "${REPORTS_ROOT}/validation-skip.audit.txt"
[[ ! -s "${VALIDATION_LOG}" ]] || fail 'Skipped validation unexpectedly invoked validators.'

# Missing pwsh runtime must block even when bash validation passes.
: > "${VALIDATION_LOG}"
expect_failure "${REPORTS_ROOT}/validation-missing-pwsh.stdout.txt" \
    env PATH="${VALIDATION_BASH_ONLY_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${VALIDATION_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --audit-report "${REPORTS_ROOT}/validation-missing-pwsh.audit.txt"
require_grep '[validation|validation-pwsh] Missing validator runtime: pwsh.' \
    "${REPORTS_ROOT}/validation-missing-pwsh.audit.txt"
require_grep '[bash] status=passed command=bash tests/validate-plugin.sh exit_code=0' \
    "${REPORTS_ROOT}/validation-missing-pwsh.audit.txt"
require_grep '[pwsh] status=failed command=pwsh -NoLogo -NoProfile -File tests/validate-plugin.ps1' \
    "${REPORTS_ROOT}/validation-missing-pwsh.audit.txt"
require_grep 'message: Missing validator runtime: pwsh.' \
    "${REPORTS_ROOT}/validation-missing-pwsh.audit.txt"

# Missing bash runtime must block even when pwsh validation passes.
: > "${VALIDATION_LOG}"
expect_failure "${REPORTS_ROOT}/validation-missing-bash.stdout.txt" \
    env PATH="${VALIDATION_NO_BASH_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${VALIDATION_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --audit-report "${REPORTS_ROOT}/validation-missing-bash.audit.txt"
require_grep '[validation|validation-bash] Missing validator runtime: bash.' \
    "${REPORTS_ROOT}/validation-missing-bash.audit.txt"
require_grep '[bash] status=failed command=bash tests/validate-plugin.sh' \
    "${REPORTS_ROOT}/validation-missing-bash.audit.txt"
require_grep 'message: Missing validator runtime: bash.' \
    "${REPORTS_ROOT}/validation-missing-bash.audit.txt"
require_grep '[pwsh] status=passed command=pwsh -NoLogo -NoProfile -File tests/validate-plugin.ps1 exit_code=0' \
    "${REPORTS_ROOT}/validation-missing-bash.audit.txt"

# Failing bash validator must block and capture the validator result.
: > "${VALIDATION_LOG}"
expect_failure "${REPORTS_ROOT}/validation-failing-bash.stdout.txt" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" MOCK_VALIDATE_BASH_EXIT=17 MOCK_VALIDATE_BASH_OUTPUT='mock bash failure' \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${VALIDATION_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --audit-report "${REPORTS_ROOT}/validation-failing-bash.audit.txt"
require_grep '[validation|validation-bash] bash tests/validate-plugin.sh failed with exit code 17.' \
    "${REPORTS_ROOT}/validation-failing-bash.audit.txt"
require_grep '[bash] status=failed command=bash tests/validate-plugin.sh exit_code=17' \
    "${REPORTS_ROOT}/validation-failing-bash.audit.txt"
require_grep 'message: bash tests/validate-plugin.sh failed with exit code 17.' \
    "${REPORTS_ROOT}/validation-failing-bash.audit.txt"
require_grep '  mock bash failure' "${REPORTS_ROOT}/validation-failing-bash.audit.txt"

# Failing pwsh validator must block and capture the validator result.
: > "${VALIDATION_LOG}"
expect_failure "${REPORTS_ROOT}/validation-failing-pwsh.stdout.txt" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" MOCK_VALIDATE_PWSH_EXIT=19 MOCK_VALIDATE_PWSH_OUTPUT='mock pwsh failure' \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${VALIDATION_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --audit-report "${REPORTS_ROOT}/validation-failing-pwsh.audit.txt"
require_grep '[validation|validation-pwsh] pwsh -NoLogo -NoProfile -File tests/validate-plugin.ps1 failed with exit code 19.' \
    "${REPORTS_ROOT}/validation-failing-pwsh.audit.txt"
require_grep '[pwsh] status=failed command=pwsh -NoLogo -NoProfile -File tests/validate-plugin.ps1 exit_code=19' \
    "${REPORTS_ROOT}/validation-failing-pwsh.audit.txt"
require_grep 'message: pwsh -NoLogo -NoProfile -File tests/validate-plugin.ps1 failed with exit code 19.' \
    "${REPORTS_ROOT}/validation-failing-pwsh.audit.txt"
require_grep '  mock pwsh failure' "${REPORTS_ROOT}/validation-failing-pwsh.audit.txt"

# Exact occurrence waivers: one content waiver must not suppress another match in the same file.
OCCURRENCE_TREE="${TREES_ROOT}/occurrence-tree"
OCCURRENCE_DENY="${REPORTS_ROOT}/occurrence-deny.json"
OCCURRENCE_ALLOWLIST="${REPORTS_ROOT}/occurrence-allowlist.json"
mkdir -p -- "${OCCURRENCE_TREE}"
git -C "${SANDBOX}" archive --format=tar HEAD | tar -xf - -C "${OCCURRENCE_TREE}"
mkdir -p -- "${OCCURRENCE_TREE}/docs"
cat <<'MATCHES' > "${OCCURRENCE_TREE}/docs/multi-occurrence.txt"
EXACT-OCCURRENCE-MARKER first
EXACT-OCCURRENCE-MARKER second
MATCHES
cat <<'OCCURRENCE_RULES' > "${OCCURRENCE_DENY}"
{
  "content": [
    {
      "id": "content-occurrence-marker",
      "pattern": "EXACT-OCCURRENCE-MARKER",
      "description": "Reject exact occurrence coverage marker.",
      "allowlistWaivable": true
    }
  ]
}
OCCURRENCE_RULES
expect_failure "${REPORTS_ROOT}/occurrence-base.stdout.txt" \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${OCCURRENCE_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --skip-validation \
    --deny-file "${OCCURRENCE_DENY}" \
    --audit-report "${REPORTS_ROOT}/occurrence-base.audit.txt"
mapfile -t occurrence_records < <(node - <<'EOF_NODE' "${REPORTS_ROOT}/occurrence-base.audit.txt"
const fs = require('fs');
const report = fs.readFileSync(process.argv[2], 'utf8');
const matches = [...report.matchAll(/\[content\|content-occurrence-marker\] docs\/multi-occurrence\.txt:(\d+):(\d+) match_hash=([0-9a-f]+) /g)];
if (matches.length !== 2) {
  throw new Error(`Expected 2 occurrence findings, found ${matches.length}`);
}
for (const match of matches) {
  console.log(`${match[1]}:${match[2]}:${match[3]}`);
}
EOF_NODE
)
[[ "${#occurrence_records[@]}" -eq 2 ]] || fail 'Expected two occurrence records.'
IFS=':' read -r first_line first_column first_hash <<< "${occurrence_records[0]}"
IFS=':' read -r second_line second_column second_hash <<< "${occurrence_records[1]}"
[[ "${first_hash}" != "${second_hash}" ]] || fail 'Occurrence hashes must differ.'
cat <<EOF_ALLOWLIST > "${OCCURRENCE_ALLOWLIST}"
{
  "entries": [
    {
      "kind": "content",
      "path": "docs/multi-occurrence.txt",
      "ruleId": "content-occurrence-marker",
      "line": ${first_line},
      "matchHash": "${first_hash}",
      "reviewedBy": "release-reviewer",
      "reason": "Exact occurrence waiver coverage."
    }
  ]
}
EOF_ALLOWLIST
expect_failure "${REPORTS_ROOT}/occurrence-waived.stdout.txt" \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-preflight.sh" \
    --destination "${OCCURRENCE_TREE}" \
    --source-commit "${SANDBOX_COMMIT}" \
    --skip-validation \
    --deny-file "${OCCURRENCE_DENY}" \
    --allowlist-file "${OCCURRENCE_ALLOWLIST}" \
    --audit-report "${REPORTS_ROOT}/occurrence-waived.audit.txt"
require_grep "[content|content-occurrence-marker] docs/multi-occurrence.txt:${first_line}:${first_column} match_hash=${first_hash} reviewedBy=release-reviewer reason=Exact occurrence waiver coverage." \
    "${REPORTS_ROOT}/occurrence-waived.audit.txt"
require_grep "[content|content-occurrence-marker] docs/multi-occurrence.txt:${second_line}:${second_column} match_hash=${second_hash} Reject exact occurrence coverage marker." \
    "${REPORTS_ROOT}/occurrence-waived.audit.txt"
reject_grep "[content|content-occurrence-marker] docs/multi-occurrence.txt:${first_line}:${first_column} match_hash=${first_hash} Reject exact occurrence coverage marker." \
    "${REPORTS_ROOT}/occurrence-waived.audit.txt"

# Synthetic git-archive regression: export-ignore omits HANDOFF.md and the
# private deny overlay from the exported file list.
ARCHIVE_SOURCE="${WORK_ROOT}/archive-source"
ARCHIVE_DEST="${WORK_ROOT}/archive-destination"
prepare_source_repository "${ARCHIVE_SOURCE}"
ensure_release_gate_files "${ARCHIVE_SOURCE}"
write_mock_validator_scripts "${ARCHIVE_SOURCE}"
cat <<'HANDOFF' > "${ARCHIVE_SOURCE}/HANDOFF.md"
Private handoff notes should not be archived.
HANDOFF
printf '\nHANDOFF.md export-ignore\ntools/public-release/private-deny-patterns.json export-ignore\n' >> "${ARCHIVE_SOURCE}/.gitattributes"
commit_all "${ARCHIVE_SOURCE}" 'archive-regression'
[[ -z "$(git -C "${ARCHIVE_SOURCE}" status --porcelain --untracked-files=all)" ]] || fail 'Archive regression source must be clean before export.'
: > "${VALIDATION_LOG}"
expect_failure "${REPORTS_ROOT}/archive-export.stdout.txt" \
    env PATH="${VALIDATION_FULL_BIN}" PUBLIC_RELEASE_VALIDATION_LOG="${VALIDATION_LOG}" \
    "${REAL_BASH}" "${ARCHIVE_SOURCE}/tools/public-release/public-export.sh" \
    --source-ref HEAD \
    --destination "${ARCHIVE_DEST}" \
    --audit-report "${REPORTS_ROOT}/archive-export.audit.txt"
require_grep '  tools/public-release/public-release.mjs' "${REPORTS_ROOT}/archive-export.audit.txt"
reject_grep '  HANDOFF.md' "${REPORTS_ROOT}/archive-export.audit.txt"
reject_grep '  tools/public-release/private-deny-patterns.json' "${REPORTS_ROOT}/archive-export.audit.txt"

# Failed extraction must leave an existing empty destination untouched and clean staging directories.
[[ -z "$(git -C "${SANDBOX}" status --porcelain --untracked-files=all)" ]] || fail 'Sandbox source must be clean before export coverage.'
mkdir -p -- "${FAILED_DEST}"
cat <<EOF_TAR > "${FAKE_BIN}/tar"
#!${REAL_BASH}
printf 'forced tar failure\n' >&2
exit 91
EOF_TAR
chmod +x "${FAKE_BIN}/tar"
expect_failure "${REPORTS_ROOT}/failed-extraction.stdout.txt" \
    env PATH="${FAKE_BIN}:${PATH}" \
    "${REAL_BASH}" "${SANDBOX}/tools/public-release/public-export.sh" \
    --source-ref HEAD \
    --destination "${FAILED_DEST}" \
    --skip-validation \
    --audit-report "${REPORTS_ROOT}/failed-extraction.audit.txt"
require_grep '[export|archive-extraction] tar extraction failed: forced tar failure' \
    "${REPORTS_ROOT}/failed-extraction.audit.txt"
if find "${FAILED_DEST}" -mindepth 1 -print -quit | grep -q .; then
    fail 'Failed extraction left files in the destination.'
fi
if find "${FAILED_PARENT}" -maxdepth 1 -mindepth 1 -type d -name '.export-destination.public-release-staging-*' -print -quit | grep -q .; then
    fail 'Failed extraction left staging directories behind.'
fi

printf 'public-release sandbox tests passed\n'
