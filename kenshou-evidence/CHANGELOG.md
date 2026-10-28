# Changelog

## 0.1.0.0 - 2026-10-28

### New Features

- First public release of immutable run records, verification bundles, attestation, and history.
- The record subject resolves from `--subject`, then the run layer's bundle, then `evidence.default-subject`; `history` takes the bundle URI from `evidence.bundle-uri` or `--bundle-uri`.

### Other Changes

- Extracted from `mori://shinzui/keiro-runtime-kenshou` at commit `a1648293443ad88ff1695ed800ff44c99993574e`, with its package and module names unchanged.
- Consumer records written before the extraction still read and compare unchanged.
