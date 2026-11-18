---
type: Architecture Decision Record
title: Resolve owner records read-only and replay them from snapshots
description: Owner-record resolution lives in kenshou-evidence, reports owners' claims without verifying or editing them, records only relative provenance, and replays reports from create-once snapshots that run nothing live.
timestamp: 2026-11-18T04:00:00Z
generated:
  by: process:claude-code
  at: "2026-11-18T04:00:00Z"
docId: ADR-21
status: Accepted
date: 2026-11-18
originatingPlan: docs/plans/8-resolve-owner-records-through-consumer-supplied-sources.md
---

# Resolve owner records read-only and replay them from snapshots

## Context

Known defects and consumer findings cite owner records: bug reports and improvement
requests in the repositories that own the broken behavior. Consumers need to know what
the owners currently claim (fixed, in which version, duplicate of what) without keeping
a hand-copied register. Later verification rounds must be able to report from exactly
the bytes an earlier round saw, and snapshots are meant to be checked in as fixtures.
The first consumer also attaches identifiers from a personal tracker, which no generic
package may depend on.

## Decision

Owner-record discovery, resolution, and reporting live in `kenshou-evidence` under
`Kenshou.Evidence.Owner`, and no new package is created. The standard command list
includes `owners`. A consumer replaces it with `ownersCommandWith`, using
`withCommand`, to add sources, a resolver, record kinds, and enrichments.

A reference is an owner record only when it has the canonical concept form and the
concept's `type` is a configured record kind. Anything else is reported as
`not-a-record` and is never counted as a defect. The full Mori URI is the identity. A
record is matched by its frontmatter handle, never by its file name. Values are kept
exactly as written, and version fields are classified, never normalised. The command
never writes to an owner's files and never claims that a fix was verified.

Documents record only relative locations. Resolvers do not read git state; the
`withGitProvenance` decorator adds the checkout revision and dirty flag to live reads
unless `--no-git-provenance` is given.

A snapshot is a directory created once and never overwritten. It stores every
reference reached during resolution, each resolver answer, the record kinds, the
citations, and the enrichment links. A replay verifies every digest and rebuilds the
report from those stored values alone; it runs no source, resolver, or enrichment.

## Consequences

- A report from a snapshot is repeatable: the same snapshot gives the same report on
  any machine, whatever the owners have changed since.
- A checked-in snapshot or golden file does not change when the surrounding repository
  gains a commit, provided it was taken without git provenance.
- A consumer's enrichment can be arbitrary I/O, because it runs only when bytes are
  captured.
- A program that already contributes a command named `owners` must replace the
  standard one with `withCommand`.
