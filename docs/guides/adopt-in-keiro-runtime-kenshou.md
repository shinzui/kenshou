---
type: Guide
title: Adopt the kenshou release in keiro-runtime-kenshou
description: Replace the Keiro verification suite's local copies of the harness with the published kenshou packages and prove that no verdict or comparison key changed.
docId: DOC-2
tags: [adoption, release, cohort, consumer, migration]
generated:
  by: process:claude-code
  at: "2026-10-28T20:00:00Z"
---

# Adopt the kenshou release in keiro-runtime-kenshou

This guide is for the plan that moves `mori://shinzui/keiro-runtime-kenshou`
(the consumer) onto the published kenshou packages. That plan is created and
executed in the consumer repository, not here. This repository's release plan,
[EP-7](../plans/7-publish-the-first-kenshou-release-and-prepare-the-consumer-adoption-path.md),
stops after running each of the guide's read-only commands once against the
consumer's checkout. Read
[Adopt kenshou in a project](adopting-kenshou-in-a-project.md) first. It
explains the registration contract this guide applies to the consumer's six
runtime layers.

The harness was copied from the consumer at commit
`a1648293443ad88ff1695ed800ff44c99993574e`. Since then it was generalized
without renaming any package or module
([ADR-18](../adr/0018-keep-the-package-and-module-names-of-the-extracted-harness.md)).
The adoption therefore deletes directories and rewires registrations; it does
not rename imports.

## 1. Audit divergence since the pin

Port any change that the consumer made to its copies of the generic packages
after the pin before you delete those copies. Run this in the consumer
checkout. The path list is the set of paths imported by
[the import record](../import-provenance.md):

```bash
PIN=a1648293443ad88ff1695ed800ff44c99993574e
GENERIC='kenshou-core kenshou-check kenshou-measure kenshou-diagnose kenshou-telemetry kenshou-evidence kenshou-remote kenshou-cli schemas suites policies/default.json policies/selftest.json policies/leak-default.json policies/telemetry-overhead.json :(exclude)kenshou-cli/src/Kenshou/Cli/Attest'
git fetch origin
git diff --stat "$PIN"..origin/master -- $GENERIC
git log --oneline --no-merges "$PIN"..origin/master -- $GENERIC
```

Both commands print nothing when nothing moved. On 2026-10-28 they printed
nothing. `origin/master` was then at `2129bb9`, three commits past the pin,
and none of the three touched an imported path.

When the audit lists commits, read each diff. If it changes generic behavior,
port it to `mori://shinzui/kenshou` and release a patch version before
adopting. Paths are identical in both repositories, so
`git format-patch -1 <commit> -- $GENERIC` here and `git am --3way` there is
the fast path. Where a file was rewritten by the generalization, port by hand.

## 2. What the consumer deletes and what it keeps

Delete the seven generic package directories:

```text
kenshou-core/
kenshou-check/
kenshou-measure/
kenshou-diagnose/
kenshou-telemetry/
kenshou-evidence/
kenshou-remote/
```

Delete every generic module of `kenshou-cli/`; the published `kenshou-cli`
provides them. List them by comparing the consumer's `kenshou-cli/src` with the
released package:

```bash
comm -23 \
  <(cd kenshou-cli/src && find . -name '*.hs' | sort) \
  <(cabal get -d /tmp/kenshou-cli-src kenshou-cli-0.1.0.0 >/dev/null && cd /tmp/kenshou-cli-src/kenshou-cli-0.1.0.0/src && find . -name '*.hs' | sort)
```

On 2026-10-28 this printed exactly the twelve `Kenshou.Cli.Attest.Keiro*`
modules. Those modules, `Kenshou.Cli.Registry`, the Keiro and Kafka parts of
`Kenshou.Cli.Attest`, and `app/Main.hs` are the consumer-specific parts that
step 3 relocates. Everything else under `kenshou-cli/` is deleted.

The consumer's `Kenshou.Cli.Registry` and `Kenshou.Cli.Attest` share their
names with modules of the released `kenshou-cli`. The released modules hold the
self-test assembly and the generic recomputers. So the consumer's versions
cannot keep those names: an import of either name would be ambiguous once both
packages are in scope.

Keep:
- the six layer packages: `kenshou-pgmq`, `kenshou-kiroku`, `kenshou-shibuya`,
  `kenshou-kafka`, `kenshou-keiro`, `kenshou-runtime`;
- `cohort/`, `docs/`, the committed verification records, and the
  layer-specific policies and schemas.

## 3. Relocate what stays

The consumer can no longer own a package named `kenshou-cli`, because Hackage
now has one. Its executable moves to a new consumer package. Its name is the
adoption plan's decision; the rest of this guide calls it `kenshou-suite`. Move
these into it:
- `app/Main.hs`;
- the consumer's `Kenshou.Cli.Registry`, renamed (for example to
  `Kenshou.Suite.Registry`);
