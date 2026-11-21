#!/usr/bin/env bash
# Set the HEXhand version in every place the release workflow checks.
# Usage: scripts/set-version.sh 0.11.16
# The release "verify" job fails whenever package.json and Cargo.toml disagree
# (that is what killed v0.11.13 and v0.11.14), so always bump through this.
set -euo pipefail
new="${1:?usage: scripts/set-version.sh X.Y.Z}"
[[ "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "not a semver: $new" >&2; exit 1; }
cd "$(dirname "$0")/.."

sed -i.bak -E "0,/^version = \"[0-9]+\.[0-9]+\.[0-9]+\"/s//version = \"${new}\"/" Cargo.toml
sed -i.bak -E "0,/\"version\": \"[0-9]+\.[0-9]+\.[0-9]+\"/s//\"version\": \"${new}\"/" package.json
rm -f Cargo.toml.bak package.json.bak
cargo update -p hexhand --precise "$new" >/dev/null 2>&1 || true

cargo_v=$(grep -m1 -E '^version = ' Cargo.toml | cut -d'"' -f2)
npm_v=$(node -p "require('./package.json').version")
lock_v=$(awk '/^name = "hexhand"/{f=1} f && /^version = /{print; exit}' Cargo.lock | cut -d'"' -f2)
echo "Cargo.toml=$cargo_v package.json=$npm_v Cargo.lock=$lock_v"
[ "$cargo_v" = "$new" ] && [ "$npm_v" = "$new" ] && [ "$lock_v" = "$new" ] || { echo "MISMATCH" >&2; exit 1; }
echo "ok — now: git commit -am 'chore(release): $new' && git tag -a v$new -m 'HEXhand v$new' && git push hexhand HEAD:main && git push hexhand v$new"
