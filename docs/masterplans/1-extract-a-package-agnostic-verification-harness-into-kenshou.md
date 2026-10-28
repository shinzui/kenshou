---
id: 1
slug: extract-a-package-agnostic-verification-harness-into-kenshou
title: "Extract a package-agnostic verification harness into kenshou"
kind: master-plan
created_at: 2026-10-28T12:01:38Z
intention: "intention_01m6165ywkevaayscg2v99y0nt"
provenance:
  created_by:
    model: "claude-fable-5-1"
    harness: "claude-code"
    at: 2026-10-28T12:01:38Z
  revisions:
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-10-28T13:02:34Z
      mode: "implement"
      note: "Began implementation; EP-1 in progress"
---

# Extract a package-agnostic verification harness into kenshou

This MasterPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.


## Vision & Scope

`mori://shinzui/keiro-runtime-kenshou` is the verification suite for the Keiro runtime. About
27k of its 74k lines of Haskell are generic verification machinery: a scenario kernel that owns
versioned run, result, worker, and manifest documents; a correctness toolkit with fact ledgers,
invariants, fault injection, and process control; a measurement toolkit with load generators,
samplers, and paired comparison; a diagnostics toolkit for heap leaks and stalls; telemetry
arms with overhead reports; immutable evidence records; and leased remote verification cells.
None of that depends on the Keiro, Kiroku, PGMQ, Shibuya, or Kafka layer packages, but the
kernel and toolkits still *name* those layers in a closed `Layer` sum type, a closed schema
component type, Kafka-shaped environment fields, hard-coded oracles, lock labels, tuning
constants, and evidence URIs. That naming is what stops any other project from using the
harness.

After this initiative, this repository publishes that machinery as a set of Haskell packages
that any project can depend on and verify its own system with. A consuming project registers
one or more *layer bundles* (a layer identifier, scenarios, worker roles, schema migrations,
extra resources, oracles, diagnostic labels, and an evidence subject), assembles the operator
commands into its own executable, and gets the same `kenshou list`, `kenshou run`,
`kenshou plan`, `kenshou compare`, `kenshou diagnose`, `kenshou cell`, and evidence commands
that the Keiro suite uses today, writing the same versioned JSON documents. The repository
itself ships a synthetic reference bundle that links only the generic packages, so the boundary
is proven by a build rather than by review, and that bundle doubles as the worked example for
consumers.

The user-visible behaviors enabled are these. A maintainer can run `nix develop` here, build
`cabal build all`, and run the synthetic bundle's scenarios end to end with the standalone `kenshou`
executable, including change-aware planning, a leak verdict, a paired comparison, and a sealed
evidence record, with no Keiro cohort package in the build plan. A consumer can add the
published `kenshou-*` packages to a cabal project, register a suite in a few dozen lines, and
run it. The Keiro suite can later delete its local copies of the seven packages and the
generic CLI library and depend on the published release instead, keeping every existing
module import because the package and module names do not change.

The scope boundary is deliberate. In scope: importing the seven generic packages and the
generic part of `kenshou-cli` from `mori://shinzui/keiro-runtime-kenshou` at a pinned
revision, removing every layer-specific name from them, replacing closed types with
suite-registered data, keeping every published document shape readable, the synthetic suite
and a build-time coupling guard, the harness ADRs and terminology, an adoption guide, and the
first published release. Out of scope: the Keiro, Kiroku, PGMQ, Shibuya, and Kafka layer
packages, the Keiro-specific attestation modules under `Kenshou.Cli.Attest.Keiro*`, the
three runtime oracles in `Kenshou.Check.Oracle.{Keiro,Kiroku,Pgmq}`, the Keiro cohort
descriptors and `cohort/*.project` files, and the committed verification records. Those stay
in the consumer. The consumer's own adoption of the release is also out of scope here; by the
user's direction `keiro-runtime-kenshou` does not use kenshou until the first release is
published, and the adoption is a separate plan in that repository. EP-7 prepares the
checklist and the divergence audit that adoption will need.


## Decomposition Strategy

