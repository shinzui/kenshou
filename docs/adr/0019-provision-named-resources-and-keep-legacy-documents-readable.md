---
type: Architecture Decision Record
title: Provision named resources and keep legacy documents readable
description: Scenarios require named resources that suites provision; the protocol documents carry them as resource maps, and the one resource older documents named as a field stays readable.
timestamp: 2026-10-28T17:00:00Z
generated:
  by: process:claude-code
  at: "2026-10-28T17:00:00Z"
docId: ADR-19
status: Accepted
date: 2026-10-28
originatingPlan: docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md
---

# Provision named resources and keep legacy documents readable

## Context

The kernel knew one kind of infrastructure besides PostgreSQL, a Kafka broker, and
named it in the run specification, the worker initialization message, the comparison
key, and the cell protocol. Committed records and live cells use those shapes.

## Decision

A scenario requires resources by `ResourceName`, and a bundle registers a
`ResourceProvider` per name: it normalizes the specification value, acquires the
resource around a local run, and may declare a cell binding. Workers receive the
provisioned values in `WorkerInit.resources`, and the run result records each
provider's fingerprint under `fingerprint.resources` only when one was provisioned.

`kenshou.run-spec/v1` and `kenshou.worker-init/v1` keep their identifiers and gain a
`resources` object. Readers map a legacy non-null `kafka` field to the resource of
that name; writers emit only the map. The `compat-key/v1` algorithm renders that one
resource where the legacy field was, so recorded comparison keys do not change.
Cell environments and submission resets gain an optional `resources` block written
only when non-empty; `Kenshou.Remote.Cell.Legacy` is the one place that maps a cell
broker to that resource and moves its reset into the legacy `reset.broker` field,
because the cell agent decodes submissions strictly.

## Consequences

- A suite can provision any resource without a harness change.
- Every document the first consumer committed stays readable, and its comparison keys
  hold; the coupling guard's allow-list names exactly this shim.
- `Kenshou.Remote.Cell.Legacy` is deleted when `mori://shinzui/load-testing-infra`
  publishes `resources` and accepts `reset.resources`.
