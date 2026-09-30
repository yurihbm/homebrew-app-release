#!/usr/bin/env bash
# Sets up (or updates) a macOS app repo to test and release through this repo's
# test/release actions and the yurihbm/homebrew-apps tap. Run from the app repo root:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/yurihbm/homebrew-app-release/main/install.sh) [--scheme NAME] [--cask NAME]
#
# Writes .github/workflows/{test,release}.yml, .github/dependabot.yml (if missing)
# and .claude/skills/release/SKILL.md, all pinned to this repo's latest tag.
set -euo pipefail

SHARED_REPO="yurihbm/homebrew-app-release"
TAP_REPO="yurihbm/homebrew-apps"

die() { echo "error: $*" >&2; exit 1; }
warn() { echo "warning: $*" >&2; WARNINGS=$((WARNINGS + 1)); }
WARNINGS=0

for cmd in git gh curl xcodebuild; do
    command -v "$cmd" >/dev/null || die "$cmd is required"
done

SCHEME=""
CASK=""
while [ $# -gt 0 ]; do
    case "$1" in
        --scheme) SCHEME="${2:?--scheme needs a value}"; shift 2 ;;
        --cask) CASK="${2:?--cask needs a value}"; shift 2 ;;
        *) die "unknown argument: $1" ;;
    esac
done

ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git repo"
[ "$ROOT" = "$(pwd -P)" ] || die "run this from the repo root ($ROOT)"

shopt -s nullglob
projects=(*.xcodeproj)
[ ${#projects[@]} -eq 1 ] || die "expected exactly one .xcodeproj in the repo root, found ${#projects[@]}"
PROJECT="${projects[0]}"

SCHEME="${SCHEME:-${PROJECT%.xcodeproj}}"
xcodebuild -list -json -project "$PROJECT" | grep -q "\"$SCHEME\"" \
    || die "scheme '$SCHEME' not found in $PROJECT (pass --scheme)"

# KeyboardCleanTool -> keyboard-clean-tool
CASK="${CASK:-$(echo "$SCHEME" | sed -E 's/([a-z0-9])([A-Z])/\1-\2/g' | tr '[:upper:]' '[:lower:]')}"

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || die "couldn't resolve the GitHub repo (is gh logged in?)"

TAG=$(git ls-remote --tags --refs --sort=-v:refname "https://github.com/$SHARED_REPO.git" 'v*' | head -1 | sed 's|.*refs/tags/||')
[ -n "$TAG" ] || die "no v* tag found in $SHARED_REPO"

echo "Installing $SHARED_REPO $TAG into $REPO"
echo "  project: $PROJECT"
echo "  scheme:  $SCHEME"
echo "  cask:    $CASK"

mkdir -p .github/workflows .claude/skills/release

cat > .github/workflows/test.yml <<EOF
name: Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: xcode-27

    steps:
      - uses: $SHARED_REPO/test@$TAG
        with:
          project: $PROJECT
          scheme: $SCHEME
EOF

cat > .github/workflows/release.yml <<EOF
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: xcode-27
    # Only v* tags may deploy to this environment; it holds HOMEBREW_TAP_TOKEN.
    environment: main
    permissions:
      contents: write

    steps:
      - uses: $SHARED_REPO/release@$TAG
        with:
          project: $PROJECT
          scheme: $SCHEME
          cask: $CASK
          tap-token: \${{ secrets.HOMEBREW_TAP_TOKEN }}
EOF

if [ ! -f .github/dependabot.yml ]; then
    cat > .github/dependabot.yml <<EOF
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
EOF
elif ! grep -q "github-actions" .github/dependabot.yml; then
    warn ".github/dependabot.yml exists but doesn't cover github-actions; the workflow pin won't be updated automatically"
fi

curl -fsSL "https://raw.githubusercontent.com/$SHARED_REPO/$TAG/skills/release/SKILL.md" -o .claude/skills/release/SKILL.md

# One-time setup that this script deliberately doesn't do for you.
gh api "repos/$TAP_REPO/contents/Casks/$CASK.rb" --silent 2>/dev/null \
    || warn "Casks/$CASK.rb doesn't exist in $TAP_REPO yet; create it (see $SHARED_REPO README)"
if gh api "repos/$REPO/environments/main" --silent 2>/dev/null; then
    gh api "repos/$REPO/environments/main/secrets" --jq '.secrets[].name' | grep -qx HOMEBREW_TAP_TOKEN \
        || warn "the 'main' environment has no HOMEBREW_TAP_TOKEN secret"
    gh api "repos/$REPO/environments/main/deployment-branch-policies" --jq '.branch_policies[] | "\(.type):\(.name)"' | grep -qx 'tag:v\*' \
        || warn "the 'main' environment isn't restricted to v* tags"
else
    warn "$REPO has no 'main' environment; create it with a v* tag rule and the HOMEBREW_TAP_TOKEN secret"
fi

echo
echo "Done. Review with 'git diff' and 'git status', then commit."
[ "$WARNINGS" -eq 0 ] || echo "$WARNINGS warning(s) above need attention before the first release."