The decomposition follows the three steps of the improvement request that motivated the
extraction, `mori://shinzui/keiro-runtime-kenshou/okf/improvement-requests/concepts/IR-1`
(Extract a layer-agnostic verification harness from Kenshou): open the kernel, move layer
knowledge out of the toolkits, and prove the boundary. It adds the work that the request left
to "a later decision" and that the user has now decided: a separate repository with its own
build, documentation, and release.

The work streams are grouped by functional concern, not by package. Importing and building
standalone is one concern because a build that links nothing layer-specific is the first
observable result and every later stream needs it. The kernel's layer identity and schema
composition are one concern because `Kenshou.Core.Id.Layer` and `Kenshou.Core.Env`'s schema
components are the two closed types everything else pattern-matches on. The Kafka-specific
environment fields are a separate concern because they thread through the worker protocol
documents and the remote cell protocol, and the compatibility rule for those documents is the
hardest part of the whole initiative; keeping it in its own plan keeps the kernel plan
reviewable. The residual toolkit knowledge (oracles, lock labels, pool methodology, evidence
subjects and bundle URI, cell route rules) is one concern because every item is a small
relocation or a new configuration knob with the same shape. Proving the boundary is one
concern because the synthetic suite, the standalone executable, and the coupling guard are
one acceptance criterion. Documentation is one concern because the ADRs, terminology, and
adoption guide must agree with each other and with the final interfaces. The release is one
concern because versioning, publication, registration, and the consumer checklist are
decided together.

Alternatives considered. Refactoring in place inside `keiro-runtime-kenshou` and moving the
packages afterwards was rejected because the user directed that the harness be built here and
adopted by the Keiro suite only after publication; building here also makes the "no layer
package in the build plan" criterion trivially checkable from the first commit. Renaming the
packages or the `Kenshou.*` module namespace was rejected because the first consumer already
imports every module by its current name, and a rename would turn adoption into a large
mechanical diff with no verification value. One large "open the kernel" plan covering both the
layer identity and the environment resources was rejected because both change
`Kenshou.Core.Env` and the worker initialization document; splitting them and serializing
them keeps each change independently verifiable. Waiting for the Keiro suite's first master
plan to finish, as IR-1 proposed, was rejected by the user; the risk that the generic packages
keep changing in the consumer while this work proceeds is handled by pinning the import
revision in EP-1 and auditing divergence in EP-7.

No local ADR exists yet in this repository; `docs/adr/` is created by EP-6. The relevant
cross-repository decisions are in `mori://shinzui/keiro-runtime-kenshou`:

- `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-1` (Layer packages never
  import one another) fixes the dependency direction this initiative relies on: toolkits
  never depend on layer packages, so only naming has to be removed.
- `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-2` (Every result carries a
  resolved cohort identity) is generic and moves unchanged; the cohort descriptor files stay
  with the consumer.
- `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3` (Kenshou owns the runtime
  verification protocol) is the reason every document keeps its `kenshou.*/v1` identifier and
  why a changed shape needs a new version with a reader for the old one.
- `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-4` (Scenarios use provisioned
  databases and one ledger) names the Kiroku, Keiro, and PGMQ migration sets explicitly and
  must be superseded here by a decision that keeps the one-ledger rule with suite-supplied
  migration sets.
- `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-18`,
  `.../ADR-19`, and `.../ADR-20` constrain the evidence and cell surfaces: committed records
  are immutable, the evidence profile may only relax after records exist, and cell payloads
  stay pinned to verified cohort identities. EP-3 and EP-4 must not change what an existing
  record or payload means.
- `.../ADR-7`, `.../ADR-8`, `.../ADR-9`, `.../ADR-10`, and `.../ADR-11` record how
  measurements, invariants, crashes, heap leaks, and sealed runs are judged. They describe
  the toolkits and are carried into this repository by EP-6.


## Exec-Plan Registry

