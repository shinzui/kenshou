---
type: Term
title: round evaluation
description: A named capture of the candidate evidence used to report on a verification round.
generated: {by: 'codex/gpt-6.2-sol', at: '2026-11-20T03:40:10Z'}
termId: TERM-40
status: current
tags: [evidence]
related: [TERM-38, TERM-39]
anchors:
  - {kind: file, resource: kenshou-evidence/src/Kenshou/Evidence/Round/Evaluation.hs}
  - {kind: file, resource: schemas/kenshou.round-report.v1.schema.json}
---

# round evaluation

An evaluation freezes candidate [observations](observation.md) with their trust
and binds them to the definition of a [round](round.md). When supplied, it also
captures a plan, coverage and execution summaries that connect retry attempts
to the planned runs. A round report derives from one evaluation. Capture a new
evaluation to include later observations or attestations.
