---
type: Term
title: observation
description: A captured reading of a published evidence record or a sealed local run for fix verification.
generated: {by: 'codex/gpt-6.2-sol', at: '2026-11-20T02:36:22Z'}
termId: TERM-37
status: current
tags: [evidence]
related: [TERM-12, TERM-18, TERM-35]
anchors:
  - {kind: file, resource: kenshou-evidence/src/Kenshou/Evidence/Observation.hs}
  - {kind: file, resource: schemas/kenshou.disposition-input.v1.schema.json}
---

# observation

An observation captures a run's identity, scenario and revision, resolved cohort
packages, outcome, failure labels, and evidence trust. Its source is a published
verification record or a sealed local run directory. Labels come from the
run-result bytes matched against their digest. Unavailable labels carry a reason
and remain distinct from a verified empty list. The published record takes
precedence when both sources contain the same run.
