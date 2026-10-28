---
type: Architecture Decision Record
title: Keep the package and module names of the extracted harness
description: The harness keeps the package names kenshou-core, kenshou-check, kenshou-measure, kenshou-diagnose, kenshou-telemetry, kenshou-evidence, kenshou-remote, and kenshou-cli and the Kenshou.* module namespace.
timestamp: 2026-10-28T17:00:00Z
generated:
  by: process:claude-code
  at: "2026-10-28T17:00:00Z"
docId: ADR-18
status: Accepted
date: 2026-10-28
originatingPlan: docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md
---

# Keep the package and module names of the extracted harness

## Context

The first consumer imports every harness module by its current name. It adopts the
published harness by deleting its local copies of these packages and depending on
the release.

## Decision

The packages `kenshou-core`, `kenshou-check`, `kenshou-measure`, `kenshou-diagnose`,
`kenshou-telemetry`, `kenshou-evidence`, `kenshou-remote`, and `kenshou-cli` and the
`Kenshou.*` module namespace keep the names they had in the consumer. New harness
packages, such as `kenshou-synthetic`, follow the same prefix.

## Consequences

- Adoption is a deletion of local packages plus a dependency change, with no import
  churn and no verification value lost to a rename.
- The protocol document identifiers `kenshou.*/v1` stay consistent with the packages
  that own them.
- Interfaces that changed in the extraction (for example `LayerId`, `Program`, and
  named resources) are the adoption work; names are not.
