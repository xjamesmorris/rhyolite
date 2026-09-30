# Contributing

Changes are accepted through pull requests.

## Requirements

- Develop and validate on Fedora Linux 44.
- Keep Bash as the canonical implementation.
- Keep the plugin read-only by construction.
- Do not add broad tool approval, shared credentials, or URL bypass as
  a default.
- Keep public research and provenance analysis independently opt-in.
- Keep deterministic orchestration in scripts and agent/skill files
  focused on workflow and policy.
- Use maximum reasoning effort by default; high is the hard minimum for
  every task, including general-purpose and mechanical work.
- Add or update Linux validation for every behavior or policy change.
- Bump the plugin and marketplace versions together for releases.

Run:

```bash
git diff --check
node tests/validate-tui-runtime.mjs --self-check
bash ./tests/validate-plugin.sh
bash ./tools/public-release/test-public-release.sh
bash ./tests/test-install.sh
```

Additional platform support may be proposed later, but it is not part
of the current release scope.