| # | Title | Path | Hard Deps | Soft Deps | Status |
|---|-------|------|-----------|-----------|--------|
| 1 | Import the harness packages from keiro-runtime-kenshou and build them standalone | docs/plans/1-import-the-harness-packages-from-keiro-runtime-kenshou-and-build-them-standalone.md | None | None | Complete |
| 2 | Open the kernel layer identity and schema composition to registered suites | docs/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites.md | EP-1 | None | In Progress |
| 3 | Replace Kafka-specific environment fields with suite-provisioned named resources | docs/plans/3-replace-kafka-specific-environment-fields-with-suite-provisioned-named-resources.md | EP-2 | None | Not Started |
| 4 | Move residual layer knowledge out of the toolkits and make evidence targets configuration | docs/plans/4-move-residual-layer-knowledge-out-of-the-toolkits-and-make-evidence-targets-configuration.md | EP-2 | EP-3 | Not Started |
| 5 | Prove the harness boundary with a synthetic layer and a coupling guard | docs/plans/5-prove-the-harness-boundary-with-a-synthetic-layer-and-a-coupling-guard.md | EP-2, EP-3, EP-4 | None | Not Started |
| 6 | Carry the harness decisions, vocabulary, and adoption guide into kenshou documentation | docs/plans/6-carry-the-harness-decisions-vocabulary-and-adoption-guide-into-kenshou-documentation.md | EP-1 | EP-2, EP-3, EP-4, EP-5 | Not Started |
| 7 | Publish the first kenshou release and prepare the consumer adoption path | docs/plans/7-publish-the-first-kenshou-release-and-prepare-the-consumer-adoption-path.md | EP-5, EP-6 | None | Not Started |

Status values: Not Started, In Progress, Complete, Cancelled.
Hard Deps and Soft Deps reference other rows by their # prefix (e.g., EP-1, EP-3).
A whole-child hard dependency requires that child to be Complete. If only a milestone's
accepted output is needed, name it explicitly (e.g., EP-1 M1) and explain it below.


## Dependency Graph

The initiative runs in four phases. Phase A is EP-1 alone. Phase B is EP-2, then EP-3, with
EP-4 able to start as soon as EP-2 is complete. Phase C is EP-5 and EP-6. Phase D is EP-7.

EP-1 has no dependencies. It copies the seven generic packages and the generic modules of
`kenshou-cli` from `mori://shinzui/keiro-runtime-kenshou` at commit
`a1648293443ad88ff1695ed800ff44c99993574e` (2026-10-12), together with the generic JSON
schemas and policy examples, and makes `cabal build all` and `cabal test all` pass in a
project whose build plan contains no `kenshou-{pgmq,kiroku,shibuya,kafka,keiro,runtime}`
package. At the end of EP-1 the kernel still links the `keiro-migrations`,
`kiroku-store-migrations`, and `pgmq-migration` libraries from Hackage; removing them is
EP-2's job. Every later plan edits files that EP-1 creates, so every later plan depends on it.

EP-2 depends on EP-1 because it edits the imported kernel. It replaces the closed
`Kenshou.Core.Id.Layer` with an open identifier that suites register, replaces
`Kenshou.Core.Env.SchemaComponent` and the hard-coded migration imports with suite-supplied
migration sets composed into one `pg-migrate` ledger, turns the "Keiro scenarios require
PostgreSQL 18" rule in `Kenshou.Core.Bundle` into registry data, and removes the three
migration dependencies from `kenshou-core.cabal`.

EP-3 depends on EP-2 as a whole, not only because it needs the open layer identifier but
because both plans change the `Kenshou.Core.Env.EnvRequirements` record and the
`kenshou.worker-init/v1` document. Serializing them means each plan's golden decode tests
are checked against one baseline. EP-3 replaces the `kafka` boolean and the `Maybe Value`
Kafka fields in `Kenshou.Core.Role.WorkerInit` and `Kenshou.Core.RunSpec.EnvironmentSpec`
with a map of named resources that suites provision locally and in cells, and generalizes
the broker-shaped cell documents in `Kenshou.Remote.Cell.Docs`.

