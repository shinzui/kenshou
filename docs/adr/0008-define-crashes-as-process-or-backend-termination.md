---
type: Architecture Decision Record
title: Define crashes as process or backend termination
description: Kenshou exercises crash recovery by terminating an operating-system process or PostgreSQL backend, never by throwing an in-process exception.
timestamp: 2026-10-28T16:00:00Z
generated:
  by: process:claude-code
  at: "2026-10-28T16:00:00Z"
docId: ADR-8
status: Accepted
date: 2026-10-28
originatingPlan: docs/plans/6-carry-the-harness-decisions-vocabulary-and-adoption-guide-into-kenshou-documentation.md
---

# Define crashes as process or backend termination

## Context

An exception or `killThread` inside the process under test runs Haskell cleanup
handlers and releases resources cooperatively. A production crash does not. It
can leave acknowledged work between durable boundaries, abandon a PostgreSQL
session, and prevent finalizers from flushing state. Tests based only on
exceptions therefore cannot substantiate recovery claims.

## Decision

Kenshou calls an event a crash only when it terminates the relevant execution
boundary from outside that boundary:

- a worker crash is `SIGKILL` of its operating-system process group;
- a database-client crash is termination of its PostgreSQL backend; and
- a PostgreSQL server crash is an immediate stop (or explicit postmaster kill)
  followed by recovery and restart under harness-owned server control.

Graceful `SIGTERM`, cooperative stop commands, and thrown exceptions remain
useful controls, but they are not crash evidence. Every crash opens a durable
disturbance window before termination and closes it only after the replacement
reports ready or the database accepts connections again.

## Consequences

- Crash scenarios exercise skipped cleanup and actual reconnect/recovery paths.
- The supervisor must own process groups, pid bookkeeping, log capture, and
  orphan cleanup.
- Server-crash claims require an ephemeral, harness-controlled PostgreSQL
  environment; external databases can exercise backend termination only.
- Scenario reports can distinguish tolerated duplicates inside a crash window
  from unexcused duplicates outside it.

## Origin

Adopted from `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-9`, decided 2026-09-21, when the harness was extracted into this repository by [the extraction MasterPlan](../masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md). The decision binds the generic packages here; anything it says about a particular runtime layer belongs to the suite that verifies that layer.
