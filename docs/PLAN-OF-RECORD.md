# Platform plan of record

**Decision date:** September 30, 2026

**Constrained broker exception approved:** October 1, 2026

**Claude Code production harness approved:** October 7, 2026

## Decision

Rhyolite is a **Linux-only, Bash-first** product for this release, with
**Fedora Linux 44** as its development and release validation baseline.

- All validation so far has been on Fedora Linux 44.
- Runtime support is Linux-only. Other Fedora versions and Linux
  distributions may work; contributions and test reports from other Linux
  flavors are welcome, without implying validated support.
- Bash is the canonical launcher, helper, runner, and validation
  implementation.
- The bundled Python 3 standard-library research egress broker is the one
  approved constrained exception. Bash remains authoritative for
  orchestration, planning, lifecycle, policy trust, cleanup, failure mapping,
  and artifact finalization.
- Validation is local only. Hosted continuous integration is not part of
  the current release gate.
- Non-Linux operating systems and alternate shells are not
  supported or validated.
- GitHub Copilot CLI and Claude Code are the supported production review
  harnesses. Claude Code was approved after the evidence recorded in
  [CLAUDE-HARNESS-EVIDENCE.md](CLAUDE-HARNESS-EVIDENCE.md). The fixed harness
  seam does not advertise or imply support for other CLIs.

Contributions and test reports for other Linux flavors can help establish
compatibility evidence, but do not replace the Fedora Linux 44 release gate.
Expanding validated platform support requires a new explicit project
decision; compatibility must not be preserved speculatively.

## Immediate engineering policy

1. New features and fixes target Linux and Bash only, except for the approved
   local Python research broker. Do not add alternate shells, platforms,
   broker runtimes, or PowerShell parity.
2. Do not add alternate-platform implementations, branches, or parity
   assertions unless a later decision explicitly restores that scope.
3. `bash ./tests/validate-all.sh` on Fedora 44 is the authoritative
   full validation gate. It runs the focused harness contract validator
   before the legacy monolithic plugin validator.
4. No hosted workflow is required or shipped. Maintainers run release
   validation locally on Fedora Linux 44.
5. Public documentation describes the Linux/Bash workflow, identifies Fedora
   Linux 44 as the only platform validated so far, and welcomes contributions
   and test reports from other Fedora versions and Linux distributions.

## Contributor and harness guidance

- [../AGENTS.md](../AGENTS.md) is the canonical repository-wide contributor
  and LLM development contract. Tool-specific files point to it rather than
  maintaining divergent policy copies.
- [HARNESS-ARCHITECTURE.md](HARNESS-ARCHITECTURE.md) describes the implemented
  Contract-v5 seam.
- [ADDING-A-HARNESS.md](ADDING-A-HARNESS.md) is the required implementation
  playbook for Contract v5 and any future production adapter.
- The contract retains approval-bound harness execution identity and validated runtime
  selection into approval-bound data using plan schema 5 and state schema 6.
  Its provider summary is a validated
  object with `Id`, `Host`, and `ForwardedEnvVarNames`.
- Contract v5 moves the dedicated scope 2/3 research worker behind four
  adapter functions and gates scope 2/3 on the adapter's `web_research`
  capability. The runner keeps broker lifecycle, validation, cleanup, and
  artifacts.
- Contract v4 added an isolated, fresh, zero-tool report-repair invocation.
  The plan's fixed `ReportRepairPolicy` allows one confidence-edit attempt
  within at most 300 seconds, capped by the session timeout, under the approved
  model settings. Research is never
  repeated, and strict validation plus deterministic preservation remain
  authoritative. The same policy discloses runner-owned, model-free
  `markdown-table-rows` normalization for eligible Markdown tables,
  `confidence-level-delimiters` normalization for assessment confidence
  values whose single level is directly followed by explanatory words, and
  `wrapped-field-labels` normalization for a missing required assessment
  field label wrapped across one line break at a space in its own section.
- The no-op harness is development-only under `tests/fixtures`. It is
  never registered by production code, packaged, exposed through launcher or
  runner choices, or described as supported runtime behavior.
- Any further production harness requires a separate explicit support
  decision, complete safety and capability evidence, Fedora validation,
  packaging and user-documentation updates, and a release. Contract
  generalization alone is not that decision. The Claude Code decision followed
  that process.

## Refactor sequence

- [x] Remove alternate-platform launchers, helpers, runners, output
  modules, and tests from the packaged and development trees.
- [x] Remove alternate-platform hook entries and metadata.
- [x] Remove parity assertions from the Linux validator.
- [x] Remove hosted CI workflows.
- [x] Consolidate duplicated orchestration and output logic around the
  Bash implementation.
- [x] Drop non-Fedora compatibility constraints and document the
  supported Linux/Bash/GNU toolchain.
- [x] Add any remaining useful Linux-native installation coverage.
- [x] Re-run public-release export/preflight and update package contents
  after the removal.

## Non-goals

- Maintaining dormant alternate-platform behavior while Linux evolves.
- Keeping duplicate implementations synchronized for possible future
  use.
- Adding compatibility shims that increase the Linux maintenance
  burden.
- Claiming support for an unvalidated operating system or shell.
- Treating a development fixture or a safe harness ID as production support.

## Completion criteria

The platform refactor is complete when no supported documentation,
packaged runtime path, hosted workflow, or required validator depends
on an alternate implementation, and the Linux validator covers the
single Bash implementation end to end.
