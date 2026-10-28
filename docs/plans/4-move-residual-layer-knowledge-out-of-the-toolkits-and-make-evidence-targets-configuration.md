---
id: 4
slug: move-residual-layer-knowledge-out-of-the-toolkits-and-make-evidence-targets-configuration
title: "Move residual layer knowledge out of the toolkits and make evidence targets configuration"
kind: exec-plan
created_at: 2026-10-28T12:02:04Z
intention: "intention_01m6165ywkevaayscg2v99y0nt"
master_plan: "docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md"
provenance:
  created_by:
    model: "claude-fable-5-1"
    harness: "claude-code"
    at: 2026-10-28T12:02:04Z
  revisions:
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-10-28T14:38:30Z
      mode: "update"
      note: "Context updated with implementation state left by EP-1 and EP-2"
---

# Move residual layer knowledge out of the toolkits and make evidence targets configuration

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

After this plan, none of the six toolkit packages (`kenshou-check`, `kenshou-measure`,
`kenshou-diagnose`, `kenshou-telemetry`, `kenshou-evidence`, `kenshou-remote`) knows the name
of any runtime layer that the Keiro verification suite happens to test. Today the correctness
toolkit ships SQL oracles for Keiro, Kiroku, and PGMQ tables; the measurement toolkit
recommends a Kiroku connection-pool size; the diagnostics toolkit knows the advisory-lock
labels of Keiro workflows, Kiroku consumer groups, and PGMQ queues; the evidence toolkit maps
each layer to a hard-coded Mori project URI and renders history documents against one
hard-coded evidence bundle; and the remote toolkit carries a PGMQ-specific cell routing rule
and a self-test that requires the Kiroku schema. A consumer that is not the Keiro suite gets
all of that for free and cannot use any of it.

When the plan is complete, a suite contributes those things through its registered bundle:
oracle SQL it wants the harness to run, advisory-lock labels it wants stall diagnoses to name,
its pool-size methodology, its cell routing rules, and the Mori URI that its evidence records
should name as their subject. The evidence bundle URI that `kenshou history` prints comes from
configuration. Every committed verification record in the consumer still validates, still
lives at the same path, and still re-renders the same frontmatter, which is what keeps the
consumer's immutable evidence corpus readable after it adopts this release.

You can see it working in three ways. A grep for the five layer names across the six
toolkits returns nothing outside one directory of verbatim consumer records kept as
compatibility fixtures. The evidence tests parse two real records copied from the consumer
and reproduce their committed paths `runs/selftest/2026/09/<id>.md` and
`runs/keiro/2026/10/<id>.md`. And the remote self-test scenario
`selftest/remote/correctness/cell-environment` runs against the harness's own self-test
schema instead of `kiroku.events`.


## Progress

- [x] M1: Oracle SQL, advisory-lock labels, and pool methodology are bundle contributions.
  `kenshou-check`, `kenshou-measure`, and `kenshou-diagnose` build and pass their test
  suites with the three oracle modules deleted, the five layer lock-label constructors
  deleted, and the Kiroku pool constants replaced by a `PoolMethodology` record; the grep
  described in Validation returns nothing for those three packages.
  (2026-10-28; `Kenshou.Core.Contribution` holds the types; the three suites pass with new
  `registered oracles`, `pool methodology`, and advisory-lock cases; the grep returns nothing
  for the three packages, and `just coupling-check` now audits them for every layer name.)
- [x] M2: Evidence subject and history bundle URI are configuration. `kenshou record`
  resolves the subject from the registry or `evidence.default-subject`, `kenshou history`
  prints the `evidence.bundle-uri` value, and the new consumer-record fixtures (two verbatim
  records plus the seven layer strings) parse, re-render byte-identically, and reproduce
  their committed paths.
  (2026-10-28; `LayerBundle.evidenceSubject`, `registrySubjects`, and the keys
  `evidence.default-subject` / `evidence.bundle-uri` exist; `kenshou history` exits 2 without
  a bundle URI; the two records in `kenshou-evidence/test/fixtures/consumer-records/` re-render
  byte-identically without `verified` and reproduce the paths in `record-paths.json`; the
  layer strings were already there from EP-2 as `layer-strings.json`; all suites and schemas
  pass.)
- [ ] M3: The remote self-test depends only on the self-test schema, every layer-named
  fixture or test string in `kenshou-core/test`, `kenshou-evidence/test`, and
  `kenshou-remote/test` uses the synthetic layer name, and the PGMQ routing rule has left
  `Kenshou.Remote.Cell.RouteRules` for bundle data (this last step waits for EP-3).
- [ ] M4: The audit grep over the six toolkits returns only the allow-listed directory and
  lines, and the `justfile` `coupling-check` recipe that runs it is part of `just verify`.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence. Friction with the tools, documents, and processes
used to do the work belongs in the friction log (see FRICTION.md); cite an entry's FRIC-N
handle here only when it also changed the plan.

(None yet.)


## Decision Log

- Decision: Delete `Kenshou.Check.Oracle.Keiro`, `Kenshou.Check.Oracle.Kiroku`, and
  `Kenshou.Check.Oracle.Pgmq` outright rather than moving them anywhere in this repository.
  Rationale: No module in the consumer imports them; every layer package already defines its
  own oracle queries (for example `kenshou-kiroku/src/Kenshou/Suite/Kiroku/Fixture/Oracle.hs`
  in the consumer). The SQL text is preserved in the consumer's git history and EP-7's
  adoption checklist tells the consumer to recreate them inside its layer packages if it
  still wants them.
  Date: 2026-10-28

