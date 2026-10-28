#!/usr/bin/env bash
# Fail when the resolved Cabal plan contains a consumer layer package or a runtime
# migration library.
set -euo pipefail
cd "$(dirname "$0")/.."
cabal build all --dry-run >/dev/null
forbidden='^(kenshou-(pgmq|kiroku|shibuya|kafka|keiro|runtime)|keiro-migrations|kiroku-store-migrations|pgmq-migration)$'
found=$(jq -r '."install-plan"[] | ."pkg-name"' dist-newstyle/cache/plan.json | sort -u | grep -E "$forbidden" || true)
if [ -n "$found" ]; then
  echo "plan-check: forbidden packages in build plan:" >&2
  printf '%s\n' "$found" >&2
  exit 1
fi
echo "plan-check: clean"
