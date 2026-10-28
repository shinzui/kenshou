---
type: Architecture Decision Record
title: Distinguish documented limitations from known defects
description: Verification classifies unpromised behavior as implementation findings and links confirmed contract failures to reproducible owner-repository bug reports.
timestamp: 2026-10-28T16:00:00Z
generated:
  by: process:claude-code
  at: "2026-10-28T16:00:00Z"
docId: ADR-11
status: Accepted
date: 2026-10-28
originatingPlan: docs/plans/6-carry-the-harness-decisions-vocabulary-and-adoption-guide-into-kenshou-documentation.md
---

# Distinguish documented limitations from known defects

## Context

Runtime verification must expose hazards such as stale acknowledgements,
unlogged crash loss, grouped-batch successor leasing, commit-order inversion,
and notification throttle loss. Some are deliberately documented semantics;
others have accepted upstream work intended to change them. Marking every
hazard as a defect misrepresents the supported contract, while hiding expected
limitations leaves platform owners without operational evidence.

## Decision

Kenshou represents a documented limitation or desired improvement as an
implementation-class invariant. Its measured behavior stays visible even when
the run passes its published-contract checks. An upstream improvement plan
alone does not turn an unpromised target into a contract or a `KnownDefect`.

Known-defect references use canonical `mori://` URIs. A new observation is
recorded as evidence and remains blocking when it violates a contract; the
suite does not invent or claim a defect filing.

For a newly reproduced failure of behavior the producer already promises,
file an OKF `Bug Report` in the repository that owns the behavior. State the
affected released version (or `unreleased` for an unshipped head), the
observed and expected behavior, the source of the expectation, and ordered
steps that reproduce it. Include the exact Kenshou cohort and run evidence,
and set `origin` to the canonical URI of the suite's plan or project that found
it. Record the report's canonical concept URI wherever the suite tracks its
findings. Reuse an
equivalent existing report; where the behavior was never promised, file an
improvement request instead. Only attach `KnownDefect` to the scenario's
specific failure labels and affected cohorts, so another failure remains
blocking.

A layer's scenarios state desired behavior in their implementation-class oracles
and keep the upstream improvement links in the suite's own guides and plans. Each
run reports a violated desired-behavior cell as an implementation finding and
still checks the layer's contract invariants, so the probe documents the gap
without blocking on a behavior the producer never promised.

## Consequences

- Reports demonstrate operational hazards without falsely describing supported
  semantics as regressions.
- Confirmed contract defects are traceable to durable upstream ownership and
  can become cohort-specific when a fix ships.
- Undocumented failures cannot be made non-blocking merely by labeling them
  defects locally.
- Scenario documentation must state whether it verifies a contract, an
  implementation property, or a referenced known defect.
- A confirmed runtime failure has a versioned, reproducible owner-repository
record and a canonical URI that remains visible in this repository.

One scenario may reproduce independent owner defects in the same run. In that
case it declares a group of separately scoped `KnownDefect` entries. The
runner considers only entries applicable to the resolved cohort and makes a
failed run nonblocking only when it has at least one failure label and every
label belongs to an applicable entry. A new label still blocks. The run
result records each applicable reference and whether its own labels occurred;
the evidence record preserves all of those references. Existing single-defect
results retain their original JSON shape.

## Origin

Adopted from `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-14`, decided 2026-09-21, when the harness was extracted into this repository by [the extraction MasterPlan](../masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md). The decision binds the generic packages here; anything it says about a particular runtime layer belongs to the suite that verifies that layer.
