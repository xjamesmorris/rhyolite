## Summary

Describe the change and why it is needed.

Confirm that the change follows the canonical contract in `AGENTS.md`. Harness
work must also follow `docs/ADDING-A-HARNESS.md`.

## Validation

- [ ] `git diff --check`
- [ ] `bash ./tests/validate-all.sh`
- [ ] `bash ./tests/test-install.sh`
- [ ] `bash ./tools/public-release/test-public-release.sh`
- [ ] Not run (explain why below)

## Public release checklist

- [ ] No internal-only URLs, branding, or governance files were added to
      public-facing docs or metadata.
- [ ] The read-only boundary is preserved; no target-code execution or
      mutation was introduced.
- [ ] Scope 3 is still described as evidence-based provenance review for
      agentically generated code.
- [ ] Fedora Linux 44 remains the sole supported validation platform.
- [ ] Maximum reasoning effort remains the cross-session default; only
      mechanical or fully scoped work may downgrade, and only to high.
- [ ] Production runtime harness support remains limited to GitHub Copilot
      CLI and Claude Code unless this PR is the separately approved, fully
      validated adapter release.
- [ ] Development-only harness fixtures remain under `tests/fixtures` and are
      not registered, packaged, launcher-exposed, or advertised to users.

## Additional context

Add screenshots, logs, or rollout notes if helpful.
