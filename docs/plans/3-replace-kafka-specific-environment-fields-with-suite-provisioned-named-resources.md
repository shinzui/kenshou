---
id: 3
slug: replace-kafka-specific-environment-fields-with-suite-provisioned-named-resources
title: "Replace Kafka-specific environment fields with suite-provisioned named resources"
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

# Replace Kafka-specific environment fields with suite-provisioned named resources

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

The harness kernel can provision a PostgreSQL server for a scenario, but the only other kind
of infrastructure it knows how to hand to a scenario is a Kafka broker, and it knows it by
name. A scenario says `requires = kafkaEnvironment`, the run specification carries an
`environment.kafka` value, the worker initialization message carries a `kafka` field, the
process supervisor copies that field, and the remote cell client binds a Kafka broker from the
cell's `broker` block. A project that wants to verify a system against Redis, an object store,
a second message broker, or a stub HTTP service has no place to put it.

After this plan a scenario declares the named resources it needs, a suite registers a
provider for each name, and the kernel provisions those resources for a local run, passes a
per-resource JSON value to every worker, records a per-resource fingerprint in the run result,
and binds the resource from a cell's environment when the run is placed on a leased
verification cell. Nothing in `kenshou-core`, `kenshou-check`, or `kenshou-remote` names
Kafka except a small, enumerated compatibility layer that keeps every document the Keiro
suite has already written readable. You can see it working by running the self-test suite,
whose scenarios require no resources, and by running the compatibility test that reads a run
specification produced by the Keiro suite with an `environment.kafka` value and decodes it as
the resource named `kafka`.


## Progress

- [x] M1: `Kenshou.Core.Resource` exists; `EnvRequirements`, `EnvironmentSpec`, `WorkerInit`,
  and `CompatInputs` carry named resources; the compatibility golden test in
  `kenshou-core/test/Kenshou/ResourceSpec.hs` decodes the consumer-produced fixtures and the
  synthetic resource-map fixture and round-trips both; `cabal test kenshou-core` passes.
  (2026-10-28; the types are in `Kenshou.Core.Resource.Types`; the consumer-document cases
  are in the `consumer compatibility` group of `kenshou-evidence/test/Main.hs` with goldens in
  `kenshou-evidence/test/fixtures/consumer-records/`, and the synthetic `named resources`
  group is in `ResourceSpec`; see Decision Log. All suites green; the allow-list holds only
  the legacy shim lines.)
- [x] M2: `LayerBundle` carries resource providers; `mkRegistry` rejects an unprovided or
  duplicate resource; `Kenshou.Core.Run` brackets providers and `Kenshou.Core.Role.Spawn` and
  `Kenshou.Check.Process` send provisioned values to workers; every self-test bundle registers
  no providers and `cabal test all` passes.
  (2026-10-28; the `resource provisioning` group runs a scenario through `executeRun` with a
  stub provider and observes `acquire`, `run`, `release`, the normalized value in
  `run-spec.json`, and `fingerprint.resources.stub` in `run-result.json`; all suites,
  schemas, and self-tests pass. `resolveRunSpec` now does the validation the CLI's interim
  `validateKafkaEnvironment` did, which is deleted.)
- [x] M3: the cell environment and submission documents carry a `resources` block beside the
  legacy `broker` fields, `Kenshou.Remote.Cell.Legacy` adapts a cell broker to the `kafka`
  resource, the Kafka probe is gone from `Kenshou.Remote.Selftest`, and
  `cabal test kenshou-remote` passes with the cell goldens unchanged byte for byte.
  (2026-10-28; 157 remote examples pass, including the new `ResourceUnavailable` and
  resources round-trip cases; `just schemas-check` validates the unchanged cell examples
  against the extended schema copies; `selftest/remote/correctness/cell-environment` is at
  revision 2 with the `remote.tcp-endpoint` knob.)
- [x] M4: the coupling grep in this plan (EP-5 wraps it into the `coupling-check` recipe)
  reports only allow-listed lines, and `just verify` passes.
  (2026-10-28; `just coupling-check` now also audits every generic package and `schemas/`
  for the Kafka layer, excluding `kenshou-evidence/test/fixtures/consumer-records/`, and
  fails when a Kafka mention is injected into `kenshou-check`; `just verify` exits 0.)


## Surprises & Discoveries

- The plan's protocol design would have broken live cells: it sends `reset.resources` beside
  `reset.broker`, but the cell agent decodes submissions with `additionalProperties: false`.
  `legacyBrokerReset` moves the entry instead (Decision Log). Evidence:
  `kenshou-remote/test/golden/cell/cell.submission.v1.schema.json` in this repository's copy
  sets `additionalProperties: false` on `reset`.

- `HasField` cannot select a rank-N record field, so `provider.withLocal` does not
  type-check; the runner binds the field with a record pattern.

- The Kafka search finds two kinds of hit outside this plan's shim: verbatim consumer data
  in `kenshou-evidence/test/fixtures/consumer-records/` (excluded by the check), and evidence
  knowledge that `docs/plans/4-…` owns (`defaultSubject` in `Kenshou.Evidence.Record`, and
  `kenshou-evidence/test/Main.hs` literals naming a Kafka soak scenario and Kafka-adapter bug
  URIs). The latter are allow-listed in a section marked for EP-4.


## Decision Log

