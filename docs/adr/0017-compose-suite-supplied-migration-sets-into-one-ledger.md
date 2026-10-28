---
type: Architecture Decision Record
title: Compose suite-supplied migration sets into one ledger
description: Scenarios receive database handles from the harness, and every migration set a scenario requires is composed into one pg-migrate ledger per database, from sets the registered bundles supply.
timestamp: 2026-10-28T17:00:00Z
generated:
  by: process:claude-code
  at: "2026-10-28T17:00:00Z"
docId: ADR-17
status: Accepted
date: 2026-10-28
originatingPlan: docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md
---

# Compose suite-supplied migration sets into one ledger

## Context

Database setup is part of the experiment: PostgreSQL major version, durability,
schemas, resets, and server control affect correctness and performance. A scenario
that provisions or migrates its own database can diverge from its run specification
and create several migration histories in one database. The first consumer settled
this with one ledger built from three migration libraries the kernel linked and
ordered by name, which no other project could use.

## Decision

Scenarios never open, initialize, migrate, or tear down their declared database
environment; they declare `PostgresRequirement` values and receive a `PostgresEnv`.
The harness owns the server lifecycle, configuration checks, template cloning,
connection strings, snapshots, server control, and teardown.

The migration sets a scenario names are supplied by registered bundles as
`MigrationSet` values (a name, the sets it requires, and a `pg-migrate` component),
resolved by name across the registry so one layer can require another's schema
without depending on its package. `Kenshou.Core.Env.Migration.composePlan` keeps the
order the scenario declared, inserts each set's requirements first, transitively,
applies each set once, and builds one plan applied to the template database: one
`pgmigrate` ledger per database. Two bundles defining one set name, or a scenario
requiring an undefined set, is a registry error. The kernel's own set,
`kenshou-selftest`, serves its self-test scenarios.

Each run receives its own PostgreSQL server in ephemeral mode, never shared between
runs; a scenario requiring crash or restart control cannot use an external server.

## Consequences

- Every schema in a database has one ordered, inspectable migration history.
- The kernel links no migration library but `pg-migrate`.
- A set's name is what a run's comparison key records, in declaration order, so a
  suite that names its sets after its schemas keeps its recorded keys.
- Environment setup failures are infrastructure failures, not scenario failures.

## Origin

Supersedes `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-4`, decided
2026-09-20, which named three migration libraries and ordered them in the kernel.
