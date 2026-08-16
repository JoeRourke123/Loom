#!/usr/bin/env bash
# Download @swc/wasm and extract wasm.js + wasm_bg.wasm into Loom/Resources/SWC/.
# Run from repo root: ./Scripts/fetch-swc.sh
# Run once when upgrading SWC version. Output is committed to repo.
#
# Note: @swc/wasm ships the binary as a SEPARATE wasm_bg.wasm (~19 MB) with a small JS glue
# file, unlike @swc/wasm-typescript which embedded it as base64 in a single wasm.js. Both
# files are needed. swc-compat.js shims the require('fs')/require('path') pair the glue uses
# to load the binary, and SWCCompiler hands it the bytes straight from the app bundle.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/Loom/Resources/SWC"
TMP="$(mktemp -d)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

mkdir -p "$OUT"
cd "$TMP"
echo "Fetching @swc/wasm..."
npm pack @swc/wasm >/dev/null 2>&1
tar xzf swc-wasm-*.tgz >/dev/null 2>&1
cp package/wasm.js "$OUT/wasm.js"
cp package/wasm_bg.wasm "$OUT/wasm_bg.wasm"
echo "Done:"
echo "  $(du -h "$OUT/wasm.js" | cut -f1)	$OUT/wasm.js"
echo "  $(du -h "$OUT/wasm_bg.wasm" | cut -f1)	$OUT/wasm_bg.wasm"
