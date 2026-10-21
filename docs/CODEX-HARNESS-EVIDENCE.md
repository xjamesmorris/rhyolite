# Codex harness discovery evidence

## Status

Codex is not a supported production Rhyolite harness. No Codex adapter or
production registry entry has been added.

Initial discovery found a prerequisite that the planned adapter cannot
currently satisfy: the tested shell-free Codex configuration exposes no
ordinary snapshot file-read or search tools. Advertising those tools in a
local model catalog did not add them. An explicit snapshot-interface design
decision is required before adapter implementation.

This record describes Codex CLI 0.163.0 only. It does not establish the
behavior of another release, an internally configured provider, or a
completed Rhyolite review.

## Environment and provenance

- Fedora Linux 44, Linux x86-64, Node.js 22.22.2.
- Official `@openai/codex@0.163.0`, installed into a private probe directory,
  with install scripts disabled and package integrity verified. No global
  installation or user configuration was changed.
- Source tag `rust-v0.163.0`, resolved to commit
  `83086188ae0614bd882818ff1aa23f3194962012`. Inspected source blobs were
  checked against the pinned Git tree and Git blob hashes.
- Every execution used fresh synthetic `HOME` and `CODEX_HOME` directories,
  an explicit clean environment, and a local non-Git fixture directory.
- No credentials, real model service, target tool calls, or target code were
  used. Raw diagnostic files remain private; only normalized observations
  are recorded here.

## Probe method

A fixed loopback HTTP fixture captured the CLI's outgoing Responses request.
It supplied no model generation or tool calls and returned HTTP 503 after
capture. Consequently, CLI exit status 1 was expected: capture success does
not mean that a model invocation or review completed.

The invocation used `codex exec` with `--ignore-user-config`,
`--strict-config`, `--ignore-rules`, JSON output, the read-only sandbox, and
`approval_policy="never"`. Shell/unified execution, JavaScript execution,
agents, plugins, skill discovery, web search, plan updates, and questions
were disabled. The provider and model were synthetic fixture values.

The final two cases additionally disabled `features.goals` and
`features.view_image`. The catalog case loaded a synthetic model with
`shell_type="disabled"`, no patch tool, and
`experimental_supported_tools` containing `read_file`, `grep_files`, and
`list_dir`. A unique instruction marker verified that the catalog was
actually loaded rather than silently ignored.

## Results

| Probe | Observed result | Meaning |
| --- | --- | --- |
| Version and help | Version 0.163.0; `exec`, explicit-session resume, plugin commands, JSON output, and final-message output were present. | Candidate interfaces exist; their full Rhyolite behavior remains unverified. |
| Invalid tool configuration | A boolean supplied where `tools.update_plan` requires an object was rejected before any request. The corrected form uses `tools.update_plan.enabled`. | Configuration types matter; a similarly named flag or setting is not evidence that a restriction is applied. |
| Shell-free inventory before utility-tool exclusions | `create_goal`, `get_goal`, `update_goal`, and `view_image`. | Shell tools were absent from this request, but the request was not tool-less and had no ordinary file-read/search tools. |
| Utility exclusions applied | Empty `tools` array; requested effort `xhigh`. | A zero-tool request can be constructed. This is not yet proof of the complete repair protocol or actual service-side model/effort identity. |
| Read-tool metadata alternative | Catalog marker present, but the `tools` array was still empty. | Catalog advertising did not provide a native snapshot reader. It is not a workaround for the missing interface. |

Confidence is **High** for these captured request inventories and
configuration results: they came from the pinned executable, not a mock CLI
or a model's description of its tools. No conclusion is claimed for untested
versions or live provider behavior.

## Source cross-check

At the pinned commit:

- `codex-rs/core/src/tools/spec_plan.rs:1245-1291` gates shell-tool
  registration on the shell feature and model metadata.
- `codex-rs/core/src/tools/spec_plan.rs:1307-1452` handles utility tools and
  selected metadata-driven tools; it does not register the advertised
  `read_file`, `grep_files`, or `list_dir` names.
- `codex-rs/core/src/tools/handlers/mod.rs:1-37` lists the core handlers and
  has no ordinary file-read/search handler corresponding to those names.

Official source references:

- `https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/spec_plan.rs`
- `https://github.com/openai/codex/blob/83086188ae0614bd882818ff1aa23f3194962012/codex-rs/core/src/tools/handlers/mod.rs`

## Required decision and remaining gates

Do not enable shell commands as a substitute for snapshot reads, introduce
an unapproved broker/runtime, or register a partial harness.

Choose whether to design a constrained, trusted snapshot-read interface,
design a bounded runner-mediated tool-less input protocol, or retain the
current contract and pause Codex support. Installation and authentication
alone do not resolve the observed interface gap.

Live model/effort/context verification, filesystem/instruction isolation,
dedicated research, exact output, continuation, tool-less repair completion,
native guided setup, installation/update, and lifecycle cleanup all remain
unverified. Production enablement still requires the complete
[harness playbook](ADDING-A-HARNESS.md), automated coverage, real-run
evidence, and Fedora validation.
