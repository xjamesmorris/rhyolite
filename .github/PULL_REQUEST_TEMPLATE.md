## Summary

Describe the change and why it is needed.

## Validation

- [ ] `bash ./tests/validate-plugin.sh`
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
- [ ] Maximum reasoning effort remains the default and high remains the
      hard minimum.

## Additional context

Add screenshots, logs, or rollout notes if helpful.
