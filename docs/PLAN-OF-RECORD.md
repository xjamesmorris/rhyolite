# Platform plan of record

**Decision date:** September 30, 2026

**Constrained broker exception approved:** October 1, 2026

## Decision

Rhyolite is a **Fedora Linux 44, Bash-only** product for this release.

- Fedora Linux 44 is the only supported development and validation
  platform.
- Runtime support is Linux-only; other Linux distributions are not
  currently validated.
- Bash is the canonical launcher, helper, runner, and validation
  implementation.
- The bundled Python 3 standard-library research egress broker is the one
  approved constrained exception. Bash remains authoritative for
  orchestration, planning, lifecycle, policy trust, cleanup, failure mapping,
  and artifact finalization.
- Validation is local only. Hosted continuous integration is not part of
  the current release gate.
- Additional operating systems, shells, and Linux distributions are not
  supported or validated.
- GitHub Copilot is the only supported production review harness. The fixed
  harness seam does not advertise or imply support for other CLIs.

Broader platform support may be reconsidered after the Fedora/Bash
implementation is stable and easier to maintain. Reconsideration
requires a new explicit project decision; compatibility must not be
preserved speculatively.

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
5. Public documentation advertises only the Fedora/Linux/Bash workflow.

## Contributor and harness guidance

- [../AGENTS.md](../AGENTS.md) is the canonical repository-wide contributor
  and LLM development contract. Tool-specific files point to it rather than
  maintaining divergent policy copies.
- [HARNESS-ARCHITECTURE.md](HARNESS-ARCHITECTURE.md) describes the implemented
  Contract-v3 seam.
- [ADDING-A-HARNESS.md](ADDING-A-HARNESS.md) is the required implementation
  playbook for Contract v3 and any future production adapter.
- Contract v3 promotes harness execution identity and validated runtime
  selection into approval-bound data using plan schema 5 and state schema 6.
  Its provider summary is a validated
  object with `Id`, `Host`, and `ForwardedEnvVarNames`.
- The no-op harness is development-only under `tests/fixtures`. It is
  never registered by production code, packaged, exposed through launcher or
  runner choices, or described as supported runtime behavior.
- A second production harness requires a separate explicit support decision,
  complete safety and capability evidence, Fedora validation, packaging and
  user-documentation updates, and a release. Contract generalization alone is
  not that decision.

## Refactor sequence

- [x] Remove alternate-platform launchers, helpers, runners, output
  modules, and tests from the packaged and development trees.
- [x] Remove alternate-platform hook entries and metadata.
- [x] Remove parity assertions from the Linux validator.
- [x] Remove hosted CI workflows.
- [ ] Consolidate duplicated orchestration and output logic around the
  Bash implementation.
- [x] Drop non-Fedora compatibility constraints and document the
  supported Linux/Bash/GNU toolchain.
- [ ] Add any remaining useful Linux-native installation coverage.
- [ ] Re-run public-release export/preflight and update package contents
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
