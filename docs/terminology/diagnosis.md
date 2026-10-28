---
type: Term
title: diagnosis
description: A recomputable explanation of a suspected leak or stall from saved samples and captures.
generated: {by: 'process:claude-code', at: '2026-10-28T17:30:00Z'}
termId: TERM-26
status: current
tags: [observability]
related: [TERM-4, TERM-13]
anchors:
  - {kind: file, resource: schemas/diagnosis.v1.schema.json}
---

# diagnosis

A diagnosis names the source series or capture, observation window, estimator,
thresholds, and evidence behind a leak or concurrency-stall classification.
`kenshou diagnose` can rejudge a [sealed run](sealed-run.md) under a changed
policy without changing that run's files. A diagnosis is more than a label:
the supporting data remains available for inspection. See the
[diagnosis guide](../guides/diagnosing-leaks-and-stalls.md).
