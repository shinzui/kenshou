---
type: Term
title: scope reconciliation
description: Comparing each known defect's cohort scope with the version claims of the owner record it cites, and proposing reviewable corrections without editing source or owner records.
generated: {by: 'process:claude-code', at: '2026-11-19T05:30:00Z'}
termId: TERM-36
status: current
tags: [evidence, correctness]
related: [TERM-18, TERM-34, TERM-35]
anchors:
  - {kind: file, resource: kenshou-evidence/src/Kenshou/Evidence/Owner/Reconcile.hs}
  - {kind: file, resource: schemas/kenshou.scope-reconciliation.v1.schema.json}
  - {kind: file, resource: schemas/kenshou.owner-package-map.v1.schema.json}
---

# scope reconciliation

A [known defect's](known-defect.md) scope is written by hand and goes stale. If the
owner fixed the bug in 1.3.0 but the scope still excuses the failure below 1.4.0, a
regression in 1.3.0 is silently excused. `kenshou owners reconcile` reads an
[owner snapshot](owner-snapshot.md), the catalog's complete declarations, and a
consumer-written package map, and gives each individual defect exactly one primary
finding from an ordered list of rules.

The package map (`kenshou.owner-package-map/v1`) says which cabal packages an owner
project's defect lives in, and which of them carry the project's release version
numbers (`versionsApplyTo`). Nothing is guessed: a project mapped to several
packages that the scope does not disambiguate, or an owner version that is not a
version of the compared package, is a warning with no proposal. A `fixedVersion`
counts as a fix claim only when the owner's status is `fixed`.

A contradiction makes the command exit 1 and carries a proposed scope: a
`version-below` bound set to the owner's released fixed version, or a bound removed
that no owner claim supports. A proposal never changes failure labels, source
conditions, or revisions, and the command never edits the consumer's source or the
owner's records. Applying a proposal is a reviewed edit by the consumer.
