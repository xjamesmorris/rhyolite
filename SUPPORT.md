# Support

## Getting help

- **Guided setup help:** while the `repository-review` agent is
  collecting answers, use the exact phrases `help`, `status`, or
  `explain scopes` without resetting the current setup state. Exact
  `help` rerenders the static panel and immediately follows it with
  `CURRENT SETUP STATUS`.
- **Bug reports:** open a bug report with the GitHub issue template.
- **Feature requests:** open a feature request with the GitHub issue
  template.
- **Usage questions:** open a usage question with the GitHub question
  issue template in `.github/ISSUE_TEMPLATE/question.yml`.
- **Security issues:** follow [SECURITY.md](SECURITY.md), use
  [GitHub private vulnerability reporting](https://github.com/xjamesmorris/rhyolite/security/advisories/new),
  and do not post credentials, non-public repository details, or
  working exploits in a public issue.
- **Conduct concerns:** follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
  and contact [jmorris@namei.org](mailto:jmorris@namei.org).

## Response expectations

Support is best-effort and may vary by maintainer availability. Include
the plugin version, operating system, installation path, whether the
load status and review-start plaque appeared, and sanitized logs
when possible. For setup questions, include the `CURRENT SETUP STATUS`
block or `status` output if it helps show the current
source/output/scope/provenance selections. If the runner reports a
plan-hash mismatch, include the mismatch message and the regenerated
`EFFECTIVE REVIEW PLAN` summary if available.

## Pre-publication note

GitHub private vulnerability reporting can be enabled only after the
repository becomes public. Enable it immediately after the visibility
change and before announcing the release. The published docs/support
URLs shown in the onboarding notice and panel must also be smoke-tested
before shipping.
