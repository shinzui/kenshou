---
type: Term
title: dimension
description: A named verification axis whose supported values select a run's instrumentation or PostgreSQL mode.
generated: {by: 'process:claude-code', at: '2026-10-28T17:30:00Z'}
termId: TERM-6
status: current
tags: [execution]
related: [TERM-1, TERM-7, TERM-25]
anchors:
  - {kind: file, resource: kenshou-core/src/Kenshou/Core/Dimension.hs}
---

# dimension

Kenshou's shared axes are `telemetry.tracing`, `telemetry.metrics`,
`pg.durability`, and `pg.version`. A [scenario](scenario.md) declares which
values are supported and which default applies. The planner can expand a matrix
across these axes, while `--dim NAME=VALUE` chooses one value. A
[knob](knob.md) instead controls scenario-specific workload behavior.
