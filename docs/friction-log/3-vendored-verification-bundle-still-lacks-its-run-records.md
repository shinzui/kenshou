---
type: Friction Entry
title: "Vendored verification bundle still lacks its run records"
description: "The three kenshou-evidence failures recorded as FRIC-2 recur on plan 9, so every evidence test run needs a filtered rerun to separate them from new failures."
generated:
  by: "claude-code/claude-opus-5-5"
  at: "2026-11-19T04:56:22Z"
frictionId: FRIC-3
status: logged
impact: slowdown
kind: environment
origin: "mori://shinzui/kenshou"
affects: "mori://shinzui/kenshou"
plan: "docs/plans/9-reconcile-known-defect-scopes-with-owner-version-claims.md"
workaround: "Matched the failures to FRIC-2 and validated the new tests with --match"
---
# Vendored verification bundle still lacks its run records

## Attempted

Running cabal test kenshou-evidence:tests after Milestone 2

## Encountered

loadComparisonSource and two attest tests fail with BundleInvalid DanglingReference to runs/selftest/2026/09/*.md

```text
45 examples, 3 failures; same three tests as FRIC-2
```

## Workaround

Matched the failures to FRIC-2 and validated the new tests with --match
