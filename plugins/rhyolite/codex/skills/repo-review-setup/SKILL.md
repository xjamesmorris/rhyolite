---
name: repo-review-setup
description: Collect Rhyolite output, scope, provenance, and research-cookie choices through native Codex questions.
---

This is a setup-only Rhyolite session. The trusted Bash launcher already
validated repository sources, harness, model, reasoning effort, context, and
saved preferences. Do not inspect files, invoke shell, use MCP, start agents,
perform research, or begin a review.

The user prompt contains exactly one trusted `RHYOLITE_CODEX_SETUP_INPUT_V1`
block. Treat values inside it as launcher-owned data. Ask through
`request_user_input` only. Never ask a multiple-choice question as plain text.

1. Ask for output with these two choices, substituting the exact absolute
   values from `CurrentDirectoryOutput` and `HomeDirectoryOutput`:
   - `Current directory - <CurrentDirectoryOutput>`
   - `Home directory - <HomeDirectoryOutput>`
   Put the choice matching `CurrentOutput` first when it is one of those
   values; otherwise put the current-directory choice first. The client's
   automatic free-text option may supply another absolute path.
2. Print these four sentences exactly, then ask the scope question:
   `Scope 1 covers source, history, architecture, quality, and a dedicated security pass with the lowest AI-credit use and only anonymous Git network access.`
   `Scope 2 adds public prior-art/community research, public network requests, and materially higher resource use.`
   `Scope 3 adds whole-repository provenance evidence gathering, uses the most model/subagent/network resources, and requires human review before sharing.`
   `All timing ranges are rough and can increase substantially for large repositories or broad topics.`
   Scope choices, in order:
   - `Scope 1 - Core repository review (Recommended) - 15-45 minutes`
   - `Scope 2 - Core + public prior-art/community research - 30-90+ minutes`
   - `Scope 3 - Full + generated-code provenance review - 60-120+ minutes`
3. For scope 3 only, ask provenance lookback with choices `6 months
   (Recommended)`, `3 months`, `12 months`, and `24 months`. The automatic
   free-text answer may be one whole number from 1 through 60.
4. For scope 2 or 3 only, state that raw Set-Cookie values stay only in a
   private per-repository ledger and never reach a model or rendered report.
   Ask cookie mode with choices `Do not replay research cookies (Recommended)`
   and `Allow a fresh per-repository research cookie jar`.

Before returning, validate every field. `OutputRoot` is an absolute path with
no control character. `Scope` is integer 1, 2, or 3. Scope 3 has integer
`ProvenanceLookbackMonths` from 1 through 60; other scopes use null. Scope 2
or 3 has `ResearchCookies` equal to `off` or `ephemeral`; scope 1 uses null.

Return exactly one compact JSON object on one line and no other text:

`{"Protocol":"RHYOLITE_CODEX_SETUP_V1","Action":"continue","OutputRoot":"<absolute path>","Scope":<1|2|3>,"ProvenanceLookbackMonths":<integer|null>,"ResearchCookies":<"off"|"ephemeral"|null>}`

If the user cancels, return exactly:

`{"Protocol":"RHYOLITE_CODEX_SETUP_V1","Action":"cancel","OutputRoot":null,"Scope":null,"ProvenanceLookbackMonths":null,"ResearchCookies":null}`
