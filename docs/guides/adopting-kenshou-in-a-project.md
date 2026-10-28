---
type: Guide
title: Adopt kenshou in a project
description: Add the kenshou packages to a cabal project, register a layer bundle, assemble the verification executable, and run a first scenario.
docId: DOC-1
tags: [adoption, layer-bundle, cabal, scenario, evidence]
generated:
  by: process:claude-code
  at: "2026-10-28T18:00:00Z"
---

# Adopt kenshou in a project

This guide is for a Haskell developer who has a system to verify and has not
used kenshou before. By the end you have a cabal project with its own
verification executable. That executable registers your scenarios and runs one
of them against a disposable PostgreSQL database. It also knows where its
evidence records belong.

The worked example is `kenshou-synthetic`, the reference suite in this
repository. It is built only on the generic packages, so it exercises every
extension point a consuming suite uses. Every snippet below is copied from it
and names its file, so it compiles as shown. When your own layer needs
something this guide skips, read the matching synthetic module.

## What you build

Kenshou splits a verification suite into the harness and the parts that know
your system.

- **The harness.** The kernel (`kenshou-core`), the toolkits (`kenshou-check`,
  `kenshou-measure`, `kenshou-diagnose`, `kenshou-telemetry`,
  `kenshou-evidence`, `kenshou-remote`), and the operator command library
  (`kenshou-cli`). None of these packages knows anything about your system.
- **Layer bundles.** Your system contributes one
  [layer bundle](../terminology/layer-bundle.md) per layer it wants verified.
  A bundle is a plain value. It holds a
  [layer identifier](../terminology/layer-identifier.md), the layer's
  scenarios and worker roles, and the database migrations they need. It also
  holds any [named resources](../terminology/named-resource.md) to provision,
  the oracles that check durable state, diagnostic lock labels, the evidence
  subject, and cell-routing rules.
- **A program.** Your executable assembles its bundles and the standard
  commands into a `Program` and hands it to `mainWith`. The executable is
  yours, with your name and your help header.

Two decisions govern this split. [ADR-16](../adr/0016-register-a-suite-as-layer-bundles-assembled-into-a-program.md)
describes the registration contract. [ADR-1](../adr/0001-toolkit-packages-never-depend-on-a-layer-bundle.md)
explains why toolkits never depend on a bundle and layers never depend on one
another.

## Add the packages to your cabal project

Kenshou expects your project to name its cohort: the exact versions your
verification runs against. Every run result records the cohort identity that
cabal resolved, not the cohort you intended, and `run` refuses to start when it
cannot resolve one. [ADR-2](../adr/0002-every-result-carries-a-resolved-cohort-identity.md)
explains why. Lay the project out the way this repository is laid out:

```text
cabal.project            imports cohort/active.project
cohort/active.project    exactly one line: import: <name>.project
cohort/<name>.project    the index-state and exact constraints of the cohort
cohort/<name>.json       the kenshou.cohort/v1 descriptor of the same cohort
```

Start `cohort/<name>.project` from kenshou's `cohort/harness.project` at the
commit you pin. The harness is built and tested against exact versions of a few
narrowly bounded packages (`pg-migrate`, `ephemeral-pg`, `settei`, and the
`hs-opentelemetry` family). Then add the pins of the system you verify. Start
`cohort/<name>.json` from kenshou's `cohort/harness.json`: set `name` and
`projectFile` to match, and add one component per part of your system, each
with its canonical `mori://` URI. `cohort/active.project` then reads:

```cabal
import: <name>.project
```

Until the first kenshou release reaches Hackage, depend on this repository as a
git source pinned to a commit:

```cabal
import: cohort/active.project

packages: .

source-repository-package
  type: git
  location: https://github.com/shinzui/kenshou.git
  tag: <full commit hash>
  subdir:
    kenshou-core
    kenshou-check
    kenshou-measure
    kenshou-diagnose
    kenshou-telemetry
    kenshou-evidence
    kenshou-remote
    kenshou-cli

with-compiler: ghc-9.12.4
```

If you work against a local checkout instead, replace the
`source-repository-package` stanza with a package glob such as
`packages: . ../kenshou/kenshou-*/*.cabal`.

Add `kenshou-synthetic` to `subdir` only if you want to register the reference
suite next to your own. The walkthrough below does that, so you can run a
known-good scenario before writing your own.

After the first `cabal build`, `cohort check` compares cabal's resolved plan
(`dist-newstyle/cache/plan.json`) with the descriptor and exits 0 when they
agree. A run that must use an identity resolved elsewhere, such as one built
by Nix, reads it from the file named by `KENSHOU_COHORT_IDENTITY`.

## Declare a layer bundle

