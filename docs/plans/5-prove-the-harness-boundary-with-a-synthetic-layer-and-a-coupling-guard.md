---
id: 5
slug: prove-the-harness-boundary-with-a-synthetic-layer-and-a-coupling-guard
title: "Prove the harness boundary with a synthetic layer and a coupling guard"
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

# Prove the harness boundary with a synthetic layer and a coupling guard

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

After this plan, a maintainer of this repository can prove, with a build and a short command
sequence, that the kenshou harness knows nothing about the Keiro runtime. The proof has two
halves. The first half is a complete reference suite for a layer called `synthetic` that lives
in the `kenshou-synthetic` package, links only the generic harness packages, and exercises every
extension point that the earlier plans opened: it registers its own layer identifier, supplies
its own PostgreSQL schema migration, provisions one named extra resource, contributes an oracle,
advisory lock labels, a component graph, and an evidence subject, and runs scenarios of all four
kinds (correctness, concurrency, benchmark, and soak) through the unchanged `kenshou`
command set. The second half is a coupling guard: a script that fails the build if any generic
package names a Keiro layer again, plus a check that the resolved cabal build plan contains none
of the consumer's layer packages or the three runtime migration libraries.

Someone can see it working by entering `nix develop` in this repository, running
`cabal build all`, listing the synthetic scenarios with `kenshou list --layer synthetic`,
planning a run from a changed component with `kenshou plan`, running each synthetic scenario
with exit code 0, judging a soak run for leaks with `kenshou diagnose leak`, comparing two
interleaved benchmark runs with `kenshou compare`, recording a run into a scratch evidence bundle
with `kenshou record`, and finally running `just verify`, which now includes the coupling guard
and the plan check and finishes green. The synthetic suite is also the worked example that a
consuming project copies when it registers a suite of its own, so every registration step in it
is written to be read, not only to pass.


## Progress

- [ ] M1: `kenshou-synthetic` registers the `synthetic` layer with its migration set, worker
  roles, and the correctness scenario; `kenshou list --layer synthetic` shows it, and
  `kenshou run synthetic/table/correctness/append-survives-kill-restart` exits 0 with the
  no-loss, per-key-order, duplicates-within-windows, and ledger-versus-oracle verdicts held.
- [ ] M2: the concurrency, benchmark, soak, and resource round-trip scenarios exist and each
  exits 0; the `echo` resource is provisioned by the suite and the suite oracle, lock labels,
  and evidence subject are registered on the bundle.
- [ ] M3: `kenshou plan --changed synthetic-table` selects only the table scenarios,
  `kenshou diagnose leak` on a soak run exits 0, `kenshou compare` over interleaved benchmark
  pairs writes a comparison document with a pass verdict, and `kenshou record` writes a sealed
  run record into a scratch evidence bundle with subject `mori://shinzui/kenshou`.
- [ ] M4: `scripts/coupling-guard.sh` and `scripts/plan-check.sh` exist, run from
  `just verify` and CI, and pass; a deliberately injected layer name in a generic package makes
  the guard fail, and `kenshou-synthetic`'s cabal file depends only on generic packages.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: The named extra resource is a loopback TCP echo service started in-process by the
  suite's provisioner, not a second database or a container.
  Rationale: It is the cheapest deterministic resource that still proves the full path from
  requirement declaration through provisioning to a worker reading the resource's address, and
  it needs nothing the dev shell does not already have.
  Date: 2026-10-28

- Decision: The coupling guard is a fixed-string allow list over `path:text` lines, not a
  per-pattern exemption language.
  Rationale: The only legitimate matches are the compatibility readers that EP-3 keeps for the
  consumer's old `kafka` fields and a handful of prose lines; an exact-line allow list makes
  every exemption visible in review and goes stale loudly when the line changes.
  Date: 2026-10-28


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This repository, `kenshou`, is the extracted verification harness described in
`docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md`. By the
time this plan starts, the earlier child plans have left the following state in the working
tree. EP-1 imported eight generic packages from `mori://shinzui/keiro-runtime-kenshou` at commit
`a1648293443ad88ff1695ed800ff44c99993574e`: `kenshou-core` (the kernel), `kenshou-check`
(correctness toolkit), `kenshou-measure` (measurement toolkit), `kenshou-diagnose`
(diagnostics), `kenshou-telemetry` (telemetry arms), `kenshou-evidence` (evidence records),
`kenshou-remote` (verification cells), and the generic part of `kenshou-cli` (operator
commands as a library). EP-1 also created the `kenshou-synthetic` package with a `kenshou`
executable in `kenshou-synthetic/app/Main.hs` that registers only the self-test bundles, the
generic JSON schemas under `schemas/`, the policy examples under `policies/`, the named suites
under `suites/`, and the `justfile` whose `verify` recipe is the local gate. EP-2 replaced the
closed layer type with an open identifier and made schema migrations suite-supplied. EP-3
replaced the Kafka-specific environment fields with a map of named resources that suites
provision. EP-4 moved oracles, lock labels, and the evidence subject onto the suite bundle and
made the evidence bundle URI configuration. This plan uses every one of those extension points.
Where this plan names an extension point by role rather than by its final Haskell name, read
the Interfaces and Dependencies section of the plan that owns it:
`docs/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites.md`,
`docs/plans/3-replace-kafka-specific-environment-fields-with-suite-provisioned-named-resources.md`,
and
`docs/plans/4-move-residual-layer-knowledge-out-of-the-toolkits-and-make-evidence-targets-configuration.md`.

