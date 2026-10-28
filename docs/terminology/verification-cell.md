---
type: Term
title: verification cell
description: A leased and resettable machine environment for controlled remote verification runs.
generated: {by: 'process:claude-code', at: '2026-10-28T17:30:00Z'}
termId: TERM-29
status: current
tags: [environment]
related: [TERM-4, TERM-22]
---

# verification cell

A cell provides an isolated driver, database, monitoring services, and optional
broker under an exclusive lease. It resets its state before a submitted workload
and publishes the output with a cell fingerprint and manifest. Kenshou can use a
cell for scenarios whose placement is `cell` or `either`, especially controlled
benchmarks. The infrastructure is owned by
`mori://shinzui/load-testing-infra`; this repository defines how Kenshou uses
it. See the [cell plan](../plans/16-provide-leased-verification-cells-in-load-testing-infra.md).
