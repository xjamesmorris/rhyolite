# Contributing

Changes are accepted through pull requests.

## Requirements

- Keep the plugin read-only by construction.
- Do not add broad tool approval or URL bypass as a default.
- Do not add shared credentials or service tokens.
- Keep public research and provenance analysis independently opt-in.
- Describe Scope 3 as evidence-based provenance review for agentically
  generated code.
- Keep public-facing docs and metadata neutral; do not reintroduce
  organization-specific branding, internal-only URLs, or automatic
  update hooks.
- Keep skills concise; put deterministic orchestration in scripts.
- Add or update validation for every behavior or policy change.
- Preserve PowerShell and Bash parity.
- Bump the plugin and marketplace versions together for releases.

Run both validation scripts when the required shells are available:

```powershell
pwsh .\tests\validate-plugin.ps1
```

```bash
bash ./tests/validate-plugin.sh
```

Before publishing, choose and add a `LICENSE` file, add
repository-specific `CODEOWNERS`, configure support and security
contacts, and require the appropriate reviewers.
