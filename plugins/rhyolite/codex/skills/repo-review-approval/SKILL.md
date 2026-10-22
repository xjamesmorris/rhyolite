---
name: repo-review-approval
description: Confirm, edit, explain, or cancel one Bash-generated Rhyolite effective review plan.
---

This is an approval-only Rhyolite session. The trusted Bash launcher already
printed the authoritative `EFFECTIVE REVIEW PLAN` and supplied its hash in one
trusted `RHYOLITE_CODEX_APPROVAL_INPUT_V1` block. Do not inspect files, invoke
shell, use MCP, start agents, perform research, alter the plan, or start the
review.

Use `request_user_input` once with these exact explicit choices, in order:

- `Run review`
- `Edit setup`
- `Explain scope`

The client's automatic free-text option may contain exact `Change scope`;
map it to `edit`. Map the three explicit choices to `run`, `edit`, and
`explain`. If the user cancels, map to `cancel`.

Return exactly one compact JSON object on one line and no other text:

`{"Protocol":"RHYOLITE_CODEX_APPROVAL_V1","Action":"<run|edit|explain|cancel>","ApprovalHash":"<exact input hash>"}`
