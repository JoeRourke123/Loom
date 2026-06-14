#!/usr/bin/env bash
# Bundle vendor npm packages for use in Loom's JSC execution environment.
# Run from repo root: ./Scripts/bundle-vendors.sh
# Requires: node, npm, npx (esbuild is auto-downloaded via npx)
# Output: Loom/Resources/Vendors/*.js (committed to repo)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/Loom/Loom/Resources/Vendors"
TMP="$(mktemp -d)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

cd "$TMP"
npm init -y >/dev/null
npm install --save lodash date-fns zod cheerio mathjs marked csv-parse yaml >/dev/null 2>&1

bundle() {
  local pkg="$1"
  local entry="${2:-$pkg}"
  local global="__loom_vendor_${pkg//-/_}__"
  echo -n "  $pkg... "
  npx esbuild "$entry" \
    --bundle \
    --format=iife \
    --global-name="$global" \
    --outfile="$OUT/$pkg.js" \
    --platform=browser \
    --define:process.env.NODE_ENV='"production"' \
    --log-level=error
  echo "$(du -sh "$OUT/$pkg.js" | cut -f1)"
}

echo "Bundling vendor packages → $OUT"
bundle lodash
bundle date-fns
bundle zod
bundle cheerio
bundle mathjs
bundle marked
bundle csv-parse csv-parse/browser/esm
bundle yaml

echo "Done."
