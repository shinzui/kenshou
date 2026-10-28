---
type: Friction Entry
title: "Shared Haskell package set cannot build the harness cohort's pinned dependencies"
description: "The haskell-nix extension's package set lacks hs-opentelemetry-exporter-prometheus and carries newer majors of settei, okf-core, pg-migrate, and the migration libraries than a cohort pins, so callCabal2nix package outputs fail to configure."
generated:
  by: "claude-code/claude-opus-5-5"
  at: "2026-10-28T13:25:37Z"
frictionId: FRIC-1
status: "accepted"
impact: detour
kind: tooling
origin: "mori://shinzui/kenshou"
affects: "mori://shinzui/haskell-nix"
plan: "docs/plans/1-import-the-harness-packages-from-keiro-runtime-kenshou-and-build-them-standalone.md"
workaround: "Composed a cohort overlay in flake.module.nix that builds the exact pinned Hackage releases with callHackageDirect, jailbroken and without tests"
resolution: "The harness keeps a cohort overlay in flake.module.nix while its cohort pins below the shared package set; the list shrinks when docs/plans/2-… removes the three migration libraries."
amended:
  - by: "claude-code/claude-opus-5-5"
    at: "2026-10-28T13:38:06Z"
    change: "Accepted: a project-local overlay is the intended place for cohort pins below the shared set"
---
# Shared Haskell package set cannot build the harness cohort's pinned dependencies

## Attempted

nix build .#kenshou-core with packages defined by callCabal2nix over inputs.haskell-nix.lib.haskellExtension, as the consumer's flake.module.nix does

## Encountered

Configure failed with Cabal-8010 missing settei-yaml >=0.2.0.0 && <0.3; a version comparison of the Cabal plan against the package set found nine divergent or missing packages

```text
kenshou-core> Error: [Cabal-8010]
kenshou-core>     settei-yaml >=0.2.0.0 && <0.3
```

## Workaround

Composed a cohort overlay in flake.module.nix that builds the exact pinned Hackage releases with callHackageDirect, jailbroken and without tests
