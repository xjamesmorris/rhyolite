# Publishing preparation

This repository is prepared for a public release path, but it is not
fully publishable until the gates below are closed.

If a public release originates from a non-public preparation repository,
never push that repository's history or tags directly to the public
remote. Publish only from an approved exported tree.

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

## First public release

1. Approve the exact source ref to publish after completing review in the
   preparation repository.
2. Export the approved ref into an empty destination and run preflight. Bash
   example:

   ```bash
   tools/public-release/public-export.sh \
     --source-ref <approved-commit-or-tag> \
     --destination ../rhyolite-public

   tools/public-release/public-preflight.sh \
     --destination ../rhyolite-public \
     --source-commit <resolved-commit-from-export-audit>
   ```

3. Review the export audit report and preflight output. Do not proceed until
   the exported tree is approved.
4. The target `xjamesmorris/rhyolite` repository may be created privately
   before export, but it must remain empty. Initialize the approved exported
   tree as a brand-new Git history and push its root commit:

   ```bash
   git init
   git add .
   git commit -m "Initial public release"
   git branch -M main
   git remote add origin https://github.com/xjamesmorris/rhyolite.git
   git push -u origin main
   ```

5. If the release was prepared in a non-public repository, do not push that
   repository's branch, history, or tags to the public remote. Never use
   `git push --mirror`, never create the first public tag from the
   non-public repository, and never reuse non-public tags by pushing them
   outward.
6. After the exported tree is committed and pushed from the new public
   repository, create and push the first public stable tag from that public
   repository, for example `v0.4.1`.
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

Before announcing the release, make the repository public, enable
GitHub private vulnerability reporting, verify the report form, and
confirm anonymous marketplace installation. GitHub Copilot plugins are
currently public-preview features.

## Later public releases

1. Make and review release changes in the preparation repository, then
   approve the exact source ref to publish.
2. Re-run `tools/public-release/public-export.*` and
   `tools/public-release/public-preflight.*` for that approved ref.
3. Update a checkout of the existing public repository from the approved
   exported tree only, review the public diff there, commit the release in the
   public repository, and push the public branch.
4. Create and push the matching stable tag from the public repository commit
   after the public branch is pushed.
5. Never merge, rebase, fetch, or push non-public preparation history or
   tags into the public repository. Public history must remain the
   sequence of approved exported trees only.

## Versioning

- Keep `VERSION`, `plugin.json`, and `marketplace.json` versions
  synchronized.
- Create release tags in the public repository only, after the approved
  exported tree is committed there.
- Record security or behavior changes in release notes.
- Test installation from the remote public repository, not only a local path.

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
7. Apply the approved exported tree to the public repository checkout, review
   the public diff, commit there, and push the public branch.
8. Create and push the matching stable tag from the public repository, for
   example `v0.4.1`.
9. Verify a fresh remote install and a manual update from the prior public
   release, including the one-line load status, the large plaque after
   a review-start command, and the exact
   `help`/`status`/`explain scopes` setup behavior.
10. If the source of truth is non-public, never push its branch, history,
   or tags to the public remote.

Only stable tags matching `vX.Y.Z` and created in the public repository should
be treated as public release versions.
