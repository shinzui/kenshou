---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Improvement Request

- [Derive fix-verification dispositions from immutable evidence](derive-fix-verification-dispositions-from-immutable-evidence.md) - Join canonical owner snapshots, scenario declarations, resolved cohorts, and immutable run evidence to derive traceable fix-verification dispositions with separate evidence trust.
- [Reconcile known-defect scopes with owner version claims](reconcile-known-defect-scopes-with-owner-version-claims.md) - Expose complete defect scope data and reusable reconciliation against owner version claims, with explicit consumer package mappings and reviewable corrections rather than automatic source edits.
- [Resolve owner records through consumer-supplied sources](resolve-owner-records-through-consumer-supplied-sources.md) - Provide reusable owner-record discovery, resolution, duplicate handling, and status reporting from consumer-supplied findings and scenario references, without embedding a particular runtime or tracker.
- [Run every package test suite from its source distribution](run-every-package-test-suite-from-its-source-distribution.md) - About eighty test cases read fixtures outside their own package (the consumer baseline, the repository's policies and suites, and sibling packages' goldens), so the suites pass only in the repository checkout. Make each suite pass, or skip those cases explicitly, when built from its Hackage tarball, so builders that run tests by default can consume the release.
- [Run verification rounds against frozen baseline evidence](run-verification-rounds-against-frozen-baseline-evidence.md) - Provide generic round snapshots, conservative rerun planning, and replayable reports that compare exact baseline and candidate evidence without imposing consumer-specific tracking or repair policy.
