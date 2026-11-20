---
type: Term
title: disposition
description: The evidence-based conclusion about one owner's defect for a resolved cohort.
generated: {by: 'codex/gpt-6.2-sol', at: '2026-11-20T02:36:22Z'}
termId: TERM-38
status: current
tags: [evidence]
related: [TERM-18, TERM-34, TERM-35, TERM-37]
anchors:
  - {kind: file, resource: kenshou-evidence/src/Kenshou/Evidence/Disposition.hs}
  - {kind: file, resource: schemas/kenshou.dispositions.v1.schema.json}
---

# disposition

`kenshou owners dispositions` derives the conclusion from a frozen owner claim,
scenario declarations, coverage, and [observations](observation.md). A
`verified-fixed` conclusion requires a compatible confirmed pass for every
required scenario on a cohort containing the released fix. A disposition is
reported separately from the owner's status. See
[ADR-23](../adr/0023-derive-fix-dispositions-from-frozen-evidence.md).
