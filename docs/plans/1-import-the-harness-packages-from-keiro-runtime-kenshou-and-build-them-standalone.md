---
id: 1
slug: import-the-harness-packages-from-keiro-runtime-kenshou-and-build-them-standalone
title: "Import the harness packages from keiro-runtime-kenshou and build them standalone"
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

# Import the harness packages from keiro-runtime-kenshou and build them standalone

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

Today this repository has Nix tooling, a Mori registration, and plans, but no Haskell code. The
generic verification harness it is meant to publish lives inside the Keiro runtime's
verification suite, `mori://shinzui/keiro-runtime-kenshou`, next to five packages that verify
specific runtime layers. After this plan, a maintainer can clone this repository, enter
`nix develop`, run `cabal build all`, and get eight library packages plus one executable
named `kenshou` that lists and runs the harness's own self-test scenarios, writes the same
versioned run documents the Keiro suite writes, and passes every unit test, with no
`kenshou-pgmq`, `kenshou-kiroku`, `kenshou-shibuya`, `kenshou-kafka`, `kenshou-keiro`, or
`kenshou-runtime` package anywhere in the build plan. The proof is a `just verify` run that
builds, tests, checks formatting, validates the JSON schemas, and fails if any of those six
names appears in Cabal's resolved plan.

This plan deliberately does not remove the layer names that remain inside the imported code.
The kernel still links three migration libraries from Hackage, still has a closed `Layer`
type, and still has Kafka-shaped environment fields. Those are the work of the plans that
follow (`docs/plans/2-…`, `docs/plans/3-…`, and `docs/plans/4-…`). What this plan proves is
narrower and comes first: the generic packages build and run on their own.


## Progress

Use checkboxes for verifiable milestones or substantial deliverables, not individual
edits, commands, tests, commits, or session activity. Update this section when a milestone
is accepted, a material blocker or change of course arises, or work is handed off. For a
handoff during a milestone, add a short prose note stating the remaining outcome.

- [ ] M1: the workspace scaffold builds. `cabal.project`, `flake.module.nix`, `justfile`, and
  `docs/import-provenance.md` exist, `nix develop` enters a shell with GHC 9.12.4, and
  `cabal build all` succeeds on a placeholder package.
- [ ] M2: the seven generic packages are imported at the pinned revision and
  `cabal build kenshou-core kenshou-check kenshou-measure kenshou-diagnose kenshou-telemetry
  kenshou-evidence kenshou-remote` succeeds.
- [ ] M3: `kenshou-cli` builds as a library that takes its registry from the caller, and the
  `kenshou` executable in `kenshou-synthetic` lists only `selftest/…` scenarios and runs
  `selftest/kernel/correctness/always-pass` to a sealed run directory.
- [ ] M4: `just verify` passes: unit tests, formatting, schema checks, the self-test
  recipe, and the plan check that proves no layer package is in the build plan; the CI
  workflow runs the same gate on push.


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence. Friction with the tools, documents, and processes
used to do the work belongs in the friction log (see FRICTION.md); cite an entry's FRIC-N
handle here only when it also changed the plan.

(None yet.)


## Decision Log

Record decisions that change scope, architecture, interfaces, acceptance, or the path a
future contributor should follow. Omit routine implementation choices.

- Decision: Import the packages with `git archive` from the pinned consumer commit rather
  than with a history-preserving subtree or filter.
  Rationale: The pinned commit hash in `docs/import-provenance.md` is the provenance that
  matters for the divergence audit in `docs/plans/7-…`; carrying the consumer's history into
  this repository would bring thousands of commits about layer packages that this repository
  does not contain.
  Date: 2026-10-28

- Decision: The generic CLI library exposes an assembly record (bundles, commands, help
  topics) that the executable supplies, and ships a ready-made self-test assembly.
  Rationale: Today `Kenshou.Cli.Registry` is a fixed list that names layer packages. A value
  the executable passes in is the smallest change that lets `kenshou-synthetic` here and the
  Keiro suite later link different suites against one library, and it is already how
  `Kenshou.Core.Cli.runCli` is shaped.
  Date: 2026-10-28

