---
type: Architecture Decision Record
title: Address cell runs by submission and nested run
description: A cell run is identified by its submission and nested run IDs, with cell evidence linked to sealed results and infrastructure failure governing the effective outcome.
timestamp: 2026-10-28T16:00:00Z
generated:
  by: process:claude-code
  at: "2026-10-28T16:00:00Z"
docId: ADR-15
status: Accepted
date: 2026-10-28
originatingPlan: docs/plans/6-carry-the-harness-decisions-vocabulary-and-adoption-guide-into-kenshou-documentation.md
---

# Address cell runs by submission and nested run

## Context

One cell submission can execute a plan containing many Kenshou runs. The cell
seals the submitted work tree, while Kenshou seals each nested run directory.
The cell can judge health and infrastructure only after the nested result has
been written. Editing that result to add later observations would invalidate
both manifests and obscure which system made each claim.

The evidence bundle already treats verification records and linked data as
immutable, as described in
[ADR-12](0012-keep-verification-records-immutable-and-derive-baselines.md).

## Decision

`<cell-run-id>/<run-id>` is the address of a Kenshou run on a cell. The first
identifier names one cell submission; the second names one run produced by
that submission. A fetched cell tree mirrors the sealed results-bucket tree,
so `tree/output/<run-id>/` remains an ordinary run directory. The cell
manifest, nested Kenshou manifest, and their recorded digests remain intact.

Information known while the run executes belongs in its `fingerprint.cell`.
Later cell reset evidence, health observations, and manifest references are
linked from a derived `cell-run.json`. That document reports the effective
outcome for each nested run. A cell infrastructure failure overrides a nested
success or other nested outcome when consumers decide whether the run is
valid evidence; it never rewrites `run-result.json`.

The recorder uses the two-part address and the cell result's effective
outcome. Its data base URI points to the submission's sealed `output` tree,
where the nested run ID selects the ordinary run files. A fetched tree is
verified before recording and remains byte-identical to the published tree.

## Consequences

- A submission can contain several runs without conflating their identities.
- Cell health can invalidate a nested result without mutating either sealed
  manifest or its run result.
- Old cell evidence can be fetched and verified after the cell is gone, using
  the submission ID and the nested run ID.
- Evidence consumers must read the effective outcome from `cell-run.json` and
  retain links to both manifests and their digests.

## Origin

Adopted from `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-21`, decided 2026-09-29, when the harness was extracted into this repository by [the extraction MasterPlan](../masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md). The decision binds the generic packages here; anything it says about a particular runtime layer belongs to the suite that verifies that layer.