Some terms of art, in plain language. A *scenario* is one named verification procedure with
the four-segment identifier `layer/component/kind/name`, declared as a `Scenario` record in
`kenshou-core/src/Kenshou/Core/Scenario.hs`; its `run` field is an `IO` action that receives a
`RunContext` (`kenshou-core/src/Kenshou/Core/Context.hs`) and returns a `ScenarioReport`. A
*layer* is the runtime boundary a scenario tests; the first identifier segment names it. A
*bundle* is the value a suite registers: a `LayerBundle` from
`kenshou-core/src/Kenshou/Core/Bundle.hs` carrying the layer identifier, scenarios, worker roles,
and, after EP-2 to EP-4, the migration set, resource provisioners, oracle, lock labels, and
evidence subject. A *worker role* is a named child-process entry point (`WorkerRole` in
`kenshou-core/src/Kenshou/Core/Role.hs`); the kernel spawns the same executable with a hidden
`worker` command, hands it a `kenshou.worker-init/v1` document on standard input, and exchanges
JSON lines with it. A *run directory* is what `kenshou run --out DIR` writes: the effective
`run-spec.json`, then `run-result.json`, then `manifest.json`, plus logs, verdicts, samples, and
series. A *fact ledger* is the append-only JSON Lines evidence that `kenshou-check` writes under
`verdicts/ledger/` through `Kenshou.Check.Ledger`; each fact has a kind (`Intent`, `Produced`,
`Observed`, `Effect`, `Terminal`, `Acquired`, `Acted`, `Released`, `Checkpoint`, and the
disturbance edges), a key, a sequence number, and an item. A *checker* evaluates an invariant
over the ledger (`kenshou-check/src/Kenshou/Check/Invariant.hs`: `noLoss`, `perKeyOrder`,
`duplicatesWithin`, `disjointOwnership`, `eventualQuiescence`, and others) and produces a
*verdict* (`held`, `violated`, or `not-evaluated`); `Kenshou.Check.Scenario.withCheck` opens the
ledger for a scenario and `finishWithVerdicts` turns verdicts into the scenario report. An
*oracle* is a SQL query that reads durable state so `Kenshou.Check.Oracle.reconcile` can confirm
that acknowledged ledger facts exist in storage. A *measurement* wraps a benchmark in
`Kenshou.Measure.Session.withMeasurement`, drives load with `Kenshou.Measure.Load.runLoad`, and
records latency histograms and samples that `kenshou compare` later evaluates against a
`kenshou.comparison-policy/v1` document such as `policies/default.json`. An *evidence record* is
the immutable OKF concept that `kenshou record` adds to a verification bundle for one finished
run.

The reference for how a real suite is written is the consumer repository at
`/Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou`, which this plan does not modify. Its
smallest layer package is `kenshou-pgmq`: `kenshou-pgmq/src/Kenshou/Suite/Pgmq.hs` builds the
bundle by concatenating scenario lists from one module per concern,
`kenshou-pgmq/src/Kenshou/Suite/Pgmq/Roles.hs` defines the producer, consumer, and reconciler
roles that parse their `args`, send `WrkReady`, wait for `CtlStart`, and report facts and
progress with `WrkFacts`, `WrkCustom`, and `WrkProgress`, and
`kenshou-pgmq/src/Kenshou/Suite/Pgmq/Oracle.hs` reads the durable tables back. The self-tests
that already run without any layer are the closest model for scenario bodies:
`kenshou-core/src/Kenshou/Core/Selftest.hs` (an echo role spawned with
`Kenshou.Core.Role.Spawn.withWorker`, a PostgreSQL round-trip that checks the composed migration
ledger), `kenshou-check/src/Kenshou/Check/Selftest.hs` (writing facts and running the checker
catalogue), `kenshou-check/src/Kenshou/Check/Selftest/KillRestart.hs` (a supervised child killed
with `SIGKILL` and restarted through `Kenshou.Check.Process`), and
`kenshou-check/src/Kenshou/Check/Selftest/ProxyPartition.hs` (a TCP proxy from
`Kenshou.Check.Fault.Network`). In this repository those files are at the same relative paths.
`kenshou-check/README.md` explains the checker catalogue, the three clock regimes, and the
failure controls. The change-aware planner reads a component graph document
(`kenshou.component-graph/v1`, see the consumer's `kenshou-core/data/components.json` for the
shape: components with `selectors` that map to scenario identifiers, `dependsOn` edges, and
`repositoryPaths` that map changed files to selectors).