EP-4 depends on EP-2 because the evidence layout and frontmatter render the layer string
through the identifier EP-2 introduces. It has a soft dependency on EP-3 because the PGMQ
partitioned-queue cell route rule becomes suite-contributed data in the same shape EP-3 uses
for resources; EP-4 may start before EP-3 finishes if it leaves the route rule for last.

EP-5 depends on EP-2, EP-3, and EP-4 because the synthetic suite must exercise every
extension point they define: an open layer identifier, a suite-supplied migration set, a
named extra resource with a local provisioner, a suite-supplied oracle and lock labels, and
a configured evidence subject. The coupling guard it adds would fail before those plans are
complete, so it cannot be the gate until they are.

EP-6 depends only on EP-1 for the repository to document, and softly on EP-2 to EP-5 because
the ADRs that supersede the consumer's ADR-4 and describe the suite registration contract
must state the final interfaces. The terminology and the carried-over ADRs can be written
while Phase B is in progress; the adoption guide is finished after EP-5.

EP-7 depends on EP-5 and EP-6 because a release must contain the proven boundary and the
documentation consumers need. It has no soft dependencies.

EP-2 and EP-6 can run in parallel after EP-1. EP-4 can run in parallel with EP-3 once EP-2
is complete, subject to the route-rule ordering above. EP-5 and the last part of EP-6 can
run in parallel.


## Integration Points

Layer bundle registration contract, owned by EP-2 and extended by EP-3 and EP-4, consumed by
EP-5 and documented by EP-6 and EP-7. The shared artifact is `Kenshou.Core.Bundle.LayerBundle`
and the registry built by `mkRegistry` in `kenshou-core`. Today a bundle carries a `Layer`,
scenarios, and roles. EP-2 replaces the constructor with
`mkBundle :: LayerId -> [Scenario] -> [WorkerRole] -> LayerBundle` and adds
`migrations :: [MigrationSet]` and `rules :: [ScenarioRule]`; EP-3 adds
`resources :: [ResourceProvider]` from the new module `Kenshou.Core.Resource`; EP-4 adds
`oracles`, `advisoryLabels`, `methodology`, `evidenceSubject`, and `routingRules`, with their
types in the new module `Kenshou.Core.Contribution`. Each plan adds its fields to `mkBundle`
with defaults so the self-test bundles in `kenshou-core`, `kenshou-check`, `kenshou-measure`,
`kenshou-diagnose`, `kenshou-telemetry`, and `kenshou-remote` keep compiling, and EP-5 fills
every field for the synthetic bundle. The kernel's own self-test migration set creates the
schema `kenshou_selftest` with the table `roundtrip`; EP-4's remote self-test and EP-5's
fixtures use it. The registration contract is the cross-plan decision most deserving of an
ADR, and EP-6 records it. The names above were fixed when the child plans were drafted; the
implemented code is authoritative if it differs, and the child plans say so.

Open layer identifier, owned by EP-2, consumed by EP-4 and EP-5. The shared artifact is
`Kenshou.Core.Id.LayerId`, a validated lowercase segment built with `mkLayerId`, together with
`selftestLayer`, `renderLayer`, and `parseLayer`, replacing the closed `Layer` type. The committed
evidence layout `runs/<layer>/YYYY/MM` in `Kenshou.Evidence.Bundle` and
`Kenshou.Evidence.Check`, the frontmatter `layer` field in `Kenshou.Evidence.Frontmatter`,
and the scenario identifier text `<layer>/<component>/<kind>/<name>` must render exactly the
same strings for the identifiers `selftest`, `pgmq`, `kiroku`, `shibuya`, `kafka`, `keiro`,
and `runtime` that existing consumer records already contain. EP-2 owns the type and proves
the rendering with a golden test over those seven strings; EP-4 consumes it in the evidence
modules without introducing a second parser.