A bundle starts from `mkBundle`, which takes the layer identifier, the
scenarios, and the worker roles. Record update syntax then fills in whatever
else the layer contributes. This is the synthetic suite's bundle, from
`kenshou-synthetic/src/Kenshou/Suite/Synthetic.hs`:

```haskell
syntheticLayer :: LayerId
syntheticLayer = either (error . show) id (mkLayerId "synthetic")

syntheticBundle :: LayerBundle
syntheticBundle =
  (mkBundle syntheticLayer [appendSurvivesKillRestart, competingWriters, appendThroughput, steadyAppend, resourceRoundtrip] [writerRole, readerRole, contenderRole, echoClientRole])
    { migrations = [syntheticMigrationSet],
      rules = [requirePgVersionsFor syntheticSchema (Pg18 :| [Pg17])],
      resources = [echoProvider],
      oracles = [itemsOracle],
      advisoryLabels = [leaseLabel ("lease-" <> Text.pack (show key)) | key <- [0 .. 9 :: Int]],
      methodology = Just (PoolMethodology 8 (4, 16)),
      evidenceSubject = Just "mori://shinzui/kenshou",
      -- An example rule: a run that asks for unlogged item tables needs a cell whose
      -- PostgreSQL allows them.
      routingRules = [RoutingRule (KnobEquals "writer.storage" "unlogged") "postgres.unlogged-tables" "Unlogged item tables need a cell PostgreSQL that allows them."]
    }
```

Each field is covered below, in the order you are likely to need it. Every
field except the layer, scenarios, and roles is optional; `mkBundle` leaves the
others empty.

### The layer identifier and scenario identifiers

`mkLayerId` accepts one lowercase, hyphen-separated segment of at most 48
characters. Every scenario identifier has four such segments: layer,
component, kind, and name. The kind is one of `correctness`, `concurrency`,
`soak`, or `benchmark`. For example:
`synthetic/table/correctness/append-survives-kill-restart`.

### Scenarios

A [scenario](../terminology/scenario.md) is a record. It holds the identifier,
a revision that you bump when the scenario's meaning changes, its
[knobs](../terminology/knob.md) and [dimensions](../terminology/dimension.md),
its [phases](../terminology/phase.md), the environment it requires, and the
function that runs it. This one is from
`kenshou-synthetic/src/Kenshou/Suite/Synthetic/Correctness.hs`:

```haskell
appendSurvivesKillRestart :: Scenario
appendSurvivesKillRestart =
  Scenario
    { id = either (error . show) id (parseScenarioId "synthetic/table/correctness/append-survives-kill-restart"),
      revision = 1,
      summary = "Appends items through a writer that is killed and restarted, and checks a reader sees each exactly once.",
      tier = TierSmoke,
      placement = PlaceEither,
      knobs =
        [ intKnob "writer.count" "Items per key" 500 1 100000,
          intKnob "writer.keys" "Keys written in turn" 8 1 1000,
          intKnob "kill.count" "Times the writer is killed and restarted" 2 0 20
        ],
      dimensions = postgresDimensions (PgFsyncOff :| [PgDurable]) (Pg18 :| [Pg17]) noDimensions,
      phases = zeroPhases,
      requires = noEnvironment {Env.postgres = Just (PostgresRequirement [syntheticSchema] [] False)},
      knownDefect = Nothing,
      run = runAppend
    }
```

The same module's `runAppend` shows the correctness toolkit at work. It starts
worker processes under a supervisor and kills and restarts the writer. Then it
records the workers' facts in a [fact ledger](../terminology/fact-ledger.md)
and checks [invariants](../terminology/invariant.md) over it. The module
`Concurrency.hs` adds disjoint lease ownership. `Bench.hs` measures load
through the measurement toolkit and runs a soak that feeds the leak diagnosis.

### Worker roles

A role is code that runs in its own process, so a scenario can kill it,
restart it, or run several copies. A role receives a
`kenshou.worker-init/v1` document and exchanges messages with the scenario.
The executable re-runs itself to start a worker, so every role a scenario
starts must be registered in some bundle. This is how a role begins, from
`kenshou-synthetic/src/Kenshou/Suite/Synthetic/Roles.hs`:

```haskell
writerRole :: WorkerRole
writerRole = WorkerRole (roleName "synthetic/writer") "Appends items to synthetic.items, resuming after a restart." \context -> do
  connection <- requireConnection context
```

### Migrations

A layer that needs tables contributes a migration set: a name, the names of
the sets it builds on, and a `pg-migrate` component. A scenario lists the sets
it needs in its `PostgresRequirement`. The kernel then composes every required
set and its prerequisites into one migration ledger for the run's database, as
[ADR-17](../adr/0017-compose-suite-supplied-migration-sets-into-one-ledger.md)
decides. This set is from
`kenshou-synthetic/src/Kenshou/Suite/Synthetic/Schema.hs`:

