#!/usr/bin/env bash
# Download htmx and extract htmx.min.js into Loom/Resources/Web/.
# Run from repo root: ./Scripts/fetch-htmx.sh
# Run once when upgrading htmx version. Output is committed to repo.
#
# Loom.ui.web() serves this from the loomweb:// scheme handler, so web sheets work offline
# and never touch a CDN.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/Loom/Resources/Web"
TMP="$(mktemp -d)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$OUT"
cd "$TMP"
echo "Fetching htmx.org..."
npm pack htmx.org >/dev/null 2>&1
tar xzf htmx.org-*.tgz >/dev/null 2>&1
cp package/dist/htmx.min.js "$OUT/htmx.min.js"
echo "Done. $(du -sh "$OUT/htmx.min.js" | cut -f1) written to $OUT/htmx.min.js"