Environment requirements and the worker protocol, owned by EP-2 for schemas and by EP-3 for
resources. The shared artifacts are `Kenshou.Core.Env.EnvRequirements`,
`Kenshou.Core.Role.WorkerInit` (document `kenshou.worker-init/v1`), and
`Kenshou.Core.RunSpec.EnvironmentSpec` (document `kenshou.run-spec/v1`). The rule from
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3` applies: a document keeps its
wire shape under its current identifier, or changes under a new versioned identifier with a
reader for the old one. The early representative check, owned by EP-3, is a golden decode test
that reads a consumer-produced `run-spec.json` and `worker-init` message containing the
current `kafka` fields and a synthetic document containing the new resource map, and
round-trips both. EP-3's types live in `Kenshou.Core.Resource` (`ResourceName`,
`ResourceProvider`, `ProvisionedResource`, `CellBinding`); readers map a legacy non-null
`kafka` field to the resource named `kafka`, writers stop emitting `kafka`, and the
comparison key keeps rendering that resource under its old top-level name so consumer
comparison keys do not change.

Cell protocol documents, owned by EP-3, consumed by EP-4 and EP-5. The shared artifacts are
the types in `Kenshou.Remote.Cell.Docs` (`CellImages.broker`, `CellBroker` with
`bootstrapServers`, and `BrokerReset` in `ResetBlock`) and the bind and reset steps in
`Kenshou.Remote.Cell.Exec` and `Kenshou.Remote.Cell.Prepare`. These documents also live in
`mori://shinzui/load-testing-infra`, which provisions the cells, so EP-3 must keep the
existing field names readable and add the generic resource block beside them rather than
replacing them. EP-4 moves the PGMQ route rule in `Kenshou.Remote.Cell.RouteRules` into
bundle-contributed data using the same resource names. EP-3 adds a `resources` block beside
`broker` and `reset.broker`, omitted when empty so the existing goldens stay byte-identical,
and a `Kenshou.Remote.Cell.Legacy` adapter that maps a cell broker to the `kafka` resource;
EP-4's routing rules use the `CellBinding.capability` vocabulary.

Evidence configuration, owned by EP-4, consumed by EP-5 and documented by EP-6. The shared
artifacts are `Kenshou.Evidence.Record.defaultSubject`, the bundle URI in
`Kenshou.Evidence.History`, and the `settei`-based configuration in
`Kenshou.Evidence.Config`. After EP-4 the subject comes from the registered bundle and the
bundle URI from configuration, with the consumer's current values documented as the example.
The keys are `evidence.default-subject` (`KENSHOU_EVIDENCE_SUBJECT`) and
`evidence.bundle-uri` (`KENSHOU_EVIDENCE_BUNDLE_URI`).

Generic CLI assembly, owned by EP-1, extended by EP-2, consumed by EP-5 and EP-7. The shared
artifact is the `kenshou-cli` library's entry point. Today `Kenshou.Cli.Main.main` reads a
fixed `Kenshou.Cli.Registry`. EP-1 turns the registry into a value the executable supplies:
`Kenshou.Cli.Registry.CliAssembly` with `bundles`, `commands`, and `topics`, the ready-made
`selfTestAssembly`, and `Kenshou.Cli.mainWith :: CliAssembly -> IO ()`. It keeps the generic
commands in the library, leaves `Kenshou.Cli.Attest.Keiro*` behind, and ships a `kenshou`
executable in `kenshou-synthetic` whose `app/Main.hs` is `main = mainWith selfTestAssembly`
until EP-5 adds the synthetic bundle. EP-2 extends the same record, as
`Kenshou.Core.Cli.Program` of which `CliAssembly` becomes a synonym, with `name`, `header`,
`componentGraph`, and `perf`, without changing `mainWith`. EP-7 documents the entry point as
the consumer's assembly instruction.