- Decision: Keep the `kenshou.run-spec/v1` and `kenshou.worker-init/v1` identifiers and add an
  optional `environment.resources` object and a `resources` object respectively. Readers map
  a legacy non-null `kafka` field to the resource named `kafka`; writers stop emitting `kafka`.
  Rationale: Adding an optional field is non-breaking and both readers keep every committed
  document decodable, which is what `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3`
  requires. A `/v2` identifier would ripple through every `schema` check in the evidence,
  remote, and CLI code for no reader benefit. Writers drop `kafka` because no supported path
  reads a newer run directory with an older executable: the worker is always the parent's own
  executable, and cell payloads are pinned to the harness revision that submits them
  (`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-20`).
  Date: 2026-10-28

- Decision: The comparison key algorithm `kenshou.compat-key/v1` keeps rendering the resource
  named `kafka` as the top-level `kafka` member of the compatibility inputs; every other
  resource renders under a `resources` member.
  Rationale: The Keiro suite's acceptance criterion for adopting this harness is that no
  comparison key changes against its recorded baselines. Changing the rendering would
  invalidate every Kafka benchmark baseline. The shim is one function, is named in the M4
  allow list, and goes away with a future `kenshou.compat-key/v2`.
  Date: 2026-10-28

- Decision: Cell documents gain a generic `resources` block beside the existing `broker`
  fields instead of replacing them, and `Kenshou.Remote.Cell.Legacy` maps a cell `broker` to
  the `kafka` resource until `mori://shinzui/load-testing-infra` emits `resources` itself.
  Rationale: The cell agent in `mori://shinzui/load-testing-infra` decodes
  `cell.environment/v1`, `cell.submission/v1`, and `cell.descriptor/v1` strictly with
  `additionalProperties: false`; a client that stops sending `reset.broker` would stop
  wiping brokers on live cells, and a client that cannot read `broker` would lose the only
  broker cells have today. The adapter is the one place that knowledge lives.
  Date: 2026-10-28


