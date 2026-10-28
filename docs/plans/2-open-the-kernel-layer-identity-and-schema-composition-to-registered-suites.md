---
id: 2
slug: open-the-kernel-layer-identity-and-schema-composition-to-registered-suites
title: "Open the kernel layer identity and schema composition to registered suites"
kind: exec-plan
created_at: 2026-10-28T12:02:04Z
intention: "intention_01m6165ywkevaayscg2v99y0nt"
master_plan: "docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md"
provenance:
  created_by:
    model: "claude-fable-5-1"
    harness: "claude-code"
    at: 2026-10-28T12:02:04Z
---

# Open the kernel layer identity and schema composition to registered suites

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

After this plan, a project that is not the Keiro runtime can register a verification suite
with this harness. Today the kernel package `kenshou-core` only accepts scenarios whose layer
is one of seven names baked into a Haskell sum type, only knows how to migrate a database with
the Kiroku, Keiro, and PGMQ schema libraries it links directly, and refuses certain scenario
shapes with a rule written for Keiro. After this plan a suite declares its own layer name, its
own database migrations, and its own registry rules as values it passes to the kernel, and the
kernel's own self-test scenarios run against a schema the kernel owns. The build no longer
links any Keiro, Kiroku, or PGMQ library.

You can see it working in three ways. `cabal build all` succeeds with `cabal.project` listing
only the generic packages, and `cabal-plan` (or `cabal build --dry-run`) shows no
`keiro-migrations`, `kiroku-store-migrations`, or `pgmq-migration` package in the plan.
`cabal run kenshou -- run selftest/kernel/correctness/postgres-roundtrip` passes using a
self-test migration set and prints a ledger that names only that set. A unit test constructs a
bundle with a layer named `acme`, a scenario `acme/widget/correctness/roundtrip`, and a
migration set the test defines, and `mkRegistry` accepts it while `kenshou list --layer acme`
prints the scenario. The seven layer strings the first consumer has already written into
evidence records (`selftest`, `pgmq`, `kiroku`, `shibuya`, `kafka`, `keiro`, `runtime`) still
render and parse byte for byte, so nothing that was sealed becomes unreadable.


## Progress

- [ ] M1: `Kenshou.Core.Id.Layer` is an open, validated `LayerId`; the golden test over the
  seven consumer layer strings passes; `cabal build all` and `cabal test all` are green with
  only minimal adaptations in `kenshou-evidence`, `kenshou-remote`, and `kenshou-cli`.
- [ ] M2: Bundles supply migration sets; `Kenshou.Core.Env.Migration` composes them into one
  `pg-migrate` ledger; `kenshou-core.cabal` no longer depends on `keiro-migrations`,
  `kiroku-store-migrations`, or `pgmq-migration` and the `keiro-schema` flag is gone;
  `selftest/kernel/correctness/postgres-roundtrip` passes on the self-test schema.
- [ ] M3: Registry rules, the component graph, the performance validation contracts, and the
  program name and header are supplied by the executable through `Kenshou.Core.Cli.Program`;
  the synthetic `acme` registry test passes; `kenshou --help` shows the generic header.
- [ ] M4: The coupling grep over `kenshou-core/src`, `kenshou-core/test`, and
  `kenshou-core/kenshou-core.cabal` returns no match outside the allow-list file
  `scripts/coupling-allowlist.txt`, and every test fixture under `kenshou-core/test` uses
  synthetic names.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Supersede the one-ledger decision recorded in
  `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-4` with the same rule stated
  generically: every schema a scenario requires is composed into one ordered `pg-migrate`
  plan applied once per database, but the migration sets are supplied by registered bundles
  and ordered by their declared `requires` edges and the scenario's declaration order, not by
  a kernel-known list. This repository has no ADR bundle yet (EP-6 creates `docs/adr/`); if
  that bundle does not exist when this plan completes, this entry is the record and EP-6
  promotes it to an ADR with the next free `ADR-N` handle.
  Rationale: The rule is what keeps migration histories inspectable; only the hard-coded
  component names and the "Keiro implies Kiroku" special case were layer knowledge.
  Date: 2026-10-28

