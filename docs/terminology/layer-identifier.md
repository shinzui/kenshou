---
type: Term
title: layer identifier
description: The open, validated name of a layer of the system a suite verifies, which is the first segment of every scenario identifier in that layer.
generated: {by: 'process:claude-code', at: '2026-10-28T17:45:00Z'}
termId: TERM-31
status: current
tags: [registration]
related: [TERM-1, TERM-32]
anchors:
  - {kind: file, resource: kenshou-core/src/Kenshou/Core/Id.hs}
---

# layer identifier

A layer identifier names one layer of the system under test, such as `synthetic`
in `synthetic/table/correctness/append-survives-kill-restart`. It is a value of
`Kenshou.Core.Id.LayerId`, built with `mkLayerId` from lowercase ASCII letters and
digits in hyphen-separated chunks of at most 48 characters, so any suite can choose
its own. The kernel's and toolkits' own [scenarios](scenario.md) use
`selftestLayer`. Evidence records file runs under `runs/<layer>/` by the rendered
identifier.