- Decision: The resource types live in `Kenshou.Core.Resource.Types` (`ResourceName`,
  `ProvisionedResource`, `CellBinding`), and `Kenshou.Core.Resource` adds the provider
  contract. The consumer-produced goldens and the tests that read them live in
  `kenshou-evidence/test/fixtures/consumer-records/` and the `consumer compatibility` group of
  `kenshou-evidence/test/Main.hs`; the kernel's `ResourceSpec` uses synthetic documents under
  `kenshou-core/test/golden/resources/` whose resources are named `broker` and
  `object-store`. `renderResourceInputs` is exported so both groups test the shim directly.
  The legacy worker-init golden is constructed in the shape the import revision's codec
  writes, because the consumer commits no worker-init document.
  Rationale: `Kenshou.Core.Context` needs `ProvisionedResource` and the provider needs
  `RunContext`, so one module would form an import cycle. Consumer values may appear only
  in the consumer-records area and `fixtures/consumer-baseline/` (EP-2's rule), which the
  plan's `kenshou-core/test/golden/compat/` location would break.
  Date: 2026-10-28

- Decision: The run result records `fingerprint.resources` only when a scenario provisioned
  a resource, so resource-free run results keep their exact shape. The provider's
  `withLocal` is a rank-N field, which `HasField` cannot select, so the runner binds it
  with a record pattern.
  Rationale: Existing consumer run results and their attestations stay byte-comparable.
  Date: 2026-10-28

- Decision: `legacyBrokerReset` moves a reset of the legacy-named resource out of
  `reset.resources` and into `reset.broker = {"wipe": true}`, rather than adding the broker
  wipe beside a `reset.resources` entry; a Kafka submission therefore keeps exactly the
  shape it had. A required resource is available on a cell when its provider has a cell
  binding and the capability cache reports the binding's capability as present; for the
  legacy-named resource a broker image in the descriptor also counts unless the cache says
  the capability is absent.
  Rationale: The cell agent decodes `cell.submission/v1` with `additionalProperties: false`,
  so any `reset.resources` member would make every in-service cell reject Kafka runs until
  load-testing-infra adopts the extension.
  Date: 2026-10-28

## Outcomes & Retrospective

EP-3 delivered its purpose. A scenario declares named resources, a bundle registers a
provider per name, and the kernel normalizes each value during run-spec resolution,
brackets the provider around a local run, hands workers the provisioned value, and records
a per-resource fingerprint. On a cell, resources bind by name, and the legacy broker fields
keep working through one adapter module. Nothing in `kenshou-core`, `kenshou-check`, or
`kenshou-remote` names Kafka outside the enumerated shim. Every consumer document stays
readable: the `consumer compatibility` group reads a consumer run spec with a Kafka value,
a self-test run spec with a null one, and a legacy worker-init document, and the compat-key
shim keeps recorded comparison keys stable.

Three things changed from the plan, all in the Decision Log: the resource types sit in
their own module to avoid an import cycle; the consumer goldens live in the consumer-records
area under EP-2's rule; and a Kafka submission keeps its exact wire shape because the cell
agent rejects unknown reset members. No friction entry was recorded under this plan.

No `docs/adr/` bundle exists yet. `docs/plans/6-…` should record the protocol compatibility
choices as ADRs: the `kenshou.run-spec/v1` and `kenshou.worker-init/v1` resource fields
with legacy readers, the compat-key/v1 shim, and the cell `resources` extension with
`Kenshou.Remote.Cell.Legacy` as the single adapter until load-testing-infra adopts it.


## Context and Orientation

This repository, `kenshou`, holds the generic verification harness imported by
`docs/plans/1-import-the-harness-packages-from-keiro-runtime-kenshou-and-build-them-standalone.md`
from the Keiro suite `mori://shinzui/keiro-runtime-kenshou` at commit
`a1648293443ad88ff1695ed800ff44c99993574e`. After that plan the packages live at the same
paths as in the source repository: `kenshou-core/`, `kenshou-check/`, `kenshou-measure/`,
`kenshou-diagnose/`, `kenshou-telemetry/`, `kenshou-evidence/`, `kenshou-remote/`, and
`kenshou-cli/`. This plan edits `kenshou-core`, `kenshou-check`, and `kenshou-remote`, plus
the JSON schemas under `schemas/`. Every path below is relative to the repository root.

A *scenario* is one verification case: a value of `Kenshou.Core.Scenario.Scenario` with an
identifier, knobs (named parameters), dimensions, phases, a `requires` field of type
`Kenshou.Core.Env.EnvRequirements`, and a `run` function. A *layer bundle*
(`Kenshou.Core.Bundle.LayerBundle`) groups the scenarios and worker roles a suite registers;
`mkRegistry` validates a list of bundles into a `Registry`. A *run specification* is the
`kenshou.run-spec/v1` JSON document (`Kenshou.Core.RunSpec.RunSpec`) that names the scenario
and its environment; `Kenshou.Core.RunSpec.Resolve.resolveRunSpec` turns it into an
`EffectiveRunSpec`. A *worker* is a child process started by the harness to play a *role*
(`Kenshou.Core.Role.WorkerRole`); it receives one `kenshou.worker-init/v1` document
(`Kenshou.Core.Role.WorkerInit`) on standard input before anything else. A *verification
cell* is a leased set of machines in Google Cloud, provisioned by
`mori://shinzui/load-testing-infra`; `kenshou-remote` prepares, submits, and binds runs on it
using the `cell.*/v1` documents in `Kenshou.Remote.Cell.Docs`.

This is the hard dependency on
`docs/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites.md`:
EP-2 replaces the closed layer type and the closed schema component type and adds fields to
`LayerBundle`. Both plans edit `Kenshou.Core.Env.EnvRequirements` and the worker
initialization document, so this plan starts only when EP-2 is Complete and its golden tests
are green, and every type named below is as EP-2 left it.

Today the Kafka coupling is in these places. `kenshou-core/src/Kenshou/Core/Env.hs` declares
`EnvRequirements { postgres, extraPostgres, kafka :: Bool }` and exports `kafkaEnvironment`.
`kenshou-core/src/Kenshou/Core/RunSpec.hs` declares
`EnvironmentSpec { placement, machineProfile, postgres, extraPostgres, kafka :: Maybe Value, telemetry }`
and writes `"kafka"` unconditionally, even when null, next to `"telemetry"`.
`kenshou-core/src/Kenshou/Core/Role.hs` declares `WorkerInit { ..., kafka :: Maybe Value, telemetry, ... }`
and its codec writes and reads `"kafka"`. `kenshou-core/src/Kenshou/Core/Role/Spawn.hs` and
`kenshou-check/src/Kenshou/Check/Process.hs` (function `roleProcess`) both construct a
`WorkerInit` from `context.environmentSpec.kafka`, that is, they forward the *specification*
value, not a provisioned handle. `kenshou-core/src/Kenshou/Core/Compat.hs` adds
`"kafka" .= value` to the compatibility inputs when the specification has one; the
comparison key and series key are SHA-256 digests of those inputs under the algorithm
identifier `kenshou.compat-key/v1`, which `Kenshou.Core.Run` writes into every run result.
`kenshou-core/src/Kenshou/Core/Run.hs` provisions PostgreSQL in `runScenario` through
`withPrimary` and `withExtras` and never provisions anything else; the Kafka suite in the
consumer provisions its own broker inside the scenario body from the specification value.
`kenshou-core/src/Kenshou/Core/RunSpec/Resolve.hs` validates placement and PostgreSQL but not
the Kafka value; the consumer's CLI validated it in `Kenshou.Cli.Command.Run` behind a CPP
flag, which EP-1 removed with the layer packages.

In `kenshou-remote`, `src/Kenshou/Remote/Cell/Docs.hs` declares `CellNodes.broker`,
`CellImages.broker`, `CellBroker { bootstrapServers, adminUrl, implementation, version }`,
`CellEnvironment.broker :: Maybe CellBroker`, and `ResetBlock.broker :: Maybe BrokerReset`
with `BrokerReset { wipe }`. `src/Kenshou/Remote/Cell/Exec.hs` function `resolveSpec` has a
`bindKafka` step that turns the cell broker into the JSON value
`{"backend":"external","brokers":[...],"lanes":0}` when `scenario.requires.kafka` holds, and
`bindRemoteScenario` assigns the knob `remote.kafka-bootstrap` for the self-test scenario
`selftest/remote/correctness/cell-environment`. `src/Kenshou/Remote/Cell/Prepare.hs` rejects
with `NeedsBrokerButCellHasNone` when `requirements.kafka` holds and
`descriptor.images.broker` is empty, forwards `prior.kafka` into the prepared environment,
and emits `reset.broker = {"wipe": true}` for Kafka scenarios. `src/Kenshou/Remote/Selftest.hs`
declares the `remote.kafka-bootstrap` knob and the `reachableKafka` TCP probe.

The cell documents are owned jointly with `mori://shinzui/load-testing-infra`. Its
`schemas/cell/cell.environment.v1.schema.json` requires `broker` (object or null) and sets
`additionalProperties: false`; `schemas/cell/cell.submission.v1.schema.json` allows an
optional `reset.broker` object with a required boolean `wipe`; `schemas/cell/cell.descriptor.v1.schema.json`
requires `images.broker` (empty string when the cell has no broker). Its `docs/cells/protocol.md`
section "Broker role" states that a submission requests the broker with
`reset.broker: {"wipe": true}`, that `wipe: false` is rejected, and that only after a verified
broker reset does the environment carry `broker`. This repository's copies of those schemas
and examples are the goldens under `kenshou-remote/test/golden/cell/`, with the source commit
recorded in `kenshou-remote/test/golden/cell/SOURCE`; `kenshou-remote/test/DocsSpec.hs`
decodes each golden and re-encodes it, asserting the JSON is unchanged. The `justfile`
`schemas-check` recipe validates every `cell.*.v1.json` golden against its schema.

Consumer fixtures that contain the legacy fields and that this plan copies into
`kenshou-core/test/golden/compat/` are, in the Keiro suite checkout at
`/Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou`: `kenshou-core/test/golden/run-spec.effective.json`
(a self-test run with `"kafka":null`), and, from the consumer's working tree rather than the
pinned commit because the consumer does not commit `runs/`, the sealed run directory
`runs/01a0d5bf-09e3-7727-91f9-5a6b3f04ce2c/run-spec.json` (scenario
`kafka/broker/correctness/fixture-roundtrip` with
`"kafka":{"backend":"redpanda-container","brokerProps":{"auto_create_topics_enabled":"false"}}`).
No committed worker-init document exists in the consumer; the plan constructs one from the
`WorkerInit` codec at the import revision and commits it as a golden. If that run directory no
longer exists when this plan is implemented, construct the Kafka run specification the same
way, from the `RunSpec` codec at the import revision with the same scenario identifier and
Kafka value, and record that origin in the `SOURCE` file instead of a path.

No local ADR exists yet; `docs/adr/` is created by
`docs/plans/6-carry-the-harness-decisions-vocabulary-and-adoption-guide-into-kenshou-documentation.md`,
which must record the protocol compatibility choices from the Decision Log above. The
cross-repository decisions that bind this work are
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3` (the kernel owns the versioned
protocol; a changed document shape needs a new version with a reader for the old one, and
silently changing a published version is forbidden) and
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-20` (cell payloads stay pinned to
verified cohort identities, which is why the client and the payload are always the same
harness revision).


Implementation state left by EP-1 and EP-2 (added 2026-10-28 while implementing them). The
coupling check is the `justfile` recipe `coupling-check`, which runs
`grep -riE 'keiro|kiroku|pgmq|shibuya|kafka'` (no line numbers) over `kenshou-core/src`,
`kenshou-core/test`, `kenshou-core/kenshou-core.cabal`, and `kenshou-core/data`, and
filters it through the exact `path:text` lines of `scripts/coupling-allowlist.txt`. That
file currently holds only the Kafka lines this plan removes (in `Env.hs`, `RunSpec.hs`,
`Role.hs`, `Role/Spawn.hs`, `Compat.hs`, and `kenshou-core/test/golden/run-spec.effective.json`);
this plan deletes them from the allow-list as it removes the fields, and widens the check
to the toolkits. Exact pins live in `cohort/harness.project`, which `cabal.project`
imports, not in `cabal.project` itself. Verbatim consumer data may appear only in
`kenshou-evidence/test/fixtures/consumer-records/` and `fixtures/consumer-baseline/`; the
golden decode test of a consumer-produced `run-spec.json` and `worker-init` message belongs
in the former.

## Plan of Work

The work has four milestones. M1 introduces the resource vocabulary and the document codecs
and proves compatibility against consumer fixtures before anything else changes. M2 adds the
provider contract and makes the kernel provision resources. M3 generalizes the cell client.
M4 removes what is left and proves it with a search.

### M1: resource names, environment fields, and the compatibility golden

Create `kenshou-core/src/Kenshou/Core/Resource.hs` exporting `ResourceName`,
`mkResourceName`, `renderResourceName`, `legacyKafkaName`, and the JSON instances. A resource
name is lowercase ASCII, digits, and hyphens, starting with a letter, between one and 63
characters, so it can appear as a JSON object key and as the suffix of a run-result
fingerprint field without escaping. `legacyKafkaName` is the constant `kafka` with a comment
stating that it exists only for the readers and the compatibility-key shim below and that it
is in the EP-5 coupling guard allow list.

Change `Kenshou.Core.Env.EnvRequirements` to
`EnvRequirements { postgres, extraPostgres, resources :: [ResourceName] }`, delete
`kafkaEnvironment`, and add `requiresResource :: ResourceName -> EnvRequirements` as the
replacement helper. `noEnvironment` sets `resources = []`. Fix every construction site that
the compiler reports; in this repository those are the self-test bundles and the tests in
`kenshou-remote/test/PrepareSpec.hs`, which build `EnvRequirements` positionally.

Change `Kenshou.Core.RunSpec.EnvironmentSpec` to replace `kafka :: Maybe Value` with
`resources :: Map ResourceName Value`. The writer emits `"resources"` only when the map is
non-empty, exactly as it already treats `extraPostgres`, and no longer emits `"kafka"`. The
reader accepts `resources` and, when a non-null `kafka` member is present, inserts it under
`legacyKafkaName`; if both are present and differ, it fails with
`environment.kafka and environment.resources.kafka disagree`. Update the derived `Eq`
expectations in `kenshou-core/test/Main.hs` where `EnvironmentSpec` is built positionally.

Change `Kenshou.Core.Role.WorkerInit` the same way: replace `kafka :: Maybe Value` with
`resources :: Map ResourceName Value`, write `"resources"` (an object, which may be empty, so
that workers can rely on the key), and read `resources` with the same legacy `kafka` mapping.
Update `schemas/run-spec-v1.schema.json` and `schemas/worker-init-v1.schema.json`: add a
`resources` property typed as an object whose additional properties are any value, mark the
`kafka` property with a `deprecated: true` and a `description` saying readers map it to
`resources.kafka`, and leave the `schema` constant unchanged.

Change `Kenshou.Core.Compat.CompatInputs` so the compatibility value renders the resource map
as follows: the entry named by `legacyKafkaName`, if present, is rendered as the top-level
`"kafka"` member exactly where it is rendered today, and all other entries are rendered under
a `"resources"` object, omitted when empty. Name the function `renderResourceInputs` and put
the comment `compat-key/v1 shim: keeps Kafka comparison keys stable for recorded baselines`
on it. Add `CfResource ResourceName` to `CompatField` and report a difference per resource
name in `differences`.

Then write the golden test. Create `kenshou-core/test/golden/compat/` holding
`run-spec.selftest-null-kafka.json` (the consumer's `run-spec.effective.json`, copied
verbatim), `run-spec.kafka-redpanda-container.json` (the consumer's
`runs/01a0d5bf-09e3-7727-91f9-5a6b3f04ce2c/run-spec.json`, copied verbatim),
`worker-init.legacy-kafka.json` (a `kenshou.worker-init/v1` document built with the
consumer's codec at the import revision, containing
`"kafka":{"backend":"external","brokers":["10.0.0.5:9092"],"lanes":0}`), and
`run-spec.resources.json` plus `worker-init.resources.json`, two synthetic documents that use
the new `resources` object with two entries, `kafka` and `object-store`. Create
`kenshou-core/test/Kenshou/ResourceSpec.hs`, add it to `other-modules` of the
`kenshou-core-test` suite in `kenshou-core/kenshou-core.cabal`, and register it in
`kenshou-core/test/Main.hs`. The spec asserts that each legacy document decodes, that the
decoded `resources` map contains the `kafka` value under `legacyKafkaName` (and is empty for
the null case), that encoding the decoded value and decoding it again yields the same Haskell
value, that the re-encoded document has no `kafka` member, that each synthetic document
round-trips to byte-identical canonical JSON, and that the compatibility value of the
`run-spec.kafka-redpanda-container.json` specification has a top-level `kafka` member equal
to the fixture's value and no `resources` member.

Acceptance for M1 is `cabal test kenshou-core` passing with the new spec listed in its output.

### M2: the provider contract and kernel provisioning

Add to `Kenshou.Core.Resource`:

```haskell
data ProvisionedResource = ProvisionedResource
  { workerValue :: Value,   -- sent to every worker in WorkerInit.resources
    fingerprint :: Value    -- recorded in the run result fingerprint under resources.<name>
  }

data CellBinding = CellBinding
  { capability :: Text,       -- capability key a cell must report, e.g. "broker"
    reset :: Maybe Value      -- value for cell.submission reset.resources.<name>, if any
  }

data ResourceProvider = ResourceProvider
  { name :: ResourceName,
    summary :: Text,
    normalize :: Maybe Value -> Either Text Value,
    withLocal :: forall a. RunContext -> Value -> (ProvisionedResource -> IO a) -> IO a,
    cell :: Maybe CellBinding
  }
```

`normalize` turns the run-specification value (absent when the specification omits the
resource) into the complete, validated value the provider will act on; this is where a
provider applies defaults and rejects bad input, replacing the validation the consumer's CLI
did for Kafka. `withLocal` acquires the resource for one local run and releases it when the
action returns or throws; the run directory in `RunContext.outDir` is where a provider keeps
logs. A `Nothing` cell binding means the resource cannot be provided on a cell and placement
on a cell is rejected. The `RankNTypes` extension is part of `GHC2024`, so no pragma is
needed.

Add `resources :: [ResourceProvider]` to `Kenshou.Core.Bundle.LayerBundle` beside the fields
EP-2 added. In `mkRegistry`, collect every provider from every bundle into a map by name and
add two validations: a duplicate provider name is a `RegistryError`, and a scenario whose
`requires.resources` names a resource with no provider in the registry is a `RegistryError`
reading `scenario requires unprovided resource <name>: <scenario id>`. Export
`lookupResource :: Registry -> ResourceName -> Maybe ResourceProvider`. Set `resources = []`
in every self-test bundle in `Kenshou.Core.Selftest`, `Kenshou.Measure.Selftest`,
`Kenshou.Check.Selftest`, `Kenshou.Diagnose.SelfTest`, `Kenshou.Telemetry.SelfTest`, and
`Kenshou.Remote.Selftest`.

In `Kenshou.Core.RunSpec.Resolve.resolveRunSpec`, after the PostgreSQL validations, validate
resources: every key of `spec.environment.resources` must be in `scenario.requires.resources`
(otherwise `SpecError "environment names a resource the scenario does not require: <name>"`),
and for every required name call the registry provider's `normalize` on the optional value,
storing the normalized value in the effective specification. The effective run specification
written to `run-spec.json` therefore always carries the complete value, which is what the
compatibility key hashes.

Add `resources :: Map ResourceName ProvisionedResource` to `Kenshou.Core.Context.Environment`
and initialize it empty where `Run.hs` constructs the initial context. In
`Kenshou.Core.Run.runScenario`, after `withExtras`, add `withResources`, which folds over
`scenario.requires.resources` in declaration order, looks up each provider in the registry,
and nests `provider.withLocal context value` brackets, accumulating the map; a provider
exception becomes an infrastructure failure the same way an `EnvError` does today.
`runScenario` needs the registry, which `Kenshou.Core.Run` already receives for scenario
lookup; thread it through `RunnerConfig` if it is not already there. Add
`"resources" .= fmap (.fingerprint) environment.resources` to the run-result `fingerprint`
object next to `"extraPostgres"`.

In `Kenshou.Core.Role.Spawn.withWorker` and `Kenshou.Check.Process.roleProcess`, build
`WorkerInit` with `fmap (.workerValue) context.env.resources` in place of
`context.environmentSpec.kafka`. Workers that need the raw specification value still have it
in `environmentSpec.resources` through `RoleContext.init` only if the parent forwards it; do
not forward it, because the provisioned value is the contract.

Acceptance for M2 is `cabal test all` passing, plus a unit test in `ResourceSpec` that builds
a registry with one bundle containing a stub provider whose `withLocal` records acquire and
release order into an `IORef`, a scenario requiring that resource, and asserts through
`mkRegistry` that a second bundle providing the same name is rejected and that a scenario
requiring `missing` is rejected with the message above.

### M3: generic cell resources with the legacy broker kept readable

In `Kenshou.Remote.Cell.Docs`, add `resources :: Map ResourceName Value` to
`CellEnvironment` and `resources :: Map ResourceName Value` to `ResetBlock`, both written
only when non-empty and read with `.:? "resources" .!= Map.empty`. Keep `CellNodes.broker`,
`CellImages.broker`, `CellBroker`, `CellEnvironment.broker`, `BrokerReset`, and
`ResetBlock.broker` exactly as they are, because the cell agent requires them. Add
`resources` to the copies of `cell.environment.v1.schema.json` and
`cell.submission.v1.schema.json` under `kenshou-remote/test/golden/cell/` as optional objects
and append a note to `kenshou-remote/test/golden/cell/SOURCE` saying the `resources` property
is a kenshou extension pending upstream adoption in `mori://shinzui/load-testing-infra`. Do
not change the example goldens; `DocsSpec` must keep passing byte for byte, which the
omit-when-empty rule guarantees.

Create `kenshou-remote/src/Kenshou/Remote/Cell/Legacy.hs` exporting
`brokerAsResource :: CellBroker -> Value` (the exact value `bindKafka` builds today, so the
Kafka suite's worker contract does not change), `legacyBrokerReset :: ResetBlock -> ResetBlock`
(sets `broker = Just (BrokerReset True)` when `reset.resources` has a `kafka` entry), and
`legacyBrokerAvailable :: CellDescriptor -> Bool` (non-empty `images.broker`). The module
comment states the removal condition: delete it when load-testing-infra publishes
`resources` in the environment and accepts `reset.resources` in the submission. Add it to the
cabal `exposed-modules`.

In `Kenshou.Remote.Cell.Exec.resolveSpec`, replace `bindKafka` with `bindResources`: for each
name in `scenario.requires.resources`, take `environment.resources` at that name if present;
otherwise, if the name equals `legacyKafkaName` and `environment.broker` is present, use
`brokerAsResource`; otherwise fail with `cell has no resource <name> for <scenario id>`. Put
the bound values into the cell `EnvironmentSpec.resources`. Delete the `remote.kafka-bootstrap`
assignment from `bindRemoteScenario`; keep the OTLP assignment.

In `Kenshou.Remote.Cell.Prepare`, replace `NeedsBrokerButCellHasNone` with
`ResourceUnavailable ResourceName`. A resource is available when its provider has a cell
binding and either the capability cache reports the binding's `capability` as known and not
`"none"` (reuse `capabilityKnown`) or, for `legacyKafkaName`, `legacyBrokerAvailable
descriptor` holds. A provider with no cell binding is rejected the same way. Forward
`prior.resources` into the prepared `EnvironmentSpec`. Build `reset.resources` from each
required provider's `cell.reset` and pass the block through `legacyBrokerReset` so a Kafka
run still emits `reset.broker = {"wipe": true}`. Check `Kenshou.Remote.Cell.Session` and
`kenshou-remote/src/Kenshou/Remote/Cell/WorkJson.hs` for any rendering of reject reasons into
a versioned document; if the reason text is persisted, keep the rendered string for the
`kafka` case identical to today's and add the generic string for other names.

In `Kenshou.Remote.Selftest`, remove the `remote.kafka-bootstrap` knob and `reachableKafka`,
and replace them with a generic knob `remote.tcp-endpoint` ("Optional host:port to check for
TCP reachability") and a `reachableTcp` probe with the same body; the `kafka-reachable` check
label becomes `tcp-endpoint-reachable`. The self-test scenario keeps its revision bump rule:
increment `revision` because a knob name changed.

Update `kenshou-remote/test/ExecSpec.hs` ("binds the cell broker and selected OTLP endpoint
for a tracing run") to assert `run.spec.environment.resources` at `kafka` equals the legacy
value, and the assertion on `remote.kafka-bootstrap` to assert the knob is absent. Update
`PrepareSpec.hs` constructions of `EnvRequirements` and add a case where a scenario requires
`object-store` on a cell whose capability cache does not know `object-store`, expecting
`ResourceUnavailable`. Add a `DocsSpec` case that encodes a `CellEnvironment` with a
`resources` entry and decodes it back, and one that confirms a submission with
`reset.resources` and the legacy `reset.broker` both present re-encodes unchanged.

Acceptance for M3 is `cabal test kenshou-remote` passing and `just schemas-check` validating
the goldens against the updated schema copies.

### M4: remove the rest and prove it

Run the search below. Every remaining hit must be in this allow list:
`kenshou-core/src/Kenshou/Core/Resource.hs` (the `legacyKafkaName` constant),
`kenshou-core/src/Kenshou/Core/RunSpec.hs` and `kenshou-core/src/Kenshou/Core/Role.hs` (the
legacy readers, one `.:? "kafka"` each), `kenshou-core/src/Kenshou/Core/Compat.hs`
(`renderResourceInputs`), `kenshou-remote/src/Kenshou/Remote/Cell/Legacy.hs`,
`kenshou-remote/src/Kenshou/Remote/Cell/Exec.hs` and `Prepare.hs` (the calls into
`Legacy`), `schemas/run-spec-v1.schema.json` and `schemas/worker-init-v1.schema.json` (the
deprecated property), the goldens under `kenshou-core/test/golden/compat/`, and the test
specs that assert on those goldens. If EP-1 imported `schemas/kenshou.kafka-env.v1.json`,
delete it in this milestone: it describes the Kafka suite's own resource value and belongs
with that suite. Any other hit is work left to do. Record the allow list in
`scripts/coupling-allowlist.txt`, the file EP-2 created, as one exact `path:text` line per
permitted match, so that EP-5's guard reads one list for all five layer names.


## Concrete Steps

All commands run from the repository root `/Users/shinzui/Keikaku/bokuno/kenshou` inside
the Nix development shell. Enter it once:

```bash
cd /Users/shinzui/Keikaku/bokuno/kenshou
nix develop
```

Confirm the prerequisite before touching anything: EP-2 is Complete in the master plan's
Exec-Plan Registry and the tree builds.

```bash
grep -n "EP-2" docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md | head -3
cabal build all && cabal test kenshou-core
```

Copy the consumer fixtures for M1 from the Keiro suite checkout and record their origin.

```bash
mkdir -p kenshou-core/test/golden/compat
cp /Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou/kenshou-core/test/golden/run-spec.effective.json \
   kenshou-core/test/golden/compat/run-spec.selftest-null-kafka.json
cp /Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou/runs/01a0d5bf-09e3-7727-91f9-5a6b3f04ce2c/run-spec.json \
   kenshou-core/test/golden/compat/run-spec.kafka-redpanda-container.json
printf 'mori://shinzui/keiro-runtime-kenshou\nCommit: a1648293443ad88ff1695ed800ff44c99993574e\n  kenshou-core/test/golden/run-spec.effective.json\n  runs/01a0d5bf-09e3-7727-91f9-5a6b3f04ce2c/run-spec.json\n' \
  > kenshou-core/test/golden/compat/SOURCE
```

Produce the legacy worker-init golden with the consumer's codec before changing
`Kenshou.Core.Role`. From the consumer checkout, a one-line GHCi session suffices:

```bash
cd /Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou
nix develop -c cabal repl kenshou-core --repl-options=-ghci-script=/dev/null <<'EOF'
import Data.Aeson
import qualified Data.ByteString.Lazy as L
import Kenshou.Core.Role
import Kenshou.Core.Id
import Kenshou.Core.Knob
import Kenshou.Core.Dimension
Right sid = parseScenarioId "selftest/kernel/correctness/postgres-roundtrip"
Right role = mkRoleName "selftest/worker"
Right rid = parseRunId "01997f3a-5b7c-7e21-8a44-0d6c2f9b1e55"
L.writeFile "/tmp/worker-init.legacy-kafka.json" (encode (WorkerInit rid sid role "worker-0" (mkSeed 7) emptyResolvedKnobs noDimensions Nothing (Just (object ["backend" .= ("external" :: String), "brokers" .= ["10.0.0.5:9092" :: String], "lanes" .= (0 :: Int)])) Nothing "/tmp/out" (object [])))
EOF
cp /tmp/worker-init.legacy-kafka.json /Users/shinzui/Keikaku/bokuno/kenshou/kenshou-core/test/golden/compat/
```

The exact constructor names for an empty knob set and default dimensions are in
`kenshou-core/src/Kenshou/Core/Knob.hs` and `kenshou-core/src/Kenshou/Core/Dimension.hs`;
substitute them if they differ from `emptyResolvedKnobs` and `noDimensions`. Hand-write the
two synthetic `*.resources.json` documents with `kafka` and `object-store` entries.

Implement M1 and run its acceptance:

```bash
cd /Users/shinzui/Keikaku/bokuno/kenshou
cabal test kenshou-core --test-show-details=direct 2>&1 | grep -E "ResourceSpec|examples|failures"
```

Expected tail:

```text
Kenshou.ResourceSpec
  decodes the consumer run specification with a null kafka field to no resources
  decodes the consumer Kafka run specification to the kafka resource
  decodes the legacy worker-init document to the kafka resource
  round-trips the resource-map documents to canonical bytes
  keeps the compat-key/v1 kafka member for a Kafka run
...
N examples, 0 failures
```

Implement M2 and M3, running `cabal test all` after each. Validate the schema copies and the
goldens:

```bash
check-jsonschema --schemafile schemas/run-spec-v1.schema.json kenshou-core/test/golden/compat/run-spec.*.json
check-jsonschema --schemafile schemas/worker-init-v1.schema.json kenshou-core/test/golden/compat/worker-init.*.json
just schemas-check
```

For M4, run the coupling search and compare against the allow file:

```bash
grep -rniE 'kafka' kenshou-core kenshou-check kenshou-measure kenshou-diagnose kenshou-telemetry kenshou-evidence kenshou-remote kenshou-cli schemas \
  --include='*.hs' --include='*.cabal' --include='*.json' --include='*.md' \
  | grep -vxFf scripts/coupling-allowlist.txt ; echo "exit=$?"
```

Expect only `exit=1`: every remaining hit must be an allow-listed line. Finish with the full gate:

```bash
just verify
```


## Validation and Acceptance

The plan is accepted when all of the following hold. First, the compatibility spec in
`kenshou-core/test/Kenshou/ResourceSpec.hs` passes against the three consumer-derived
goldens and the two synthetic goldens, and `check-jsonschema` validates all five against the
updated `schemas/run-spec-v1.schema.json` and `schemas/worker-init-v1.schema.json`. Second,
`kenshou list` from the standalone executable in `kenshou-synthetic` (or, before EP-5, the
self-test registry EP-1 wired) still lists every self-test scenario, and
`kenshou run selftest/kernel/correctness/postgres-roundtrip` writes a `run-result.json` whose
`fingerprint.resources` is `{}` and whose `compatibility.inputs` has neither `kafka` nor
`resources`. Third, the registry test proves that an unprovided resource and a duplicate
provider are rejected at `mkRegistry` time, not at run time. Fourth, the cell goldens under
`kenshou-remote/test/golden/cell/` are byte-identical to their state at the start of the plan
(`git diff --exit-code kenshou-remote/test/golden/cell/*.json`), while the new `DocsSpec`
cases show a `resources` block and a legacy `reset.broker` block coexisting. Fifth, the
search in M4 returns only the allow-listed files.

The early representative check the master plan assigns to this plan is the M1 golden test; do
it first, because it decides whether the legacy mapping is sound before the provider contract
is built on it. A proposal for additional scope, not required here, is a live round-trip on a
leased cell with a broker; that needs cell access the Keiro suite owns and belongs to its
adoption plan.


## Idempotence and Recovery

Every step is a source edit or a test run and can be repeated. The fixture copies are
overwrite-safe. If the M1 golden test shows that a consumer document cannot be mapped (for
example a run specification where `kafka` is `null` but a future `resources.kafka` is also
present), stop and record the case in Surprises & Discoveries before changing the reader; do
not widen the reader silently. If `DocsSpec` reports a changed golden after M3, the writer
emitted an empty `resources` object; restore the omit-when-empty rule rather than editing the
golden. Work on a branch is not required; commit at the end of each milestone with the
`MasterPlan:`, `ExecPlan:`, and `Intention:` trailers so a half-finished milestone can be
reverted as one commit.


## Interfaces and Dependencies

Prerequisite: `docs/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites.md`
Complete, with its open layer identifier in `Kenshou.Core.Id` and its new `LayerBundle`
fields in place.

Types this plan defines and that later plans consume: `Kenshou.Core.Resource.ResourceName`,
`ResourceProvider`, `ProvisionedResource`, `CellBinding`, and `legacyKafkaName`;
`Kenshou.Core.Env.EnvRequirements.resources` and `requiresResource`;
`Kenshou.Core.RunSpec.EnvironmentSpec.resources`; `Kenshou.Core.Role.WorkerInit.resources`;
`Kenshou.Core.Bundle.LayerBundle.resources` and `lookupResource`;
`Kenshou.Core.Context.Environment.resources`; `Kenshou.Remote.Cell.Docs.CellEnvironment.resources`
and `ResetBlock.resources`; and `Kenshou.Remote.Cell.Legacy`.

`docs/plans/4-move-residual-layer-knowledge-out-of-the-toolkits-and-make-evidence-targets-configuration.md`
turns the PGMQ route rule in `Kenshou.Remote.Cell.RouteRules` into suite data; it should
express that rule's `requires` capability with the same capability vocabulary `CellBinding`
uses. `docs/plans/5-prove-the-harness-boundary-with-a-synthetic-layer-and-a-coupling-guard.md`
registers a synthetic provider with a `withLocal` that starts and stops a local process and a
`cell` binding of `Nothing`, and extends `scripts/coupling-allowlist.txt` to the other layer
names. At adoption, the Keiro suite's `kenshou-kafka` package replaces `kafkaEnvironment` with
`requiresResource legacyKafkaName`, moves its `Kenshou.Env.Kafka.Spec` validation into
`normalize`, moves `withKafkaEnv` into `withLocal` returning the resolved broker addresses as
the worker value, and sets `cell = Just (CellBinding "broker" (Just (object ["wipe" .= True])))`.

Libraries whose choice matters: `aeson` for the codecs (hand-written instances, as ADR-3
requires), `containers` for `Map ResourceName Value`, and `hspec` for the golden test. No new
dependency is added to any cabal file.
