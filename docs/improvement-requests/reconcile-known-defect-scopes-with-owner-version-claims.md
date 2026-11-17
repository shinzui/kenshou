---
type: Improvement Request
title: "Reconcile known-defect scopes with owner version claims"
description: "Expose complete defect scope data and reusable reconciliation against owner version claims, with explicit consumer package mappings and reviewable corrections rather than automatic source edits."
generated:
  by: "codex/gpt-6.1-sol"
  at: "2026-11-17T15:52:19Z"
requestId: IR-3
status: proposed
origin: mori://shinzui/keiro-runtime-kenshou/masterplans/2-close-the-verification-and-repair-loop-for-the-keiro-runtime-in-rounds
dependencies:
  - ref: mori://shinzui/kenshou/okf/improvement-requests/concepts/IR-2
    kind: hard
    reason: "Scope reconciliation requires canonical resolved owner claims and duplicate handling."
acceptanceCriteria:
  - id: AC-1
    statement: "Catalog output preserves every defect reference, expected failure label, grouped defect, and cohort condition without breaking existing catalog readers."
    verification: "Round-trip the supported scope constructors and grouped defects through versioned fixture catalogs, and retain compatibility checks for the existing reference field."
  - id: AC-2
    statement: "Reconciliation identifies stale bounds and unsupported claims without guessing versions or package mappings."
    verification: "Check fixtures for a released fix boundary, an unreleased fix, no fixed version, a stale speculative bound, a duplicate record, and a project affecting multiple packages."
  - id: AC-3
    statement: "One reusable evaluator agrees with execution scope applicability for the same resolved cohort and supports later evidence analysis."
    verification: "Compare its result with cohortScopeApplies on Hackage/Git sources, exact revisions, version boundaries, grouped defects, and missing packages; report malformed inputs separately."
  - id: AC-4
    statement: "Corrections are reviewable consumer proposals and do not rewrite source or broaden known-defect labels automatically."
    verification: "Run text/JSON reconciliation against a synthetic consumer, inspect source locations and reasons, and verify all source and owner records are unchanged."
reviews:
  - kind: model
    reviewer: codex
    reviewed_at: "2026-11-17T15:52:57Z"
    document_timestamp: "2026-11-17T15:52:19Z"
    scope: content-and-metadata
    outcome: commented
    provider: openai
    model: "gpt-6.1-sol"
    effort: unspecified
    context: >-
      Author self-check against the registered consumer request, the generic Program
      command contribution, catalog/scope/history source, relevant local ADRs, and
      the pinned improvement-request profile. Checked ownership, source relationships,
      acceptance criteria, and canonical cross-repository references. This is not an
      independent review or evidence that the requested capability is implemented.
---

# Reconcile known-defect scopes with owner version claims

## Problem

A stale defect scope can excuse a failure on a release that its owner says fixed
it, or make a still-affected release appear unexpectedly broken. Execution has
`cohortScopeApplies`, but `kenshou list --json` currently emits only defect
references rather than their full failure labels and conditions. Other tools
cannot reliably inspect those declarations or compare them with owner claims.

The motivating consumer integration is
`mori://shinzui/keiro-runtime-kenshou/plans/21-reconcile-known-defect-cohort-scopes-with-owner-records`.
Its historical audit found speculative Kafka adapter bounds and a fixed-version
mismatch. Those are examples to recheck at execution time, not permanent version
constants to build into Kenshou.

## Requested outcome

Expose complete, versioned defect declarations from the generic catalog while
preserving compatibility for existing readers. Include grouped defects, labels,
and each supported `CohortScope`/`PackageCondition`. Provide reusable scope
inspection/evaluation and reconciliation with the canonical owner snapshot from
the owner-reader request. Use a single semantic implementation rather than a
second evaluator that disagrees with execution.

Consumers supply the mapping between an owner's affected project/package and
resolved cohort packages, plus source locations when available. A project with
several packages must not be mapped arbitrarily. Released fixed versions can
support proposed boundaries; unreleased, unknown, malformed, or missing versions
produce explicit diagnostics. An absent owner fix cannot justify a speculative
upper bound. Respect source-kind/revision conditions and labels as well as
numeric versions. An owner status alone is insufficient to narrow a scope.

Return text and versioned JSON reports, with machine-detectable error status for
contradictions and distinct ambiguity warnings. Each proposal names the owner
snapshot, scenario, current declaration, proposed correction, and rationale.
Source changes remain consumer-owned reviewed edits. No generic command rewrites
Haskell modules, changes owner records, or broadens covered failure labels.

## Existing seams and boundaries

Read `kenshou-core/src/Kenshou/Core/Scenario.hs`, including grouped defects,
`cohortScopeApplies`, and package conditions, and
`kenshou-core/src/Kenshou/Core/Bundle.hs` for catalog serialization. Changes belong
in the generic kernel/tooling here, with consumer inputs supplied through public
extensions. Do not add runtime package-name constants or a Keiro source scanner
to the generic model.

Read [ADR-3](../adr/0003-kenshou-owns-the-verification-protocol.md) and
[ADR-11](../adr/0011-distinguish-documented-limitations-from-known-defects.md).
The generic implementation and its synthetic acceptance belong here; actual
consumer mapping and scope corrections remain in that consumer. This request
assigns no implementation plan or release version.
