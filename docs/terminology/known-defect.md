---
type: Term
title: known defect
description: An owner-repository contract failure whose reference and expected failure labels are scoped to affected cohorts.
generated: {by: 'process:claude-code', at: '2026-10-28T17:30:00Z'}
termId: TERM-18
status: current
tags: [correctness]
related: [TERM-2, TERM-12, TERM-15, TERM-34, TERM-36]
anchors:
  - {kind: file, resource: kenshou-core/src/Kenshou/Core/Scenario.hs}
  - {kind: file, resource: kenshou-core/src/Kenshou/Core/Defect.hs}
  - {kind: doc, resource: docs/adr/0011-distinguish-documented-limitations-from-known-defects.md}
---

# known defect

A scenario may cite a confirmed bug report using its canonical `mori://` URI.
Kenshou applies that reference only to the specified [cohorts](cohort.md) and
failure labels. Reproducing exactly the covered labels can make a failed run
nonblocking; a new failure label still blocks. A documented limitation or
desired improvement is an implementation finding, not a known defect. See
[ADR-11](../adr/0011-distinguish-documented-limitations-from-known-defects.md).

A declaration is a single defect (reference, summary, the excused failure labels,
and a cohort scope) or a group of declarations. Its scope is `all-cohorts` or
`only-when` a list of package conditions, every one of which must hold for some
resolved package: `resolved-from-hackage`, `resolved-from-git`, `version-below`
(a strict upper bound, compared as versions), and `revision-is` (an exact Git
revision). `kenshou list --json` carries the complete declaration, groups
preserved, under `knownDefectDeclaration`:

```json
{"kind": "single", "reference": "mori://<namespace>/<owner>/okf/bug-reports/concepts/BUG-2",
 "summary": "Lease is not released after a cancelled write", "expectedFailures": ["lease-held"],
 "appliesTo": {"kind": "only-when", "conditions": [
   {"kind": "resolved-from-hackage", "package": "fixture-store"},
   {"kind": "version-below", "package": "fixture-store", "version": "1.3.0"}]}}
```

The older `knownDefect` field keeps carrying only the reference, or a group's
references. Execution and later analysis decide whether a scope applies with one
evaluator, `evaluateScope`, so they never disagree. A stale scope is found by
[scope reconciliation](scope-reconciliation.md).
