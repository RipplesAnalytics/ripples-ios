#!/usr/bin/env bash
# Usage: ./scripts/release.sh 0.1.1
#
# Bumps RipplesVersion.current, commits, tags, and pushes. The git tag is
# what SPM consumers resolve against — see README.md for pinning options.

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <version>   e.g. $0 0.1.1" >&2
    exit 1
fi

version="$1"

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "Error: '$version' is not a valid semver string" >&2
    exit 1
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Error: working tree has uncommitted changes — commit or stash first" >&2
    exit 1
fi

if git rev-parse "$version" >/dev/null 2>&1; then
    echo "Error: tag '$version' already exists" >&2
    exit 1
fi

version_file="Sources/Ripples/RipplesVersion.swift"
sed -i.bak -E "s/static let current = \".*\"/static let current = \"$version\"/" "$version_file"
rm "${version_file}.bak"

if git diff --quiet -- "$version_file"; then
    echo "Error: version file unchanged — is RipplesVersion.current already at $version?" >&2
    exit 1
fi

swift build

git add "$version_file"
git commit -m "Release $version"
git tag "$version"

echo
echo "Tagged $version locally. To publish:"
echo "    git push && git push origin $version"
