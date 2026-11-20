# Changelog

## 0.2.0.0 - 2026-11-19

- Add digest-verified published and sealed run observations, the pure disposition
  derivation, and versioned capture and replay for `owners dispositions`.
- Breaking API change for positional constructors and matches. `RunResultView`
  adds optional failure labels and scenario revision. `OwnerConfig` adds locations,
  a data locator, and an observation replay hook. Existing run-result files remain
  readable.

## 0.1.2.0 - 2026-11-19

### New Features

- `Kenshou.Evidence.Owner.Reconcile` compares each known defect's cohort scope with the version claims of the owner record it cites. `reconcileScopes` gives each individual defect exactly one primary finding from an ordered rule list, proposes only a `version-below` bound at the owner's released fixed version or the removal of an unsupported bound, and never changes labels, source conditions, or revisions. It reads the consumer's `kenshou.owner-package-map/v1` (`decodePackageMap`, `ownerPackages`, `choosePackage`) and encodes `kenshou.scope-reconciliation/v1`.
- The `owners` command has a `reconcile` subcommand: `--snapshot DIR` and `--package-map FILE` are required, `--catalog FILE` replaces the registered scenarios, and `--json` prints the versioned report. It exits 1 when a finding is a contradiction and writes nothing.

### Other Changes

- Owner version claims are classified with `Kenshou.Core.Scenario.parseScopeVersion`, the parser scope bounds use; the classification is unchanged.
- Requires `kenshou-core` 0.1.1.0.

## 0.1.1.0 - 2026-11-18

### New Features

- `Kenshou.Evidence.Owner` resolves the owner records that known defects and consumer findings cite. The module gathers citations from the registry and `kenshou.owner-findings/v1` files, follows duplicate chains with cycle detection, keeps every owner claim exactly as written, and encodes `kenshou.owner-status/v1`.
- `Kenshou.Evidence.Owner.Resolver` provides the mapped-directory, Mori, chained, and in-memory resolvers, and `withGitProvenance`. Provenance records only relative locations.
- `Kenshou.Evidence.Owner.Snapshot` writes create-once `kenshou.owner-snapshot/v1` directories of the exact record bytes, and reports from them without reading the owners' files again.
- `Kenshou.Evidence.Owner.Cli` provides the `owners status` and `owners snapshot` command. Consumers customise it with `ownersCommandWith` and `OwnerConfig`, which adds sources, a resolver, record kinds, and enrichments.

## 0.1.0.0 - 2026-10-28

### New Features

- First public release of immutable run records, verification bundles, attestation, and history.
- The record subject resolves from `--subject`, then the run layer's bundle, then `evidence.default-subject`; `history` takes the bundle URI from `evidence.bundle-uri` or `--bundle-uri`.

### Other Changes

- Extracted from `mori://shinzui/keiro-runtime-kenshou` at commit `a1648293443ad88ff1695ed800ff44c99993574e`, with its package and module names unchanged.
- Consumer records written before the extraction still read and compare unchanged.
