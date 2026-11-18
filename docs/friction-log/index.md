---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Friction Entry

- [Shared Haskell package set cannot build the harness cohort's pinned dependencies](1-shared-haskell-package-set-cannot-build-the-harness-cohort-s-pinned-dependencies.md) - The haskell-nix extension's package set lacks hs-opentelemetry-exporter-prometheus and carries newer majors of settei, okf-core, pg-migrate, and the migration libraries than a cohort pins, so callCabal2nix package outputs fail to configure.
- [Vendored verification bundle lacks its run records](2-vendored-verification-bundle-lacks-its-run-records.md) - Three kenshou-evidence tests fail on a clean master because fixtures/consumer-baseline/docs/verification has attestations but no runs/, which the top-level .gitignore rule runs/ kept out of git.
