# Changelog

## 0.1.1.0 - 2026-11-18

### New Features

- `standardCommands` now includes `owners`, which reports what owners claim about the records that known defects and findings cite, live or from a snapshot. `kenshou help owners` describes it.
- `withCommand` replaces the command of the same name in a command list, or appends the command when none has that name. It is re-exported from `Kenshou.Cli`.

### Other Changes

- A program that already contributes its own command named `owners` now has two commands with that name. Replace the standard one with `withCommand` instead of appending yours.

## 0.1.0.0 - 2026-10-28

### New Features

- First public release of the operator command library: `list`, `plan`, `run`, `execute`, `summarize`, `compare`, `diagnose`, `overhead`, `cell`, `record`, `attest`, `evidence`, `history`, `cohort`, and `perf`.
- The library takes its assembly from the executable: `mainWith`, `runWithArgsWith`, `standardCommands`, `standardTopics`, and `selfTestAssembly`.

### Other Changes

- Extracted from `mori://shinzui/keiro-runtime-kenshou` at commit `a1648293443ad88ff1695ed800ff44c99993574e`, with its package and module names unchanged.
