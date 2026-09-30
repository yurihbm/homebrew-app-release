# homebrew-app-release

Shared CI and release tooling for my macOS apps distributed through the [`yurihbm/homebrew-apps`](https://github.com/yurihbm/homebrew-apps) tap (e.g. [Lucid](https://github.com/yurihbm/lucid), [Keyboard Clean Tool](https://github.com/yurihbm/keyboard-clean-tool)).

- `test` — composite action: checks out the repo and runs `xcodebuild test`.
- `release` — composite action, for a `v*` tag: tests, archives an ad-hoc signed Release build versioned from the tag, publishes a GitHub Release with the zipped `.app`, and bumps the cask in the tap.
- `skills/release/SKILL.md` — the `/release` Claude Code skill, copied into each app repo.
- `install.sh` — wires an app repo up to all of the above.

The app repo's workflows declare the runner, environment, permissions, and secrets; the actions only hold the steps:

```yaml
jobs:
  release:
    runs-on: xcode-27
    environment: main
    permissions:
      contents: write

    steps:
      - uses: yurihbm/homebrew-app-release/release@v0.1.0
        with:
          project: Lucid.xcodeproj
          scheme: Lucid
          cask: lucid
          tap-token: ${{ secrets.HOMEBREW_TAP_TOKEN }}
```

## Installing into an app repo

From the app repo root:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/yurihbm/homebrew-app-release/main/install.sh)
```

It detects the `.xcodeproj`, uses its name as the scheme and derives the cask name from it (`KeyboardCleanTool` → `keyboard-clean-tool`); override with `--scheme NAME` / `--cask NAME`. It writes, pinned to this repo's latest tag:

- `.github/workflows/test.yml` and `release.yml`, using the actions above
- `.github/dependabot.yml`, if missing, so Dependabot opens PRs when a new tag of this repo ships
- `.claude/skills/release/SKILL.md`

Re-running it updates everything to the latest tag, including the skill. It never commits; review with `git diff`.

The release zip is always `<scheme>.zip`; the `.app` inside is named after the target's `PRODUCT_NAME`, which can contain spaces (e.g. `Keyboard Clean Tool.app`).

## One-time setup for a new app

`install.sh` checks these and warns if anything is missing, but doesn't create them:

1. **Cask** — add `Casks/<cask>.rb` to `yurihbm/homebrew-apps`. `version` and `sha256` get overwritten on every release:

   ```ruby
   cask "<cask>" do
     version "0.0.0"
     sha256 "0"

     url "https://github.com/yurihbm/<repo>/releases/download/v#{version}/<scheme>.zip"
     name "<App Name>"
     desc "<One-line description>"
     homepage "https://github.com/yurihbm/<repo>"

     app "<PRODUCT_NAME>.app"

     postflight_steps do
       run "/usr/bin/xattr", args: ["-cr", "{{appdir}}/<PRODUCT_NAME>.app"]
     end
   end
   ```

   The `postflight_steps` clears the quarantine flag because the apps aren't notarized — worth saying so in the app's README.

2. **Environment** — in the app repo, create a GitHub Environment named `main` whose "Deployment branches and tags" rule allows only the `v*` tag pattern.

3. **Secret** — add `HOMEBREW_TAP_TOKEN` to that environment: a fine-grained PAT scoped only to `yurihbm/homebrew-apps` with `Contents: Read and write`. The generated `release.yml` passes it to the action as `tap-token`.

## Releasing a new version of this repo

Commit to `main`, push an annotated `vX.Y.Z` tag, then `gh release create vX.Y.Z --generate-notes`. App repos pick it up through Dependabot (workflows) or by re-running `install.sh` (workflows + skill).
