# Changelog

## 0.1.0.0 - 2026-10-28

### New Features

- First public release of the correctness toolkit: fact ledgers, invariants, fault injection, process supervision, and linearizability checking.
- Oracles are registered on bundles by name and turned into typed queries with `fromSpec`; `registeredOracle` looks them up.

### Other Changes

- Extracted from `mori://shinzui/keiro-runtime-kenshou` at commit `a1648293443ad88ff1695ed800ff44c99993574e`, with its package and module names unchanged.
- The layer-specific oracle modules stay with the suites that own them.
