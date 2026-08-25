#!/usr/bin/env bash
# Sync this mirror to an upstream tag: our files are purely additive (paths
# unique to this repo), so syncing = checkout upstream tag + re-apply our tree.
set -euo pipefail

TAG="${1:?usage: sync-upstream.sh <upstream-tag> e.g. v7.4.0+rev5}"
BRANCH="${2:-abrp-main}"

export CI=1 GIT_TERMINAL_PROMPT=0

git remote get-url upstream >/dev/null 2>&1 || \
  git remote add upstream https://github.com/balena-os/balena-raspberrypi.git
# fetch ONLY the target tag: upstream moves branch-like tags (alexgg/EXT-*)
# which 'fetch --tags' refuses to clobber -> silent exit-1 failure
git fetch upstream --no-tags "+refs/tags/${TAG}:refs/tags/${TAG}"

# our additive tree, saved aside
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
for p in layers/meta-abrp .github/workflows/build-os.yml \
         .github/workflows/build-supervisor.yml \
         .github/workflows/yocto-build-deploy.yml \
         .github/workflows/seed-sstate.yml \
         scripts/patch-workflow.py scripts/sync-upstream.sh ABRP.md; do
  mkdir -p "$WORK/$(dirname "$p")"
  cp -a "$p" "$WORK/$p"
done

git checkout --quiet -B "$BRANCH" "$TAG"
for p in layers/meta-abrp .github/workflows/build-os.yml \
         .github/workflows/build-supervisor.yml \
         .github/workflows/yocto-build-deploy.yml \
         .github/workflows/seed-sstate.yml \
         scripts/patch-workflow.py scripts/sync-upstream.sh ABRP.md; do
  rm -rf "$p"; mkdir -p "$(dirname "$p")"; cp -a "$WORK/$p" "$p"
done

# drop upstream CI entrypoints again (they deploy to balena-cloud)
rm -f .github/workflows/raspberrypi*.yml .github/workflows/revpi*.yml \
      .github/workflows/flowzone.yml .github/workflows/esr.yml \
      .github/workflows/npe-x500-m3.yml .github/workflows/rt-rpi-300.yml

# NOTE: do NOT regenerate .github/workflows/yocto-build-deploy.yml from this
# tag's submodule pin here. GITHUB_TOKEN (a GitHub App token) cannot push
# refs that change workflow files vs the default branch ('workflows'
# permission is not grantable to GITHUB_TOKEN). The additive copy taken
# from abrp-main above is byte-identical to the default branch, which keeps
# the auto branch pushable by CI. Regeneration happens when abrp-main
# itself is updated (pushed with a human credential).


git add -A
git commit --quiet -m "Sync upstream ${TAG} + abrp additive tree" || true
echo "Synced to ${TAG} on ${BRANCH}. Review: git diff HEAD~1 --stat"

# tag OUR sync commit, not the fetched upstream tag object: upstream tags
# carry their .github tree, and pushing a ref whose tree creates/updates
# workflow files (e.g. an esr.yml change in the upstream release) is
# rejected for GitHub App tokens.
git tag -f "$TAG" "$BRANCH"
