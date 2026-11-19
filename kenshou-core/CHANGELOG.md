# Changelog

## 0.1.1.0 - 2026-11-19

### New Features

- `kenshou.scenario-list/v1` documents, from `scenarioListDocumentFor` and the planning catalog's `ToJSON ScenarioInfo`, carry each scenario's complete known-defect declaration under the new optional field `knownDefectDeclaration`: every reference, summary, excused failure label, group (nested groups preserved), and cohort condition. The `knownDefect` reference field is unchanged, and the schema identifier stays `v1`.
- `Kenshou.Plan.Catalog.decodeCatalog` reads `knownDefectDeclaration` back, so a catalog written to a file keeps its declarations. Documents without the field still decode, with no declaration.
- `Kenshou.Core.Defect` provides the hand-written declaration codec (`defectValue`, `parseDefect`, and the scope and condition codecs).
- `Kenshou.Core.Scenario.evaluateScope` explains whether a scope applies to a list of `ScopePackage` values, condition by condition (`ConditionHolds`, `ConditionFails`, `ConditionPackageMissing`, `ConditionMalformed`). `scopeApplies` reduces the explanation to a Boolean, `cohortScopePackages` converts a resolved cohort, and `parseScopeVersion` is the version parser for bounds. All are re-exported from `Kenshou.Core.Defect`.

### Other Changes

- `cohortScopeApplies` keeps its type and meaning and is now defined through `evaluateScope`; a test compares it with a frozen copy of the previous definition.
- `suiteVersion` is now `0.1.1.0`. It is part of comparison and series keys, so runs made with this version do not compare with runs made with 0.1.0.0.

## 0.1.0.0 - 2026-10-28

### New Features

- First public release of the scenario kernel: run specifications, results, worker roles, knobs, dimensions, phases, cohort identity, change-aware planning, and the performance session protocol.
- Open layer identifiers (`LayerId`, `mkLayerId`) replace the closed `Layer` type, and a suite registers its layers as `LayerBundle` values built with `mkBundle`.
- Suite-supplied migration sets (`MigrationSet`) compose into one pg-migrate ledger per run database.
- Named resources (`ResourceProvider`, `requiresResource`) replace the broker-shaped environment fields; documents written in the legacy shape remain readable.
- Bundles contribute oracles, advisory-lock labels, pool methodology, routing rules, and their evidence subject.
- `Program`, `defaultProgram`, and `runCli` let an executable supply its bundles, commands, component graph, and performance contracts.

### Other Changes

- Extracted from `mori://shinzui/keiro-runtime-kenshou` at commit `a1648293443ad88ff1695ed800ff44c99993574e`, with its package and module names unchanged.
- The kernel no longer depends on any runtime migration library; its own self-test schema is the `kenshou-selftest` migration set.
