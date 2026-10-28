---
type: Architecture Decision Record
title: Toolkit packages never depend on a layer bundle
description: Each runtime layer is its own cabal package depending only on the kernel and toolkits, so a red layer is attributable and layers build and run independently.
timestamp: 2026-10-28T16:00:00Z
generated:
  by: process:claude-code
  at: "2026-10-28T16:00:00Z"
docId: ADR-1
status: Accepted
date: 2026-10-28
originatingPlan: docs/plans/6-carry-the-harness-decisions-vocabulary-and-adoption-guide-into-kenshou-documentation.md
---

# Toolkit packages never depend on a layer bundle

## Context

A suite built on Kenshou must identify which part of the system under test failed
and select only the verification work affected by a change. Organizing code
primarily by evidence axis (`correctness`, `concurrency`, or `benchmarking`) would
spread one layer across several build units and make both attribution and
selection ambiguous. And the harness can only be reused if nothing in it depends
on the system a particular suite verifies.

The harness therefore has a kernel, reusable verification toolkits, and an
operator command library; a consuming suite adds one layer bundle per layer of its
system and assembles them into its own executable.

## Decision

The kernel (`kenshou-core`) and the toolkits (`kenshou-check`, `kenshou-measure`,
`kenshou-diagnose`, `kenshou-telemetry`, `kenshou-evidence`, `kenshou-remote`)
depend only on one another, in the order their cabal files declare, and never on a
layer bundle or the system under test; `kenshou-cli` depends on them and on nothing
layer-specific. A consuming suite's layer packages depend on the kernel and the
toolkits and never on one another; only the suite's assembled executable links
several of them. The coupling guard (`scripts/coupling-guard.sh`) and the plan
check (`scripts/plan-check.sh`) enforce this for the generic packages here.

Correctness, concurrency, soak, and benchmark coverage live below the applicable
layer rather than forming top-level package boundaries. A layer may add modules
or tests, but it may not reach across to another layer to reuse fixtures or
implementation; what layers share is contributed through their bundles.

## Consequences

- A failing layer build or scenario has one attributable runtime boundary.
- Change-aware planning can map a changed runtime component to its layer without
  interpreting evidence-axis directories.
- Layers remain independently buildable and runnable, allowing parallel work and
  focused CI targets.
- Shared fixtures and helpers must be promoted to the kernel or a toolkit instead
  of being imported from another layer.
- Cross-layer behavior belongs in `kenshou-runtime`; command aggregation belongs
  in `kenshou-cli`.

## Origin

Adopted from `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-1`, decided 2026-09-20, when the harness was extracted into this repository by [the extraction MasterPlan](../masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md). The decision binds the generic packages here; anything it says about a particular runtime layer belongs to the suite that verifies that layer.