- Decision: Migration set definitions are registry-global and resolved by name. A scenario
  names the sets it needs; any registered bundle may define a set; two bundles defining the
  same set name is a registry error.
  Rationale: A consumer's Keiro bundle must be able to require the Kiroku schema without
  importing the Kiroku layer package, which
  `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-1` forbids. Resolution by name
  across the registry keeps that boundary and makes the consumer's CLI, which assembles the
  bundles, responsible for supplying every set. The alternative of a shared migration-sets
  package in the consumer remains available to the consumer without kernel support.
  Date: 2026-10-28

- Decision: Registry rules are values of a kernel-defined `ScenarioRule` record
  (a name and a check function) contributed per bundle, with a kernel helper that reproduces
  the consumer's "require PostgreSQL 18 for this migration set" rule. Performance validation
  contracts and cohort lane stanzas are supplied by the executable through
  `Kenshou.Core.Cli.Program` rather than by new fields in the `kenshou.perf-catalog/v1` or
  `kenshou.cohort/v1` documents.
  Rationale: `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3` requires a new
  schema version for any document shape change. Program-level values change no document, and
  value-level extension is the style ADR-3 already prescribes for commands and bundles.
  Date: 2026-10-28


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This repository holds the generic verification harness extracted from
`mori://shinzui/keiro-runtime-kenshou` (the Keiro runtime's verification suite, called "the
consumer" below). The plan at
`docs/plans/1-import-the-harness-packages-from-keiro-runtime-kenshou-and-build-them-standalone.md`
has already copied the packages into this repository at the paths used here, so every path in
this plan is repository-relative to this checkout and identical to the consumer's. If a file
named below is missing, EP-1 is not complete and this plan must wait.

The packages involved are `kenshou-core` (the kernel), and, for small adaptations only,
`kenshou-evidence`, `kenshou-remote`, `kenshou-cli`, and the self-test modules of
`kenshou-check`, `kenshou-measure`, `kenshou-diagnose`, and `kenshou-telemetry`.

Some terms. A *layer* is the name of the thing a suite verifies; it is the first segment of a
scenario identifier such as `selftest/kernel/correctness/always-pass`. A *bundle*
(`Kenshou.Core.Bundle.LayerBundle`) is what a suite hands the kernel: a layer plus its
scenarios and worker roles. The *registry* is the validated set of all bundles an executable
links, built by `Kenshou.Core.Bundle.mkRegistry`. A *migration set* is a named group of
database migrations in the format of the `pg-migrate` library
(`Database.PostgreSQL.Migrate.MigrationComponent`); the kernel applies migration sets to the
PostgreSQL database it provisions for a scenario. The *compatibility key* (`comparisonKey` in
`kenshou-core/src/Kenshou/Core/Compat.hs`) is a hash of the inputs that make two runs
comparable; the names of the schemas a scenario required are part of it, so their text must
not change.

The coupling this plan removes is concentrated in these files.

`kenshou-core/src/Kenshou/Core/Id.hs` declares
`data Layer = Selftest | Pgmq | Kiroku | Shibuya | Kafka | Keiro | Runtime` with
`renderLayer` and `parseLayer`, and `ScenarioId` carries a `layer :: Layer`. `parseScenarioId`
and `renderScenarioId` compose the four-segment identifier text. Everything that constructs a
bundle writes `LayerBundle Selftest …`.

`kenshou-core/src/Kenshou/Core/Env.hs` declares
`data SchemaComponent = SchemaKiroku | SchemaKeiro | SchemaPgmq`, used in
`PostgresRequirement.schemas :: [SchemaComponent]`, and the Kafka fields that EP-3 owns (do
not touch `kafka` or `kafkaEnvironment` here). `kenshou-core/src/Kenshou/Core/Env/Migration.hs`
imports `Keiro.Migrations` (behind the `KENSHOU_KEIRO_SCHEMA` CPP flag),
`Kiroku.Store.Migrations`, and `Pgmq.Migration`, and `composePlan` sorts the requested
components, inserts Kiroku whenever Keiro is requested, and calls `migrationPlan`.
`migrateIfNeeded` in `kenshou-core/src/Kenshou/Core/Env/Postgres.hs` calls `composePlan`
with the scenario's requirement; `withPostgresEnv`, `withPostgresEnvKeeping`, and
`withPostgresEnvNamed` are its callers' entry points.

`kenshou-core/src/Kenshou/Core/Compat.hs` renders `schemas` into the compatibility value with
`schemaText`, mapping the constructors to the strings `kiroku`, `keiro`, and `pgmq` in the
order the scenario declared them. `kenshou-core/src/Kenshou/Core/Run.hs` (around line 79)
collects `scenario.requires.postgres.schemas` into those inputs.

`kenshou-core/src/Kenshou/Core/Bundle.hs` validates scenarios in `validateScenario`; the
`postgresErrors` branch rejects a scenario that requires `SchemaKeiro` unless its PostgreSQL
version dimension supports only 18, with the message "keiro scenarios require PostgreSQL 18".
`mkRegistry` also checks that every scenario's layer equals its bundle's layer and that every
role name starts with `renderLayer bundle.layer <> "/"`. `ListFilter.layers :: [Layer]` is
used by `kenshou list --layer`, parsed in `kenshou-cli/src/Kenshou/Cli/Command/List.hs` by
`readLayer`.

`kenshou-core/src/Kenshou/Core/Selftest.hs` defines the kernel's self-test bundle. Its
`postgres-roundtrip` scenario requires `[SchemaKiroku, SchemaKeiro, SchemaPgmq]`, asserts
that the schemas `keiro,kiroku,pgmigrate,pgmq` exist, asserts that the `pgmigrate.migrations`
ledger lists `keiro,kiroku,pgmq`, and writes summary keys named `kirokuEvents`,
`keiroTimers`, and `pgmqMessages`. Its `known-defect` scenario cites the consumer's plan URI
`mori://shinzui/keiro-runtime-kenshou/plans/2-…` as the defect reference.

`kenshou-core/src/Kenshou/Core/Cli.hs` builds the option parser with the header
`"kenshou - verify the Keiro runtime"` and passes the literal program name `"kenshou"` into
`CliEnv`. `runCli :: [LayerBundle] -> [CliCommand] -> [HelpTopic] -> [String] -> IO ExitCode`
is the entry point EP-1 exposed to the executable.

`kenshou-core/src/Kenshou/Plan/Components.hs` embeds `kenshou-core/data/components.json` at
compile time (`embeddedGraphBytes = $(embedFile "data/components.json")`) and exposes
`embeddedGraph` and `loadGraphFile`. That JSON file is the consumer's component graph: it
names `keiro`, `kiroku-store`, `pgmq-hs`, `shibuya-core`, Kafka libraries, and their
repositories. `kenshou-cli/src/Kenshou/Cli/Command/Plan.hs` (`loadGraph Nothing`) and
`kenshou-cli/src/Kenshou/Cli/Command/Perf.hs` (around line 338) fall back to the embedded
graph.

`kenshou-core/src/Kenshou/Perf/Plan.hs` (`validateProfile`) accepts only two reviewed
scenario and revision pairs, both Shibuya benchmarks, and reads the steady-count knob by the
literal name `shibuya.messages`. `kenshou-core/src/Kenshou/Perf/Prepared.hs` defines
`isolatedShibuyaCohort` and, in `renderBoundsProject`, emits the Cabal stanzas
`package kenshou-cli / flags: -runtime-suites` and `package kenshou-core / flags:
-keiro-schema` for that lane. These were not in the improvement request's list because the
Perf modules postdate it.

`kenshou-core/kenshou-core.cabal` has the synopsis "Shared contracts for Keiro runtime
verification", the manual flag `keiro-schema`, the `KENSHOU_KEIRO_SCHEMA` CPP option on the
library and the test suite, and the three migration dependencies.

Outside the kernel, these sites pattern-match on `Layer` or `SchemaComponent` and must keep
compiling after M1 and M2. `kenshou-evidence/src/Kenshou/Evidence/Record.hs` has
`defaultSubject :: Layer -> Text` with one equation per constructor (EP-4 owns moving this to
configuration; this plan only keeps it compiling). `kenshou-evidence/src/Kenshou/Evidence/
Bundle.hs`, `Check.hs`, and `Frontmatter.hs` only call `renderLayer` and need no change beyond
the type. `kenshou-remote/src/Kenshou/Remote/Selftest.hs` requires `[SchemaKiroku]` and
counts rows in `kiroku.events`. `kenshou-remote/test/PrepareSpec.hs` and `ExecSpec.hs` build
`LayerBundle Selftest …` values. `kenshou-check/src/Kenshou/Check/Selftest.hs`,
`kenshou-measure/src/Kenshou/Measure/Selftest.hs`, `kenshou-diagnose/src/Kenshou/Diagnose/
SelfTest.hs`, `kenshou-telemetry/src/Kenshou/Telemetry/SelfTest.hs`, and
`kenshou-remote/src/Kenshou/Remote/Selftest.hs` each build one `LayerBundle Selftest …`.
`kenshou-cli/src/Kenshou/Cli/Command/List.hs` parses `--layer`.

The kernel test suite under `kenshou-core/test` also carries consumer names: `Main.hs`
composes `[SchemaKiroku, SchemaPgmq]` and checks for the `kiroku`, `keiro`, and `pgmq`
schemas; `Kenshou/PlanSpec.hs` walks the embedded consumer graph (`pgmq-hs`,
`shibuya-core:runner`, `keiro-pgmq`); `Kenshou/PerfSpec.hs` and `Kenshou/PerfPreparedSpec.hs`
use Shibuya package manifests and read `../cohort/shibuya-current.json` from the consumer
checkout; and the goldens `test/golden/perf-prepared.fixture.json`, `perf-plan.json`,
`perf-request.json`, `perf-result.*.fixture.json`, `run-spec.effective.json`, and
`test/fixtures/plan/catalog-planned.json` and `plan-missing-edge.json` contain Shibuya and
Keiro names.

No local ADR exists yet; `docs/adr/` is created by EP-6. The cross-repository decisions that
govern this plan are `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-1` (layer
packages never import one another, which is why migration sets resolve by name),
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3` (the kernel owns the versioned
documents; `kenshou.scenario-list/v1`, `kenshou.run-spec/v1`, and `kenshou.worker-init/v1`
keep their shapes under this plan), and
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-4` (one migration ledger per
database), which this plan supersedes as recorded in the Decision Log.


## Plan of Work

The work is four milestones, each leaving the build and tests green.

M1 opens the layer identity. In `kenshou-core/src/Kenshou/Core/Id.hs`, replace the `Layer`
sum type with `newtype LayerId = LayerId Segment`, reusing the existing `Segment` validation
(lowercase ASCII letters and digits in hyphen-separated chunks, at most 48 characters), and
export `mkLayerId :: Text -> Either Text LayerId`, `selftestLayer :: LayerId` (the string
`selftest`), and keep the names `renderLayer :: LayerId -> Text` and
`parseLayer :: Text -> Either Text LayerId` so call sites change type but not name.
`parseLayer` validates the segment and no longer consults a closed list. `ScenarioId.layer`
becomes `LayerId`; the `ToJSON` and `FromJSON` instances, `parseScenarioId`, and
`renderScenarioId` keep their text format. In `kenshou-core/src/Kenshou/Core/Bundle.hs`,
`LayerBundle.layer` becomes `LayerId`, `ListFilter.layers` becomes `[LayerId]`, and a smart
constructor `mkBundle :: LayerId -> [Scenario] -> [WorkerRole] -> LayerBundle` fills the new
fields that M2 and M3 add with empty defaults; every `LayerBundle Selftest …` construction in
the self-test modules and the `kenshou-remote` tests becomes `mkBundle selftestLayer …`.
Do not add a uniqueness check on layer identifiers across bundles: six self-test bundles share
the `selftest` layer today and must continue to. In `kenshou-evidence/src/Kenshou/Evidence/
Record.hs`, rewrite `defaultSubject` as a lookup over the seven rendered strings with the same
seven URIs and the self-test subject as the fallback, with a comment that EP-4 replaces it. In
`kenshou-cli/src/Kenshou/Cli/Command/List.hs`, `readLayer` validates through `parseLayer`.
Add a test in `kenshou-core/test/Main.hs` that renders and parses the seven strings and checks
`renderScenarioId` on one identifier per layer against literal text, so a sealed consumer
record's identifiers keep decoding.

M2 makes migration sets suite-supplied. In `kenshou-core/src/Kenshou/Core/Env.hs`, replace
`SchemaComponent` with `newtype MigrationSetName = MigrationSetName Text` (validated with the
same rules as `pg-migrate`'s `componentName`, that is, the `Database.PostgreSQL.Migrate.
componentName` validator) and `data MigrationSet = MigrationSet { name :: MigrationSetName,
requires :: [MigrationSetName], component :: Either Text MigrationComponent }`. The `Either`
lets a suite register a set whose library is unavailable in a given build and fail with a
clear message only when a scenario requires it, which replaces the CPP branch in
`Env/Migration.hs`. `PostgresRequirement.schemas` becomes `[MigrationSetName]`. Add
`migrations :: [MigrationSet]` to `LayerBundle` (default `[]` in `mkBundle`) and
`registryMigrationSets :: Registry -> Map MigrationSetName MigrationSet` to `Bundle.hs`;
`mkRegistry` reports a duplicate set name across bundles and a scenario that requires a set no
bundle defines as `RegistryError`s. Rewrite `composePlan :: Map MigrationSetName MigrationSet
-> [MigrationSetName] -> Either MigrationSetupError MigrationPlan` so that it walks the
scenario's declared names in order, inserts each set's `requires` (transitively) before the set
that needs them, removes duplicates keeping the first occurrence, and calls
`Database.PostgreSQL.Migrate.migrationPlan` on the components. This reproduces the consumer's
current ledger order because its scenarios already declare Kiroku before Keiro before PGMQ.
Thread the set map from the registry into provisioning: add `migrationSets :: Map
MigrationSetName MigrationSet` to `RunnerConfig` in `kenshou-core/src/Kenshou/Core/Run.hs`,
built from the registry where the config is constructed in `kenshou-cli/src/Kenshou/Cli/
Command/Run.hs` and in the cell runner, and pass it as a new first argument to
`withPostgresEnvNamed`, `withPostgresEnvKeeping`, and `withPostgresEnv` in
`Env/Postgres.hs` so `migrateIfNeeded` can call `composePlan`. In `Compat.hs`, `schemas`
becomes `[MigrationSetName]` and `schemaText` becomes the name's text, still in declaration
order, so a consumer scenario's comparison key is unchanged. Define the kernel's own
migration set in a new module `kenshou-core/src/Kenshou/Core/Selftest/Schema.hs`: a
`pg-migrate` component named `kenshou-selftest` built with `sqlMigration` and
`migrationComponent` from one SQL migration that creates schema `kenshou_selftest` and table
`kenshou_selftest.roundtrip (id bigint primary key, payload text not null)`. Rewrite
`postgres-roundtrip` in `Selftest.hs` to require only that set, to insert and read back the
knob-configured number of rows in that table, to assert that the schemas present are exactly
`kenshou_selftest,pgmigrate` and that the ledger lists exactly `kenshou-selftest`, and to
write summary keys `rows` and `ledgerComponents`. Change the `known-defect` reference to this
repository's URI for this plan,
`mori://shinzui/kenshou/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites`.
Switch `kenshou-remote/src/Kenshou/Remote/Selftest.hs` to require the `kenshou-selftest` set
and to count rows in `kenshou_selftest.roundtrip` instead of `kiroku.events`; leave its Kafka
probe alone, EP-3 owns it. Remove `keiro-migrations`, `kiroku-store-migrations`,
`pgmq-migration`, the `keiro-schema` flag, and both `KENSHOU_KEIRO_SCHEMA` CPP options from
`kenshou-core/kenshou-core.cabal`, and delete the `hasKeiroSchema` CPP block from
`kenshou-core/test/Main.hs`. Update the PostgreSQL environment tests in `test/Main.hs` to use
the self-test set and expect `kenshou_selftest,pgmigrate`, and rewrite `migrationPlanSpec` to
check composition order and dependency insertion with two synthetic sets `alpha` and `beta`
where `beta` requires `alpha`.

M3 moves the remaining kernel rules and program identity into values the executable supplies.
In `Bundle.hs`, add `data ScenarioRule = ScenarioRule { name :: Text, check :: Scenario ->
[Text] }` and `rules :: [ScenarioRule]` to `LayerBundle` (default `[]`); `mkRegistry` applies
every bundle's rules to every scenario in the registry and turns each returned message into a
`RegistryError` prefixed with the scenario identifier. Provide the helper
`requirePgVersionsFor :: MigrationSetName -> NonEmpty PgVersion -> ScenarioRule`, whose
message for the set `keiro` and the version `Pg18` is exactly `keiro scenarios require
PostgreSQL 18`, and delete the inline Keiro branch from `validateScenario`. In `Cli.hs`,
introduce `data Program = Program { name :: String, header :: String, bundles ::
[LayerBundle], commands :: [CliCommand], topics :: [HelpTopic], componentGraph :: ByteString,
perf :: PerfContracts }` with `defaultProgram :: Program` (name `kenshou`, header
`kenshou - run verification scenarios`, no bundles or commands, the self-test graph, and
empty contracts), change `runCli` to `Program -> [String] -> IO ExitCode`, store the program
in `CliEnv`, and use `program.name` wherever the literal `"kenshou"` appeared. In
`kenshou-cli`, make EP-1's `Kenshou.Cli.Registry.CliAssembly` a type synonym for `Program`,
redefine `selfTestAssembly` as `defaultProgram` carrying the six self-test bundles,
`standardCommands`, and `standardTopics`, and keep `mainWith` and `runWithArgsWith` with their
EP-1 names and types, so the only change an executable sees is that the assembly now also
carries `name`, `header`, `componentGraph`, and `perf`. Define
`data PerfContracts = PerfContracts { reviewedPhaseContracts :: [(Text, Int)],
steadyCountKnob :: Maybe KnobName, laneStanzas :: CohortDescriptor -> [Text] }` in a new
module `kenshou-core/src/Kenshou/Perf/Contracts.hs`; `validateProfile` in `Perf/Plan.hs`
takes the contracts as an argument, checks membership against `reviewedPhaseContracts`, and
compares the steady count against `steadyCountKnob` when it is set; `renderBoundsProject` in
`Perf/Prepared.hs` takes `laneStanzas` and `isolatedShibuyaCohort` is deleted. Replace
`kenshou-core/data/components.json` with a self-test graph containing the components
`postgresql`, `pg-migrate`, `ephemeral-pg`, `hs-opentelemetry`, and `kenshou-harness` (the
last with selector `selftest/**` and the existing repository-path rules for this
repository's own directories), rename `embeddedGraph` to `selftestGraph`, and make
`Kenshou.Cli.Command.Plan.loadGraph Nothing` and the perf command read
`program.componentGraph` instead. Change the `kenshou-core.cabal` synopsis to "Scenario
kernel and protocol for the Kenshou verification harness". Adjust the executable in
`kenshou-synthetic` (created by EP-1) to build a `Program` from the self-test bundles. Add a
registry test in `kenshou-core/test/Main.hs` that builds a bundle for the layer `acme` with one
scenario `acme/widget/correctness/roundtrip`, a migration set `acme` with an inline SQL
component, and a rule, and checks that `mkRegistry` accepts it, that `registryMigrationSets`
contains `acme`, and that a scenario violating the rule is rejected with the rule's message.

M4 removes every remaining layer name from `kenshou-core`. Rewrite `kenshou-core/test/
Kenshou/PlanSpec.hs` against a new fixture `kenshou-core/test/fixtures/plan/components.
synthetic.json` that keeps the shapes the tests exercise (a library with subcomponents and
`uses` edges, `dependsOn` edges with `fromSubs` and `toSubs`, a `changeImplies` policy, and
repository paths) under synthetic names such as `acme-core`, `acme-adapter`, and
`acme-queue`. Regenerate `test/fixtures/plan/catalog-planned.json` and `plan-missing-edge.json`
from self-test and `acme` scenarios. Rewrite `Kenshou/PerfSpec.hs` and `Kenshou/
PerfPreparedSpec.hs` with synthetic package manifests and a synthetic cohort descriptor
checked in under `test/fixtures/perf/`, replacing the read of `../cohort/shibuya-current.json`
with a fixture that exercises `laneStanzas`. Regenerate `test/golden/perf-prepared.fixture.
json`, `perf-plan.json`, `perf-request.json`, the `perf-result.*.fixture.json` files, and
`run-spec.effective.json` from the synthetic inputs using the same code paths that produced
them (the perf request and plan commands), and update the golden digests the specs compare.
Create `scripts/coupling-allowlist.txt` containing one line per permitted match in the form
`<path>:<exact text>`; the intended content of that file for `kenshou-core` is empty, and any
line added must be generic prose (for example a comment that explains the history of the
compatibility key) and never a type, identifier, URI, schema name, or fixture value. EP-5
reuses this file for the repository-wide guard.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/kenshou` inside
`nix develop`. Before M1, confirm the baseline is green:

```bash
nix develop -c cabal build all
nix develop -c cabal test all
```

Both commands must end with `Build profile` output and no failing suite. Then, for M1, after
editing `Id.hs`, `Bundle.hs`, the self-test modules, `Record.hs`, and `List.hs`, build and run
the kernel test suite:

```bash
nix develop -c cabal build all
nix develop -c cabal test kenshou-core-test --test-show-details=direct
```

Expect a new test group in the output:

```text
layer identifiers
  renders and parses the seven consumer layer strings byte for byte
  renders one scenario identifier per layer
```

For M2, after the migration-set changes, confirm the migration libraries are gone from the
build plan and the self-test schema works end to end:

```bash
nix develop -c cabal build all --dry-run 2>&1 | grep -E 'keiro-migrations|kiroku-store-migrations|pgmq-migration' ; echo "exit=$?"
nix develop -c cabal run kenshou -- run selftest/kernel/correctness/postgres-roundtrip runs
```

The first command prints nothing and `exit=1` from `grep` (no matches). The second writes a
run directory under `runs/` and its `run-result.json` contains `"outcome": "passed"` and a
`postgres-roundtrip` summary whose `ledgerComponents` is `["kenshou-selftest"]`:

```bash
jq '.summaries' runs/*/run-result.json | grep -A3 ledgerComponents
```

For M3, confirm the generic header and the synthetic registry test:

```bash
nix develop -c cabal run kenshou -- --help | head -3
nix develop -c cabal test kenshou-core-test --test-show-details=direct 2>&1 | grep -A4 'open registry'
```

Expect the first line of help to read `kenshou - run verification scenarios` and the test
group `open registry` to list the `acme` bundle cases as passing.

For M4, run the coupling grep. It must print nothing:

```bash
grep -rniE 'keiro|kiroku|pgmq|shibuya|kafka' kenshou-core/src kenshou-core/test kenshou-core/kenshou-core.cabal \
  | grep -vxFf scripts/coupling-allowlist.txt ; echo "exit=$?"
```

Expect only `exit=1`. Any other line is a remaining coupling site or a fixture that still
carries a consumer name. Then run the full suite once more:

```bash
nix develop -c cabal test all
```


## Validation and Acceptance

Acceptance is the four milestone checks above, all observable. M1 is accepted when the kernel
test suite contains the layer-identifier golden group and the whole workspace builds. M2 is
accepted when the build plan contains none of the three migration packages, `kenshou-core.
cabal` has no `keiro-schema` flag, and `selftest/kernel/correctness/postgres-roundtrip` passes
with a ledger naming only `kenshou-selftest`. M3 is accepted when the `acme` registry test
passes, `kenshou --help` shows the generic header, and `kenshou plan --graph-check` succeeds
against the self-test graph with no `--graph` argument. M4 is accepted when the coupling grep
prints nothing and the full test suite passes.

The compatibility guarantee has a specific check. Before changing `Compat.hs`, record the
comparison key of one consumer run result that required schemas (any `run-result.json` from
the consumer checkout at `/Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou/runs/`, or the
golden `kenshou-core/test/golden/run-result.passed.json` if it carries a compatibility block)
and add a test that feeds the same `CompatInputs` values with `MigrationSetName`s `kiroku`,
`keiro`, and `pgmq` in that order and asserts the same `comparisonKey` hex string. This proves
that a consumer scenario's comparison key does not change when it adopts this release, which
is the master plan's AC-4 precondition.

Proposals beyond required acceptance, not part of this plan: a `kenshou list --layers`
command that prints the registered layer identifiers, and a `cabal` flag that embeds a
consumer graph at build time instead of supplying it through `Program`.


## Idempotence and Recovery

Every milestone is a set of source edits plus test runs and can be repeated. The only
generated artifacts are the regenerated goldens in M4; regenerate them from the synthetic
inputs with the commands recorded in the spec files' comments, never by hand-editing the
digests. If a golden regeneration produces a different digest on a second run, the input is
not deterministic and the fixture must be fixed before the golden is committed. The
`postgres-roundtrip` run writes under `runs/`; delete that directory between attempts. If the
consumer's `runs/` directory is used for the comparison-key check, read from it only.


## Interfaces and Dependencies

This plan depends on EP-1 being Complete: the packages exist at the paths named here, the
`kenshou-synthetic` executable links the self-test bundles through `runCli`, and `cabal test
all` is green.

It defines the interfaces that EP-3, EP-4, and EP-5 must honor, all in `kenshou-core`:

```haskell
-- Kenshou.Core.Id
newtype LayerId = LayerId Segment
mkLayerId :: Text -> Either Text LayerId
selftestLayer :: LayerId
renderLayer :: LayerId -> Text
parseLayer :: Text -> Either Text LayerId

-- Kenshou.Core.Env
newtype MigrationSetName = MigrationSetName Text
mkMigrationSetName :: Text -> Either Text MigrationSetName
data MigrationSet = MigrationSet
  { name :: MigrationSetName
  , requires :: [MigrationSetName]
  , component :: Either Text Database.PostgreSQL.Migrate.MigrationComponent
  }
data PostgresRequirement = PostgresRequirement
  { schemas :: [MigrationSetName], settings :: [(Text, Text)], needsServerControl :: Bool }

-- Kenshou.Core.Bundle
data ScenarioRule = ScenarioRule { name :: Text, check :: Scenario -> [Text] }
data LayerBundle = LayerBundle
  { layer :: LayerId
  , scenarios :: [Scenario]
  , roles :: [WorkerRole]
  , migrations :: [MigrationSet]   -- new, default []
  , rules :: [ScenarioRule]        -- new, default []
  }
mkBundle :: LayerId -> [Scenario] -> [WorkerRole] -> LayerBundle
registryMigrationSets :: Registry -> Map MigrationSetName MigrationSet
requirePgVersionsFor :: MigrationSetName -> NonEmpty PgVersion -> ScenarioRule

-- Kenshou.Core.Cli
data Program = Program
  { name :: String, header :: String
  , bundles :: [LayerBundle], commands :: [CliCommand], topics :: [HelpTopic]
  , componentGraph :: ByteString, perf :: PerfContracts }
defaultProgram :: Program
runCli :: Program -> [String] -> IO ExitCode

-- Kenshou.Perf.Contracts
data PerfContracts = PerfContracts
  { reviewedPhaseContracts :: [(Text, Int)]
  , steadyCountKnob :: Maybe KnobName
  , laneStanzas :: CohortDescriptor -> [Text] }
```

EP-3 adds resource fields to `LayerBundle` and `EnvRequirements` beside these; it must add
them to `mkBundle` with defaults. EP-4 adds oracle, lock-label, and evidence-subject fields
the same way and replaces the M1 `defaultSubject` lookup. EP-5's synthetic bundle fills
`migrations` and `rules` and supplies a `Program` with its own component graph.
`Kenshou.Cli.Registry.CliAssembly` from EP-1 is the same type as `Program` after this plan
and `mainWith :: CliAssembly -> IO ()` keeps its signature, so `kenshou-synthetic/app/Main.hs`
keeps compiling and EP-5 builds its program from `selfTestAssembly`.

External libraries whose choice matters: `pg-migrate` (`Database.PostgreSQL.Migrate`:
`sqlMigration`, `migrationComponent`, `migrationPlan`, `runMigrationPlan`) remains the only
migration engine; `file-embed` keeps embedding the self-test graph; `ephemeral-pg` keeps
provisioning the self-test database. No new dependency is introduced.
