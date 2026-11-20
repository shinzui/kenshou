---
type: Term
title: round
description: A frozen baseline, pair of cohort identities, and set of inputs for verification reruns.
generated: {by: 'codex/gpt-6.2-sol', at: '2026-11-20T03:40:10Z'}
termId: TERM-39
status: current
tags: [evidence]
related: [TERM-38]
anchors:
  - {kind: file, resource: schemas/kenshou.round.v1.schema.json}
---

# round

A round freezes exact baseline [observations](observation.md) and their trust,
both resolved [cohort](cohort.md) identities, and the owner and planning inputs.
A planner derives an executable [run plan](run-plan.md) for either arm. Use
a [round evaluation](round-evaluation.md) to freeze the candidate evidence
used in a report.
