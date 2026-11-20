---
type: Friction Entry
title: "Evidence tests copy a bundle with missing run records"
description: "Three existing evidence tests fail when the vendored bundle's attestations reference ignored run files."
generated:
  by: "codex-cli/gpt-6.2-sol"
  at: "2026-11-20T02:20:59Z"
frictionId: FRIC-4
status: logged
impact: detour
kind: environment
origin: "mori://shinzui/kenshou"
affects: "mori://shinzui/kenshou"
plan: "docs/plans/10-derive-fix-verification-dispositions-from-immutable-evidence.md"
workaround: "Generate a minimal test bundle with computation definitions. Each affected test publishes its own runs and attestations."
---
# Evidence tests copy a bundle with missing run records

## Attempted

Run cabal test kenshou-evidence:test:kenshou-evidence-test

## Encountered

Three existing comparisons and attestation tests fail on a clean checkout because the copied fixture has dangling references to runs omitted by the gitignore runs/ rule. The observation loader test passed.

```text
BundleInvalid DanglingReference to runs/selftest/2026/09/*.md; 55 examples, 3 failures
```

## Workaround

Generate a minimal test bundle with computation definitions. Each affected test publishes its own runs and attestations.
