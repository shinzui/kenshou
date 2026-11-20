---
type: Improvement Request
title: "Derive fix-verification dispositions from immutable evidence"
description: "Join canonical owner snapshots, scenario declarations, resolved cohorts, and immutable run evidence to derive traceable fix-verification dispositions with separate evidence trust."
generated:
  by: "codex/gpt-6.1-sol"
  at: "2026-11-17T15:52:19Z"
requestId: IR-4
status: in-progress
targetPlan: docs/plans/10-derive-fix-verification-dispositions-from-immutable-evidence.md
origin: mori://shinzui/keiro-runtime-kenshou/masterplans/2-close-the-verification-and-repair-loop-for-the-keiro-runtime-in-rounds
dependencies:
  - ref: mori://shinzui/kenshou/okf/improvement-requests/concepts/IR-2
    kind: hard
    reason: "Dispositions require canonical owner identities, claims, and scenario reference mappings."
  - ref: mori://shinzui/kenshou/okf/improvement-requests/concepts/IR-3
    kind: hard
    reason: "Dispositions require reconciled scopes and the same evaluator as scenario execution."
acceptanceCriteria:
  - id: AC-1
    statement: "Per-owner/per-cohort conclusions link exact observations, scopes, owner claims, failure labels, and trust rather than inferring success from owner status or process exit alone."
    verification: "Replay synthetic fixtures for compatible confirmed passes, matching reproductions, unrelated failures, expected-defect exit zero, absent labels, no runs, and unresolved records."
  - id: AC-2
    statement: "Only compatible confirmed evidence for the required scenario coverage can support a verified-fixed headline."
    verification: "Demonstrate that local or unverified passes, incomplete attestations, missing required scenarios, and incompatible scenario revisions cannot produce a confirmed fix count; preserve their observations separately."
  - id: AC-3
    statement: "The derivation can find passing fixed-cohort observations even when their run records contain no applicable known-defect reference."
    verification: "Join through catalog scenario mappings in a fixture whose candidate pass omits the defect reference, then verify exact owner attribution and recorded resolved package versions."
  - id: AC-4
    statement: "Regression, remaining reproduction, new failure, missing evidence, and unreleased/unknown fix claims remain distinguishable under deterministic replay."
    verification: "Freeze input snapshots and replay the derived JSON twice; verify a later compatible failure after a confirmed pass, aggregate conflicting scenario results conservatively, and show unchanged source records."
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

# Derive fix-verification dispositions from immutable evidence

## Problem

An owner marking a record fixed says that repair was delivered. It does not prove
that a consumer executed the relevant reproduction on a compatible cohort and
observed the repair. Generic history already exposes trust and immutable run
records, but it has no reusable join that derives that conclusion from owner
claims, scenario scopes, actual run labels, and resolved package identities.

The motivating integration is
`mori://shinzui/keiro-runtime-kenshou/plans/22-derive-fix-verification-dispositions-from-recorded-evidence`.
A passing run outside a known-defect scope may omit that defect from its result,
so reading only a run record's defect references loses the successful fix case.

## Requested outcome

Provide a generic observation loader and pure derivation API, exposed through an
operator command assembled by consumers. Join canonical owner snapshots through
the catalog's scenario/defect mappings, evaluate the run's actual resolved cohort
with the shared scope evaluator, and inspect digest-verified run-result labels.
Consumers supply evidence locations and any domain-specific replay contributions;
Kenshou must not import their oracles or hard-code their evidence subjects.

Keep lifecycle claim, scope applicability, runtime outcome, and evidence trust
separate. Published history with machine-confirmed or human-reviewed trust can
support confirmed conclusions; unverified records and unpublished sealed local
runs remain explicitly weaker evidence. Missing labels, unparseable versions,
unresolved identities, insufficient required scenario coverage, or incompatible
revisions cannot be repaired by inference from an exit code. A process exit zero
may mean an expected defect reproduced. A later passing cohort outside a scope
is not by itself proof of a fix without compatible coverage and supporting
version/reproduction evidence.

The result should distinguish verified-fixed, still-reproduces,
reproduces-as-expected, not-reproduced, regressed, different-failure,
not-yet-released, not-run, and unverifiable, with explicit reasons and run IDs.
The implementation plan must specify precedence, multiple scenarios/labels,
duplicate attribution, evidence ordering, applicability to Git/released cohorts,
and unparseable claims. A later compatible failure after a confirmed pass can
support regression; a last-working-version claim alone cannot prove one. Do not
count a partially tested multi-scenario fix as wholly verified.

Return versioned JSON and a readable report. Snapshot current catalog/owner
inputs so a conclusion can be replayed without silently taking newer declarations.
Conclusions are derived readings, never edits to owner records or a new mutable
status field in immutable verification records.

## Existing seams and boundaries

Read `kenshou-evidence/src/Kenshou/Evidence/History.hs` for the existing trust
strings, `kenshou-core/src/Kenshou/Core/Scenario.hs` for scopes, and
`kenshou-cli/src/Kenshou/Cli/Registry.hs` for command/recomputer assembly. Reuse
the generic immutable evidence readers and source verification. The upstream
rule matrix uses synthetic data; the consumer owns its real mappings and oracles.

Read [ADR-12](../adr/0012-keep-verification-records-immutable-and-derive-baselines.md)
and [ADR-11](../adr/0011-distinguish-documented-limitations-from-known-defects.md).
Any later record-shape change must preserve old evidence and follow the shared
contract's release process.

## Implementation

[ExecPlan 10](../plans/10-derive-fix-verification-dispositions-from-immutable-evidence.md)
delivers the observation loader, pure derivation API, and `owners dispositions`
command. The input and report schemas support repeatable offline replay. The package
changes are in the working repository ahead of publication.
