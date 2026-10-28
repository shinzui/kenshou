---
type: Architecture Decision Record
title: Judge heap leaks on live bytes after major collections
description: Heap leak verdicts use forced-major-collection samples or the lower envelope of post-major live bytes, while native memory is reported separately.
timestamp: 2026-10-28T16:00:00Z
generated:
  by: process:claude-code
  at: "2026-10-28T16:00:00Z"
docId: ADR-9
status: Accepted
date: 2026-10-28
originatingPlan: docs/plans/6-carry-the-harness-decisions-vocabulary-and-adoption-guide-into-kenshou-documentation.md
---

# Judge heap leaks on live bytes after major collections

## Context

GHC's `live_bytes` describes the most recent garbage collection. After a minor
collection it includes everything still resident in the old generation,
including objects that a later major collection can reclaim. Raw live-byte and
resident-set-size series therefore form allocator and generational sawteeth
that can rise without a retained Haskell heap leak. `max_live_bytes` is a
high-water mark and cannot demonstrate that growth later stopped.

The verification suite must also detect memory retained by C libraries. That
memory does not appear in GHC heap statistics, while resident memory includes
both it and allocator noise.

## Decision

`kenshou-diagnose` judges `heap.live-bytes` from samples taken immediately after
an explicitly requested major collection when a scenario enables that probe.
Otherwise it fits the lower envelope of `live_bytes_last_gc` in windows where
the major-collection counter advances. The verdict uses a robust Theil–Sen
slope, a moving-block bootstrap interval, absolute and relative growth floors,
and a second-half slope that distinguishes an unbounded trend from a cache that
reaches a plateau.

Forced major collections are diagnostic perturbations. Benchmark scenarios
must reject them, and a run that enables them is not comparable latency
evidence.

Native memory is a separate, lower-confidence probe computed from resident
memory less the GHC run-time system's memory-in-use figure. It never replaces
the major-collection basis for a Haskell heap verdict.

## Consequences

- Stable allocator and generational sawteeth do not become false heap leaks.
- A short or statistically ambiguous run is `insufficient-data`, not `stable`.
- Native leaks remain visible but carry a distinct confidence statement.
- Exact major-collection sampling can change pauses and object ageing, so it is
  opt-in for correctness and soak diagnosis only.
- A periodic `live_bytes_last_gc` value is eligible for the heap trend only when
  `major_gcs` has advanced since the previous sample. A value carried through a
  minute without a major collection cannot stand in for post-major evidence.
- Long-running measurement counters must force their numeric state on each
  update, and supervised worker handles must close when workers exit. Otherwise
  the harness itself can satisfy the leak detector's growth criteria, as a
  reduced soak in the first consumer demonstrated with retained heap and
  descriptors.
- Retired worker handles must also become unreachable while the supervisor
  stays active. Force the full spine of filtered child lists and evaluate
  disturbance records before storing them: forcing only the outer cons leaves
  closures that retain completed listener threads. A weak-reference test with
  major GC verifies retirement independently of runtime-library workers.
- Resource series belong to one process incarnation. Restarted processes have
  fresh clocks and heaps, so their series must not be joined. Preserve
  insufficient-data verdicts for short incarnations and keep a continuous
  surviving worker when a soak needs a full-window process control.

- Bounded diagnostic buffers must enforce eviction when observations arrive,
  even if nobody reads the buffer during a run. A strict reference update does
  not force lazy fields inside a record. A weak-reference regression should
  verify that evicted observations become unreachable while the probe stays
  alive. A short run that is still filling its configured buffer cannot by
  itself establish a stable long-run heap; preserve that limit alongside the
  unchanged statistical verdict.

## Origin

Adopted from `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-10`, decided 2026-09-21, when the harness was extracted into this repository by [the extraction MasterPlan](../masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md). The decision binds the generic packages here; anything it says about a particular runtime layer belongs to the suite that verifies that layer.
