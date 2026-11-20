---
type: Friction Entry
title: "Existing request blocks strict validation of the registry bundle"
description: "The registry request bundle fails strict authoring validation because an existing proposed request lacks review metadata."
generated:
  by: "codex-cli/gpt-6.2-sol"
  at: "2026-11-20T19:51:09Z"
frictionId: FRIC-5
status: "accepted"
impact: detour
kind: tooling
origin: "mori://shinzui/kenshou"
affects: "mori://shinzui/haskell-nix/okf/improvement-requests"
plan: "docs/plans/7-publish-the-first-kenshou-release-and-prepare-the-consumer-adoption-path.md"
workaround: "Run strict profile and log enforcement on an isolated copy of IR-6 and run profile and log enforcement on the whole bundle."
resolution: "IR-6 passed strict validation in isolation and the owner bundle passed profile and log enforcement; IR-5 has its own review history."
amended:
  - by: "codex-cli/gpt-6.2-sol"
    at: "2026-11-20T20:49:15Z"
    change: "Accepted the isolated strict check for the family request because the committed baseline reproduces the IR-5 diagnostic."
---
# Existing request blocks strict validation of the registry bundle

## Attempted

Run okf validate docs/improvement-requests --strict --profile mori/improvement-requests-profile.dhall --profile-enforce --log-enforce for the new family request.

## Encountered

The validator rejected IR-5 for missing recommended review metadata. The same diagnostic occurs in the committed baseline.

```text
profile: carry-shomei-token-verification-for-rei: missing profile-recommended field: reviews
```

## Workaround

Run strict profile and log enforcement on an isolated copy of IR-6 and run profile and log enforcement on the whole bundle.