- the `runtime-suites` flag that leaves the full runtime suites out of the
  isolated Shibuya lane.

The oracle modules move to the layers that own them. Each move is a file move
plus an `exposed-modules` edit, because nothing outside `kenshou-check` imports
them:

| Module | New package |
| ------ | ----------- |
| `Kenshou.Check.Oracle.Keiro` | `kenshou-keiro` |
| `Kenshou.Check.Oracle.Kiroku` | `kenshou-kiroku` |
| `Kenshou.Check.Oracle.Pgmq` | `kenshou-pgmq` |
| `Kenshou.Cli.Attest.Keiro*` (twelve modules) | `kenshou-keiro` |

The consumer's `Kenshou.Cli.Attest` also routes Keiro and Kafka scenarios to
those recomputers inside `runOutcomeRecomputer`, and it defines
`FencingFacts`. The released `Kenshou.Cli.Attest` keeps only the generic
fallthrough. Move the routing into a `Recomputer` that the consumer's executable
passes to `standardCommands`. Keep its name, `run-outcome`, so attestations
already recorded under that name still verify.

## 4. Re-express the layers through their bundles

The generalization turned several kernel facts into values that a bundle
contributes. [ADR-16](../adr/0016-register-a-suite-as-layer-bundles-assembled-into-a-program.md)
is the contract. For each of these, the consumer writes the value its kernel
used to hard-code:

- **Layers.** Each layer's bundle is built with `mkBundle` from a `LayerId`
  made by `mkLayerId`. The consumer's layer strings (`pgmq`, `kiroku`,
  `shibuya`, `kafka`, `keiro`, `runtime`, and `selftest`) keep the same
  spelling, so scenario identifiers and recorded run results are unchanged.
- **Migrations.** The consumer's `kenshou-core` built with a `keiro-schema`
  flag that compiled the Keiro, Kiroku, and PGMQ migrations into the kernel.
  The released kernel has no such flag and depends on no runtime migration
  library. Each layer instead contributes a `MigrationSet` whose `requires`
  names the sets it builds on, and scenarios require sets by name
  ([ADR-17](../adr/0017-compose-suite-supplied-migration-sets-into-one-ledger.md)).
- **Kafka.** The Kafka environment fields are a named resource, `kafka`
  (`legacyKafkaName` in `Kenshou.Core.Resource.Types`). `kenshou-kafka`
  contributes a `ResourceProvider` that starts the broker for local runs.
  Cells that still describe a broker are read through
  `Kenshou.Remote.Cell.Legacy`
  ([ADR-19](../adr/0019-provision-named-resources-and-keep-legacy-documents-readable.md)).
  Run specifications and worker documents that carry the old `kafka` field
  still read, and comparison keys keep their recorded form.
- **Oracles, lock labels, and pool methodology.** The relocated oracle modules
  register their queries as `oracles` on their bundles. The Keiro and Kiroku
  advisory-lock label functions become `advisoryLabels`. The Kiroku pool
  constants become `methodology = Just (PoolMethodology 12 (10, 13))` on the
  Kiroku bundle.
- **Evidence.** Each bundle sets `evidenceSubject` to the Mori URI its records
  were filed under before. Set `evidence.bundle-uri` (or
  `KENSHOU_EVIDENCE_BUNDLE_URI`) to the consumer's verification bundle, because
  `history` now requires it.
- **Cell routing.** The rules in the consumer's `policies/cell-routing.json`
  become `routingRules` on the bundles whose knobs they test.
- **Planning and performance.** The component graph the consumer's kernel
  embedded becomes the program's `componentGraph`, read from a JSON file in
  `kenshou-suite`. The reviewed benchmark phase contracts, the steady-count
  knob, and the cohort-lane stanzas become the program's `perf` value of type
  `PerfContracts`. kenshou keeps the consumer's values verbatim in
  `fixtures/consumer-baseline/perf-contracts.json`, which is the reference for
  writing them.

## 5. Assemble the executable

`kenshou-suite`'s `Main` passes a `Program` to `mainWith`. It starts from the
released self-test assembly, so the harness's own self-test bundles stay
registered as they are today:

```haskell
module Main (main) where

import Kenshou.Cli (Program (..), mainWith, selfTestAssembly, standardCommands)
import Kenshou.Suite.Registry qualified as Registry

main :: IO ()
main =
  mainWith
    selfTestAssembly
      { bundles = selfTestAssembly.bundles <> Registry.layerBundles,
        commands = standardCommands Registry.recomputers,
        componentGraph = Registry.componentGraph,
        perf = Registry.perfContracts
      }
```

