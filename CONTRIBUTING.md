# Contributing

Changes are accepted through pull requests.

Other Fedora versions and Linux distributions may work, but all validation
so far has been on Fedora Linux 44. Contributions and test reports from
other Linux flavors are welcome, including successful runs and
compatibility failures. Include the distribution and version, relevant
tool versions, commands run, results, and sanitized logs in your issue or
pull request.

## Requirements

- Keep Fedora Linux 44 as the development and release validation baseline;
  testing on other Linux flavors supplements rather than replaces that gate.
- Keep Bash as the canonical implementation.
- Keep the plugin read-only by construction.
- Do not add broad tool approval, shared credentials, or URL bypass as
  a default.
- Keep public research and provenance analysis independently opt-in.
- Keep deterministic orchestration in scripts and agent/skill files
  focused on workflow and policy.
- Use maximum available reasoning effort by default for every
  development task. This policy persists across sessions and must be
  carried into development handoffs. Downgrade only mechanical or fully
  scoped work, and only to high; keep analytical or open-ended work at
  maximum effort.
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

Contributions and test reports do not by themselves establish validated
support for another Linux flavor. Non-Linux operating systems and alternate
shells remain outside the current release scope.
