---
type: Friction Entry
title: "Vendored verification bundle lacks its run records"
description: "Three kenshou-evidence tests fail on a clean master because fixtures/consumer-baseline/docs/verification has attestations but no runs/, which the top-level .gitignore rule runs/ kept out of git."
generated:
  by: "claude-code/claude-opus-5-5"
  at: "2026-11-18T03:03:26Z"
frictionId: FRIC-2
status: logged
impact: detour
kind: environment
origin: "mori://shinzui/kenshou"
affects: "mori://shinzui/kenshou"
plan: "docs/plans/8-resolve-owner-records-through-consumer-supplied-sources.md"
workaround: "Confirmed the failures predate this plan with git stash and validated the owner tests with --match \"owner records\""
---
# Vendored verification bundle lacks its run records

## Attempted

Running cabal test kenshou-evidence:test:kenshou-evidence-test to validate milestone 1

## Encountered

loadComparisonSource and two attest tests fail with BundleInvalid DanglingReference to runs/selftest/2026/09/*.md on the unmodified tree

```text
29 examples, 3 failures (git stash -u, clean tree); .gitignore:18:runs/
```

## Workaround

Confirmed the failures predate this plan with git stash and validated the owner tests with --match "owner records"
