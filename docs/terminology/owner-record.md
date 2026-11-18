---
type: Term
title: owner record
description: A bug report or improvement request, kept in the repository that owns a behavior, that a known defect or a consumer finding cites by its canonical concept URI.
generated: {by: 'process:claude-code', at: '2026-11-18T04:00:00Z'}
termId: TERM-34
status: current
tags: [correctness, evidence]
related: [TERM-18, TERM-35]
anchors:
  - {kind: file, resource: kenshou-evidence/src/Kenshou/Evidence/Owner.hs}
  - {kind: file, resource: kenshou-evidence/src/Kenshou/Evidence/Owner/Record.hs}
  - {kind: doc, resource: docs/adr/0021-resolve-owner-records-read-only-and-replay-them-from-snapshots.md}
---

# owner record

An owner record is an OKF concept whose `type` is a configured record kind. The
defaults are `Bug Report`, whose handle is in `bugId`, and `Improvement Request`,
whose handle is in `requestId`. A [known defect](known-defect.md) or a consumer
finding cites it as `mori://NAMESPACE/PROJECT/okf/BUNDLE/concepts/HANDLE`. That full
URI is the record's identity, so two owners' `BUG-1` stay distinct. A record is found
by the handle in its frontmatter, never by its file name.

`kenshou owners status` reports the owner's `status` and version claims exactly as
written, follows duplicate chains to the canonical record, and names every
reference that does not resolve or is not an owner record. The report states what
the owner claimed when the bytes were read. It does not verify the claim, and it
never writes to the owner's files. See [owner snapshot](owner-snapshot.md).