No local ADR exists in this repository at the time of writing; `docs/adr/` is created by
`docs/plans/6-carry-the-harness-decisions-vocabulary-and-adoption-guide-into-kenshou-documentation.md`.
If that plan has already landed when you start, cite its suite-registration ADR from this plan's
Decision Log and follow `agents/skills/exec-plan/ADR.md` for any new record. Two
cross-repository decisions govern this work.
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-1` (Layer packages never import one
another) fixes the direction this plan proves: a layer package depends on the kernel and
toolkits, never the reverse, and the coupling guard is the mechanical form of that rule.
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3` (Kenshou owns the runtime
verification protocol) means the synthetic suite must not invent a document format or bypass
the kernel runner; every artifact it produces is one of the versioned `kenshou.*/v1` documents
that `schemas/` describes, and the process exit codes (0 passed, 1 failed, 2 usage, 3
inconclusive, 4 errored or infrastructure) are the acceptance signal.
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-18` (Keep verification records
immutable and derive baselines) is why the evidence step below records into a scratch copy of a
bundle outside the repository rather than into a committed one.


Implementation state left by EP-1 and EP-2 (added 2026-10-28 while implementing them). The
repository has a top-level `fixtures/consumer-baseline/` directory of verbatim consumer
files read by tests (see its README). By the user's decision (EP-2 Decision Log), its
captured perf documents (`kenshou-core/test/golden/perf-*.json`, the consumer graph, and
`perf-contracts.json`) stay there as protocol fixtures because they cannot be regenerated
here; so the coupling guard must exclude `fixtures/consumer-baseline/` as well as
`kenshou-evidence/test/fixtures/consumer-records/`, and this plan deletes only the
entries that EP-4 has replaced, not the directory. The coupling check already exists as
the `justfile` recipe `coupling-check` with the allow-list `scripts/coupling-allowlist.txt`
(exact `path:text` lines, grep without line numbers); this plan replaces it with
`scripts/coupling-guard.sh`. The two `kenshou-cli` file-backed perf session tests in
`kenshou-cli/test/PerfSessionSpec.hs` are pending until a synthetic perf pipeline exists.
The `kenshou` executable takes a `Program` (`Kenshou.Cli.CliAssembly` is a synonym), and
`defaultProgram`, `selfTestAssembly`, `PerfContracts`, and `noPerfContracts` are the
values a synthetic bundle extends.

## Plan of Work

The work has four milestones. Each is independently verifiable from the command line and each
leaves `cabal build all` and `just verify` green.

Milestone M1 registers the synthetic layer and lands the correctness scenario. Create the
library in `kenshou-synthetic` with the modules `Kenshou.Suite.Synthetic` (the bundle),
`Kenshou.Suite.Synthetic.Schema` (the migration set), `Kenshou.Suite.Synthetic.Table` (the
hasql statements against the suite's tables), `Kenshou.Suite.Synthetic.Roles` (the worker
roles), `Kenshou.Suite.Synthetic.Knobs` (knob names and defaults), and
`Kenshou.Suite.Synthetic.Correctness` (the first scenario). The schema is one `pg-migrate`
migration component named `synthetic` that creates the schema `synthetic` with two tables:
`synthetic.items` with columns `key text`, `seq bigint`, `item text`, `writer text`, and
`written_at timestamptz`, primary key `(key, seq)`; and `synthetic.leases` with columns
`key text` primary key, `owner text`, `acquired_at timestamptz`, and `expires_at timestamptz`.
Register the migration set on the bundle through EP-2's suite-supplied migration field so that
the kernel composes it into the one `pgmigrate` ledger exactly as it composed the consumer's
runtime migrations; the correctness scenario's environment requirement names that component
instead of the old closed schema list. Define three roles. `synthetic/writer` takes `args` with
`count`, `keys`, and `writer` (an instance name); on `CtlStart` it resumes from the highest `seq`
already present for each of its keys, then inserts rows one at a time, sending a `WrkFacts`
message with an `intent` fact before each insert and a `produced` fact after the insert commits,
and `WrkProgress` every few rows. `synthetic/reader` polls `synthetic.items` in `(key, seq)`
order and sends `observed` facts for every row it has not reported yet, then `terminal` facts
once the expected count is reached. `synthetic/contender` is used by M2. The scenario body in
`Kenshou.Suite.Synthetic.Correctness` is modelled on the consumer's
`kenshou-check/src/Kenshou/Check/Selftest/KillRestart.hs`: inside `withCheck` and
`withSupervisor` it spawns one writer and one reader with `roleProcess` and `spawn`, waits for
both to be ready, starts them, kills the writer with `killChild` the number of times given by the
`kill.count` knob (each kill and restart records a disturbance window automatically), restarts it
with `restartChild`, waits until the reader's progress reaches `count` times `keys`, stops both
gracefully, and translates the facts the children reported (read with `readChildMessages`) into
ledger facts with `recordDurable` and `record`, keyed by the item key with the row's `seq` as the
sequence number. It then runs `noLoss`, `perKeyOrder`, `duplicatesWithin` with the supervisor's
`crashWindows` as the excused windows, and `eventualQuiescence`, plus
`Kenshou.Check.Oracle.reconcile` fed by the suite oracle from M2 (in M1 it may query the table
directly with `runOracle`), and finishes with `finishWithVerdicts`. The scenario identifier is
`synthetic/table/correctness/append-survives-kill-restart`, tier smoke, placement either,
requiring PostgreSQL with the `synthetic` migration component, with the knobs `writer.count`
(default 500), `writer.keys` (default 8), and `kill.count` (default 2). Wire the bundle into
`kenshou-synthetic/app/Main.hs` next to the self-test bundles. At the end of M1,
`kenshou list --layer synthetic` prints the scenario and the roles, and the run exits 0 with
every contract verdict held.

Milestone M2 completes the suite's coverage of extension points. Add
`Kenshou.Suite.Synthetic.Concurrency` with
`synthetic/table/concurrency/competing-writers-hold-disjoint-leases`: it spawns `contenders`
(knob, default 4) instances of `synthetic/contender`, each of which repeatedly tries to acquire
the lease for a random key from a small key set with an `insert ... on conflict do update`
guarded by `pg_advisory_xact_lock` on `hashtext('synthetic/lease/' || key)`, writes one item row
while it holds the lease, and releases it; each contender reports `acquired`, `acted`, and
`released` facts with the key as the lease name and its instance name as the owner, and the
scenario runs `disjointOwnership`, `noLoss`, and `duplicatesWithin`, and additionally terminates
one contender's backend once with `Kenshou.Check.Fault.Postgres.terminateOneBackend` selected by
application name so that a lease expiry is exercised. Add `Kenshou.Suite.Synthetic.Bench` with
`synthetic/table/benchmark/append-throughput`: it builds a `LoadModel` from the standard load
knobs (`Kenshou.Measure.Knobs.loadKnobs` and `loadModelFromKnobs`), builds a `MeasureConfig`
with `measureConfigFromKnobs` and `phasePlanFromCore`, and inside `withMeasurement` calls
`runLoad` with an `Operation` named `append` that inserts one row through a hasql pool; the
report's failed-operation count decides the outcome, as the consumer's
`kenshou-pgmq/src/Kenshou/Suite/Pgmq/Bench/Runner.hs` does. Give it the benchmark dimension
support that forces durable PostgreSQL and phases with short defaults (warm-up 2 s, steady 10 s,
drain 1 s) so a run is quick but still benchmark-grade when the planner asks for trials. Add
`Kenshou.Suite.Synthetic.Soak` with `synthetic/table/soak/steady-append`, tier soak, which runs
the same append operation in a closed loop at a modest rate for the steady phase (default 30 s)
under the RTS and process samplers so that `kenshou diagnose leak` has series to judge. Add
`Kenshou.Suite.Synthetic.Echo`, which has two parts. The first is the resource provisioner for a
named resource `echo`: a loopback TCP server, started with `Control.Concurrent.Async` and
`Network.Socket` from the `network` package, that echoes every byte it receives, and whose
address is exposed to scenarios and workers through EP-3's resource map as `host` and `port`
values. Register the provisioner on the bundle in EP-3's provisioner field for local placement,
and declare the resource in the scenario's environment requirement by name. The second part is
`synthetic/echo/correctness/resource-roundtrip`, which reads the resource address from the run
context, spawns one `synthetic/echo-client` worker whose `args` carry nothing (the address
arrives in the worker-init resource block), has the worker send `messages` (knob, default 100)
lines and compare the echoes, and reports `passed` only when every echo matched. Add
`Kenshou.Suite.Synthetic.Oracle` exposing an `OracleQuery [ItemRef]` that selects
`key, seq, item` from `synthetic.items` ordered by key and seq, and register it on the bundle
through EP-4's oracle field so that both the correctness scenario and `kenshou attest`'s
`verdict-recomputed` check can use it. Add `Kenshou.Suite.Synthetic.Locks` with one
`AdvisoryLabel` for the lease lock (name `synthetic lease <key>`, hashed with the same
`hashtext` expression the contender uses) and register it through EP-4's lock label field so
that `kenshou diagnose stall` names the wait. Register the evidence subject
`mori://shinzui/kenshou` through EP-4's subject field. Switch the M1 scenario to the registered
oracle. At the end of M2 all five scenarios exist and each exits 0.

