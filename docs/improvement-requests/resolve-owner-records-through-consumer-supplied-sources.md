---
type: Improvement Request
title: "Resolve owner records through consumer-supplied sources"
description: "Provide reusable owner-record discovery, resolution, duplicate handling, and status reporting from consumer-supplied findings and scenario references, without embedding a particular runtime or tracker."
generated:
  by: "codex/gpt-6.1-sol"
  at: "2026-11-17T15:52:19Z"
requestId: IR-2
status: in-progress
targetPlan: docs/plans/8-resolve-owner-records-through-consumer-supplied-sources.md
origin: mori://shinzui/keiro-runtime-kenshou/masterplans/2-close-the-verification-and-repair-loop-for-the-keiro-runtime-in-rounds
acceptanceCriteria:
  - id: AC-1
    statement: "A consumer can enumerate every cited owner record with canonical identity, raw lifecycle/version claims, resolution state, and citing scenarios/findings."
    verification: "Register a synthetic bundle and a fixture finding source, resolve their overlapping references, and compare the text and versioned JSON reports with the exact source records."
  - id: AC-2
    statement: "Duplicate chains, cycles, missing records, non-record references, unknown versions, and malformed fields remain explicit without guessed identities or versions."
    verification: "Run fixture controls for each case, including two owners whose records share the same local handle, and verify structured reasons and stable canonical references."
  - id: AC-3
    statement: "A consumer can supply its own sources, resolver, local links, and optional owner-plan metadata without changing generic package source or requiring Rei."
    verification: "Assemble the synthetic consumer through the public CLI/API extension points; run the coupling guard and prove no Keiro-specific dependency or required tracker was added."
  - id: AC-4
    statement: "Status reporting is read-only and repeatable for fixed source snapshots."
    verification: "Retain source bytes and digests, run reporting twice, compare semantic output, and verify the owner files are unchanged."
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

# Resolve owner records through consumer-supplied sources

## Problem

Consumers can already register scenarios and publish evidence, but the generic
command assembly has no owner-record status command. A scenario's canonical
`KnownDefect.reference` and a consumer's findings cannot currently be joined by
a reusable reader to answer what owners claim is fixed, where the records came
from, and which scenarios cite them. A manually copied issue register becomes
stale as owners release changes.

The motivating consumer is the origin MasterPlan. Its integration work is
`mori://shinzui/keiro-runtime-kenshou/plans/20-report-owner-record-status-for-every-kenshou-finding`.
That consumer currently retains local harness copies and has not adopted the
extracted packages. This request asks for the generic capability here, not an
implementation in those consumer copies.

## Requested outcome

Expose a public owner-source and resolver contribution, and an operator status
view usable by an arbitrary consumer. A source supplies canonical references
from findings and registered scenarios; a resolver supplies owner bytes and
provenance. A Mori-backed adapter may use `mori path`, while fixtures can operate
from frozen input without a running registry. Preserve a record's kind, raw
status, affected/fixed version vocabulary, affected project/package identity,
duplicate target, resolved source, and diagnostic reasons. Parse handles from
record metadata, never filenames. Follow duplicate chains with cycle detection
and retain aliases and citing consumer links.

Keep released versions, unreleased, unknown, and unparseable text distinct.
Resolution failure and a canonical reference to documentation rather than an
owner record must remain visible and must not be counted as verified bugs.
Allow consumer-owned plan/intention enrichment through configuration or an
adapter; no generic dependency on a personal tracker is needed. Status is the
owner's claim at the captured observation time, not verification of that claim.

A proposed command is `owners status` with text and versioned JSON output. Final
package and command placement belongs to the implementation plan; diagnostics
go to stderr. Snapshot provenance must permit later rounds to report from the
same bytes rather than silently reread changed upstream state.

## Existing seams and boundaries

`kenshou-core/src/Kenshou/Core/Scenario.hs` defines defect references, and
`kenshou-core/src/Kenshou/Core/Bundle.hs` serializes their catalog references.
`kenshou-cli/src/Kenshou/Cli/Registry.hs` exposes `Program` and generic command
contributions. Build on those seams. Do not introduce a second catalog or evidence
protocol, import a consumer layer, hard-code its paths/buckets/packages, edit
owner lifecycle fields, or perform repairs. Package placement is deliberately
left to Kenshou's implementation plan.

Read [ADR-1](../adr/0001-toolkit-packages-never-depend-on-a-layer-bundle.md) and
[ADR-3](../adr/0003-kenshou-owns-the-verification-protocol.md). Acceptance must
include the synthetic consumer so the first runtime's configuration cannot become
a hidden requirement. No upstream implementation plan is assigned by this request.
