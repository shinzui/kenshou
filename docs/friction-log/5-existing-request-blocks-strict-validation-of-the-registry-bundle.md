---
type: Friction Entry
title: "Existing request blocks strict validation of the registry bundle"
description: "The registry request bundle fails strict authoring validation because an existing proposed request lacks review metadata."
generated:
  by: "codex-cli/gpt-6.2-sol"
  at: "2026-11-20T19:51:09Z"
frictionId: FRIC-5
status: logged
impact: detour
kind: tooling
origin: "mori://shinzui/kenshou"
affects: "mori://shinzui/haskell-nix/okf/improvement-requests"
plan: "docs/plans/7-publish-the-first-kenshou-release-and-prepare-the-consumer-adoption-path.md"
workaround: "Run strict profile and log enforcement on an isolated copy of IR-6 and run profile and log enforcement on the whole bundle."
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