```haskell
syntheticSchema :: MigrationSetName
syntheticSchema = MigrationSetName "synthetic"

syntheticMigrationSet :: MigrationSet
syntheticMigrationSet =
  MigrationSet
    { name = syntheticSchema,
      requires = [],
      component = either (Left . Text.pack . show) Right do
        tables <-
          sqlMigration
            "create-tables"
            "create schema synthetic;\n\
            \create table synthetic.items (key text not null, seq bigint not null, item text not null, writer text not null, written_at timestamptz not null default now(), primary key (key, seq));\n\
            \create table synthetic.leases (key text primary key, owner text not null, acquired_at timestamptz not null, expires_at timestamptz not null);\n"
        migrationComponent "synthetic" Set.empty (tables :| [])
    }
```

The rule `requirePgVersionsFor syntheticSchema (Pg18 :| [Pg17])` in the bundle
makes registration reject any scenario that needs the synthetic schema but
does not declare those PostgreSQL versions as dimensions.

### Named resources

A layer may need a service besides PostgreSQL. A broker, a cache, and an HTTP
stub are typical. The layer provides it with a `ResourceProvider`. The provider
starts the service around a local run, and it also says how a verification
cell would supply it. Scenarios require the resource by name. Workers find its
connection details in the `resources` block of their initialization document.
[ADR-19](../adr/0019-provision-named-resources-and-keep-legacy-documents-readable.md)
records the design. This provider starts a loopback echo server, from
`kenshou-synthetic/src/Kenshou/Suite/Synthetic/Echo.hs`:

```haskell
echoProvider :: ResourceProvider
echoProvider =
  ResourceProvider
    { name = echoResource,
      summary = "Loopback TCP echo server",
      normalize = Right . fromMaybe (object []),
      withLocal = \_ _ action -> withEchoServer \port ->
        action (ProvisionedResource (object ["host" .= ("127.0.0.1" :: Text), "port" .= port]) (object ["kind" .= ("loopback-echo" :: Text)])),
      cell = Nothing
    }
```

The scenario `synthetic/echo/correctness/resource-roundtrip` in the same file
declares `requires = requiresResource echoResource`. The provider sets
`cell = Nothing`, so that scenario can only run locally.

### Oracles

An [oracle](../terminology/oracle.md) is a SQL query that recomputes the
durable state a scenario's ledger claims. The scenario reconciles the ledger
against it, and later attestation runs the same query by name. Registering the
query on the bundle keeps the scenario and the attestation consistent. This
oracle is from `kenshou-synthetic/src/Kenshou/Suite/Synthetic/Oracle.hs`:

```haskell
itemsOracle :: OracleSpec
itemsOracle = OracleSpec "synthetic-items" "select key || '|' || seq || '|' || item from synthetic.items order by key, seq"
```

`fromSpec itemsOracle decoder` turns the registered query into a typed
`OracleQuery` for the scenario to run.

When a layer you measure has no metrics endpoint, poll its own SQL surface
instead: its tables, views, or functions. A sampler can read those as easily as
it scrapes an endpoint.

### Diagnostics, methodology, evidence, and routing

- `advisoryLabels` gives PostgreSQL advisory-lock keys readable names. A stall
  capture then shows `lease-3` instead of a pair of integers.
- `methodology` is the connection-pool size the layer recommends, with the
  range a benchmark may sweep. Leave it `Nothing` if the layer has no opinion.
- `evidenceSubject` is the canonical Mori URI that evidence records of this
  layer are filed under. Usually this is the project the layer verifies.
- `routingRules` maps scenario knobs to capabilities a
  [verification cell](../terminology/verification-cell.md) must offer. A run
  that sets a knob is then never placed on a cell that cannot honour it.

## Assemble the executable

The executable passes a `Program` to `mainWith` from `kenshou-cli`.
`selfTestAssembly` holds the standard commands, their help topics, and the
harness's own self-test bundles. Extend it with your bundles. This is the
reference suite's program, from
`kenshou-synthetic/src/Kenshou/Suite/Synthetic.hs`:

```haskell
syntheticProgram :: Program
syntheticProgram = selfTestAssembly {bundles = selfTestAssembly.bundles <> [syntheticBundle], componentGraph = syntheticGraphBytes}
```

and its `main`, from `kenshou-synthetic/app/Main.hs`:

```haskell
main :: IO ()
main = mainWith syntheticProgram
```

