---
type: Architecture Decision Record
title: Freeze round baselines and candidate evaluations
description: Bind verification rounds to explicit baseline evidence and arm identities, and replay reports from named candidate evaluations.
timestamp: 2026-11-20T03:40:10Z
generated:
  by: codex/gpt-6.2-sol
  at: "2026-11-20T03:40:10Z"
docId: ADR-24
status: Accepted
date: 2026-11-20
originatingPlan: docs/plans/11-run-verification-rounds-against-frozen-baseline-evidence.md
---

# Freeze round baselines and candidate evaluations

## Context

A release refresh often compares against evidence collected across many plans.
A new record or attestation changes a live history query. Repeating a query
after a run can therefore silently change the baseline or the trust on which a
conclusion depends.

## Decision

A round names exact baseline observations and freezes their trust, the
owner snapshot, the catalog, the package map, the component graph, and the
resolved identities of both arms. The round definition records SHA-256
digests of the captured files. A consumer can adopt an earlier capture with
the same input layout.

Each run plan binds to the frozen identity of its requested arm. The planner
considers the entire catalog for a release refresh and the graph's package
change closure for change-only planning. Both modes account for owner
reproductions and record why work was left out.

Create a named evaluation to bring candidate observations and trust into
the round. When it uses a named plan, the evaluation freezes the plan and
coverage documents. It also freezes supplied executor summaries so the
report can associate retried run IDs with their planned entries. Running a
report later replays that evaluation with the same baseline, declarations
and shared disposition rules. A new evaluation records any change to the
candidate evidence.

## Consequences

The report can identify the exact runs, trust and scope evaluations behind
a conclusion. A missing or incompatible control makes a comparison
inconclusive in the absence of a blocking failure. Scope overrides apply
only within the round and carry their rationale into affected conclusions.
A report may link controlled comparisons as performance evidence. The
functional and owner conclusions do not determine a performance verdict.

See [ADR-12](0012-keep-verification-records-immutable-and-derive-baselines.md),
[ADR-23](0023-derive-fix-dispositions-from-frozen-evidence.md), and
[ADR-5](0005-comparison-verdicts-require-controlled-benchmark-evidence.md).
