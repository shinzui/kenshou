# Kenshou

**検証** — *kenshou*: verification, validation, examination. The act of putting a
claim to the test and recording whether it held.

| 漢字 | Reading | Sense                                              |
| ---- | ------- | -------------------------------------------------- |
| 検   | ken     | to examine, to inspect, to verify                  |
| 証   | shou    | proof, evidence, attestation                       |

Kenshou is a package-agnostic verification harness for Haskell systems. It is
the scenario kernel and the toolkits that
[`keiro-runtime-kenshou`](mori://shinzui/keiro-runtime-kenshou) built to verify
the Keiro runtime, extracted so that any project can register its own layer
bundles and produce the same kind of evidence: executable correctness properties,
concurrency and fault-injection suites, heap-leak and stall diagnostics,
telemetry-overhead reports, and benchmarks with retained baselines for
cross-release regression detection.

## Why this exists

The Keiro verification suite is about 74k lines of Haskell. Roughly 27k of
those lines know nothing about Keiro: run specifications, scenario registries,
worker roles, fact ledgers, invariants, fault injection, load generators,
samplers, paired comparison, leak verdicts, stall capture, telemetry arms,
immutable evidence records, and leased verification cells. The only thing that
stops another project from using that machinery is that the kernel and the
toolkits *name* the layers they happen to test today: a closed `Layer` sum
type, a closed schema-component type, Kafka-shaped environment fields, three
hard-coded oracles, advisory-lock labels, a pool-size constant, and an evidence
bundle URI.

This repository removes that naming and publishes the result. The improvement
request that scoped the work is
[IR-1](mori://shinzui/keiro-runtime-kenshou/okf/improvement-requests/concepts/IR-1)
in the Keiro suite; the initiative that delivers it is
[MasterPlan 1](docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md)
here.

## What a consumer gets

A consuming project depends on the `kenshou-*` packages, registers one or more
*layer bundles*, and assembles the operator commands into its own executable. A
bundle is a value: a layer identifier, scenarios, worker roles, the schema
migrations its database needs, any extra resources it must provision, the
oracles that reconcile ledger evidence with durable state, diagnostic lock
labels, and the evidence subject its records are filed under. In return the
project gets `list`, `plan`, `run`, `execute`, `summarize`, `compare`,
`diagnose`, `overhead`, `cell`, `record`, `attest`, `evidence`, and `history`
commands that write the same versioned `kenshou.*/v1` JSON documents the Keiro
suite writes, so evidence from different projects is comparable and the same
tooling can read it.

The repository ships a synthetic reference bundle that links only the generic
packages. It proves the boundary by construction, and it is the worked example
for adopting the harness.

## Scope

Three axes, verified together rather than in separate efforts, exactly as in
the Keiro suite:

- **Correctness** — guarantees stated as executable properties over a bounded
  fact ledger: no loss, per-key and global order, duplicates only within
  declared fault windows, exactly-n effects, eventual quiescence, monotonic
  checkpoints, disjoint ownership, linearizability.
- **Concurrency** — the same guarantees under interleaving, process kill and
  restart, backend termination, network partition, and clock skew.
- **Benchmarking** — throughput, latency distributions, and resource behavior
  measured with enough rigor to be compared across releases through paired
  comparison against retained baselines.

## Non-goals

This repository is not the home for:

- **The Keiro runtime suites** — `kenshou-pgmq`, `kenshou-kiroku`,
  `kenshou-shibuya`, `kenshou-kafka`, `kenshou-keiro`, and `kenshou-runtime`
  stay in `keiro-runtime-kenshou`, together with the Keiro oracles,
  attestations, cohort descriptors, and committed verification records.
- **Unit-test frameworks** — unit tests belong to the package they test.
  Kenshou is for cross-package, multi-process, multi-run, and
  comparative-over-time verification.
- **Store-level comparisons** between event stores or queues; that is
  `keiro-benchmarks`.

## Status

Planning. The repository holds the Nix tooling, the Mori and Rei
registrations, the master plan, and its seven child plans. No cabal package
exists yet; the first child plan imports the packages from
`keiro-runtime-kenshou` at commit `a1648293443ad88ff1695ed800ff44c99993574e`.
The master plan's Exec-Plan Registry is the source of truth for plan status.

By the user's direction, `keiro-runtime-kenshou` keeps its local copies of
these packages until the first Kenshou release is published; adoption is a
later plan in that repository.

## Planned layout

```text
cabal.project          discovers every kenshou-* package; pins the index-state
kenshou-core/          scenario kernel: run specs, results, roles, knobs,
                       dimensions, cohort identity, change-aware planning
kenshou-check/         fact ledgers, invariants, fault injection, process
                       control, linearizability
kenshou-measure/       load generation, recorder, samplers, statistics,
                       paired comparison, health gates
kenshou-diagnose/      heap-leak verdicts, stall capture, lock graphs,
                       profiling guards
kenshou-telemetry/     tracing and metrics arms, endpoint scraping,
                       observability-overhead reports
kenshou-evidence/      immutable run records, bundles, attestation, history
kenshou-remote/        leased verification cells, payload publishing,
                       file and GCS object stores
kenshou-cli/           the operator command set, assembled by each consumer
                       into its own executable
kenshou-synthetic/     synthetic reference bundle and the standalone `kenshou`
                       executable that proves the boundary
schemas/               versioned JSON Schemas for every published document
scripts/               coupling guard and plan checks run by `just verify`
docs/masterplans/      initiative coordination
docs/plans/            child execution plans
docs/adr/              durable architecture decisions (created by EP-6)
docs/terminology/      controlled vocabulary (created by EP-6)
docs/guides/           adoption guide for consumers (created by EP-6)
```

## Getting started

Enter the locked development environment with `nix develop`. The flake is
generated by the `nix-haskell-flake` seihou module and pins GHC 9.12.4,
PostgreSQL 18, process-compose, treefmt, and pre-commit hooks; project-specific
Nix wiring lives in the unmanaged `flake.module.nix`. Once the first child plan
lands, build the workspace with `cabal build all`, run the local gate with
`just verify`, and run a synthetic scenario with the standalone executable:

```bash
nix develop
cabal build all
cabal run kenshou -- list
```

## Planning and tracking

Plans follow the exec-plan and master-plan skills installed under
`agents/skills/`. Every plan is linked to a Rei intention; the project's root
intention and the `検証` title prefix for new child intentions are recorded in
`mina.kdl`, and the project identity in `mori.dhall` is registered as
`mori://shinzui/kenshou`.

## Related

- `mori://shinzui/keiro-runtime-kenshou` — the first consumer and the source
  of the extracted packages
- `mori://shinzui/keiro-runtime-kenshou-insights` — browses the evidence the
  harness produces
- `mori://shinzui/load-testing-infra` — provisions the leased verification
  cells that `kenshou-remote` talks to
- `mori://shinzui/okf-profiles` — the documentation profiles the OKF bundles
  under `docs/` will use
