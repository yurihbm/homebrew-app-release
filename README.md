# homebrew-app-release

Shared CI and release tooling for my macOS apps distributed through the [`yurihbm/homebrew-apps`](https://github.com/yurihbm/homebrew-apps) tap (e.g. [Lucid](https://github.com/yurihbm/lucid), [Keyboard Clean Tool](https://github.com/yurihbm/keyboard-clean-tool)).

- `.github/workflows/test.yml` — reusable workflow: `xcodebuild test`.
- `.github/workflows/release.yml` — reusable workflow, run on a `v*` tag: tests, archives an ad-hoc signed Release build versioned from the tag, publishes a GitHub Release with the zipped `.app`, and bumps the cask in the tap.
- `skills/release/SKILL.md` — the `/release` Claude Code skill, copied into each app repo.
- `install.sh` — wires an app repo up to all of the above.

## Installing into an app repo

From the app repo root:

```sh
bash <(curl -fsSL https://raw.githubusercontent.com/yurihbm/homebrew-app-release/main/install.sh)
```

It detects the `.xcodeproj`, uses its name as the scheme and derives the cask name from it (`KeyboardCleanTool` → `keyboard-clean-tool`); override with `--scheme NAME` / `--cask NAME`. It writes, pinned to this repo's latest tag by commit SHA:

- `.github/workflows/test.yml` and `release.yml` (thin callers of the reusable workflows)
- `.github/dependabot.yml`, if missing, so Dependabot opens PRs when a new tag of this repo ships
- `.claude/skills/release/SKILL.md`

Re-running it updates everything to the latest tag, including the skill. It never commits; review with `git diff`.

The app's scheme must build `<scheme>.app`.

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

     app "<scheme>.app"

     postflight_steps do
       run "/usr/bin/xattr", args: ["-cr", "{{appdir}}/<scheme>.app"]
     end
   end
   ```

   The `postflight_steps` clears the quarantine flag because the apps aren't notarized — worth saying so in the app's README.

2. **Environment** — in the app repo, create a GitHub Environment named `main` whose "Deployment branches and tags" rule allows only the `v*` tag pattern.

3. **Secret** — add `HOMEBREW_TAP_TOKEN` to that environment: a fine-grained PAT scoped only to `yurihbm/homebrew-apps` with `Contents: Read and write`. The reusable workflow declares `environment: main`, which resolves to the *calling* repo's environment, so the secret never has to be passed explicitly.

## Releasing a new version of this repo

Commit to `main`, then push an annotated `vX.Y.Z` tag. App repos pick it up through Dependabot (workflows) or by re-running `install.sh` (workflows + skill).
