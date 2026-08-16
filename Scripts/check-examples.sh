#!/usr/bin/env bash
# Parse-check every shipped example. Run from repo root: ./Scripts/check-examples.sh
# Requires: node, npx (esbuild is auto-downloaded via npx)
#
# This is the fast pre-check, not the real gate. The real gate is
# ExampleCatalog.runCompilerSelfCheck(), which runs on every DEBUG launch and puts each example
# through the actual shipping pipeline — scaffold, SWC, ModuleBundler, ConfigExtractor, SiriLint.
# This only catches syntax errors, but it catches them in two seconds instead of a build-and-launch.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLES="$REPO_ROOT/Examples"
DOCS="$REPO_ROOT/Loom/Resources/Docs/examples"
CATALOG="$REPO_ROOT/Loom/Examples/Example.swift"

fail=0

echo "Parsing $EXAMPLES/**/*.ts"
while IFS= read -r file; do
  if ! out=$(npx --yes esbuild "$file" --loader:.ts=ts --format=cjs --target=es2022 2>&1 >/dev/null); then
    echo "  FAIL ${file#$REPO_ROOT/}"; echo "$out" | sed 's/^/       /'; fail=1
  else
    echo "  ok   ${file#$REPO_ROOT/}"
  fi
done < <(find "$EXAMPLES" -name '*.ts' | sort)

echo
echo "Checking every example folder has a write-up"
for dir in "$EXAMPLES"/*/; do
  slug="$(basename "$dir")"
  [ -f "$dir/main.ts" ] || { echo "  FAIL $slug: no main.ts"; fail=1; }
  [ -f "$DOCS/$slug.md" ] || { echo "  FAIL $slug: no $slug.md in Docs/examples"; fail=1; }
  grep -q "slug: \"$slug\"" "$CATALOG" || { echo "  FAIL $slug: not in ExampleCatalog"; fail=1; }
done
[ "$fail" -eq 0 ] && echo "  ok   all $(find "$EXAMPLES" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ') examples"

echo
if [ "$fail" -eq 0 ]; then echo "Done."; else echo "Failures above."; exit 1; fi
