---
type: Architecture Decision Record
title: Evaluate known-defect scopes once and propose corrections
description: One evaluator in kenshou-core decides whether a known-defect scope applies, for execution and for analysis alike; scope reconciliation against owner claims produces reviewable proposals from an explicit consumer package map and never edits source, owner records, or failure labels.
timestamp: 2026-11-19T05:30:00Z
generated:
  by: process:claude-code
  at: "2026-11-19T05:30:00Z"
docId: ADR-22
status: Accepted
date: 2026-11-19
originatingPlan: docs/plans/9-reconcile-known-defect-scopes-with-owner-version-claims.md
---

# Evaluate known-defect scopes once and propose corrections

## Context

A known defect excuses specific failure labels on the cohorts its scope names
(ADR-11). The scope is written by hand in the consumer's Haskell source and goes
stale when an owner ships a fix, so tools outside the run must read it, decide
whether it applies to a set of resolved packages, and compare it with the owner's
version claims (ADR-21). If those tools evaluated scopes with their own code, an
analysis could disagree with what a run actually excused. Owner records name an
affected project, not cabal packages, and the packages of one project can carry
unrelated version numbers.

## Decision

`Kenshou.Core.Scenario.evaluateScope` is the only scope evaluator. It works on a
neutral `ScopePackage` list, to which a run's cohort identity and an evidence
record's components both convert, and explains each condition (holds, fails,
package missing, malformed version). `cohortScopeApplies` is defined through it, and
`parseScopeVersion` is the one version parser for scope bounds and owner version
claims. The catalog carries every declaration completely, groups preserved, in an
optional `knownDefectDeclaration` field of `kenshou.scenario-list/v1`, so the schema
stays `v1` and older readers keep working.

Reconciliation is a pure function of an owner snapshot, the catalog, and a
consumer-written `kenshou.owner-package-map/v1`. The map names each owner's packages
and, explicitly and without a default, the packages whose versions the owner's
version fields denote. Each individual defect gets one primary finding from an
ordered rule list. Only two corrections are ever proposed: set a `version-below`
bound to the owner's released fixed version, or remove a bound no owner claim
supports. A status alone never narrows a scope, a `fixedVersion` counts only with
the `fixed` status, and labels, source kinds, and revisions are never changed.
`owners reconcile` exits 1 on a contradiction and writes nothing but its report.

## Consequences

- Execution, reconciliation, and later evidence analysis cannot disagree about
  whether a scope applies to the same packages; a change to scope semantics is a
  change to one function and its oracle test.
- A consumer must write and maintain a package map; an unmapped or ambiguous owner
  is a warning, never a guess.
- Applying a proposal is a reviewed source edit by the consumer, so reconciliation
  can run in CI as a gate without any write access.
