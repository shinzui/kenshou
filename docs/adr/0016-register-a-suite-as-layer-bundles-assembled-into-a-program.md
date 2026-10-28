---
type: Architecture Decision Record
title: Register a suite as layer bundles assembled into a program
description: A consuming suite registers everything it verifies as layer bundles and assembles them, with its commands and contracts, into the program its executable runs.
timestamp: 2026-10-28T17:00:00Z
generated:
  by: process:claude-code
  at: "2026-10-28T17:00:00Z"
docId: ADR-16
status: Accepted
date: 2026-10-28
originatingPlan: docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md
---

# Register a suite as layer bundles assembled into a program

## Context

The harness was extracted from a suite that named its layers, schemas, resources,
oracles, lock labels, routing rules, evidence subjects, and performance contracts in
closed types and literals inside the kernel and toolkits. Any other project needed to
fork the harness to verify its own system.

## Decision

A suite registers one `Kenshou.Core.Bundle.LayerBundle` per layer, built with
`mkBundle` from an open layer identifier (`Kenshou.Core.Id.LayerId`), its scenarios,
and its worker roles, and sets its contributions by record update:

- `migrations`: `Kenshou.Core.Env.MigrationSet` values, resolved by name across the
  whole registry ([ADR-17](0017-compose-suite-supplied-migration-sets-into-one-ledger.md));
- `rules`: `ScenarioRule` checks that `mkRegistry` applies to every scenario, such as
  `requirePgVersionsFor`;
- `resources`: `Kenshou.Core.Resource.ResourceProvider` values for named resources
  ([ADR-19](0019-provision-named-resources-and-keep-legacy-documents-readable.md));
- `oracles`, `advisoryLabels`, `methodology`, and `routingRules`: the types in
  `Kenshou.Core.Contribution`, read by the correctness, diagnostics, measurement, and
  remote toolkits;
- `evidenceSubject`: the canonical Mori URI that records of the layer name.

`mkRegistry` validates the whole set: identifiers, duplicate scenarios, roles,
migration sets, providers and oracles, undefined migration sets and resources,
subject URIs, and every contributed rule. The executable then supplies a
`Kenshou.Core.Cli.Program` (in `kenshou-cli`, `CliAssembly`) with its name, header,
bundles, commands, help topics, component graph, and
`Kenshou.Perf.Contracts.PerfContracts`, and calls `Kenshou.Cli.mainWith`. The
evidence subject of a run record is the `--subject` override, else the registered
bundle's subject for the run's layer, else `evidence.default-subject`; otherwise
recording fails with exit code 2. History documents cite the bundle named by
`evidence.bundle-uri`, which has no default.

Every field has an empty default, so a new contribution never breaks a suite.

## Consequences

- The kernel and toolkits name no layer; `scripts/coupling-guard.sh` enforces it.
- A suite adds coverage by adding a bundle or a contribution, never by editing the
  harness.
- The synthetic reference suite in `kenshou-synthetic` fills every field and is the
  worked example.
- Several bundles may share a layer; suite contributions are read from the first
  bundle of a layer.
