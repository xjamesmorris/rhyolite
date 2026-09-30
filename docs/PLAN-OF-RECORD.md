# Platform plan of record

**Decision date:** September 30, 2026

## Decision

Rhyolite is a **Fedora Linux 44, Bash-only** product for this release.

- Fedora Linux 44 is the only supported development and validation
  platform.
- Runtime support is Linux-only; other Linux distributions are not
  currently validated.
- Bash is the canonical launcher, helper, runner, and validation
  implementation.
- Validation is local only. Hosted continuous integration is not part of
  the current release gate.
- Additional operating systems, shells, and Linux distributions are not
  supported or validated.

Broader platform support may be reconsidered after the Fedora/Bash
implementation is stable and easier to maintain. Reconsideration
requires a new explicit project decision; compatibility must not be
preserved speculatively.

## Immediate engineering policy

1. New features and fixes target Linux and Bash only.
2. Do not add alternate-platform implementations, branches, or parity
   assertions unless a later decision explicitly restores that scope.
3. `bash ./tests/validate-plugin.sh` on Fedora 44 is the authoritative
   full plugin validator.
4. No hosted workflow is required or shipped. Maintainers run release
   validation locally on Fedora Linux 44.
5. Public documentation advertises only the Fedora/Linux/Bash workflow.

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

## Completion criteria

The platform refactor is complete when no supported documentation,
packaged runtime path, hosted workflow, or required validator depends
on an alternate implementation, and the Linux validator covers the
single Bash implementation end to end.
