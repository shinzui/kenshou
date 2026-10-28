---
type: Improvement Request
title: Run every package test suite from its source distribution
description: >-
  About eighty test cases read fixtures outside their own package (the consumer baseline, the
  repository's policies and suites, and sibling packages' goldens), so the suites pass only in the
  repository checkout. Make each suite pass, or skip those cases explicitly, when built from its
  Hackage tarball, so builders that run tests by default can consume the release.
generated: {by: 'process:claude-code', at: '2026-10-28T21:30:00Z'}
requestId: IR-1
status: proposed
origin: mori://shinzui/kenshou
reviews:
  - kind: model
    reviewer: claude-code
    reviewed_at: '2026-10-28T21:20:00Z'
    document_timestamp: '2026-10-28T21:00:00Z'
    scope: technical-accuracy
    outcome: commented
    provider: anthropic
    model: claude-opus-5-5
    effort: unspecified
    context: >-
      Independent subagent audit of the first revision against kenshou-*/test, the cabal files,
      and the linked documents. It confirmed the core claim, the absence of shipped repository
      paths, and the plausibility of the failure counts. It found three reads the table omitted
      (`policies/default.json` in kenshou-measure and kenshou-remote,
      `policies/telemetry-overhead.json` in kenshou-cli) and asked for the cli siblings to be
      named. All of these are applied in this revision.
targetPlan: docs/plans/7-publish-the-first-kenshou-release-and-prepare-the-consumer-adoption-path.md
acceptanceCriteria:
  - id: AC-1
    statement: >-
      Each of the eight packages that has a test suite passes `cabal test` in a project whose only sources are
      the unpacked `cabal sdist` tarballs.
    verification: >-
      Unpack the nine tarballs into an empty directory, import the harness cohort project, and run
      `cabal test` for each package. All eight exit 0.
  - id: AC-2
    statement: >-
      No case that reads repository-level data is lost. It either moves its data into the
      package's `extra-source-files`, or it is pending outside the repository with a message that
      names the missing path.
    verification: >-
      The repository's `just verify` reports the same example counts as before, with no new
      pending cases. A tarball run lists each pending case with the path it lacked.
---

# Run every package test suite from its source distribution

## Problem

The 0.1.0.0 release was checked by unpacking the nine tarballs and running each test suite from
them. That check is EP-7's readiness check
([the release plan](../plans/7-publish-the-first-kenshou-release-and-prepare-the-consumer-adoption-path.md)).
After each package shipped its own fixtures, these failures remained:

| Package | Failures | Repository paths read |
| ------- | -------- | --------------------- |
| `kenshou-core` | 16 of 131 | `../fixtures/consumer-baseline/`, `../suites/` |
| `kenshou-measure` | 6 of 43 | `../fixtures/consumer-baseline/policies/`, `../policies/default.json` (through a fallback in `PerfSpec.hs`) |
| `kenshou-diagnose` | 1 of 35 | `../policies/leak-default.json` |
| `kenshou-evidence` | 3 of 29 | `../fixtures/consumer-baseline/docs/verification` |
| `kenshou-remote` | 32 of 157 | `../fixtures/consumer-baseline/`, `../kenshou-core/test/golden/`, `../policies/default.json` |
| `kenshou-cli` | 26 of 44 | `kenshou-core` and `kenshou-remote` goldens, `kenshou-diagnose` fixtures, `../policies/telemetry-overhead.json`, the consumer baseline |

`kenshou-check` and `kenshou-telemetry` pass from their tarballs.

Hackage does not run test suites, so publication is not blocked. A Nix builder does run them
by default. That includes `callHackageDirect` and a future `haskell-nix` family. Until this
request is met, such a builder must build the kenshou packages with tests disabled. The consumer
adoption guide, [DOC-2](../guides/adopt-in-keiro-runtime-kenshou.md), says so.

## Desired outcome

Each package's test suite passes from its own tarball, and the repository keeps running every
case that depends on repository data. Some of that data is the consumer baseline, which
[ADR-20](../adr/0020-verify-the-harness-against-its-own-cohort-and-confine-consumer-data.md)
deliberately keeps outside the packages. Those cases stay where they are, but they must say why
they were skipped rather than fail.
