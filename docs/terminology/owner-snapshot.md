---
type: Term
title: owner snapshot
description: A create-once directory holding the exact owner-record bytes, their digests, the citations, and the enrichment links from which an owner status can be reported again.
generated: {by: 'process:claude-code', at: '2026-11-18T04:00:00Z'}
termId: TERM-35
status: current
tags: [evidence]
related: [TERM-34, TERM-27]
anchors:
  - {kind: file, resource: kenshou-evidence/src/Kenshou/Evidence/Owner/Snapshot.hs}
  - {kind: file, resource: schemas/kenshou.owner-snapshot.v1.schema.json}
---

# owner snapshot

`kenshou owners snapshot --out DIR` writes `snapshot.json`
(`kenshou.owner-snapshot/v1`) and `records/`, which holds each resolved
[owner record's](owner-record.md) bytes in a file named by their SHA-256. The index
stores the capture time, the record kinds, every citation, each resolver answer with
its relative provenance, and the enrichment links. Every reference reached through a
duplicate chain is included. The directory is never overwritten.

`kenshou owners status --snapshot DIR` checks every file against its digest and
rebuilds the report from those bytes alone. It runs no source, resolver, or
enrichment, so a later verification round reports from the same bytes even after the
owners change their records. The snapshot's digest is the SHA-256 of `snapshot.json`.
A snapshot taken with `--no-git-provenance` contains no machine-specific data and can
be checked in as a fixture.
