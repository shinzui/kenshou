---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Improvement Request

- [Run every package test suite from its source distribution](run-every-package-test-suite-from-its-source-distribution.md) - About eighty test cases read fixtures outside their own package (the consumer baseline, the repository's policies and suites, and sibling packages' goldens), so the suites pass only in the repository checkout. Make each suite pass, or skip those cases explicitly, when built from its Hackage tarball, so builders that run tests by default can consume the release.

