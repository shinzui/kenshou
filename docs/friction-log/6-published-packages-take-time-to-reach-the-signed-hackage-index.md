---
type: Friction Entry
title: "Published packages take time to reach the signed Hackage index"
description: "The package pages, archives and module documentation were live while Cabal still received a pre-release signed index snapshot."
generated:
  by: "codex-cli/gpt-6.2-sol"
  at: "2026-11-20T20:51:02Z"
frictionId: FRIC-6
status: "accepted"
impact: slowdown
kind: environment
origin: "mori://shinzui/kenshou"
affects: "https://hackage.haskell.org/"
plan: "docs/plans/7-publish-the-first-kenshou-release-and-prepare-the-consumer-adoption-path.md"
workaround: "Poll cabal update until all nine published versions appear before recording an index-state for the probes."
resolution: "Hackage indexing caught up at 20:54 UTC, and the release procedure now checks for all nine versions before pinning the index."
amended:
  - by: "codex-cli/gpt-6.2-sol"
    at: "2026-11-20T20:55:28Z"
    change: "Accepted the registry propagation delay and documented the Cabal index check."
---
# Published packages take time to reach the signed Hackage index

## Attempted

Run cabal update and build clean Cabal probes with the reported index-state after the final upload.

## Encountered

Cabal reported 2026-11-20T19:54:08Z, before publication at 20:48 UTC, and did not know the uploaded packages.

```text
Cabal-7107: unknown package: kenshou-core (dependency of probe)
```

## Workaround

Poll cabal update until all nine published versions appear before recording an index-state for the probes.
