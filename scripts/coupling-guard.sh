#!/usr/bin/env bash
# Fail when a generic harness package, the synthetic suite, or a JSON schema names a
# consumer runtime layer outside the exact lines in scripts/coupling-allowlist.txt.
set -euo pipefail
cd "$(dirname "$0")/.."
packages=(kenshou-core kenshou-check kenshou-measure kenshou-diagnose kenshou-telemetry kenshou-evidence kenshou-remote kenshou-cli kenshou-synthetic)
pattern='keiro|kiroku|pgmq|shibuya|kafka'
# kenshou-evidence/test/fixtures/consumer-records/ holds verbatim consumer evidence and
# is the only directory-level exemption; fixtures/consumer-baseline/ is outside every
# package.
hits=$(grep -riE "$pattern" "${packages[@]}" schemas --include='*.hs' --include='*.cabal' --include='*.json' --include='*.md' | grep -v '/test/fixtures/consumer-records/' || true)
remaining=$(printf '%s\n' "$hits" | sed '/^$/d' | grep -vxFf scripts/coupling-allowlist.txt || true)
if [ -n "$remaining" ]; then
  echo "coupling-guard: layer names found in generic packages:" >&2
  printf '%s\n' "$remaining" >&2
  exit 1
fi
echo "coupling-guard: clean"
