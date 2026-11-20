---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Friction Entry

- [Shared Haskell package set cannot build the harness cohort's pinned dependencies](1-shared-haskell-package-set-cannot-build-the-harness-cohort-s-pinned-dependencies.md) - The haskell-nix extension's package set lacks hs-opentelemetry-exporter-prometheus and carries newer majors of settei, okf-core, pg-migrate, and the migration libraries than a cohort pins, so callCabal2nix package outputs fail to configure.
- [Vendored verification bundle lacks its run records](2-vendored-verification-bundle-lacks-its-run-records.md) - Three kenshou-evidence tests fail on a clean master because fixtures/consumer-baseline/docs/verification has attestations but no runs/, which the top-level .gitignore rule runs/ kept out of git.
- [Vendored verification bundle still lacks its run records](3-vendored-verification-bundle-still-lacks-its-run-records.md) - The three kenshou-evidence failures recorded as FRIC-2 recur on plan 9, so every evidence test run needs a filtered rerun to separate them from new failures.
- [Evidence tests copy a bundle with missing run records](4-evidence-tests-copy-a-bundle-with-missing-run-records.md) - Three existing evidence tests fail when the vendored bundle's attestations reference ignored run files.