Milestone M3 drives the generic commands over the synthetic suite and fixes the data they need.
Create `kenshou-synthetic/data/components.json` as a `kenshou.component-graph/v1` document with
the components `postgresql` (service), `pg-migrate` (library, `mori://shinzui/pg-migrate`),
`ephemeral-pg` (harness, selectors `selftest/kernel/**`), `kenshou-harness` (harness, source
root `kenshou-core/`, selectors `selftest/**`), `synthetic-table` (selectors
`synthetic/table/**`, source roots `kenshou-synthetic/src/Kenshou/Suite/Synthetic/Table.hs`,
`Roles.hs`, `Schema.hs`, `Correctness.hs`, `Concurrency.hs`, `Bench.hs`, `Soak.hs`, depending on
`pg-migrate` and `postgresql`), and `synthetic-echo` (selectors `synthetic/echo/**`, source
root `kenshou-synthetic/src/Kenshou/Suite/Synthetic/Echo.hs`), with `repositoryPaths` entries
mapping `kenshou-core/`, `kenshou-check/`, `kenshou-measure/`, `kenshou-cli/`, `schemas/`,
`suites/`, and `policies/` to `selftest/**` and `synthetic/**`. Contribute it through EP-2's
component-graph data hook (the kernel no longer embeds a graph; the suite or the executable
supplies one) so that `kenshou plan --graph-check` passes and `kenshou plan --changed
synthetic-table --explain` selects exactly the four table scenarios. Make sure `suites/smoke.json`
includes the synthetic correctness and concurrency scenarios through its selection mode, and add
`policies/synthetic-compare.json`, a copy of `policies/default.json` with `name` set to
`synthetic-compare` and `minimumPairs` left at 5 so the acceptance below is honest about the
default. Then exercise, in order, planning, execution of the plan, the leak diagnosis of a soak
run, an interleaved ABBA benchmark comparison, and recording of one passing run into a scratch
evidence bundle. The commands are in Concrete Steps. Fix whatever these commands reveal in the
suite; do not change the generic commands to fit the suite unless a generic defect is found, in
which case record it in Surprises & Discoveries and in the friction log.

