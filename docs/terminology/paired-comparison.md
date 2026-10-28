---
type: Term
title: paired comparison
description: A controlled performance comparison of interleaved baseline and candidate run trials.
generated: {by: 'process:claude-code', at: '2026-10-28T17:30:00Z'}
termId: TERM-20
status: current
tags: [measurement]
related: [TERM-21, TERM-22, TERM-23]
anchors:
  - {kind: doc, resource: docs/adr/0005-comparison-verdicts-require-controlled-benchmark-evidence.md}
---

# paired comparison

`kenshou compare` judges matched [baseline](baseline.md) and candidate trials
run in interleaved ABBA or BAAB order. It checks compatibility and evidence
quality before assessing metric changes. A historical trend can suggest what
to investigate, but it does not replace this controlled comparison. See
[measuring and comparing](../guides/measuring-and-comparing.md).