A suite of your own also sets `name` and `header`, so its help output names
your executable. It builds a fresh `Program` when it wants to leave out the
self-test bundles. The `componentGraph` is the
[component graph](../terminology/component-graph.md) that `plan` uses to pick
scenarios for a change. Keep it as a checked-in JSON file next to your bundles,
and extend the self-test graph the way `kenshou-synthetic/data/components.json`
does. [ADR-4](../adr/0004-select-runs-from-a-checked-in-component-graph.md)
explains why the graph is reviewed rather than inferred.

Build the executable with the threaded runtime and runtime statistics enabled.
The samplers and the leak diagnosis read GHC's runtime statistics, which
`-T` turns on. This stanza is from `kenshou-synthetic/kenshou-synthetic.cabal`:

```cabal
executable kenshou
  hs-source-dirs: app
  main-is: Main.hs
  ghc-options:
    -threaded
    -rtsopts
    -with-rtsopts=-N
    -with-rtsopts=-T
```

## Run a first scenario

A local run creates a disposable PostgreSQL cluster for each scenario that
needs one. It looks for the server binaries in `KENSHOU_PG18_BIN` (or
`KENSHOU_PG17_BIN` when the run selects PostgreSQL 17). Without those
variables it uses `postgres` on `PATH`. The kenshou development shell
(`nix develop`) provides PostgreSQL 18. To use a server you already run, pass
`--pg-url` or `--pg-url-env` instead.

List what your executable registers, then run the resource scenario, which
needs no database, and the correctness scenario, which needs one:

```bash
K=$(cabal list-bin <your-executable>)
"$K" list --layer synthetic
"$K" run synthetic/echo/correctness/resource-roundtrip --out runs
"$K" run synthetic/table/correctness/append-survives-kill-restart --out runs
```

Each run writes a run directory under `runs/`, containing the effective run
specification, the result, the ledgers, and the sampled series. The exit code
tells you the [outcome](../terminology/outcome.md):

| Exit code | Outcome |
| --------- | ------- |
| 0 | passed |
| 1 | failed |
| 2 | usage error |
| 3 | inconclusive |
| 4 | errored or infrastructure failure |

Change a knob with `--set NAME=VALUE`, pin a dimension with
`--dim NAME=VALUE`, and shorten or lengthen a phase with
`--phase NAME=SECONDS`. `"$K" list --json` shows every knob and its default.
`"$K" run SCENARIO --print-spec` shows the effective specification without
running anything.

## Record evidence

`record` files a finished run as an immutable
[evidence record](../terminology/evidence-record.md) in an OKF verification
bundle. The record's subject comes from the first of these that is set:

1. the `--subject` flag;
2. the `evidenceSubject` of the bundle that registers the run's layer;
3. the `evidence.default-subject` setting, or the `KENSHOU_EVIDENCE_SUBJECT`
   environment variable.

If none is set, `record` exits with code 2 and names the layer. The
verification bundle lives at `evidence.bundle-root`, which defaults to
`docs/verification`. Set `evidence.bundle-uri` (or
`KENSHOU_EVIDENCE_BUNDLE_URI`) to that bundle's canonical Mori URI, because
`history` queries the bundle by URI.

`record` uploads the run's files to object storage and pins each file in the
record by its SHA-256 digest. A real record names the bucket prefix and the GCP
project:

```bash
"$K" record runs/<run directory> --data-base-uri gs://<bucket>/<prefix> --purpose release --project <gcp project>
```

To rehearse without a bucket, copy the verification bundle outside your
repository. Then pass `--store-root`, so the bytes go to a local directory
while the record keeps its `gs://` links:

```bash
"$K" record runs/<run directory> --bundle /tmp/rehearsal/bundle --store-root /tmp/rehearsal/store \
  --data-base-uri gs://<bucket>/<prefix> --purpose investigation --allow-dirty
```

`--allow-dirty` admits a run built from uncommitted sources and files it as an
investigation. Run `"$K" help evidence` for attestation, history, and the
remaining store options.
[ADR-12](../adr/0012-keep-verification-records-immutable-and-derive-baselines.md)
explains why records are never edited after they are written.

## Where to read next

- [The architecture decisions](../adr/index.md) record why the harness works
  the way it does. ADR-3 (the verification protocol), ADR-5 (comparison
  verdicts), and ADR-7 (invariant classes) are the ones a new suite meets
  first.
- [The terminology](../terminology/index.md) defines every term this guide
  links.
- `"$K" help` lists the commands. `"$K" help <topic>` explains measurement,
  diagnosis, telemetry arms, cells, and evidence.
- The modules under `kenshou-synthetic/src/Kenshou/Suite/Synthetic/` are a
  complete small suite. Read them when your layer needs a pattern this guide
  only mentions.
