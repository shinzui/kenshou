---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Architecture Decision Record

- [Toolkit packages never depend on a layer bundle](0001-toolkit-packages-never-depend-on-a-layer-bundle.md) - Each runtime layer is its own cabal package depending only on the kernel and toolkits, so a red layer is attributable and layers build and run independently.
- [Every result carries a resolved cohort identity](0002-every-result-carries-a-resolved-cohort-identity.md) - Verification results identify the complete runtime cohort actually selected by Cabal, including immutable sources and a deterministic plan hash, rather than recording only intended pins.
- [Kenshou owns the verification protocol](0003-kenshou-owns-the-verification-protocol.md) - The harness kernel owns versioned list, run, result, worker, and manifest documents so every layer and external runner shares one stable protocol.
- [Select runs from a checked-in component graph and over-select when unsure](0004-select-runs-from-a-checked-in-component-graph.md) - Kenshou maps changes through a reviewed build-and-runtime dependency graph, verifies build edges mechanically, and selects all evidence when an input cannot be mapped safely.
- [Comparison verdicts require controlled benchmark evidence](0005-comparison-verdicts-require-controlled-benchmark-evidence.md) - Performance verdicts come only from paired, interleaved, compatibility-checked, benchmark-grade runs, while historical measurements remain telemetry.
- [Record measurements independently of the feature under test](0006-record-measurements-independently-of-the-feature-under-test.md) - The measurement toolkit records latency, load, runtime, process, host, and database evidence without depending on application telemetry paths being tested.
- [Classify invariants by contract strength](0007-classify-invariants-by-contract-strength.md) - Kenshou labels every correctness invariant as a public contract or an implementation property and only contract failures block a release.
- [Define crashes as process or backend termination](0008-define-crashes-as-process-or-backend-termination.md) - Kenshou exercises crash recovery by terminating an operating-system process or PostgreSQL backend, never by throwing an in-process exception.
- [Judge heap leaks on live bytes after major collections](0009-judge-heap-leaks-on-live-bytes-after-major-collections.md) - Heap leak verdicts use forced-major-collection samples or the lower envelope of post-major live bytes, while native memory is reported separately.
- [Never mutate a sealed run during offline diagnosis](0010-never-mutate-a-sealed-run-during-offline-diagnosis.md) - Offline analysis reads immutable run evidence and writes requested derived output outside the sealed run directory.
- [Distinguish documented limitations from known defects](0011-distinguish-documented-limitations-from-known-defects.md) - Verification classifies unpromised behavior as implementation findings and links confirmed contract failures to reproducible owner-repository bug reports.
- [Keep verification records immutable and derive baselines](0012-keep-verification-records-immutable-and-derive-baselines.md) - Verification records are immutable events that link to digest-pinned data, while baselines are selected from confirmed compatible history.
- [Relax the evidence profile after records are committed](0013-relax-the-evidence-profile-after-records-are-committed.md) - Once an evidence record is committed, its type and field names stay stable and later profile revisions may only relax validation.
- [Pin cell payloads to verified cohort identities](0014-pin-cell-payloads-to-verified-cohort-identities.md) - A cell payload pins runtime packages from the cohort descriptor and is accepted only after its resolved Nix identity passes the cohort check.
- [Address cell runs by submission and nested run](0015-address-cell-runs-by-submission-and-nested-run.md) - A cell run is identified by its submission and nested run IDs, with cell evidence linked to sealed results and infrastructure failure governing the effective outcome.

