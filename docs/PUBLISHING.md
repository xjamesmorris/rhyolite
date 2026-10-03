# Publishing and release process

`xjamesmorris/rhyolite` is the canonical source and release repository.
Release branches, commits, and stable tags originate here. Repository
visibility is an independent administrative decision; changing visibility is
not part of the release script or checklist.

The clean export and preflight remain mandatory release gates. They validate
the exact candidate tree but do not create a separate history or release
repository.

## Mandatory pre-publication gates

1. Keep the canonical GNU GPL version 2 text in `LICENSE` and the
   project designation as `GPL-2.0-only`. Do not publish without the
   license file.
2. Keep the published owner/repository URLs synchronized under
   `https://github.com/xjamesmorris/rhyolite`, including
   `plugins/rhyolite/branding/welcome-metadata.json` and the
   prompt-native help panel.
3. Keep `.github/CODEOWNERS` assigned to `@xjamesmorris`. The initial
   branch policy must not require hosted validation checks or an
   unavailable external approval.
4. Publish the support routes, including the usage-question issue form,
   GitHub private vulnerability reporting, and the private conduct
   contact.
5. Configure branch protection without hosted-CI requirements and
   smoke-test the published support and release paths.
6. Run the Fedora Linux 44 Bash validator and smoke-test installation
   and manual update from the published repository.
7. Smoke-test the onboarding flow from a new Copilot CLI session:
   confirm the one-line version/start status, invoke `/rhyolite:start`
   to see the large plaque, verify exact
   `help`/`status`/`explain scopes` behavior, and confirm isolated child
   review homes still disable hooks.
   Also trigger launcher and extension failures and confirm their
   `Support`/`Contribute` lines now use the published issue and pull
   request URLs.
8. Export and preflight the exact approved source ref with
   `tools/public-release/` before any public push or tag.

## Canonical release workflow

1. Prepare and review the release on a feature branch in this repository.
2. Export the exact candidate commit into an empty destination and run
   preflight. Bash example:

   ```bash
   tools/public-release/public-export.sh \
     --source-ref <approved-commit-or-tag> \
     --destination ../rhyolite-public

   tools/public-release/public-preflight.sh \
     --destination ../rhyolite-public \
     --source-commit <resolved-commit-from-export-audit>
   ```

3. Review the export audit report and preflight output. Do not proceed until
   the candidate tree is approved.
4. Fast-forward `main` to the approved candidate commit. Do not rewrite
   `main`, publish a different tree, or tag an unpushed commit.
5. Push `main`, create the matching annotated stable tag on that exact commit,
   and push the tag, for example `v0.5.0`.
6. Verify that local `main`, `origin/main`, and the stable tag resolve to the
   same commit and that every version surface matches the tag.
7. Ask users to register the marketplace repository:

   ```text
   copilot plugin marketplace add https://github.com/xjamesmorris/rhyolite
   ```

8. Install the plugin:

   ```text
   copilot plugin install rhyolite@rhyolite-tools
   ```

   Installation only registers the plugin components. Start a new
   Copilot CLI session after installation to load the local
   display-only `sessionStart` availability hook.

9. Confirm the installation:

   ```text
   copilot plugin list
   ```

10. Enable extension commands with `/experimental on`, then start a new
    session. Confirm the one-line version/start status appears, then the
    large plaque appears only after a review-start command;
    `/rhyolite:start` selects `rhyolite:repo-review`,
    `/rhyolite:repo-review` remains compatible, `/repo-review` provides
    the experimental shorthand, and the full welcome panel is
    followed by the first setup question in the same turn. Confirm the
    source, output, scope, provenance-lookback, final run/edit/explain,
    and open-HTML decisions use Copilot CLI's numbered picker with its
    automatic final `Other` custom-answer option.

If public distribution is intended, separately verify repository visibility,
GitHub private vulnerability reporting, support forms, anonymous marketplace
installation, and update behavior before announcing the release. GitHub
Copilot plugins are public-preview features.

## Versioning

- Keep `VERSION`, `plugin.json`, and `marketplace.json` versions
  synchronized.
- Create release tags in this canonical repository only after the approved
  commit is pushed to `origin/main`.
- Record security or behavior changes in release notes.
- Test installation from the canonical remote repository or tag, not only a
  local path.

## User update process

Users update both the marketplace checkout and the installed plugin:

```text
copilot plugin marketplace update rhyolite-tools && copilot plugin update rhyolite@rhyolite-tools
```

They can verify the installed version with:

```text
copilot plugin list
```

This release configuration does not ship automatic update hooks; updates
are manual unless a future public release deliberately adds an approved
replacement. It does ship a local display-only `sessionStart` hook, so
users should restart Copilot CLI after installing or updating to load
that onboarding notice.

## Maintainer release checklist

1. Update `VERSION`, `plugins/rhyolite/plugin.json`,
   `.github/plugin/marketplace.json`, and `CHANGELOG.md`.
2. On Fedora Linux 44, run the release validator:

   ```bash
   bash ./tests/validate-all.sh
   ```

3. Run `git diff --check`,
   `node tests/validate-tui-runtime.mjs --self-check`, and review the
   complete source change set.
4. Run `bash ./tests/test-install.sh`.
5. Export the approved source ref with `tools/public-release/public-export.sh`
   and run `tools/public-release/public-preflight.sh` against the exported tree.
6. Install from a local marketplace fixture and smoke-test the namespaced
   agents from the approved exported tree.
7. Fast-forward local `main` to the approved release commit and push
   `origin/main`.
8. Create and push the matching annotated stable tag on that exact commit,
   for example `v0.5.0`.
9. Verify a fresh remote install and a manual update from the prior public
   release, including the one-line load status, the large plaque after
   a review-start command, and the exact
   `help`/`status`/`explain scopes` setup behavior.
10. Verify the remote branch and tag resolve to the same commit, then remove
   merged release branches.

Only stable tags matching `vX.Y.Z` and created in this canonical repository
should be treated as release versions.