Milestone M4 adds the coupling guard and the plan check and makes them part of the gate. Write
`scripts/coupling-guard.sh` and `scripts/coupling-allowlist.txt` as described in Concrete Steps,
and `scripts/plan-check.sh`. Add `coupling-check` and `plan-check` recipes to the `justfile`, add
both to the `verify` recipe's dependency list, and add both to the CI workflow EP-1 established
(find it under `.github/workflows/` or wherever EP-1's Outcomes & Retrospective says CI lives).
Then prove the guard bites: temporarily add a comment containing `kiroku` to any generic
module, run `just coupling-check`, observe the failure, and revert. Finally confirm that
`kenshou-synthetic/kenshou-synthetic.cabal` lists only generic `kenshou-*` packages and ordinary
Hackage libraries in `build-depends`.


## Concrete Steps

All commands run from the repository root, `/Users/shinzui/Keikaku/bokuno/kenshou`, inside the
dev shell. Enter it once; it starts nothing by itself. PostgreSQL for scenarios is provisioned
per run by the kernel through `ephemeral-pg`, so no database service needs to be running.

```bash
cd /Users/shinzui/Keikaku/bokuno/kenshou
nix develop
cabal build all
K=$(cabal list-bin kenshou)
```

For M1, after adding the modules, confirm registration and run the correctness scenario.

```bash
"$K" list --layer synthetic
"$K" list --layer synthetic --roles
mkdir -p runs
"$K" run synthetic/table/correctness/append-survives-kill-restart --set kill.count=2 --out runs; echo "exit=$?"
```

Expected: the first command prints one line per synthetic scenario (one after M1, five after
M2); the run prints the run directory path and ends with `exit=0`. Inside the run directory,
`run-result.json` has `"outcome": "passed"`, `verdicts/` holds one JSON verdict per checker with
`"status": "held"`, and `verdicts/ledger/` holds the fact segments. A quick check:

```bash
RUN=$(ls -d runs/*/ | tail -1)
jq -r '.outcome' "$RUN/run-result.json"
jq -r '.summary.verdicts.checks[] | "\(.checker) \(.status)"' "$RUN/run-result.json"
```

```text
passed
no-loss held
per-key-order held
duplicates held
eventual-quiescence held
ledger-versus-oracle held
```

For M2, run each remaining scenario and expect `exit=0` from each.

```bash
"$K" run synthetic/table/concurrency/competing-writers-hold-disjoint-leases --out runs; echo "exit=$?"
"$K" run synthetic/echo/correctness/resource-roundtrip --out runs; echo "exit=$?"
"$K" run synthetic/table/benchmark/append-throughput --dim pg.durability=durable --out runs; echo "exit=$?"
"$K" run synthetic/table/soak/steady-append --phase steady=30 --out runs; echo "exit=$?"
```

For M3, check the graph, plan from a changed component, and execute the plan.

```bash
"$K" plan --graph-check
"$K" plan --changed synthetic-table --explain --max-tier smoke --kind correctness --kind concurrency --out runs/plan.json
jq -r '.entries[].scenario' runs/plan.json
"$K" execute --plan runs/plan.json --out runs; echo "exit=$?"
```

Expected: `--graph-check` exits 0; the explain output lists `synthetic-table` as the changed
component and the selected identifiers are exactly the synthetic table correctness and
concurrency scenarios (no `selftest/**`, no `synthetic/echo/**`); `execute` exits 0 and writes a
plan summary. Then diagnose the soak run from M2 for leaks:

```bash
SOAK=$(grep -l '"synthetic/table/soak/steady-append"' runs/*/run-spec.json | head -1 | xargs dirname)
"$K" diagnose leak "$SOAK" --policy policies/leak-default.json; echo "exit=$?"
```

Expected `exit=0` (no finding). Exit 3 means the steady phase was too short to judge; rerun the
soak with `--phase steady=60`. Now produce an ABBA comparison. Run five interleaved pairs with
the benchmark scenario, varying one knob so the two arms are distinguishable, then compare them
under the synthetic policy; the plan command can also produce the interleaving for you, but the
explicit form shows what the comparison needs.

```bash
for i in 1 2 3 4 5; do
  "$K" run synthetic/table/benchmark/append-throughput --dim pg.durability=durable --set load.rate-per-second=200 --out runs/cmp/a$i
  "$K" run synthetic/table/benchmark/append-throughput --dim pg.durability=durable --set load.rate-per-second=220 --out runs/cmp/b$i
  "$K" run synthetic/table/benchmark/append-throughput --dim pg.durability=durable --set load.rate-per-second=220 --out runs/cmp/b$i-2
  "$K" run synthetic/table/benchmark/append-throughput --dim pg.durability=durable --set load.rate-per-second=200 --out runs/cmp/a$i-2
done
"$K" compare \
  $(for i in 1 2 3 4 5; do echo --baseline $(ls -d runs/cmp/a$i/*/) --candidate $(ls -d runs/cmp/b$i/*/); done) \
  --vary knob:load.rate-per-second --policy policies/synthetic-compare.json --out runs/comparison.json; echo "exit=$?"
jq -r '.verdict' runs/comparison.json
```

Use the real load knob names from `Kenshou.Measure.Knobs.loadKnobs` if they differ from
`load.rate-per-second`; `"$K" list --json` shows every knob with its default. Expected: exit 0
and a `pass` verdict, or exit 3 with `inconclusive` when the two rates are too close for the
confidence interval, which is acceptable evidence that the comparison ran; a usage error (exit 2)
or infrastructure failure (exit 4) is not. Finally record one passing run into a scratch bundle
outside the repository. If EP-6 has created `docs/verification`, copy it; otherwise initialise a
bundle from the published verification-evidence profile the way the consumer's
`docs/verification/profile.dhall` does (it imports `assurance.verificationEvidence` from
`mori://shinzui/okf-profiles`), using `okf profile init` and `okf validate` on the scratch
directory.

```bash
SCRATCH=$(mktemp -d)
if [ -d docs/verification ]; then cp -R docs/verification "$SCRATCH/bundle"; else okf profile init "$SCRATCH/bundle" --profile docs/verification/profile.dhall; fi
"$K" record "$RUN" --bundle "$SCRATCH/bundle" --store-root "$SCRATCH/store" \
  --data-base-uri gs://kenshou-local/synthetic --purpose investigation --allow-dirty --json; echo "exit=$?"
okf validate "$SCRATCH/bundle" --strict
```

Expected: `record` exits 0 and prints one `kenshou.record-result/v1` document whose `subject`
is `mori://shinzui/kenshou` and whose record path is under `runs/synthetic/`; a second identical
invocation reports `already recorded`; `okf validate` passes. If `record` insists on
`--project`, run `"$K" help evidence` and pass the flag the current help text requires for a
store-root rehearsal.

For M4, create the guard. `scripts/coupling-guard.sh`:

```bash
#!/usr/bin/env bash
# Fail when a generic harness package names a consumer runtime layer.
set -euo pipefail
cd "$(dirname "$0")/.."
packages=(kenshou-core kenshou-check kenshou-measure kenshou-diagnose kenshou-telemetry kenshou-evidence kenshou-remote kenshou-cli)
pattern='keiro|kiroku|pgmq|shibuya|kafka'
targets=()
for p in "${packages[@]}"; do
  targets+=("$p/$p.cabal")
  [ -d "$p/src" ] && targets+=("$p/src")
  [ -d "$p/test" ] && targets+=("$p/test")
done
# consumer-records holds verbatim consumer evidence kept by EP-4; it is the only directory-level exemption.
hits=$(grep -riE "$pattern" --exclude-dir=consumer-records --include='*.hs' --include='*.cabal' --include='*.json' --include='*.md' "${targets[@]}" || true)
remaining=$(printf '%s\n' "$hits" | sed '/^$/d' | grep -vFxf scripts/coupling-allowlist.txt || true)
if [ -n "$remaining" ]; then
  echo "coupling-guard: layer names found in generic packages:" >&2
  printf '%s\n' "$remaining" >&2
  exit 1
fi
echo "coupling-guard: clean"
```

`scripts/coupling-allowlist.txt` holds one exact `path:text` line per permitted match, copied
verbatim from the guard's output, for example the EP-3 compatibility reader that still accepts
the old `kafka` field, and nothing else; the directory
`kenshou-evidence/test/fixtures/consumer-records/` of verbatim consumer records kept by EP-4 is
excluded by the script itself and is the only directory-level exemption. Every line added later needs a review that explains
why the text is generic. `scripts/plan-check.sh`:

```bash
#!/usr/bin/env bash
# Fail when the resolved cabal plan contains a consumer layer package or runtime migration library.
set -euo pipefail
cd "$(dirname "$0")/.."
cabal build all --dry-run >/dev/null
forbidden='^(kenshou-(pgmq|kiroku|shibuya|kafka|keiro|runtime)|keiro-migrations|kiroku-store-migrations|pgmq-migration)$'
found=$(jq -r '."install-plan"[] | ."pkg-name"' dist-newstyle/cache/plan.json | sort -u | grep -E "$forbidden" || true)
if [ -n "$found" ]; then
  echo "plan-check: forbidden packages in build plan:" >&2
  printf '%s\n' "$found" >&2
  exit 1
fi
echo "plan-check: clean"
```

Add the recipes to the `justfile` and extend `verify`:

```text
[group('boundary')]
coupling-check:
    bash scripts/coupling-guard.sh

[group('boundary')]
plan-check:
    bash scripts/plan-check.sh
```

Then prove the guard bites and restore the tree:

```bash
chmod +x scripts/coupling-guard.sh scripts/plan-check.sh
just coupling-check && just plan-check
echo '-- kiroku' >> kenshou-core/src/Kenshou/Core/Id.hs
just coupling-check; echo "exit=$?"
git checkout -- kenshou-core/src/Kenshou/Core/Id.hs
just verify
```

Expected: the first `coupling-check` and `plan-check` print `clean`; after the injected comment
the guard prints the offending `path:text` line and `exit=1`; after the checkout, `just verify`
runs every recipe including the two new ones and exits 0.


## Validation and Acceptance

Required acceptance, all from a clean checkout inside `nix develop`:

`cabal build all` succeeds, and `scripts/plan-check.sh` reports a clean plan, which is the
master plan's "no layer package in the build plan" criterion (IR-1 acceptance criterion AC-5).
`kenshou list --layer synthetic` prints exactly five scenarios and the `synthetic/writer`,
`synthetic/reader`, `synthetic/contender`, and `synthetic/echo-client` roles. Each of the five
scenarios, run as shown in Concrete Steps, exits 0 and writes a run directory with
`manifest.json` present. The correctness run's `run-result.json` lists held verdicts for
`no-loss`, `per-key-order`, `duplicates`, `eventual-quiescence`, and `ledger-versus-oracle`,
and its `logs/pids.jsonl` shows at least `kill.count` plus one writer incarnations.
`kenshou plan --graph-check` exits 0 and `kenshou plan --changed synthetic-table` selects only
`synthetic/table/**` scenarios. `kenshou diagnose leak` on a soak run of at least 30 s steady
phase exits 0. `kenshou compare` over five interleaved pairs under
`policies/synthetic-compare.json` exits 0 or 3, never 2 or 4, and writes a
`kenshou.comparison/v1` document. `kenshou record` writes a record with subject
`mori://shinzui/kenshou` into a scratch bundle that `okf validate --strict` accepts.
`scripts/coupling-guard.sh` reports clean on the committed tree and fails on an injected layer
name (IR-1 acceptance criteria AC-1 and AC-2, as far as a textual guard can establish them;
the registered synthetic layer is the AC-2 witness). `just verify` is green with both new
recipes in it, and CI runs them.

The early representative check for the uncertain interfaces is the M1 run itself: it is the
first consumer of EP-2's migration-set registration and EP-4's oracle field together, and the
M2 echo round-trip is the first consumer of EP-3's resource provisioner from a worker process.
Run those two before expanding the remaining scenarios; a failure there is a boundary defect to
report to the owning plan, not something to work around in the suite.

Proposed, not required: a `kenshou attest` of the recorded run reaching `confirmed` through the
registered oracle, and a cell placement of the echo resource. Both are worth a Surprises &
Discoveries note if attempted; neither gates this plan.


## Idempotence and Recovery

Every step is safe to repeat. Scenario runs create fresh run directories under `runs/` (which
is untracked; add it to `.gitignore` if EP-1 has not) and provision a fresh ephemeral
PostgreSQL per run, so a failed run leaves nothing to clean except the directory. Worker
processes are supervised in their own process group and killed on scenario exit; if a run is
interrupted with `Ctrl-C`, `Kenshou.Check.Process.sweepOrphans` is run by the next scenario
start, and `pgrep -f 'kenshou worker'` shows anything left behind. The echo resource binds an
ephemeral port chosen by the operating system, so two runs never collide. The comparison and
record steps read sealed run directories and never modify them; delete `runs/cmp` and the
scratch directory to start over. The coupling guard and plan check are read-only. The injected
comment in the M4 proof is reverted with `git checkout`; if you forget, `just verify` fails on
the guard and tells you which line. The migration set is applied by the kernel to a fresh
database on every run, so changing the schema during development needs no manual migration.


## Interfaces and Dependencies

This plan starts only after EP-2, EP-3, and EP-4 are Complete in the master plan registry, and
it builds on the `kenshou-synthetic` package, the `justfile` `verify` recipe, and the CI
workflow that EP-1 created. EP-6 is a soft dependency: its `docs/verification` bundle, when
present, is the source of the scratch bundle copy, and its ADRs are cited from this plan once
they exist.

From the kernel (`kenshou-core`) the suite uses `Kenshou.Core.Bundle.LayerBundle` and
`mkRegistry`, `Kenshou.Core.Scenario.Scenario` and the report constructors,
`Kenshou.Core.Context.RunContext` with `requirePostgres`, `putSummary`, and `artifactPath`,
`Kenshou.Core.Role` (`WorkerRole`, `RoleContext`, `ControlMessage`, `WorkerMessage`,
`mkRoleName`), `Kenshou.Core.Role.Spawn.withWorker` for the echo client, `Kenshou.Core.Knob`
for knob specs, `Kenshou.Core.Dimension` for durability and telemetry support, and
`Kenshou.Core.Env` for the environment requirement. The following extension points were
introduced by earlier plans and their exact field and function names are defined there: the open
layer identifier and its constructor (EP-2, used for the `synthetic` layer and in every scenario
identifier through `parseScenarioId`); the bundle's suite-supplied migration set and the
environment requirement's migration component reference (EP-2); the component-graph data hook
that replaces the embedded `kenshou-core/data/components.json` (EP-2); the named resource
requirement, the local provisioner interface, and the resource block that reaches
`Kenshou.Core.Role.WorkerInit` (EP-3); and the bundle's oracle, lock label, and evidence subject
fields (EP-4). At drafting time those plans fixed these names, which this plan uses unless
the implemented code differs: `Kenshou.Core.Id.LayerId` with `mkLayerId` and
`selftestLayer`; `Kenshou.Core.Bundle.mkBundle :: LayerId -> [Scenario] -> [WorkerRole] ->
LayerBundle` with the fields `migrations :: [MigrationSet]`, `rules :: [ScenarioRule]`,
`resources :: [ResourceProvider]`, `oracles`, `advisoryLabels`, `methodology`,
`evidenceSubject :: Maybe Text`, and `routingRules`; `Kenshou.Core.Env.MigrationSet` with
`name`, `requires`, and `component`; `Kenshou.Core.Resource` with `ResourceName`,
`ResourceProvider {name, summary, normalize, withLocal, cell}`, and `ProvisionedResource`;
`Kenshou.Core.Contribution` with `OracleSpec`, `AdvisoryLabel`, `PoolMethodology`, and
`RoutingRule`; and `Kenshou.Core.Cli.Program` with `componentGraph :: ByteString`. From
`kenshou-check` the suite uses `Kenshou.Check.Scenario` (`withCheck`,
`finishWithVerdicts`), `Kenshou.Check.Ledger` (`record`, `recordDurable`, `sealLedger`),
`Kenshou.Check.Ledger.Read` (`discoverLedgers`, `loadWindows`), `Kenshou.Check.Invariant`
(`runCheckers`, `noLoss`, `perKeyOrder`, `duplicatesWithin`, `disjointOwnership`,
`eventualQuiescence`), `Kenshou.Check.Oracle` (`OracleQuery`, `ItemRef`, `runOracle`,
`reconcile`), `Kenshou.Check.Process` (`withSupervisor`, `roleProcess`, `spawn`, `awaitReady`,
`sendCommand`, `killChild`, `restartChild`, `stopGracefully`, `crashWindows`,
`readChildMessages`), and `Kenshou.Check.Fault.Postgres.terminateOneBackend`. From
`kenshou-measure` it uses `Kenshou.Measure.Knobs` (`loadKnobs`, `measureKnobs`,
`loadModelFromKnobs`), `Kenshou.Measure.Session` (`measureConfigFromKnobs`,
`phasePlanFromCore`, `withMeasurement`, `measuredOutcome`), `Kenshou.Measure.Load` (`runLoad`,
`Operation`, `LoadModel`), and `Kenshou.Measure.Recorder` (`OpName`, `OpResult`). From
`kenshou-diagnose` it uses the `AdvisoryLabel` type in `Kenshou.Diagnose.Postgres`. Database
access uses `hasql` and `hasql-pool` directly, as the consumer's suites do; migrations use
`pg-migrate`'s `MigrationComponent`; the echo server uses `network` and `async`. The executable
`kenshou-synthetic/app/Main.hs` calls `Kenshou.Cli.mainWith` (EP-1) with a `CliAssembly`,
which after EP-2 is the kernel's `Program` record, built from `selfTestAssembly` by appending
`Kenshou.Suite.Synthetic.bundle` to its bundles and replacing its component graph with the
synthetic one.
The `kenshou-synthetic.cabal` `build-depends` for the library must be exactly: `base`,
`aeson`, `async`, `bytestring`, `containers`, `hasql`, `hasql-pool`, `network`, `pg-migrate`,
`random`, `stm`, `text`, `time`, `vector`, and the generic packages `kenshou-core`,
`kenshou-check`, `kenshou-measure`, `kenshou-diagnose`, and `kenshou-cli`; anything else is a
sign that the suite is reaching past the boundary.