- Decision: Suite-contributed data types (`OracleSpec`, `AdvisoryLabel`, `AdvisoryKeySpec`,
  `PoolMethodology`, `RoutingRule`, `RuleCondition`) live in one new kernel module,
  `Kenshou.Core.Contribution`, and the toolkits re-export them from their current modules.
  Rationale: `LayerBundle` is defined in `kenshou-core`, which cannot import the toolkits, so
  any value a bundle carries must have a kernel type. Re-exporting from
  `Kenshou.Diagnose.Postgres` and `Kenshou.Remote.Cell.RouteRules` keeps the consumer's
  imports compiling at adoption.
  Date: 2026-10-28

- Decision: The evidence subject is resolved in this order: the `--subject` flag, then the
  registered bundle's `evidenceSubject` for the run's layer, then the configuration key
  `evidence.default-subject`, and otherwise `kenshou record` exits with code 2. The history
  bundle URI has no built-in default; `evidence.bundle-uri` (or `--bundle-uri`) is required
  for `kenshou history`.
  Rationale: A generic harness cannot know a consumer's Mori project. Failing loudly is
  better than recording evidence under a wrong subject, which would be immutable afterwards
  under `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-18`.
  Date: 2026-10-28

- Decision: Two real consumer records and the seven consumer layer strings are kept
  verbatim as fixtures under `kenshou-evidence/test/fixtures/consumer-records/`, and that
  directory is the only allow-listed location in the coupling audit.
  Rationale: The acceptance of this plan is that existing records still parse and re-render.
  Synthetic fixtures cannot prove that; verbatim ones can, and confining them to one
  directory keeps the audit mechanical.
  Date: 2026-10-28


- Decision: The verbatim records' committed paths live as data in
  `kenshou-evidence/test/fixtures/consumer-records/record-paths.json`, and the record tests
  sit in the existing `consumer compatibility` group of `kenshou-evidence/test/Main.hs`
  rather than a new `ConsumerRecordsSpec` module; the layer strings file is EP-2's
  `layer-strings.json`. Tests that build records pass `subjects` for the self-test layer as
  `mori://shinzui/kenshou`, and the history test passes `--bundle-uri`.
  Rationale: A committed path names the consumer's layer, so it belongs with the consumer's
  data, not in test code the coupling check reads. The bridged bundle's profile closes only
  the `layer` and `tier` vocabularies, so a new subject URI validates.
  Date: 2026-10-28

## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Cite the friction entries recorded under
this plan by handle with their triage outcome. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

This repository, `kenshou`, is a Haskell cabal workspace at `/Users/shinzui/Keikaku/bokuno/kenshou`.
Enter the development shell with `nix develop` at the repository root; it provides GHC 9.12.4,
`cabal`, PostgreSQL 18, `psql`, and `just`. The packages were copied by EP-1
(`docs/plans/1-import-the-harness-packages-from-keiro-runtime-kenshou-and-build-them-standalone.md`)
from the Keiro verification suite `mori://shinzui/keiro-runtime-kenshou` at commit
`a1648293443ad88ff1695ed800ff44c99993574e`, keeping the same package directories and module
names. Where this plan names a path, the same path exists in that consumer checkout at
`/Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou`, which is useful for reading the
original code and the committed evidence records.

Some vocabulary, defined once here. A *layer* is a unit of the system under test that one
suite verifies; in the consumer the layers are `pgmq`, `kiroku`, `shibuya`, `kafka`, `keiro`,
`runtime`, and the harness's own `selftest`. A *bundle* is the value a suite registers,
`Kenshou.Core.Bundle.LayerBundle` in `kenshou-core/src/Kenshou/Core/Bundle.hs`; it names a
layer and lists scenarios and worker roles, and after EP-2 it also carries the open layer
identifier and the suite's schema migrations. The *registry* (`Kenshou.Core.Bundle.Registry`)
is the validated list of bundles that the `kenshou` executable is linked with; every command
receives it through `Kenshou.Core.Cli.CliEnv.registry`
(`kenshou-core/src/Kenshou/Core/Cli.hs`). A *scenario identifier* has the text form
`<layer>/<component>/<kind>/<name>`; its `layer` segment is what the evidence toolkit renders
into paths and frontmatter. An *oracle* is a SQL query the correctness toolkit runs with
`psql` against the run's database and saves under `verdicts/oracle/<name>.json`
(`kenshou-check/src/Kenshou/Check/Oracle.hs`). An *advisory label* is a human-readable name
plus the recipe for reconstructing a PostgreSQL advisory-lock key, so a stall diagnosis can
say which lock a backend is waiting on (`AdvisoryLabel` and `AdvisoryKeySpec` in
`kenshou-diagnose/src/Kenshou/Diagnose/Postgres.hs`). An *evidence record* is a Markdown
file with YAML frontmatter in an OKF bundle, written by `kenshou record`; its shape is in
`kenshou-evidence/src/Kenshou/Evidence/Frontmatter.hs`, its path is computed by
`eventRecordPath` in `kenshou-evidence/src/Kenshou/Evidence/Bundle.hs` as
`runs/<layer>/<YYYY>/<MM>/<run-id>.md`, and `kenshou evidence check`
(`kenshou-evidence/src/Kenshou/Evidence/Check.hs`, function `pathChecks` near line 345)
re-derives that path from the frontmatter and reports `path-consistency` when it differs. A
*cell routing rule* says that a run whose spec matches a condition needs a named cell
capability, such as `postgres.pg_partman`
(`kenshou-remote/src/Kenshou/Remote/Cell/RouteRules.hs`).