Verification gate, owned by EP-1, extended by EP-2, EP-3, EP-4, and EP-5. The shared artifact
is the `justfile` `verify` recipe and the CI workflow. EP-1 establishes build, test, format,
and schema checks plus `scripts/plan-check.sh` behind `just plan-check`, which fails when
`dist-newstyle/cache/plan.json` contains a consumer layer package. EP-2 creates
`scripts/coupling-allowlist.txt`, one exact `path:text` line per permitted grep match, and
audits `kenshou-core` with an inline grep; EP-3 and EP-4 extend that one list and widen the
audit to the toolkits under a `coupling-check` recipe; EP-5 replaces the inline grep with
`scripts/coupling-guard.sh`, which searches every generic package case-insensitively for
`keiro`, `kiroku`, `pgmq`, `shibuya`, and `kafka`, excludes only the verbatim consumer
records under `kenshou-evidence/test/fixtures/consumer-records/`, and proves it bites with an
injected name. EP-2 also removes the three migration libraries, so `plan-check` rejects them
from that point on.

Cross-repository adoption gate, owned by EP-7 and executed later in
`mori://shinzui/keiro-runtime-kenshou`. Acceptance criterion AC-4 of IR-1 (the Keiro suite
produces equivalent verdicts after the refactor) can only be checked where the layer packages
live. EP-7 produces the adoption checklist, the divergence audit comparing the generic
packages at the pinned import revision with the consumer's head, and the published release.
The consumer's adoption plan then deletes its local packages, relocates the three oracles and
the Keiro attestations into its layer packages, and runs the smoke and change suites against
the last pre-adoption baseline.


## Progress

Phase A is complete (EP-1, 2026-10-28): the seven generic packages and the generic
`kenshou-cli` library build and test here with no consumer layer package in Cabal's plan,
the `kenshou` executable in `kenshou-synthetic` runs the self-test scenarios, and
`just verify` passes locally. The CI run on a pushed commit is not yet observed.

Phase B is in progress. EP-2 M1 to M3 are accepted (open `LayerId`, suite-supplied
migration sets with no migration library in the plan, and `Program` carrying rules, the
component graph, and `PerfContracts`). EP-2 M4 is blocked on a scope decision about the
perf goldens (see Surprises & Discoveries). EP-3 waits on EP-2; the terminology and
carried-over ADR part of EP-6 is unblocked.

- [ ] Cross-repository adoption gate: the consumer's adoption plan exists in
  `mori://shinzui/keiro-runtime-kenshou` and the smoke suite passes against the published
  release with unchanged verdicts.


## Surprises & Discoveries

