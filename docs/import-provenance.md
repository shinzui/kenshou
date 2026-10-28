# Import provenance

The packages `kenshou-core`, `kenshou-check`, `kenshou-measure`, `kenshou-diagnose`,
`kenshou-telemetry`, `kenshou-evidence`, and `kenshou-remote`, the generic modules of
`kenshou-cli`, the generic JSON schemas under `schemas/`, the suites under `suites/`, and
four generic policies under `policies/` were copied from
`mori://shinzui/keiro-runtime-kenshou` at commit
`a1648293443ad88ff1695ed800ff44c99993574e` (2026-10-12) by
`docs/plans/1-import-the-harness-packages-from-keiro-runtime-kenshou-and-build-them-standalone.md`.
Compare against that commit, not against the consumer's head, when auditing divergence.

## Imported paths

```text
kenshou-core/
kenshou-check/
kenshou-measure/
kenshou-diagnose/
kenshou-telemetry/
kenshou-evidence/
kenshou-remote/
kenshou-cli/                     (generic modules only; see below)
schemas/                         (layer-specific schemas removed; see below)
suites/
policies/default.json
policies/selftest.json
policies/leak-default.json
policies/telemetry-overhead.json
```

## Removed after extraction

```text
schemas/kenshou.inbox-*.json
schemas/kenshou.outbox-*.json
schemas/kenshou.queue-*.json
schemas/kenshou.kafka-env.v1.json
kenshou-cli/linkproof/
kenshou-cli/app/
kenshou-cli/src/Kenshou/Cli/Attest/Keiro*.hs
kenshou-cli/test/fixtures/{inbox,outbox,queue,producer-identity}-*.json
```

The edits made to the imported `kenshou-cli` sources after extraction are recorded in the
plan named above, and are visible in this repository's history as the commits that follow
the import commit.