State of the kernel when this plan starts. EP-2
(`docs/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites.md`)
must be complete: `Kenshou.Core.Id` exposes an open layer identifier (this plan calls it
`LayerId`; use whatever name EP-2 chose) with `renderLayer` and `parseLayer` that accept any
lowercase segment, `LayerBundle` carries that identifier and a suite-supplied migration set,
and the kernel's own self-test bundle owns a migration set that creates a schema the harness
controls (EP-2 names the schema `kenshou_selftest` and its table `roundtrip`; adapt
the SQL below to EP-2's actual names). EP-3
(`docs/plans/3-replace-kafka-specific-environment-fields-with-suite-provisioned-named-resources.md`)
may still be in progress; only the last step of M3 and the audit in M4 need it finished,
because EP-3 owns every `kafka` occurrence in `kenshou-check/src/Kenshou/Check/Process.hs`,
`kenshou-remote/src/Kenshou/Remote/Cell/{Docs,Exec,Prepare}.hs`,
`kenshou-remote/test/ExecSpec.hs`, and the `remote.kafka-bootstrap` knob in
`kenshou-remote/src/Kenshou/Remote/Selftest.hs`. Do not edit those for Kafka reasons here.

What the audit found. A case-insensitive search for `keiro`, `kiroku`, `pgmq`, `shibuya`,
and `kafka` over the six toolkits' `src`, `test`, and cabal files at the import revision
returns the following, grouped by what this plan does with each. In `kenshou-check`: the
three modules `src/Kenshou/Check/Oracle/Keiro.hs`, `Kiroku.hs`, and `Pgmq.hs`, their three
`exposed-modules` lines in `kenshou-check.cabal`, and one sentence in `kenshou-check/README.md`
("The SQL oracle catalogue reconciles ledger evidence with durable Kiroku, Keiro, and PGMQ
tables"); nothing in the repository imports the three modules. In `kenshou-measure`: only
`src/Kenshou/Measure/Methodology.hs`, whose `recommendedKirokuPoolSize` and `kirokuPoolRange`
have no importers. In `kenshou-diagnose`: only `src/Kenshou/Diagnose/Postgres.hs`, whose five
constructors `keiroWorkflowStepLock`, `keiroWorkflowLifecycleLock`,
`kirokuConsumerGroupGuard`, `pgmqQueueLock`, and `pgmqFifoKeyLock` have no callers; the type
`AdvisoryLabel` is consumed only by the `advisoryLabels` field of `WatchdogConfig` in
`src/Kenshou/Diagnose/Stall.hs`, which defaults to the empty list. In `kenshou-telemetry`:
nothing. In `kenshou-evidence`: `defaultSubject` at the end of `src/Kenshou/Evidence/Record.hs`
mapping the seven layers to Mori URIs; the literal
`mori://shinzui/keiro-runtime-kenshou/okf/verification` in the `ToJSON` instances of
`src/Kenshou/Evidence/History.hs` (the document's `bundle` field and each entry's `ref`);
and in `test/Main.hs` a `kafka/pipeline/soak/...` scenario identifier with a
`measurements.kafka` summary key, two `mori://shinzui/shibuya-kafka-adapter/...` known-defect
URIs, and `mori://shinzui/keiro-runtime-kenshou` as a subject and as a cohort component URI.
In `kenshou-remote`: the `SchemaKiroku` requirement and the `SELECT count(*) FROM
kiroku.events` freshness probe in `src/Kenshou/Remote/Selftest.hs`; the PGMQ rule in
`defaultRoutingRules` in `src/Kenshou/Remote/Cell/RouteRules.hs`; the profile name
`shibuya-core-quick` in `test/PerfRunnerSpec.hs`; the `pgmq.queue-kind` knob and the test
"loads the seeded partitioned-queue routing rule" in `test/PrepareSpec.hs`, which reads
`../policies/cell-routing.json`; a `kiroku-store` component name in `test/ParitySpec.hs`;
and `test/golden/perf-session.fixture.json`, which names `shibuya-core-quick`,
`shibuya-pgmq-quick`, `shibuya/...` scenario identifiers, `shibuya.*` and `pgmq-adapter.*`
knobs, and the project `mori://shinzui/shibuya`. Outside the six toolkits but inside this
plan's fixture scope, `kenshou-core/test` carries layer names as strings in
`test/golden/perf-*.json`, `test/golden/run-spec.effective.json`,
`test/fixtures/plan/catalog-planned.json`, `test/fixtures/plan/plan-missing-edge.json`,
`test/Kenshou/PerfSpec.hs`, and `test/Kenshou/PerfPreparedSpec.hs` (which reads the
consumer's `cohort/shibuya-current.json`). The embedded component graph
`kenshou-core/data/components.json` and the `SchemaComponent` tests in
`kenshou-core/test/Main.hs` are kernel data and belong to EP-2, not to this plan.

Two JSON schemas under `schemas/` are affected: `schemas/evidence-history-v1.schema.json`
pins `bundle` to the consumer's URI with a `const` and `ref` to a consumer-specific pattern,
and `schemas/kenshou.perf-session.v1.schema.json` is validated against the remote perf
session fixture by `just schemas-check`.

No local ADR exists yet; `docs/adr/` is created by EP-6
(`docs/plans/6-carry-the-harness-decisions-vocabulary-and-adoption-guide-into-kenshou-documentation.md`).
The cross-repository decisions that bind this plan are in the consumer.
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-18` (Keep verification records
immutable and derive baselines) says committed records are never rewritten and link their
data by digest, so this plan may change how a record's subject is chosen but must not change
what an existing record says or where it lives.
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-19` (Relax the evidence profile
after records are committed) says field names and the `Verification Run` type name are
frozen and later revisions may only relax validation; the history schema change below is a
relaxation (a `const` becomes a pattern), which is allowed, and no frontmatter field is
renamed. `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3` (Kenshou owns the
runtime verification protocol) is why `kenshou.evidence-history/v1` keeps its identifier
when its schema relaxes and why no new document shape is introduced here.
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-1` (Layer packages never import
one another) is the reason the oracles can simply leave: shared helpers are promoted to the
kernel or a toolkit, never imported across layers, and these were never shared.


Implementation state left by EP-1 and EP-2 (added 2026-10-28 while implementing them). Some
imported tests read consumer files from `fixtures/consumer-baseline/` (see its README):
`kenshou-remote/test/PrepareSpec.hs` reads `policies/cell-routing.json`,
`kenshou-remote/test/PayloadSpec.hs` reads `cohort/released.json` through
`PublishOptions "../fixtures/consumer-baseline" "released" …`, and the `kenshou-evidence`
attestation tests and the `kenshou-cli` history test copy or read the pruned verification
bundle under `docs/verification/`. This plan replaces the routing-rule read and the
evidence-bundle reads with synthetic or configured data. `kenshou-evidence/test/fixtures/
consumer-records/` already exists and holds `layer-strings.json` and
`run-result.hydration-cost.json` for the `consumer compatibility` group; add this plan's
verbatim consumer records beside them. `defaultSubject` in `Kenshou.Evidence.Record` is
already a lookup over rendered layer text, waiting for this plan to replace it.

## Plan of Work

Milestone 1 makes oracle SQL, advisory-lock labels, and pool methodology things a suite
contributes. Start by creating `kenshou-core/src/Kenshou/Core/Contribution.hs`, listed in
`kenshou-core.cabal` under `exposed-modules`, holding the data a bundle can carry that the
toolkits consume: `data OracleSpec = OracleSpec {name :: Text, sql :: Text}`;
`data AdvisoryKeySpec = HashTextExtended Text | HashText Text | LiteralKey Int64` and
`data AdvisoryLabel = AdvisoryLabel {label :: Text, key :: AdvisoryKeySpec}` moved verbatim
from `Kenshou.Diagnose.Postgres`; and
`data PoolMethodology = PoolMethodology {recommendedPoolSize :: Int, poolRange :: (Int, Int)}`.
Give each `Eq` and `Show` and hand-written `ToJSON`/`FromJSON` instances with the field
names shown, because EP-5's synthetic suite and EP-6's adoption guide will show them as
JSON. Extend `LayerBundle` in `kenshou-core/src/Kenshou/Core/Bundle.hs` with
`oracles :: [OracleSpec]`, `advisoryLabels :: [AdvisoryLabel]`, and
`methodology :: Maybe PoolMethodology`, defaulting to empty and `Nothing` in whatever
constructor or defaults value EP-2 introduced so that the six self-test bundles
(`Kenshou.Core.Selftest`, `Kenshou.Measure.Selftest`, `Kenshou.Check.Selftest`,
`Kenshou.Diagnose.SelfTest`, `Kenshou.Telemetry.SelfTest`, `Kenshou.Remote.Selftest`) keep
compiling without edits. Add `lookupBundle :: Registry -> LayerId -> Maybe LayerBundle` next
to `lookupScenario`, and have `mkRegistry` reject duplicate oracle names within one bundle
with a `RegistryError`, in the style of the existing `duplicateErrors`.

Then, in `kenshou-check`, delete `src/Kenshou/Check/Oracle/Keiro.hs`, `Kiroku.hs`, and
`Pgmq.hs` and their three lines in `kenshou-check.cabal`. In `src/Kenshou/Check/Oracle.hs`
add `fromSpec :: OracleSpec -> (Text -> Either Text value) -> OracleQuery value` and
`registeredOracle :: Registry -> LayerId -> Text -> Maybe OracleSpec` (a lookup through
`lookupBundle`), and keep `runOracle`, `sampleOracle`, `reconcile`, and `awaitQuiescence`
unchanged. Replace the Kiroku sentence in `kenshou-check/README.md` with one that says
suites register their SQL oracles on their bundle and the toolkit runs and records them
without linking any runtime library. In `kenshou-measure/src/Kenshou/Measure/Methodology.hs`
remove `recommendedKirokuPoolSize` and `kirokuPoolRange`, re-export `PoolMethodology (..)`
from the kernel, add `poolMethodologyFor :: Registry -> LayerId -> Maybe PoolMethodology`,
and keep `minimumTrials` and `defaultTrials`. In `kenshou-diagnose/src/Kenshou/Diagnose/Postgres.hs`
delete the five layer constructors, re-export `AdvisoryLabel (..)` and `AdvisoryKeySpec (..)`
from the kernel so `Kenshou.Diagnose.Stall`, `Kenshou.Diagnose.Stall.Types`, and
`kenshou-cli/src/Kenshou/Cli/Diagnose.hs` (which imports the module unqualified) keep
compiling, keep `pgMigrateLedgerLock` because `pg-migrate` is the harness's own dependency,
and keep `reconstructAdvisoryKey`. In `kenshou-diagnose/src/Kenshou/Diagnose/Stall.hs` add
`watchdogConfigFor :: LayerBundle -> WatchdogConfig`, which is `defaultWatchdogConfig` with
`advisoryLabels` set to the bundle's list plus `pgMigrateLedgerLock`, so a scenario that
wants its suite's labels named in a stall capture has a one-line way to get them. Add unit
tests: `kenshou-check/test` round-trips an `OracleSpec` through `fromSpec` and checks that
`registeredOracle` finds a spec on a bundle built in the test and `Nothing` on an unknown
name; `kenshou-measure/test` checks `poolMethodologyFor` on a bundle with and without a
methodology; `kenshou-diagnose/test/Kenshou/Diagnose/StallSpec.hs` checks that
`watchdogConfigFor` carries the bundle's labels and the ledger lock. At the end of this
milestone the grep in Validation returns nothing for `kenshou-check`, `kenshou-measure`, and
`kenshou-diagnose` except the single `kafka` field access in `Kenshou.Check.Process`, which is
EP-3's.

Milestone 2 makes the evidence subject and the history bundle URI configuration. Add
`evidenceSubject :: Maybe Text` to `LayerBundle` (a canonical `mori://` URI; `mkRegistry`
rejects a value that does not start with `mori://`), and `registrySubjects :: Registry ->
Map LayerId Text` in `Kenshou.Core.Bundle`. In `kenshou-evidence/src/Kenshou/Evidence/Config.hs`
add two optional keys with environment bindings in the existing style:
`evidence.default-subject` bound to `KENSHOU_EVIDENCE_SUBJECT`, and `evidence.bundle-uri`
bound to `KENSHOU_EVIDENCE_BUNDLE_URI`; add them to `EvidenceDefaults` as `defaultSubject ::
Maybe Text` and `bundleUri :: Maybe Text`. In `kenshou-evidence/src/Kenshou/Evidence/Record.hs`
delete `defaultSubject`, add `subjects :: Map LayerId Text` and `fallbackSubject :: Maybe Text`
to both `RecordOptions` and `RecordInput`, and resolve the subject in `buildRunRecord` and
`comparisonFields` as the override, else the map entry for the scenario's layer, else the
fallback, else `Left (RecordError "no evidence subject for layer <layer>; pass --subject or set
evidence.default-subject")`. The existing `mori://` prefix check stays. In
`kenshou-evidence/src/Kenshou/Evidence/Cli.hs` the record handler currently ignores its
`CliEnv` argument; use `env.registry` to fill `subjects` with `registrySubjects` and
`defaults.defaultSubject` to fill the fallback. In `kenshou-evidence/src/Kenshou/Evidence/History.hs`
add `bundleUri :: Text` to `HistoryDocument`, render `"bundle" .= document.bundleUri` and each
entry's `ref` as `document.bundleUri <> "/concepts/" <> entry.concept` (move the `ref` into
the document's entry rendering, since the entry instance no longer knows the URI), and take
the URI as a new argument of `history`. In `kenshou-evidence/src/Kenshou/Evidence/HistoryCli.hs`
add `--bundle-uri` as a named option over the new key, and exit 2 with "evidence.bundle-uri or
--bundle-uri is required" when neither is set. Relax `schemas/evidence-history-v1.schema.json`
so `bundle` is `{"type": "string", "pattern": "^mori://"}` and `ref` is
`{"type": "string", "pattern": "^mori://.+/concepts/"}`; the schema identifier stays
`kenshou.evidence-history/v1`.

Still in Milestone 2, create `kenshou-evidence/test/fixtures/consumer-records/` with three
files copied verbatim from the consumer checkout:
`docs/verification/runs/selftest/2026/09/01a0e106-c828-71ea-96f5-5a693335454f.md`
(a run record), `docs/verification/runs/keiro/2026/10/01a0f8be-8279-7667-ad13-3757c626211f.md`
(a comparison record), and a new `layers.json` containing the array
`["selftest","pgmq","kiroku","shibuya","kafka","keiro","runtime"]`. Add
`kenshou-evidence/test/ConsumerRecordsSpec.hs` (listed in the test suite's `other-modules`
and the fixtures in `extra-source-files`) that for each record parses the file with
`Okf.Document.parseDocument`, decodes it with `recordFromDocument` or
`comparisonFromDocument`, checks that `runRecordPath` or `comparisonRecordPath` returns
exactly `runs/selftest/2026/09/01a0e106-c828-71ea-96f5-5a693335454f.md` and
`runs/keiro/2026/10/01a0f8be-8279-7667-ad13-3757c626211f.md`, and checks that
`recordToDocument` or `comparisonToDocument` followed by `serializeDocument` reproduces the
file bytes after the `verified` field is removed from the original with
`Okf.Document.removeField` (the attester adds `verified` after recording, so it is not part
of what `kenshou record` writes). For `layers.json` the test checks that `parseLayer` accepts
each string and `renderLayer` returns it unchanged. Also rewrite the layer-named strings in
`kenshou-evidence/test/Main.hs`: the soak scenario becomes
`synthetic/pipeline/soak/consumer-memory-and-fd-stability-reduced` with a
`measurements.synthetic` key, the known-defect URIs become
`mori://example/synthetic/okf/bug-reports/concepts/BUG-4` and `BUG-6`, and the subject and
cohort component URIs become `mori://shinzui/kenshou`. Tests that call `buildRunRecord`
directly now pass `subjects = Map.singleton selftestLayer "mori://shinzui/kenshou"` or a
fallback, and one new test asserts the exit-2 error text when no subject can be resolved.

Milestone 3 removes layer schemas from the remote self-test, renames the remaining fixtures,
and, last, turns the routing rule into bundle data. In
`kenshou-remote/src/Kenshou/Remote/Selftest.hs` replace the Kiroku schema requirement with
the kernel self-test migration set (the value EP-2 exported for `Kenshou.Core.Selftest`; this
plan assumes it creates `kenshou_selftest.roundtrip`) and replace the freshness probe with
`SELECT count(*) FROM kenshou_selftest.roundtrip`. Leave the `remote.kafka-bootstrap` knob and
`reachableKafka` alone unless EP-3 has already replaced them with a generic resource endpoint
probe, in which case use EP-3's knob name. Rename the fixture strings: in
`kenshou-remote/test/golden/perf-session.fixture.json` replace `shibuya-core-quick` with
`synthetic-core-quick`, `shibuya-pgmq-quick` with `synthetic-queue-quick`,
`shibuya/core-ordering/benchmark/concurrency-sweep` with
`synthetic/ordering/benchmark/concurrency-sweep`,
`shibuya/pgmq-adapter/benchmark/end-to-end-throughput-latency` with
`synthetic/queue/benchmark/end-to-end-throughput-latency`, every `shibuya.` and
`pgmq-adapter.` knob prefix with `synthetic.`, the component `shibuya` with `synthetic`, and
`mori://shinzui/shibuya` with `mori://shinzui/kenshou`; make the same renames in
`kenshou-remote/test/PerfRunnerSpec.hs`, change `kiroku-store` to `synthetic-store` in
`kenshou-remote/test/ParitySpec.hs`, and apply the same pattern (layer segment `synthetic`,
component names `queue`, `store`, `ordering`, knob prefix `synthetic.`) to the strings in
`kenshou-core/test/golden/perf-*.json`, `kenshou-core/test/golden/run-spec.effective.json`,
`kenshou-core/test/fixtures/plan/catalog-planned.json`,
`kenshou-core/test/fixtures/plan/plan-missing-edge.json`, `kenshou-core/test/Kenshou/PerfSpec.hs`,
and `kenshou-core/test/Kenshou/PerfPreparedSpec.hs`. The last of these reads
`../cohort/shibuya-current.json`; EP-1 decided what happened to that test when the cohort
directory did not come along, so follow its Decision Log, and if the test survived on a copied
descriptor, rename the descriptor's component identifiers to the synthetic names too. Run
`just schemas-check` after each fixture edit because the goldens are validated against
`schemas/`.

For the routing rule, wait until EP-3 is marked Complete in the MasterPlan registry. Then
move `RoutingRule` and `RuleCondition` with their JSON instances from
`kenshou-remote/src/Kenshou/Remote/Cell/RouteRules.hs` into `Kenshou.Core.Contribution`
(they depend only on `Kenshou.Core.Knob` and `Kenshou.Plan.Selector`, both kernel modules),
re-export them from `RouteRules`, add `routingRules :: [RoutingRule]` to `LayerBundle`
defaulting to the empty list, add `registryRoutingRules :: Registry -> [RoutingRule]` that
concatenates every bundle's rules in registry order, and reduce `defaultRoutingRules` to the
empty list with a deprecation comment pointing at the registry function. In
`kenshou-cli/src/Kenshou/Cli/Command/Cell.hs` the two `maybe (pure (Right
defaultRoutingRules)) readJsonDocument rulesFile` sites and the `defaultRoutingRules` argument
in `kenshou-cli/src/Kenshou/Cli/Command/Perf/Session.hs` become
`registryRoutingRules cli.registry` (or `environment.registry` for the perf session); a
`--rules FILE` still replaces the registry rules entirely, as it does today. Replace the test
"loads the seeded partitioned-queue routing rule" in `kenshou-remote/test/PrepareSpec.hs` with
one that builds a bundle carrying a rule on knob `synthetic.queue-kind` equal to
`partitioned` requiring `postgres.pg_partman`, registers it, and checks that
`matchingRules (registryRoutingRules registry) spec` returns it for a spec with that knob and
nothing otherwise; the `postgres.pg_partman` capability name is a cell capability, not a layer
name, and may stay. Delete `policies/cell-routing.json` from this repository (it is the
consumer's data; EP-7 lists it for the consumer to keep) and remove it from the `justfile` if
EP-1 referenced it. The consumer's Keiro suite will carry the PGMQ rule on its PGMQ bundle
after adoption, which is one of the relocations EP-7 enumerates.

Milestone 4 adds the audit as a repository gate. Add a `coupling-check` recipe to the
`justfile` with the exact command in Concrete Steps, include it in the `verify` recipe's
dependency list, and run `just verify`. The recipe is the seed that EP-5 extends into the
full coupling guard (EP-5 adds the build with only the synthetic suite and may widen the
grep to `kenshou-core` and `kenshou-cli` and replaces the recipe body with
`scripts/coupling-guard.sh`); keep the allow-list in `scripts/coupling-allowlist.txt`, the
line-level file EP-2 created, so EP-5 does not have to reconcile two lists. Record the final result of the grep in this plan's Outcomes.


## Concrete Steps

All commands run at the repository root, `/Users/shinzui/Keikaku/bokuno/kenshou`, inside
`nix develop` (prefix each with `nix develop -c` if you are not in the shell).

Before starting, confirm the dependency state in the MasterPlan registry and the kernel
exports this plan relies on:

```bash
grep -n "^| 2 \|^| 3 " docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md
grep -n "renderLayer\|parseLayer\|LayerId" kenshou-core/src/Kenshou/Core/Id.hs | head
grep -n "data LayerBundle" -A 12 kenshou-core/src/Kenshou/Core/Bundle.hs
```

The first command must show EP-2 as `Complete`; the second must show the open identifier and
its render and parse functions; the third shows the fields EP-2 left, which you extend.

Milestone 1, after the edits described in Plan of Work:

```bash
git rm kenshou-check/src/Kenshou/Check/Oracle/Keiro.hs kenshou-check/src/Kenshou/Check/Oracle/Kiroku.hs kenshou-check/src/Kenshou/Check/Oracle/Pgmq.hs
cabal build kenshou-core kenshou-check kenshou-measure kenshou-diagnose kenshou-cli
cabal test kenshou-check:test:kenshou-check-test kenshou-measure:test:kenshou-measure-test kenshou-diagnose:test:kenshou-diagnose-test
grep -rniE 'keiro|kiroku|pgmq|shibuya' kenshou-check kenshou-measure kenshou-diagnose --include='*.hs' --include='*.cabal' --include='*.md'; echo "exit=$?"
```

The build must succeed with no warnings about unused imports in `Kenshou.Cli.Diagnose`, the
three test suites must pass, and the grep must print nothing and `exit=1`. (The milestone 1
grep deliberately omits `kafka`, which EP-3 owns in `Kenshou.Check.Process`.)

Milestone 2:

```bash
mkdir -p kenshou-evidence/test/fixtures/consumer-records
cp /Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou/docs/verification/runs/selftest/2026/09/01a0e106-c828-71ea-96f5-5a693335454f.md kenshou-evidence/test/fixtures/consumer-records/
cp /Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou/docs/verification/runs/keiro/2026/10/01a0f8be-8279-7667-ad13-3757c626211f.md kenshou-evidence/test/fixtures/consumer-records/
printf '%s\n' '["selftest","pgmq","kiroku","shibuya","kafka","keiro","runtime"]' > kenshou-evidence/test/fixtures/consumer-records/layers.json
cabal test kenshou-evidence:test:kenshou-evidence-test
cabal run -v0 kenshou -- history selftest/kernel/correctness/always-pass --bundle docs/verification 2>&1 | head -3
KENSHOU_EVIDENCE_BUNDLE_URI=mori://shinzui/kenshou/okf/verification cabal run -v0 kenshou -- history selftest/kernel/correctness/always-pass --bundle docs/verification | jq .bundle
```

The test suite must pass, including the new `ConsumerRecordsSpec`. The first `history` call
must fail with exit code 2 and the message `evidence.bundle-uri or --bundle-uri is required`;
the second must print `"mori://shinzui/kenshou/okf/verification"`. If this repository has no
`docs/verification` bundle yet (EP-6 may not have created one), point `--bundle` at a
temporary bundle created with `okf profile init`, or at the consumer's
`/Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou/docs/verification`, which is read-only
for this command. For the record subject, run a self-test scenario and record it:

```bash
tmp=$(mktemp -d)
cabal run -v0 kenshou -- run selftest/kernel/correctness/always-pass --out "$tmp"
cabal run -v0 kenshou -- record "$(ls -d "$tmp"/*/ | head -1)" --bundle "$tmp/bundle" --data-base-uri "file://$tmp/data" --verify-only 2>&1 | tail -1
```

With no `evidenceSubject` on the kernel self-test bundle and no `KENSHOU_EVIDENCE_SUBJECT`,
the last line must say `no evidence subject for layer selftest; pass --subject or set
evidence.default-subject` and the command must exit 2; repeating it with
`KENSHOU_EVIDENCE_SUBJECT=mori://shinzui/kenshou` must record (or verify) the run. Then set
`evidenceSubject = Just "mori://shinzui/kenshou"` on the six self-test bundles so the
harness's own evidence names this project, and repeat without the variable.

Milestone 3, self-test and fixtures:

```bash
cabal run -v0 kenshou -- run selftest/remote/correctness/cell-environment --dim pg.version=pg18 --dim pg.durability=fsync-off --out "$tmp"
just schemas-check
cabal test kenshou-core:test:kenshou-core-test kenshou-remote:test:kenshou-remote-test
```

The scenario must exit 0 and its `verdicts/cell-environment` summary must show
`database-is-fresh: true`; a `psql` error mentioning `kiroku.events` means the probe was not
replaced. Then, once the MasterPlan shows EP-3 as Complete, make the routing-rule change and
run:

```bash
cabal build all
cabal test kenshou-remote:test:kenshou-remote-test kenshou-cli:test:kenshou-cli-test
cabal run -v0 kenshou -- cell route --help | grep -- --rules
```

Milestone 4:

```bash
just coupling-check; echo "exit=$?"
just verify
```

where the recipe is exactly:

```text
[group('verification')]
coupling-check:
    ! grep -rniE 'keiro|kiroku|pgmq|shibuya|kafka' \
        kenshou-check kenshou-measure kenshou-diagnose kenshou-telemetry kenshou-evidence kenshou-remote \
        --include='*.hs' --include='*.cabal' --include='*.md' --include='*.json' --include='*.yaml' \
        | grep -v '^kenshou-evidence/test/fixtures/consumer-records/' \
        | grep -vxFf scripts/coupling-allowlist.txt
```

The recipe exits 0 only when the filtered grep prints nothing. Because `just verify` runs it,
the repository's normal gate now fails on any reintroduced layer name.


## Validation and Acceptance

Acceptance for the whole plan is behavioral. First, the audit: at the repository root,

```bash
grep -rniE 'keiro|kiroku|pgmq|shibuya|kafka' kenshou-check kenshou-measure kenshou-diagnose kenshou-telemetry kenshou-evidence kenshou-remote --include='*.hs' --include='*.cabal' --include='*.md' --include='*.json' --include='*.yaml' | grep -v '^kenshou-evidence/test/fixtures/consumer-records/' | grep -vxFf scripts/coupling-allowlist.txt
```

prints nothing. The directory-level allow-list is that one directory and nothing else; it holds the two
verbatim consumer records and `layers.json`, which necessarily contain `keiro` and
`kiroku-store` because they are real evidence. Any other hit is a failure of this plan, and
extending the allow-list needs a Decision Log entry here and a matching change in EP-5's
guard.

Second, compatibility with committed evidence: `cabal test kenshou-evidence:test:kenshou-evidence-test`
passes, and `ConsumerRecordsSpec` shows both consumer records parsing, reproducing their
committed paths, and re-rendering byte-identically. As a stronger check that the consumer's
whole corpus still validates, run the evidence checker over the consumer's bundle (read-only):

```bash
cabal run -v0 kenshou -- evidence check --bundle /Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou/docs/verification --offline
```

It must report no `path-consistency` or frontmatter findings for the `runs/` records. If the
checker needs the consumer's `profile.dhall` and the kenshou checkout cannot load it, record
the reason in Surprises and rely on the fixture test; do not weaken the checker.

Third, the registry contributions are real: the unit tests named in Milestone 1 pass, the
remote self-test scenario passes against the self-test schema, `kenshou record` resolves a
subject from a bundle, from `evidence.default-subject`, and fails with exit 2 without either,
and `kenshou history` requires and prints the configured bundle URI.

Fourth, the full gate `just verify` passes with `coupling-check` in it.

Not required by this plan, and proposed only as later scope for EP-5: widening the audit to
`kenshou-core` and `kenshou-cli`, and a `kenshou` subcommand that lists a bundle's registered
oracles, labels, and rules.


## Idempotence and Recovery

Every step is a source edit or a test run and can be repeated. The fixture copies are plain
`cp` and can be re-run; if the consumer later changes those records (it must not, under
ADR-18, but an attestation may append a `verified` entry), re-copy and re-run the test, which
strips `verified` before comparing. Deleting the three oracle modules is reversible with
`git checkout -- kenshou-check/src/Kenshou/Check/Oracle/` until the commit lands, and their
text remains in the consumer's history at the import revision afterwards. The schema
relaxation only widens accepted values, so older history documents remain valid. If the
routing-rule step is started before EP-3 is complete and conflicts with EP-3's edits to
`Kenshou.Remote.Cell.Prepare`, revert this plan's RouteRules and Cell changes with `git
checkout` on those files and redo the step after EP-3 lands; nothing else in this plan touches
EP-3's files. Commit at the end of each milestone with the trailers
`MasterPlan: docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md`,
`ExecPlan: docs/plans/4-move-residual-layer-knowledge-out-of-the-toolkits-and-make-evidence-targets-configuration.md`,
and `Intention: intention_01m6165ywkevaayscg2v99y0nt`.


## Interfaces and Dependencies

Prerequisites. EP-1 complete (the packages exist here and `cabal build all` passes). EP-2
complete: `Kenshou.Core.Id.LayerId` (or EP-2's name) with `renderLayer :: LayerId -> Text`
and `parseLayer :: Text -> Either Text LayerId`, `LayerBundle` carrying it, and the kernel
self-test migration set that creates a schema the harness owns. EP-3 complete before the
routing-rule step of Milestone 3 and before Milestone 4.

What this plan defines and other plans must honor. In `kenshou-core/src/Kenshou/Core/Contribution.hs`:
`OracleSpec {name, sql}`, `AdvisoryKeySpec`, `AdvisoryLabel {label, key}`,
`PoolMethodology {recommendedPoolSize, poolRange}`, and (after the last step)
`RoutingRule {condition, requires, why}` with `RuleCondition = KnobEquals Text Text |
ScenarioMatches Selector`, each with `ToJSON`/`FromJSON` using those field names. In
`Kenshou.Core.Bundle.LayerBundle` the new fields `oracles :: [OracleSpec]`,
`advisoryLabels :: [AdvisoryLabel]`, `methodology :: Maybe PoolMethodology`,
`evidenceSubject :: Maybe Text`, and `routingRules :: [RoutingRule]`, all defaulting to empty
or `Nothing`, plus `lookupBundle`, `registrySubjects`, and `registryRoutingRules`. In
`Kenshou.Check.Oracle`: `fromSpec` and `registeredOracle`. In `Kenshou.Measure.Methodology`:
`poolMethodologyFor`. In `Kenshou.Diagnose.Stall`: `watchdogConfigFor`. In
`Kenshou.Evidence.Config`: the keys `evidence.default-subject` (`KENSHOU_EVIDENCE_SUBJECT`)
and `evidence.bundle-uri` (`KENSHOU_EVIDENCE_BUNDLE_URI`), and `EvidenceDefaults.defaultSubject`
and `.bundleUri`. In `Kenshou.Evidence.Record`: `RecordOptions.subjects :: Map LayerId Text`
and `.fallbackSubject :: Maybe Text`. In `Kenshou.Evidence.History`: `HistoryDocument.bundleUri`
and the extra `Text` argument of `history`. The `justfile` recipe `coupling-check`, its
directory-level allow-list `kenshou-evidence/test/fixtures/consumer-records/`, and the
line-level `scripts/coupling-allowlist.txt`.

Who consumes them. EP-5's synthetic bundle must set every new `LayerBundle` field to a
non-empty value (one oracle, one advisory label, a methodology, a subject of
`mori://shinzui/kenshou`, and one routing rule) and its executable's tests must exercise
`registeredOracle`, `watchdogConfigFor`, `registrySubjects`, and `registryRoutingRules`. EP-6
documents the JSON shapes and the two configuration keys in the adoption guide and records the
suite registration contract as an ADR. EP-7's adoption checklist tells the consumer to recreate
the three oracle modules and the five lock-label constructors inside `kenshou-keiro`,
`kenshou-kiroku`, and `kenshou-pgmq`, to set `evidenceSubject` on each of its six bundles to
the URIs that `defaultSubject` used to return, to add `evidence.bundle-uri:
mori://shinzui/keiro-runtime-kenshou/okf/verification` to its configuration, to move the
partitioned-queue rule from `policies/cell-routing.json` onto its PGMQ bundle, and to keep a
Kiroku `PoolMethodology 12 (10, 13)` on its Kiroku bundle.

Libraries whose choice matters: `settei` for the configuration keys (already used by
`Kenshou.Evidence.Config`), `okf-core` for parsing and serializing records (already used), and
`aeson` for the contribution types' instances. No new dependency is added to any package.