`Registry` is the consumer's renamed registry. Its `layerBundles` is the
layer part of the CPP-selected list the registry builds today: all six layers,
or only Shibuya when `runtime-suites` is off. The self-test bundles come from
`selfTestAssembly` instead.
`Registry.recomputers` is the routed `run-outcome` recomputer from step 3
together with the released `measurementRecomputer` and
`pairedComparisonRecomputer`.

## 6. Pin the release in the cohort

Add the eight harness packages to `cohort/released.project`, in both the
`extra-packages` and `constraints` blocks. Raise `index-state` to at least the
timestamp recorded when the release was published (see EP-7's Progress):

```text
extra-packages:
  kenshou-core,
  kenshou-check,
  kenshou-measure,
  kenshou-diagnose,
  kenshou-telemetry,
  kenshou-evidence,
  kenshou-remote,
  kenshou-cli

constraints:
  kenshou-core ==0.1.0.0,
  kenshou-check ==0.1.0.0,
  kenshou-measure ==0.1.0.0,
  kenshou-diagnose ==0.1.0.0,
  kenshou-telemetry ==0.1.0.0,
  kenshou-evidence ==0.1.0.0,
  kenshou-remote ==0.1.0.0,
  kenshou-cli ==0.1.0.0
```

Add a matching component to `cohort/released.json`:

```json
{ "id": "kenshou", "moriUri": "mori://shinzui/kenshou", "source": { "type": "hackage" }, "packages": [
  { "name": "kenshou-core", "version": "0.1.0.0" },
  { "name": "kenshou-check", "version": "0.1.0.0" },
  { "name": "kenshou-measure", "version": "0.1.0.0" },
  { "name": "kenshou-diagnose", "version": "0.1.0.0" },
  { "name": "kenshou-telemetry", "version": "0.1.0.0" },
  { "name": "kenshou-evidence", "version": "0.1.0.0" },
  { "name": "kenshou-remote", "version": "0.1.0.0" },
  { "name": "kenshou-cli", "version": "0.1.0.0" }
] }
```

Every other cohort the consumer keeps (the isolated Shibuya lane among them)
needs the same block. Switch cohorts only with the recipe, never by editing
`cohort/active.project`, because the recipe also clears cabal's cached plan:

```bash
just use-cohort released
cabal build all
cabal run kenshou -- cohort check
```

`cohort check` must exit 0.

## 7. Build the release in Nix

`flake.module.nix` and `nix/kenshou/packages.nix` build every `kenshou-*`
directory with `callCabal2nix` from the checkout. Once the directories are
deleted, the eight harness packages come from Hackage instead. Until the
`haskell-nix` registry has a `kenshou` family, write each as a
`callHackageDirect` override:

```nix
kenshou-core = pkgs.haskell.lib.dontCheck (haskellPackages.callHackageDirect {
  pkg = "kenshou-core";
  ver = "0.1.0.0";
  sha256 = "<sri hash>";
} { });
```

`dontCheck` is required for now. Some of the release's test cases read fixtures
that live in the kenshou repository rather than in each package, so those
suites fail when built from a Hackage tarball.
[IR-1](../improvement-requests/run-every-package-test-suite-from-its-source-distribution.md)
asks for that to change. The consumer still runs the harness's evidence through
its own `just verify`.

Take each hash from the published tarball:

```bash
nix store prefetch-file --json --unpack \
  https://hackage.haskell.org/package/kenshou-core-0.1.0.0/kenshou-core-0.1.0.0.tar.gz | jq -r .hash
```

Cell payloads must obtain the packages the same way, because a payload is
pinned to a verified cohort identity
([ADR-14](../adr/0014-pin-cell-payloads-to-verified-cohort-identities.md)).
The isolated Shibuya lane's `--flag=-keiro-schema` on `kenshou-core` goes
away. Its `--flag=-runtime-suites` moves from `kenshou-cli` to
`kenshou-suite`.

## 8. Accept the adoption

The adoption is accepted when all three of these hold in the consumer:

1. `just verify` passes on the `released` cohort.
2. The smoke and change suites run to completion.
3. Pair a run of the last pre-adoption baseline with a run of the adopted
   build, and compare them with `kenshou compare`. The comparison reports no
   verdict change and no comparison-key change.

Use the invocations in the consumer's planning document
(`mori://shinzui/keiro-runtime-kenshou`, path `docs/planning.md`; the
artifact-level URI is pending) and in
`mori://shinzui/keiro-runtime-kenshou/okf/runbooks/concepts/RB-1`. Compare
against the recorded baseline; never regenerate records
([ADR-12](../adr/0012-keep-verification-records-immutable-and-derive-baselines.md)).
When the adoption passes, the consumer's plan reports back here: kenshou's
MasterPlan holds the cross-repository adoption gate, and that gate moves the
Mori lifecycle of `mori://shinzui/kenshou` from Experimental to Active.
