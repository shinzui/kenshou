---
type: Architecture Decision Record
title: Verify the harness against its own cohort and confine consumer data
description: The harness resolves its own harness cohort for every run, and consumer data appears only in the verbatim consumer-records fixtures and the consumer-baseline bridge.
timestamp: 2026-10-28T17:00:00Z
generated:
  by: process:claude-code
  at: "2026-10-28T17:00:00Z"
docId: ADR-20
status: Accepted
date: 2026-10-28
originatingPlan: docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md
---

# Verify the harness against its own cohort and confine consumer data

## Context

Every run records a resolved cohort identity, which needs a cohort descriptor.
Several tests also exercise documents only a real consumer run produced, such as a
captured performance preparation whose digests the code cross-checks and that
cannot be regenerated here.

## Decision

This repository verifies against its own cohort, `harness`: `cohort/active.project`
imports `cohort/harness.project`, which holds the index state and the exact pins, and
`cohort/harness.json` describes it. `cabal.project` imports the active cohort, and
`just cohort-check` validates it.

Consumer data is confined to two places. Verbatim consumer records that prove
compatibility live in `kenshou-evidence/test/fixtures/consumer-records/`, the only
directory the coupling guard excludes. Captured protocol documents and the consumer
layout some tests read live in `fixtures/consumer-baseline/`, outside every package.
Everything else uses synthetic names; the planning and perf-planning tests use a
synthetic graph, catalog, and cohort.

## Consequences

- No consumer package is part of the harness's identity.
- The coupling guard stays mechanical: one excluded directory and an exact allow-list.
- Regenerating the captured performance documents synthetically needs a synthetic
  performance pipeline, which is later work.
