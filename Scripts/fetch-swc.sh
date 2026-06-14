#!/usr/bin/env bash
# Download @swc/wasm-typescript and extract wasm.js into Loom/Resources/SWC/.
# Run from repo root: ./Scripts/fetch-swc.sh
# Run once when upgrading SWC version. Output is committed to repo.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/Loom/Loom/Resources/SWC"
TMP="$(mktemp -d)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

cd "$TMP"
echo "Fetching @swc/wasm-typescript..."
npm pack @swc/wasm-typescript >/dev/null 2>&1
tar xzf swc-wasm-typescript-*.tgz >/dev/null 2>&1
cp package/wasm.js "$OUT/wasm.js"
echo "Done. $(du -sh "$OUT/wasm.js" | cut -f1) written to $OUT/wasm.js"