- Decision: Keep every package at version `0.1.0.0` and keep every package name and module
  name unchanged.
  Rationale: Versioning for publication is decided in `docs/plans/7-…`; names are fixed by
  the MasterPlan so the first consumer adopts the release without import churn.
  Date: 2026-10-28


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Cite the friction entries recorded under
this plan by handle with their triage outcome. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

(To be filled during and after implementation.)


## Context and Orientation

This repository is `mori://shinzui/kenshou`, checked out at `/Users/shinzui/Keikaku/bokuno/kenshou`.
At the start of this plan it contains the seihou-managed Nix tooling (`flake.nix`,
`flake.lock`, `nix/haskell.nix`, `nix/treefmt.nix`, `nix/pre-commit.nix`, `fourmolu.yaml`,
`process-compose.yaml`, `.envrc`), `mori.dhall`, `mina.kdl`, the agent skills under
`agents/skills/`, and the planning documents under `docs/`. The Nix module was generated with
`nix.builtin-package=false`, which means `nix/haskell.nix` does not define a package output
and expects the unmanaged `flake.module.nix` to define every package; `flake.module.nix.example`
shows the pattern. There is no `cabal.project`, no `.cabal` file, no `justfile`, and no
`.github/` directory yet. The dev shell provides GHC 9.12.4, `cabal`, HLS, PostgreSQL 18,
`process-compose`, `just`, and the formatters wired into `nix fmt`.