Document cross-plan insights, dependency changes, scope adjustments, or unexpected
interactions between child plans. Provide concise evidence. Friction recurring across child
plans belongs here by FRIC-N handle; single occurrences stay in the friction log (see the
exec-plan skill's FRICTION.md).

- This repository has its own cohort. Cohort identity is resolved on every run from
  `cohort/active.project`, `cohort/<name>.json`, and `plan.json`, so EP-1 created the
  `harness` cohort (`cohort/harness.{project,json}`); `cabal.project` imports
  `cohort/active.project`, and the index state and exact pins live in
  `cohort/harness.project`. Every later plan that edits constraints edits that file, not
  `cabal.project`: EP-2 removes the three migration pins there and from the cohort overlay
  in `flake.module.nix`. EP-2's "synthetic cohort descriptor" for the perf tests can be
  modeled on `cohort/harness.json`. EP-6 should record the harness cohort as an ADR.

- The imported tests read consumer files, now vendored in one bridge directory,
  `fixtures/consumer-baseline/` (verbatim at the pinned commit; see its README). The
  consumers of the bridge map onto later plans: EP-2 M4 replaces the cohort descriptors and
  performance catalog reads in `kenshou-core` and `kenshou-measure`, regenerates
  `perf-prepared.fixture.json`, and un-pends the two `kenshou-cli` file-backed perf session
  tests (`kenshou-cli/test/PerfSessionSpec.hs`), which need the prepared fixture's scenarios
  to be registered; EP-4 replaces the `policies/cell-routing.json` read in
  `kenshou-remote/test/PrepareSpec.hs`, the `cohort/released.json` reads in
  `kenshou-remote/test/PayloadSpec.hs`, and the verification bundle copied by the
  `kenshou-evidence` attestation tests and read by the `kenshou-cli` history test; EP-5
  deletes the directory and its coupling guard must fail if it reappears. The `kenshou perf
  plan` command resolves `cohortTemplate` and `policies/performance/catalog.v1.json`
  relative to the working directory, which EP-2 M3's `PerfContracts` work should take into
  account.

- The coupling grep of EP-2 M4 cannot be empty before EP-3: the Kafka environment fields in
  `kenshou-core/src` (`Env.hs`, `RunSpec.hs`, `Role.hs`, `Role/Spawn.hs`, `Compat.hs`) belong
  to EP-3. Those exact lines go in `scripts/coupling-allowlist.txt` until EP-3 deletes them,
  and EP-3's acceptance should include removing them from the allow-list.

- Consumer-compatibility proofs (the seven layer strings and a recorded comparison key) live
  in `kenshou-evidence/test/fixtures/consumer-records/` and the `consumer compatibility`
  group of `kenshou-evidence/test/Main.hs`, the only place EP-5's guard lets consumer
  values appear. EP-4 adds its verbatim consumer records to the same directory.

- The perf goldens (`kenshou-core/test/golden/perf-prepared.fixture.json` and its siblings)
  are captured output of a real `kenshou perf prepare` run and are shared by tests in
  `kenshou-core`, `kenshou-remote`, and `kenshou-cli`. They cannot be regenerated from
  synthetic inputs in this repository, which blocks EP-2 M4 as written and affects EP-5's
  plan to delete `fixtures/consumer-baseline/`.


## Decision Log

- Decision: Build the harness in this repository from a pinned copy of the generic packages,
  and have `keiro-runtime-kenshou` adopt it only after the first release is published.
  Rationale: The user directed that the Keiro suite not use kenshou until it is published.
  Building here makes "no layer package in the build plan" checkable from the first commit
  and keeps the consumer's verification work unblocked during the extraction.
  Date: 2026-10-28

- Decision: Keep the package names `kenshou-core`, `kenshou-check`, `kenshou-measure`,
  `kenshou-diagnose`, `kenshou-telemetry`, `kenshou-evidence`, `kenshou-remote`, and
  `kenshou-cli`, and the `Kenshou.*` module namespace, unchanged.
  Rationale: The first consumer imports every module by these names. Adoption becomes a
  deletion of local packages plus a dependency bump, with no import churn, and the published
  document identifiers `kenshou.*/v1` stay consistent with the code that owns them.
  Date: 2026-10-28

- Decision: Start the extraction now at consumer commit
  `a1648293443ad88ff1695ed800ff44c99993574e` instead of waiting for the consumer's first
  master plan to complete, as IR-1 had proposed.
  Rationale: The user chose to proceed. The cost is possible divergence of the generic
  packages in the consumer before adoption; EP-1 records the pinned revision and EP-7 audits
  the divergence, and the consumer should treat its generic packages as frozen until adoption.
  Date: 2026-10-28

- Decision: Serialize EP-3 after EP-2 rather than running them in parallel.
  Rationale: Both change `Kenshou.Core.Env.EnvRequirements` and the `kenshou.worker-init/v1`
  document; parallel edits would need a reconciliation step with no verification value.
  Date: 2026-10-28

- Decision: Prove the boundary with a synthetic reference suite in its own package,
  `kenshou-synthetic`, and a build-time coupling guard, rather than by review of the generic
  packages.
  Rationale: IR-1's acceptance criteria AC-1, AC-2, and AC-5 are all checkable by a build
  that links nothing layer-specific. The synthetic suite is also the worked example consumers
  need, so one artifact serves both purposes.
  Date: 2026-10-28

- Decision: The registration unit is called a *layer bundle*, after the type `LayerBundle`;
  *layer suite* is discouraged wording because a *suite* already names a run selection such
  as `suites/smoke.json`.
  Rationale: EP-6 found the collision while drafting the terminology bundle. One word per
  concept keeps the adoption guide, the ADRs, and the CLI help consistent.
  Date: 2026-10-28


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original vision. Before marking the MasterPlan complete,
distill durable project context from this MasterPlan and its child ExecPlans into
docs/adr/. Keep task-local execution and coordination details here.

(To be filled during and after implementation.)
