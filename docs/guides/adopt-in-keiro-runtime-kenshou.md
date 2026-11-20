---
type: Guide
title: Adopt the kenshou release in keiro-runtime-kenshou
description: Switch the Keiro verification suite's eight Git-pinned harness packages to Hackage and verify that verdicts and comparison keys match the pre-adoption baseline.
docId: DOC-2
tags: [adoption, release, cohort, consumer, migration]
generated:
  by: process:claude-code
  at: "2026-10-28T20:00:00Z"
---

# Adopt the kenshou release in keiro-runtime-kenshou

The consumer, `mori://shinzui/keiro-runtime-kenshou`, adopted the extracted harness
in commit `62a56483ad594edb2a653f55d393a1cfcd26d0b6`. That migration removed its generic
package copies, moved its executable to `kenshou-suite`, and assembled the layer
bundles through `Kenshou.Cli.mainWith`. The migration and its verification are
recorded in
`mori://shinzui/keiro-runtime-kenshou/plans/26-adopt-the-extracted-kenshou-harness`
and `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-24`.

The remaining adoption step switches the eight packages from Git revision
`b90da77822002de46dfe310ab378f3ccd44cb1db` to Hackage `0.1.0.0`. All nine
packages are available at Hackage index-state `2026-11-20T20:48:12Z`.
The ninth, `kenshou-synthetic`, supplies the example executable.
For the assembly contract, see
[Adopt kenshou in a project](adopting-kenshou-in-a-project.md).

The paths and commands below are relative to the consumer checkout. Artifact-level
Mori URIs for these source and configuration files are pending.

## Confirm the source audit

Compare the import pin in [the import record](../import-provenance.md) to the
parent of the consumer's migration. Then inspect changes to the imported paths
through the current consumer head. Run in Bash.

```bash
pin=a1648293443ad88ff1695ed800ff44c99993574e
pre_migration=481c1e0
generic=(kenshou-core kenshou-check kenshou-measure kenshou-diagnose
  kenshou-telemetry kenshou-evidence kenshou-remote kenshou-cli schemas suites
  policies/default.json policies/selftest.json policies/leak-default.json
  policies/telemetry-overhead.json ':(exclude)kenshou-cli/src/Kenshou/Cli/Attest/Keiro*.hs')
git fetch origin
git diff --stat "$pin" "$pre_migration" -- "${generic[@]}"
git log --oneline "$pre_migration"..origin/master -- "${generic[@]}"
```

On 2026-11-20 the diff was empty and the log listed only the migration.
Comparing the published archive's CLI module inventory with the pre-migration
tree should leave twelve `Kenshou.Cli.Attest.Keiro*` modules on the consumer side.
The migration relocated those modules and the consumer's own registry and attestation
modules. The published library supplies `Kenshou.Cli.Registry` and `Kenshou.Cli.Attest`.

## Pin the eight packages in Cabal

Replace the `source-repository-package` stanza in `cohort/kenshou.project` with
the following shared stanza. The released, head and isolated Shibuya projects
already import this file.

```cabal
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

Raise each importing project's `index-state` to at least the recorded release
timestamp. Set the same `indexState` on its cohort descriptor wherever the
consumer produces a cohort identity. In each corresponding descriptor, declare
the component with its exact package versions and Hackage source.

```json
{
  "id": "kenshou",
  "moriUri": "mori://shinzui/kenshou",
  "source": { "type": "hackage" },
  "packages": [
    { "name": "kenshou-core", "version": "0.1.0.0" },
    { "name": "kenshou-check", "version": "0.1.0.0" },
    { "name": "kenshou-measure", "version": "0.1.0.0" },
    { "name": "kenshou-diagnose", "version": "0.1.0.0" },
    { "name": "kenshou-telemetry", "version": "0.1.0.0" },
    { "name": "kenshou-evidence", "version": "0.1.0.0" },
    { "name": "kenshou-remote", "version": "0.1.0.0" },
    { "name": "kenshou-cli", "version": "0.1.0.0" }
  ]
}
```

`just use-cohort released` selects the cohort and invalidates the old solver plan.
Run the following with the consumer's development tools.

```bash
cabal update
just use-cohort released
cabal build all
just cohort-check
```

Check that the eight harness entries in the new Cabal plan use Hackage tarballs.

## Use the published sources in Nix

Replace the dedicated Git harness overlay in `nix/kenshou/packages.nix` by
regenerating the released and head payload locks from their updated descriptors.

```bash
just payload-lock released
just payload-lock head
```

The existing `nix/kenshou/cohort-overlay.nix` passes each lock's unpacked source
hash to `callHackageDirect` and applies `dontCheck`.
[IR-1](../improvement-requests/run-every-package-test-suite-from-its-source-distribution.md)
tracks the repository-level fixtures read by some test suites. Keep that override
for the first release. The separate tarball SHA-256 in the lock identifies the
archive in the payload's cohort identity.

Compare the eight source hashes in each lock with the
[published source hashes](../plans/7-publish-the-first-kenshou-release-and-prepare-the-consumer-adoption-path.md#published-source-hashes).
Run `just payload-check released` and `just payload-check head`
to check the resulting Nix identities against their descriptors.

## Verify the adoption

1. Run `just verify` on the released cohort and run the isolated Shibuya checks.
2. Run the smoke and change suites using the released build.
3. Compare against the last pre-adoption baseline with equivalent scenario
   inputs and environments. Check that verdicts and comparison keys match.
   A Git-to-Hackage source change alters the cohort identity and can change the
   series key. The `0.1.0.0` comparison key excludes the cohort plan hash.

Use the invocations in `mori://shinzui/keiro-runtime-kenshou`, path
`docs/planning.md`, and in
`mori://shinzui/keiro-runtime-kenshou/okf/runbooks/concepts/RB-1`.
Preserve the recorded baseline per
[ADR-12](../adr/0012-keep-verification-records-immutable-and-derive-baselines.md).
Report the results to the
[extraction MasterPlan](../masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md).
Its adoption gate controls the move from Experimental to Active in Mori.
