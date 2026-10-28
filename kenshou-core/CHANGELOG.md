# Changelog

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