The source of everything this plan imports is the Keiro runtime's verification suite,
`mori://shinzui/keiro-runtime-kenshou`, checked out at
`/Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou`. Every copy in this plan is taken from
commit `a1648293443ad88ff1695ed800ff44c99993574e` (2026-10-12, "fix(perf): prepare isolated
Shibuya cohorts without runtime dependencies"), never from that checkout's working tree, so
the import is reproducible even if that repository moves on. That repository is one Cabal
project with fourteen packages. Seven of them are generic and are imported here whole:

`kenshou-core` is the kernel. It owns the versioned JSON documents every other package reads
and writes (run specification, run result, artifact manifest, scenario list, worker
initialization and messages, run plan, suite, plan summary, cohort identity), the scenario
and role model (`Kenshou.Core.Scenario`, `Kenshou.Core.Role`), the registry of layer bundles
(`Kenshou.Core.Bundle`), the environment model and PostgreSQL provisioning
(`Kenshou.Core.Env`, `Kenshou.Core.Env.Postgres`, `Kenshou.Core.Env.Migration`), knobs and
dimensions, the change-aware planner (`Kenshou.Plan.*`), the performance-preparation
documents (`Kenshou.Perf.*`), and the kernel self-test scenarios (`Kenshou.Core.Selftest`).
`kenshou-check` is the correctness toolkit (fact ledgers, invariants, fault injection, process
control, linearizability). `kenshou-measure` is the measurement toolkit (load generators,
samplers, histograms, paired comparison). `kenshou-diagnose` is the diagnostics toolkit (heap
leak verdicts, stall capture). `kenshou-telemetry` holds the telemetry arms and overhead
reports. `kenshou-evidence` holds immutable run records and attestation. `kenshou-remote`
holds leased verification cells, payload publishing, and object stores. Each of these has a
`src/` tree, a `test/` tree with golden files and fixtures, and a `.cabal` file with
`default-language: GHC2024` and a shared warning set; `kenshou-check` also has a
`fixture/` directory with a worker executable its tests spawn, and `kenshou-measure` has
`cbits/` with one C file used on macOS.

The eighth package, `kenshou-cli`, is only partly generic. Its library holds the operator
commands (`Kenshou.Cli.Command.*`: list, plan, run, execute, worker, cell, perf, overhead,
cohort), help topics embedded from `kenshou-cli/help/*.md`, completions, configuration, and
the attestation recomputers in `Kenshou.Cli.Attest`. Three parts are not generic and stay
behind: the twelve `Kenshou.Cli.Attest.Keiro*` modules and the Keiro and Kafka branches of
`runOutcomeRecomputer` in `Kenshou.Cli.Attest`, the `runtime-suites` Cabal flag with its
layer dependencies and the `kenshou-linkproof` test suite, and the fixed registry in
`Kenshou.Cli.Registry` that imports `Kenshou.Suite.Shibuya` and, under the flag, the other
five layer packages. The `kenshou` executable itself is three lines in `kenshou-cli/app/Main.hs`
that call `Kenshou.Cli.main`.

Two terms recur below. A *layer* is one runtime component under verification (for example
PGMQ or Keiro) and the kernel today names the possible layers in a closed type,
`Kenshou.Core.Id.Layer`, whose values are `Selftest`, `Pgmq`, `Kiroku`, `Shibuya`, `Kafka`,
`Keiro`, and `Runtime`. A *layer bundle* (`Kenshou.Core.Bundle.LayerBundle`) is the value a
suite registers: a layer, its scenarios, and its worker roles; `Kenshou.Core.Cli.runCli`
takes a list of bundles, a list of commands, and a list of help topics, builds the registry,
and dispatches the command line. The self-test bundles are the ones the toolkits define for
themselves: `Kenshou.Core.Selftest.bundle`, `Kenshou.Measure.Selftest.bundle`,
`Kenshou.Check.Selftest.bundle`, `Kenshou.Diagnose.SelfTest.bundle`,
`Kenshou.Telemetry.SelfTest.selfTestBundle`, and `Kenshou.Remote.Selftest.bundle`. All of
them use the `selftest` layer, so an executable that registers only these six lists only
`selftest/…` scenario identifiers.

What still names layers after this plan, and is left for later plans, must be stated so the
reader is not surprised. `Kenshou.Core.Id.Layer` stays closed. `Kenshou.Core.Env.Migration`
still imports `keiroMigrations`, `kirokuMigrations`, and `pgmqMigrations`, so
`kenshou-core.cabal` still depends on `keiro-migrations`, `kiroku-store-migrations`, and
`pgmq-migration`, and the `keiro-schema` flag stays. `Kenshou.Core.Env.EnvRequirements`
still has a `kafka :: Bool` field, and `Kenshou.Core.Role`, `Kenshou.Core.RunSpec`,
`Kenshou.Core.Compat`, `Kenshou.Core.Role.Spawn`, and `Kenshou.Check.Process` still thread
it. `Kenshou.Core.Cli` and `Kenshou.Cli.Options` still print the header
`kenshou - verify the Keiro runtime`. `Kenshou.Core.Selftest`'s `postgres-roundtrip` scenario
still asserts that the `kiroku`, `keiro`, and `pgmq` schemas exist. `Kenshou.Check.Oracle.
{Keiro,Kiroku,Pgmq}`, `Kenshou.Measure.Methodology`, `Kenshou.Diagnose.Postgres`,
`Kenshou.Evidence.Record`, `Kenshou.Evidence.History`, `Kenshou.Remote.Cell.RouteRules`,
`Kenshou.Remote.Cell.Exec`, `Kenshou.Remote.Cell.Prepare`, and `Kenshou.Remote.Selftest`
keep their layer-specific content. `kenshou-core/data/components.json`, the embedded
component graph the planner reads, describes the Keiro cohort, and `Kenshou.Perf.Plan` and
`Kenshou.Perf.Prepared` name Shibuya scenarios and the isolated Shibuya cohort. The
`kenshou perf prepare` command additionally assumes the consumer's repository layout
(`cohort/*.json`, `scripts/payload-lock.sh`, `nix/cohort-locks/`); this plan copies it
unchanged and does not exercise it. Golden files under `kenshou-core/test/golden/perf-*.json`
and some `kenshou-remote` and `kenshou-evidence` test fixtures contain layer names as data;
they are copied unchanged because the tests that read them are generic.

No local ADR exists yet; `docs/adr/` is created by `docs/plans/6-…`. The cross-repository
decisions that bound this plan are `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-1`
(layer packages never import one another, which is why the seven packages have no layer
dependency to cut), `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3` (the kernel
owns the versioned protocol documents, so nothing copied here may change a document shape),
and `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-2` (every result carries a
resolved cohort identity, which the imported `Kenshou.Core.Cohort` derives from Cabal's
`plan.json`; this plan keeps that behavior and uses the same `plan.json` for its own check).


## Plan of Work

Milestone 1 establishes the workspace. Create `cabal.project` at the repository root with
`packages: kenshou-*/*.cabal`, `with-compiler: ghc-9.12.4`, `tests: True`,
`test-show-details: direct`, and `index-state: 2026-09-20T13:44:47Z`, which is the index
state the consumer's released cohort uses, so the solver sees the same Hackage releases. Add
exact constraints for the Hackage packages the kernel and toolkits bind narrowly and that the
consumer pins: `keiro-migrations ==0.17.0.0`, `kiroku-store-migrations ==0.4.0.0`,
`pgmq-migration ==0.6.1.0`, `pg-migrate ==1.1.0.0`, `ephemeral-pg ==0.3.1.0`, and the seven
`hs-opentelemetry-*` packages at `1.0.0.0`. If the solver asks for more, add exact
constraints and say why in a comment; never add a blanket `allow-newer`. Copy
`flake.module.nix.example` to `flake.module.nix` and replace its body with a module that adds
`pkgs.git`, `pkgs.jq`, `pkgs.check-jsonschema`, and `pkgs.dhall` to
`haskellProject.extraDevPackages`, sets `treefmt.programs.fourmolu.package` to
`pkgs.haskell.packages.ghc9124.fourmolu`, and exports `KENSHOU_PG18_BIN` (pointing at
`pkgs.postgresql_18`) and `KENSHOU_PG17_BIN` (pointing at `pkgs.postgresql_17`) through a
setup hook exactly as the consumer's `flake.module.nix` does, because
`Kenshou.Core.Env.Postgres` resolves the `pg.major` dimension through those two variables.
Create `justfile` with the recipes named in Milestone 4, and create
`docs/import-provenance.md` stating the source project URI, the commit hash, the date, and
the list of imported paths. Put a one-package placeholder (any minimal `kenshou-synthetic`
with an executable that prints its version) in place so `cabal build all` has something to
build, then verify the shell and the build. Add `runs/`, `.dev/`, and `dist-newstyle/` to
`.gitignore` if the seihou module did not.

Milestone 2 imports the seven generic packages. Use `git archive` on the pinned commit to
extract `kenshou-core`, `kenshou-check`, `kenshou-measure`, `kenshou-diagnose`,
`kenshou-telemetry`, `kenshou-evidence`, and `kenshou-remote` into the repository root, and
extract `schemas/` and then delete the layer-specific schema files whose names begin with
`kenshou.inbox-`, `kenshou.outbox-`, `kenshou.queue-`, and the `kenshou.kafka-env.v1.json`
file; keep every other schema, including the `kenshou.perf-*`, `kenshou.cell-*`,
`kenshou.payload*`, and `kenshou.cohort*` families, and keep `schemas/README.md`. Extract
`policies/default.json`, `policies/selftest.json`, `policies/leak-default.json`, and
`policies/telemetry-overhead.json`, which are the generic comparison, leak, and overhead
policies, and all six files under `suites/`, which select by tier and kind and name no
layer. Do not extract `policies/cell-routing.json`, the `shibuya-*`, `pgmq`, and
`kafka-local-exploratory` policies, `policies/performance/`, `cohort/`, `scripts/`,
`docs/`, or any `kenshou-{pgmq,kiroku,shibuya,kafka,keiro,runtime}` directory. Do not edit
any imported Haskell source in this milestone. Build the seven packages; expect the solver to
pull `keiro-migrations`, `kiroku-store-migrations`, `pgmq-migration`, `pg-migrate`,
`ephemeral-pg`, `settei`, `okf-core`, `mmzk-typeid`, and the `hs-opentelemetry` family from
Hackage.

Milestone 3 imports and reshapes `kenshou-cli` and creates the executable. Extract
`kenshou-cli` from the pinned commit, then delete `kenshou-cli/linkproof/`, every
`kenshou-cli/src/Kenshou/Cli/Attest/Keiro*.hs`, `kenshou-cli/app/`, and the fixtures under
`kenshou-cli/test/fixtures/` whose names begin with `inbox-`, `outbox-`, `queue-`, or
`producer-identity-` (keep `perf-publication.synthetic.json`). Edit `kenshou-cli.cabal`:
remove the `runtime-suites` flag and its conditional block, remove `kenshou-shibuya` from
`build-depends`, remove the twelve `Attest.Keiro*` modules from `exposed-modules`, remove the
`executable kenshou` stanza and the `kenshou-linkproof` test suite, and keep the
`kenshou-cli-test` suite. Edit `Kenshou.Cli.Attest` so that `runOutcomeRecomputer` keeps
only the fallthrough to `Kenshou.Evidence.Attest.coreRecomputers`, and remove `FencingFacts`,
`fencingFacts`, `fencingRecomputation`, `releasedKafkaBinding`, and `readControlEvents`
together with the Keiro imports; keep `measurementRecomputer` and
`pairedComparisonRecomputer` unchanged. Edit `Kenshou.Cli.Command.Run` to drop the
`FULL_RUNTIME_SUITES` conditional: keep the branch in which `validateKafkaEnvironment`
accepts `Nothing` and rejects `Just _`, and change the rejection text to "no registered suite
provisions a Kafka environment in this build" so the message no longer names the isolated
Shibuya build. Rewrite `Kenshou.Cli.Registry` to export a record
`CliAssembly { bundles :: [LayerBundle], commands :: [CliCommand], topics :: [HelpTopic] }`,
a value `selfTestBundles :: [LayerBundle]` holding the six self-test bundles, a function
`standardCommands :: [Recomputer] -> [CliCommand]` that builds today's command list with
`attestCommandWith` applied to the given recomputers, a value `standardTopics :: [HelpTopic]`,
and a value `selfTestAssembly :: CliAssembly` that combines them with
`[runOutcomeRecomputer, measurementRecomputer, pairedComparisonRecomputer]`. Rewrite
`Kenshou.Cli.Main` to export `mainWith :: CliAssembly -> IO ()` and
`runWithArgsWith :: CliAssembly -> [String] -> IO ExitCode`, keeping the eventlog guard, the
optional ghc-debug hook, and the `--version` handling, and make `Kenshou.Cli` re-export
them. Trim `kenshou-cli/test/Main.hs` to the `performance planning CLI` and
`CLI exit contract` groups plus `PerfSessionSpec`, define a local
`runWithArgs = runWithArgsWith selfTestAssembly`, and replace the one selector that names
`keiro/outbox/soak/table-growth-reduced` with `selftest/kernel/correctness/always-pass` so
the "pinned knob absent from every selected scenario" test still selects a real scenario.
Then give `kenshou-synthetic` its real shape: a `kenshou-synthetic.cabal` with an
`executable kenshou` whose `app/Main.hs` is `main = Kenshou.Cli.mainWith selfTestAssembly`,
built with `-threaded -rtsopts "-with-rtsopts=-N -T"` like the consumer's executable, and
depending on `kenshou-cli` and `base`. The later plan `docs/plans/5-…` adds a library and
the synthetic bundle to this same package. Build everything and run the executable.

Milestone 4 closes the gate. Fill in the `justfile`: `verify` runs `fmt-check`,
`haskell-build`, `plan-check`, `haskell-test`, `schemas-check`, and `selftest`.
`haskell-test` runs the eight test suites by name (`kenshou-core:tests`,
`kenshou-check:test:kenshou-check-test`, and so on; the consumer's `justfile` lists the
exact names). `plan-check` reads `dist-newstyle/cache/plan.json` and fails if any package
named `kenshou-pgmq`, `kenshou-kiroku`, `kenshou-shibuya`, `kenshou-kafka`, `kenshou-keiro`,
or `kenshou-runtime` appears. `schemas-check` is the consumer's recipe reduced to the
goldens that were imported: drop every line that references a `kenshou-keiro`,
`kenshou-cli/test/fixtures/{inbox,outbox,queue}-*`, `nix/cohort-locks`, `policies/performance`,
or `policies/cell-routing.json` path, and keep the lines that validate kernel, measure,
diagnose, telemetry, remote, and evidence goldens and the live `list` and `run` documents.
The `evidence check` and `history` lines expect an OKF verification bundle at
`docs/verification`; until `docs/plans/6-…` decides whether this repository keeps such a
bundle, point them at a temporary directory through `KENSHOU_EVIDENCE_BUNDLE` and accept
exit code 1 from `evidence check` on an empty bundle only if the document it writes still
validates; if it does not validate, leave those two lines out and record the gap in
Surprises & Discoveries. `selftest` runs the kernel and check self-test scenarios the
consumer's recipe runs. Run `nix fmt` once and commit the reformat on its own, because
`cabal-gild` and `fourmolu` here may differ slightly from the consumer's pinned versions.
Add `.github/workflows/ci.yaml` modeled on the consumer's: install Nix with the shinzui
Cachix substituter, cache the Cabal store keyed on `cabal.project` and `**/*.cabal`,
`cabal update`, then `nix develop --command just verify`, then `nix flake check`. Finally
add `packages.kenshou-core`, `packages.kenshou-cli`, and `packages.kenshou-synthetic` to
`flake.module.nix` with `callCabal2nix` against a `pkgs.haskell.packages.ghc9124` set
overridden with `inputs.haskell-nix.lib.haskellExtension`, passing the sibling packages
explicitly as the consumer does, and build one of them with `nix build`.


## Concrete Steps

Extract the pinned sources. Run from the consumer checkout so `git archive` sees the commit;
the destination is this repository. The `--prefix` is empty so paths land at the root.

```bash
cd /Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou
git archive a1648293443ad88ff1695ed800ff44c99993574e \
  kenshou-core kenshou-check kenshou-measure kenshou-diagnose \
  kenshou-telemetry kenshou-evidence kenshou-remote kenshou-cli \
  schemas suites \
  policies/default.json policies/selftest.json policies/leak-default.json policies/telemetry-overhead.json \
  | tar -x -C /Users/shinzui/Keikaku/bokuno/kenshou
cd /Users/shinzui/Keikaku/bokuno/kenshou
rm -f schemas/kenshou.inbox-*.json schemas/kenshou.outbox-*.json schemas/kenshou.queue-*.json schemas/kenshou.kafka-env.v1.json
rm -rf kenshou-cli/linkproof kenshou-cli/app kenshou-cli/src/Kenshou/Cli/Attest
rm -f kenshou-cli/test/fixtures/inbox-*.json kenshou-cli/test/fixtures/outbox-*.json \
      kenshou-cli/test/fixtures/queue-*.json kenshou-cli/test/fixtures/producer-identity-*.json
```

Note that removing `kenshou-cli/src/Kenshou/Cli/Attest/` removes only the `Keiro*` modules;
`Kenshou/Cli/Attest.hs` is a sibling file and stays. Record the import:

```bash
cd /Users/shinzui/Keikaku/bokuno/kenshou
cat > docs/import-provenance.md <<'EOF'
# Import provenance

The packages `kenshou-core`, `kenshou-check`, `kenshou-measure`, `kenshou-diagnose`,
`kenshou-telemetry`, `kenshou-evidence`, and `kenshou-remote`, the generic modules of
`kenshou-cli`, the generic JSON schemas under `schemas/`, the suites under `suites/`, and
four generic policies under `policies/` were copied from
`mori://shinzui/keiro-runtime-kenshou` at commit
`a1648293443ad88ff1695ed800ff44c99993574e` (2026-10-12) by
`docs/plans/1-import-the-harness-packages-from-keiro-runtime-kenshou-and-build-them-standalone.md`.
Compare against that commit, not against the consumer's head, when auditing divergence.
EOF
```

Write `cabal.project`:

```text
-- One cabal project. A plan adds a package by creating
-- kenshou-<name>/kenshou-<name>.cabal; nobody edits this list.
packages: kenshou-*/*.cabal
with-compiler: ghc-9.12.4
tests: True
test-show-details: direct

-- Same Hackage snapshot as the first consumer's released cohort
-- (mori://shinzui/keiro-runtime-kenshou, cohort/released.project).
index-state: 2026-09-20T13:44:47Z

-- Exact pins for the narrowly bound Hackage packages. The three migration
-- libraries are removed by docs/plans/2-….
constraints:
  keiro-migrations ==0.17.0.0,
  kiroku-store-migrations ==0.4.0.0,
  pgmq-migration ==0.6.1.0,
  pg-migrate ==1.1.0.0,
  ephemeral-pg ==0.3.1.0,
  hs-opentelemetry-api ==1.0.0.0,
  hs-opentelemetry-sdk ==1.0.0.0,
  hs-opentelemetry-propagator-w3c ==1.0.0.0,
  hs-opentelemetry-exporter-in-memory ==1.0.0.0,
  hs-opentelemetry-exporter-otlp ==1.0.0.0,
  hs-opentelemetry-exporter-prometheus ==1.0.0.0,
  hs-opentelemetry-otlp ==1.0.0.0
```

Build and list the scenarios. The first `cabal update` is needed because the index state is
pinned; subsequent runs reuse the cache.

```bash
cd /Users/shinzui/Keikaku/bokuno/kenshou
nix develop --command cabal update
nix develop --command cabal build all
nix develop --command cabal run -v0 kenshou -- list
```

Expected output of the last command, abbreviated: every line begins with `selftest/`, for
example `selftest/kernel/correctness/always-pass`, `selftest/kernel/concurrency/worker-echo`,
`selftest/check/correctness/ledger-detects-loss-dup-reorder`, and
`selftest/measure/…`, `selftest/diagnose/…`, `selftest/telemetry/…`, and `selftest/remote/…`
identifiers; no line begins with `pgmq/`, `kiroku/`, `shibuya/`, `kafka/`, `keiro/`, or
`runtime/`.

Run one scenario to a run directory and inspect it:

```bash
cd /Users/shinzui/Keikaku/bokuno/kenshou
tmp=$(mktemp -d)
nix develop --command cabal run -v0 kenshou -- run selftest/kernel/correctness/always-pass --out "$tmp"
ls "$tmp"/*/
```

Expected: the listing shows `run-spec.json`, `run-result.json`, and `manifest.json` in one
run directory, and the `run` command exits 0.

Prove the build plan. The `plan-check` recipe in `justfile` is:

```text
[group('verification')]
plan-check:
    cabal build all --dry-run >/dev/null
    jq -r '.["install-plan"][]["pkg-name"]' dist-newstyle/cache/plan.json | sort -u | grep -E '^kenshou-' 
    ! jq -r '.["install-plan"][]["pkg-name"]' dist-newstyle/cache/plan.json | grep -qE '^kenshou-(pgmq|kiroku|shibuya|kafka|keiro|runtime)$'
```

Expected output of `just plan-check`: exactly the nine names `kenshou-check`, `kenshou-cli`,
`kenshou-core`, `kenshou-diagnose`, `kenshou-evidence`, `kenshou-measure`, `kenshou-remote`,
`kenshou-synthetic`, `kenshou-telemetry`, and exit code 0.

Run the whole gate:

```bash
cd /Users/shinzui/Keikaku/bokuno/kenshou
nix develop --command just verify
```


## Validation and Acceptance

M1 is accepted when `nix develop --command cabal build all` succeeds with the placeholder
package and `docs/import-provenance.md` names the commit above.

M2 is accepted when `cabal build kenshou-core kenshou-check kenshou-measure
kenshou-diagnose kenshou-telemetry kenshou-evidence kenshou-remote` succeeds without editing
any imported source file, which `git diff --stat` after the build confirms by showing only
the files this plan creates.

M3 is accepted when `cabal run -v0 kenshou -- list` prints only `selftest/…` identifiers,
`cabal run -v0 kenshou -- run selftest/kernel/correctness/always-pass --out <dir>` exits 0
and writes `run-spec.json`, `run-result.json`, and `manifest.json`, and
`cabal run -v0 kenshou -- --version` prints a version with a git hash.

M4 is accepted when `just verify` exits 0 in `nix develop`, which means all eight unit test
suites pass, `nix fmt -- --fail-on-change` reports no change, every schema line validates,
the self-test recipe's scenarios pass with the expected exit codes (`always-fail` exits 1
and `errors` exits 4), and `just plan-check` prints the nine package names; and when the CI
workflow on the pushed commit is green. The `kenshou-core` tests start real PostgreSQL
servers through `ephemeral-pg`, so they need `initdb` and `pg_ctl` on the path, which the
dev shell provides; outside the shell they fail with a missing-executable error, which is
not a defect in this plan.

The representative interaction check for the interface this plan introduces is the
`kenshou-cli` test suite itself: it links the library through `runWithArgsWith
selfTestAssembly`, exactly as `kenshou-synthetic` does, so a change that breaks the assembly
hand-off fails the tests before it reaches the executable.


## Idempotence and Recovery

Extracting with `git archive … | tar -x` overwrites files with the pinned content and is
safe to repeat at any time before the edits in Milestone 3; after those edits, re-extracting
`kenshou-cli` would revert them, so re-extract only the seven untouched packages if a copy is
suspected to be corrupt, and compare with `git diff`. Every step is a file write in this
repository, so `git checkout -- <path>` or `git clean -fd <path>` recovers any state. The
solver cache under `dist-newstyle/` can be deleted freely. If the index state cannot be
reached because the local Hackage index is older, `cabal update` fixes it; do not move the
index state to work around it.


## Interfaces and Dependencies

This plan has no prerequisite plan. It depends on the seihou-managed Nix tooling already in
the repository and on the pinned consumer commit being reachable in the local checkout at
`/Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou`.

The interfaces later plans build on are these. `Kenshou.Cli.Registry` in `kenshou-cli`
exports `CliAssembly`, `selfTestBundles`, `standardCommands`, `standardTopics`, and
`selfTestAssembly`; `Kenshou.Cli.Main` (re-exported by `Kenshou.Cli`) exports
`mainWith :: CliAssembly -> IO ()` and `runWithArgsWith :: CliAssembly -> [String] -> IO
ExitCode`. The attestation recomputers a consumer wants beyond the three generic ones are
passed through `standardCommands`; the Keiro suite will supply its own `runOutcomeRecomputer`
there at adoption. `kenshou-synthetic` owns the `kenshou` executable; `docs/plans/5-…` adds a
library and a synthetic `LayerBundle` to it and extends the assembly. `docs/plans/2-…` edits
`kenshou-core` in place and removes the three migration constraints from `cabal.project`.
`justfile`'s `verify` recipe is the gate every later plan extends; `docs/plans/5-…` adds the
coupling guard to it. `docs/import-provenance.md` is the input to the divergence audit in
`docs/plans/7-…`.

Hackage dependencies whose choice matters: `pg-migrate 1.1.0.0` (the kernel accepts 1.1 or
1.2, but `keiro-migrations 0.17.0.0` and `pgmq-migration 0.6.1.0` bound it to 1.1),
`ephemeral-pg 0.3.1.0`, `settei 0.2`, `okf-core 0.9`, and the `hs-opentelemetry` family at
`1.0.0.0`. The Nix package outputs resolve those through `inputs.haskell-nix`'s extension,
the same registry the consumer uses.
