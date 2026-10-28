---
type: Term
title: component graph
description: The checked-in map of build and runtime dependencies used to select verification after a change.
generated: {by: 'process:claude-code', at: '2026-10-28T17:30:00Z'}
termId: TERM-10
status: current
tags: [planning]
related: [TERM-1, TERM-11]
anchors:
  - {kind: file, resource: kenshou-core/data/components.json}
  - {kind: doc, resource: docs/adr/0004-select-runs-from-a-checked-in-component-graph.md}
---

# component graph

The graph maps runtime components and subcomponents to their dependents and
relevant [scenarios](scenario.md). It combines mechanically checked Cabal build
edges with reviewed runtime edges. The planner follows those paths when given
a changed component; if it cannot map an input safely, it selects the whole
catalog and warns. See [ADR-4](../adr/0004-select-runs-from-a-checked-in-component-graph.md).
