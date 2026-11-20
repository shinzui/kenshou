---
type: Architecture Decision Record
title: Derive fix dispositions from frozen evidence
description: Derive fix verification by joining owner claims and catalog declarations with compatible, digest-checked run evidence.
timestamp: 2026-11-20T02:36:22Z
generated:
  by: codex/gpt-6.2-sol
  at: "2026-11-20T02:36:22Z"
docId: ADR-23
status: Accepted
date: 2026-11-20
originatingPlan: docs/plans/10-derive-fix-verification-dispositions-from-immutable-evidence.md
---

# Derive fix dispositions from frozen evidence

## Context

A fix claim identifies what the owner delivered. Verification requires a compatible
run on a resolved cohort containing the released fix. A successful process exit
can accompany an expected defect, and a passing run can omit a defect reference
when its cohort falls outside the declared scope.

## Decision

Derive one conclusion per canonical owner and resolved cohort plan hash. Join runs
to owners through the catalog's scenario declarations, including duplicate
aliases, and evaluate each scope using the same evaluator as execution. Determine
reproduction from digest-verified run-result labels. The catalog revision must
match the run's revision to count as compatible evidence.

The disposition vocabulary is `verified-fixed`, `still-reproduces`,
`reproduces-as-expected`, `not-reproduced`, `regressed`, `different-failure`,
`not-yet-released`, `not-run`, and `unverifiable`. A conclusion of
`verified-fixed` requires a release comparison supported by the consumer's
package map and a compatible latest pass with `human-reviewed` or
`machine-confirmed` trust for every required scenario. `Unverified` published
evidence and unpublished `local-sealed` runs stay visible with their weaker
trust. Version numbers from Git cohorts give no release comparison. A regression
requires a previous compatible confirmed fixed-side pass for the same scenario.

Capture owner claims, full catalog declarations, package mappings, coverage,
and observations by value in a versioned input. Consumers can supply evidence
locations and attach the result of their own domain replay. Such annotations
are captured alongside the original observation. The recorded outcome, checked
labels, and attestation history determine the disposition.

## Consequences

A report cites the owner claim, compatible and incompatible runs, scope evaluations,
and the evidence behind each conclusion. Reports are derived readings of immutable
evidence. Replaying a frozen input produces the same report independently of changes
to owners, scenario declarations, or the evidence bundle. Owner records and
verification records keep their existing shapes and are never updated by derivation.
See [ADR-12](0012-keep-verification-records-immutable-and-derive-baselines.md) and
[ADR-22](0022-evaluate-known-defect-scopes-once-and-propose-corrections.md).
