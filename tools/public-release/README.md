# Public release export tooling

`public-export.sh` requires a clean source worktree, archives an exact source
ref into an empty destination with `git archive`, runs preflight, runs
`bash tests/validate-plugin.sh` from the exported tree by default, and writes
an audit report alongside the destination. Export
staging is transactional: files are extracted into a temporary sibling and
moved into the destination only after export, scanning, and validation
succeed.

`public-preflight.sh` runs the same checks and optional
validation against an existing exported tree. Preflight is self-contained: it
can scan a standalone exported directory with no source Git repo and supports
`--destination .` from a public checkout. When the destination is a Git
worktree root, preflight scans only Git-tracked, non-`export-ignore` entries
using current filesystem contents and ignores that checkout's root `.git` plus
untracked or ignored local artifacts. History-free exports with no Git
metadata are scanned entry-by-entry.

By default, release validation requires the Bash validator to run
successfully. A missing Bash runtime, missing validator script, or nonzero
validator exit blocks the release.

## Usage

```bash
tools/public-release/public-export.sh \
  --source-ref <commit-or-tag> \
  --destination ../rhyolite-public

tools/public-release/public-preflight.sh \
  --destination ../rhyolite-public \
  --source-commit <resolved-commit>

# from inside a public checkout of the exported tree
tools/public-release/public-preflight.sh \
  --destination . \
  --source-commit <resolved-commit>
```

## Common options

- `--deny-file <file>`: optional JSON file with extra path/content deny rules
  (legacy alias: `--deny-pattern-file`).
- `--allowlist-file <file>`: optional JSON file with reviewed waivers for exact
  reviewable findings. Content waivers must target one exact occurrence, and
  only rules marked as reviewable terminology checks can be waived.
- `--audit-report <file>`: optional report path. The default is
  `<destination>.audit.txt`.
- `--skip-validation`: do not run validators, but still emit a blocking finding
  and nonzero result.

The export refuses a dirty source worktree, destinations inside the source
repository, and non-empty destinations. The audit report records the resolved
source commit plus sorted relative paths and SHA-256 hashes. It is written
alongside the destination, not inside it. If export extraction, scanning, or
validation fails, the destination stays absent or empty and temporary staging
state is removed. The audit report records the Bash validator result even when
the runtime is missing, validation fails, validation is skipped, or extraction
fails before validation can run.

Default preflight blocks internal GitHub policy paths, unresolved public
placeholder tokens, non-public maintainer/tool wording, corporate email
patterns, private repository/host patterns, likely secret filenames/content,
every symlink entry, missing required public files, and `.git` metadata.
When `tools/public-release/private-deny-patterns.json` is present beside the
tool, it is merged automatically as a source-private deny overlay; public
checkouts do not require that file. `.github/CODEOWNERS` resolves only when a
regular non-symlink file exists with at least one concrete non-comment owner
rule and no unresolved placeholder finding. `LICENSE*` resolves only when a
regular non-symlink file exists with substantive non-whitespace content and no
unresolved placeholder finding. Hard sanitization rules ignore allowlists,
including unresolved `<PUBLIC_...>` placeholders, internal-only governance
paths, corporate email/private repository rules, likely secrets, symlinks, and
the private deny overlay. Public-checkout preflight audits only tracked files;
history-free export/preflight scans every entry in the destination tree.

## Extra deny rules

```json
{
  "path": [
    {
      "id": "path-extra-internal",
      "pattern": "^notes/private-only/",
      "description": "Reject extra internal notes"
    }
  ],
  "content": [
    {
      "id": "content-extra-marker",
      "pattern": "PUBLISH-BLOCKER",
      "description": "Reject unresolved publish blockers"
    },
    {
      "id": "content-reviewable-terminology",
      "pattern": "legacy pilot phrasing",
      "description": "Flag reviewable terminology for human approval",
      "allowlistWaivable": true
    }
  ]
}
```

## Reviewed allowlist

```json
{
  "entries": [
    {
      "kind": "content",
      "path": "README.md",
      "ruleId": "content-reviewable-terminology",
      "line": 12,
      "matchHash": "<sha256-of-matched-text-and-context>",
      "reviewedBy": "release-reviewer",
      "reason": "Approved terminology after review."
    }
  ]
}
```

Allowlist entries are exact matches on `kind`, `path`, and `ruleId`. Content
rules marked `allowlistWaivable: true` must also include the exact `line` and
`matchHash` reported by preflight so one waiver cannot suppress later matches
in the same file. Only explicitly reviewable terminology rules can be waived;
all hard sanitization rules, built-in path rules, required-file failures, the
`.github/CODEOWNERS` gate, the `LICENSE` gate, and validation failures remain
blocking until their resolution conditions are satisfied.

## Bash sandbox test

```bash
tools/public-release/test-public-release.sh
```
