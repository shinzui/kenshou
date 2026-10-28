---
type: Term
title: benchmark-grade run
description: A run with complete and healthy measurement evidence suitable for an authoritative performance comparison.
generated: {by: 'process:claude-code', at: '2026-10-28T17:30:00Z'}
termId: TERM-22
status: current
tags: [measurement]
related: [TERM-4, TERM-20, TERM-29]
anchors:
  - {kind: doc, resource: docs/adr/0005-comparison-verdicts-require-controlled-benchmark-evidence.md}
---

# benchmark-grade run

Kenshou requires full raw samples, applicable durable PostgreSQL settings,
and no health condition that invalidates evidence before a run can support a
performance verdict. `pg.durability=fsync-off` is exploratory. A controlled
[verification cell](verification-cell.md) is the authoritative placement for
the paired trials described in [ADR-5](../adr/0005-comparison-verdicts-require-controlled-benchmark-evidence.md).
