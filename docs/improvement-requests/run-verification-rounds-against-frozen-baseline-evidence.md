---
type: Improvement Request
title: "Run verification rounds against frozen baseline evidence"
description: "Provide generic round snapshots, conservative rerun planning, and replayable reports that compare exact baseline and candidate evidence without imposing consumer-specific tracking or repair policy."
generated:
  by: "codex/gpt-6.1-sol"
  at: "2026-11-17T15:52:19Z"
requestId: IR-5
status: proposed
origin: mori://shinzui/keiro-runtime-kenshou/masterplans/2-close-the-verification-and-repair-loop-for-the-keiro-runtime-in-rounds
dependencies:
  - ref: mori://shinzui/kenshou/okf/improvement-requests/concepts/IR-4
    kind: hard
    reason: "Round owner conclusions must use the shared evidence-based disposition derivation rather than a second implementation."
acceptanceCriteria:
  - id: AC-1
    statement: "Opening a round freezes exact baseline run IDs and trust, owner/catalog inputs, candidate identity, and selection inputs, and supports existing frozen evidence as input."
    verification: "Open a synthetic round, add newer history and changed owner data, then show the original definition and report inputs stay fixed; import a captured manual-refresh input set without querying latest."
  - id: AC-2
    statement: "Rerun planning accounts for all owner reproductions and conservatively affected scenarios, with explicit coverage, placement, and budget omissions."
    verification: "Validate and execute emitted plans through the existing executor using correctly built per-arm identities; show whole-release and change-only selections, unmapped changes, unsupported placement, and exhausted-budget omissions."
  - id: AC-3
    statement: "Reports trace baseline/candidate observations, trust, dispositions, new failures, scope overrides, and absent coverage to exact immutable artifacts."
    verification: "Replay a frozen fixture containing a confirmed fix, unrelated runtime failure, expected-defect exit zero, missing run, infrastructure failure, and incomplete evidence; verify counts and semantic replay after newer observations appear."
  - id: AC-4
    statement: "An arbitrary consumer can configure and run the protocol without Keiro packages, Rei, owner writes, or a second evidence format."
    verification: "Run a synthetic end-to-end round through public command contributions and the coupling guard; verify owner files and sealed runs are unchanged and repeated commands do not overwrite an existing round."
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

# Run verification rounds against frozen baseline evidence

## Problem

The generic planner, executor, history, and comparison commands exist, but a
consumer must manually connect them to repeat repair verification across releases.
Without a frozen baseline, querying latest history later changes what a round
claims to compare. Without a shared report, each consumer is likely to implement
its own owner conclusions or hide coverage skipped by budgets and unavailable
resources.

The motivating consumer integration is
`mori://shinzui/keiro-runtime-kenshou/plans/23-define-the-round-protocol-and-its-report`.
Its initial manual release refresh is
`mori://shinzui/keiro-runtime-kenshou/plans/24-run-the-first-repair-verification-round-against-a-fixed-cohort`.
That refresh must run without waiting for this tooling; later automation should
accept its frozen inputs and validate the same evidence rather than rerun merely
to create an automatically numbered round.

## Requested outcome

Provide versioned generic round definitions and public command/API contributions
for opening, planning, and reporting rounds. A round binds explicit baseline
run IDs and trust, baseline/candidate resolved cohort identities, owner/catalog
snapshot provenance, scoped records, plan/spec/policy references, and intended
coverage. Baselines accumulated over many plans need an explicit observation
index rather than an assumed single original plan. Support caller-supplied
frozen inputs as well as capturing a fresh snapshot, verifying their identities
and artifact references. Refuse overwriting an existing round definition.

Build rerun plans from both owner-reproduction coverage and conservative
component-change selection. Keep release-wide refresh distinct from bounded
change-only work. Plans retain skips and reasons, placement, scenarios, knobs,
dimensions, seeds, estimates, and budget omissions. Cohort-specific plans must
carry the actual executable identity; a baseline plan must not be relabeled for
a candidate. Planning must not silently switch or build cohorts.

Reports use the shared disposition engine. Include exact observations and trust,
known-defect reproductions even when nonblocking, new label-specific failures,
missing coverage, incompatible controls, infrastructure failures, and explicit
scope overrides. A lack of comparable evidence is not a pass. Render text and
versioned JSON, and support a dated human-readable report configured by the
consumer. Derived reports do not alter sealed evidence or replace owner status.
Replaying a frozen round must not substitute newer history, catalog definitions,
or owner claims without recording a separately identified evaluation.

Keep ordinary functional/owner conclusions separate from performance verdicts.
A report can link existing comparison artifacts, but must not turn historical
telemetry, a single pair, exploratory local runs, or an uncalibrated profile into
release acceptance. Use the existing comparison and evidence machinery.

## Existing seams and boundaries

Reuse `kenshou-core/src/Kenshou/Plan/`, the existing executor, generic history,
and `kenshou-cli/src/Kenshou/Cli/Registry.hs` command contributions. Consumers
supply catalog/graph, cohort sources, owner sources, evidence roots, coverage and
report policy, and optional tracking adapters. No Keiro package/path constant,
personal intention ID, mandatory Rei integration, CI orchestrator, owner-record
write, automatic scope rewrite, or runtime repair belongs in the generic engine.
The request does not mandate a new package name or a premature schema identifier.

Read [ADR-3](../adr/0003-kenshou-owns-the-verification-protocol.md),
[ADR-12](../adr/0012-keep-verification-records-immutable-and-derive-baselines.md),
and [ADR-5](../adr/0005-comparison-verdicts-require-controlled-benchmark-evidence.md).
Synthetic end-to-end acceptance belongs here; consumer adoption and the real
release-refresh evidence remain with that consumer. No target implementation
plan or shipped release is claimed by this request.
