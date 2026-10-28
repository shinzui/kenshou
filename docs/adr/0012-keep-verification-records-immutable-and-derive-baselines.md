---
type: Architecture Decision Record
title: Keep verification records immutable and derive baselines
description: Verification records are immutable events that link to digest-pinned data, while baselines are selected from confirmed compatible history.
timestamp: 2026-10-28T16:00:00Z
generated:
  by: process:claude-code
  at: "2026-10-28T16:00:00Z"
docId: ADR-12
status: Accepted
date: 2026-10-28
originatingPlan: docs/plans/6-carry-the-harness-decisions-vocabulary-and-adoption-guide-into-kenshou-documentation.md
---

# Keep verification records immutable and derive baselines

## Context

A run can produce many samples and logs. A future reader needs its exact cohort,
environment, outcome, and raw files without treating a mutable report as proof.
Measurements are too large and too easy to copy incorrectly into OKF frontmatter.
A chosen baseline can also become stale when a newer confirmed compatible run
arrives.

## Decision

The `docs/verification` bundle holds three concept types: `Attested Computation`,
`Verification Run`, and `Attestation`. One run or comparison gets one path-addressed
record with a UUIDv7 identity. The record stores identity, provenance, outcome,
cohort, and a separate durable `gs://` link with SHA-256, media type, and byte count
for every required data artifact. It stores no measurement value. Data objects and
committed records are not replaced. A correction is a new record or a subsequent
attestation that refutes the original.

Attestations are separate events. A deterministic verifier checks linked bytes
and named computation definitions; only a confirmed result can add a machine
`verified` entry. Historical queries derive a baseline from the latest confirmed,
compatible evidence at read time. No record stores a `baseline` flag or a derived
trust tier.

A comparison is also a `Verification Run` event. Its attestation verifies the
comparison document and both recorded arms, recomputes each arm's saved summary
from its samples, then replays the paired calculation under the recorded policy.
The comparison's performance verdict and the attestation's evidence verdict
answer different questions: a one-pair comparison can be faithfully confirmed
while remaining inconclusive for a release decision.

The shared contract for these three types is published as
`mori://shinzui/okf-profiles/profiles/verification-evidence` in v0.19.0. A
suite's evidence bundle imports a release of it with a Dhall semantic hash, and
its local descriptor may narrow the shared, open `layer` and `tier` vocabularies
to its own layers and Kenshou's cost tiers; the harness owns the record shapes and
the checks, and the narrowed vocabulary is the suite's. The local evidence checker still requires durable `gs://`
data links and checks the properties a profile cannot express. A future record
shape change must first be an additive relaxation in the published contract so
existing immutable records continue to validate.

## Consequences

- A reader can re-evaluate an old conclusion from digest-pinned data without
  changing what the original run claimed.
- A new confirmed run can become the baseline without rewriting prior records.
- The recorder and attester must refuse identity collisions and report incomplete
  recomputation honestly when an oracle cannot be replayed from saved artifacts.
- Storage retention and the repository's history are part of the evidence chain.
- GCS data links, the sealed manifest, and versioned computation definitions let
  another reader repeat the check without changing the historical record.

## Origin

Adopted from `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-18`, decided 2026-09-26, when the harness was extracted into this repository by [the extraction MasterPlan](../masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md). The decision binds the generic packages here; anything it says about a particular runtime layer belongs to the suite that verifies that layer.
