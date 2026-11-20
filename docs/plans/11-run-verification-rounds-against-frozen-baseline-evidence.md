---
id: 11
slug: run-verification-rounds-against-frozen-baseline-evidence
title: "Run verification rounds against frozen baseline evidence"
kind: exec-plan
created_at: 2026-11-17T19:05:20Z
intention: "intention_01m7neca9webwsp5sb4sne1932"
provenance:
  created_by:
    model: "claude-fable-5-2"
    harness: "claude-code"
    at: 2026-11-17T19:05:20Z
  reviews:
    - model: "claude-fable-5-2"
      harness: "claude-code"
      at: 2026-11-18T01:45:55Z
      verdict: "changes-requested"
      note: "Same model as author. Checked against IR-5 and source; the shared plan-option parser cannot live in kenshou-cli, scope overrides have no defined effect, and matching planned runs to observations ignores retried attempts."
  revisions:
    - model: "claude-fable-5-2"
      harness: "claude-code"
      at: 2026-11-18T01:55:31Z
      mode: "update"
      note: "Addressed the 2026-11-18 review: round command in kenshou-cli, round evaluate, effective scope overrides, attempt-aware coverage, version step."
    - model: "gpt-6.2-sol"
      harness: "codex-cli"
      at: 2026-11-20T03:25:16Z
      mode: "implement"
      note: "Implemented frozen round capture, planning, and evaluation replay."
---

# Run verification rounds against frozen baseline evidence

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

This plan implements improvement request IR-5
([docs/improvement-requests/run-verification-rounds-against-frozen-baseline-evidence.md](../improvement-requests/run-verification-rounds-against-frozen-baseline-evidence.md)).

When the packages a consumer verifies release fixes, the consumer wants to repeat its
verification against the new versions and say precisely what changed: which reported defects
are now verified fixed, which still reproduce, what broke that was not broken before, and what
could not be checked. Kenshou has the pieces (a planner, an executor, evidence history, and,
after plans 8 to 10, owner records and fix-verification dispositions), but a consumer has to
connect them by hand, and two things go wrong when it does. If "the baseline" is whatever the
history query returns today, the comparison silently changes as new runs are published. And if
each consumer writes its own report, coverage that was skipped for budget or placement reasons
tends to disappear from it.

After this plan, a consumer's executable has a `round` command with four subcommands. `round
open` writes a round definition that freezes the exact baseline runs with their trust, the
baseline and candidate cohort identities, the owner snapshot, the catalog, and the selection
inputs; it can also adopt an input set that was captured by hand earlier. `round plan` emits an
ordinary run plan for one arm of the round, covering every scenario that reproduces an owner's
defect plus the scenarios affected by the packages that changed, and states every omission with
its reason. `round evaluate` freezes the candidate observations under an identifier the caller
chooses. `round report` compares the frozen baseline with a frozen evaluation through the
disposition derivation of plan 10 and prints what is fixed, what remains, what is new, and what
is missing, each traced to exact runs. Replaying a report later gives the same answer. Nothing
here writes to owner records or sealed evidence.

Someone can see it working by running, inside `nix develop`:

```bash
K=$(cabal list-bin kenshou)
F=kenshou-evidence/test/fixtures/round
"$K" round report --round "$F/r1" --evaluation e1
echo "exit=$?"
```

which prints the fixture round's report, containing one confirmed fix, one unrelated runtime
failure, one expected defect that exited 0, one missing run, one infrastructure failure, and
one run with incomplete evidence, and exits 1 because of the new failure.


## Progress

- [x] M1 (2026-11-19): `round open` writes a create-only `kenshou.round/v1` definition with frozen inputs
  and digests, both from fresh capture and from a caller-supplied input directory; reopening an
  existing round is refused; changing owner files or adding history afterwards does not change
  what the round reads. The evidence suite passes fresh capture, offline adoption,
  exact published lookup, and missing or tampered input checks.
- [x] M2 (2026-11-19): `round plan` emits a `kenshou.run-plan/v1` document that the existing `kenshou
  execute` accepts, bound to the chosen arm's frozen cohort identity, together with a coverage
  document listing owner reproductions, change-selected scenarios, and every omission; release
  mode and change mode differ as specified; the synthetic end-to-end test executes an emitted
  plan. The core and evidence tests cover both modes, both arm identities, owner reasons and
  omissions. The CLI acceptance test executes the emitted plan and compares its policy with
  `plan`. `plan --help` is byte-identical.
- [ ] M3: `round evaluate` freezes an evaluation; `round report` derives baseline and candidate
  dispositions from it with plan 10's function and prints text, `kenshou.round-report/v1` JSON,
  and an optional dated Markdown report; the fixture replay has the expected counts and is unchanged by newer
  observations; a synthetic consumer runs open, plan, execute, and report through public
  command contributions; `just verify` passes.


## Surprises & Discoveries

Plan 8’s owner and CLI contribution tests are present. Plan 10 repaired the
fixture failure that had left Plan 8’s final verification checkbox open.
The cohort diff already conservatively selects the full catalog when a changed
package is unmapped. Change mode keeps that behavior and reports the unmapped
package explicitly, while the mode remains `change`.


## Decision Log

- Decision: A round is a directory, identified by a caller-chosen identifier, containing
  `round.json` and an `inputs/` directory. Round identifiers are not allocated automatically.
  Rationale: IR-5 says the first manual refresh must be adoptable later without rerunning
  merely to obtain an automatically numbered round, and that the request does not mandate
  consumer-specific tracking. A caller-chosen identifier lets a consumer name a round after its
  own release or plan.
  Date: 2026-11-17

- Decision: The baseline is an explicit list of run identifiers, frozen with the trust each run
  had when the round was opened. `round open` never queries "latest".
  Rationale: IR-5 requires an explicit observation index because a baseline accumulates over
  many plans, and requires that the round keeps comparing against the same evidence.
  Date: 2026-11-17

- Decision: `round plan` takes the cohort identity of the arm it plans for from the round
  definition and never resolves a cohort from the working tree. The emitted plan's runs carry
  that identity's plan hash as their cohort expectation, which the existing runner checks.
  Rationale: IR-5 states that a baseline plan must not be relabelled for a candidate and that
  planning must not silently switch or build cohorts. Today `kenshou plan` resolves the cohort
  from the current build; a round plan made that way would describe whichever cohort happened
  to be active.
  Date: 2026-11-17

- Decision: A report is always derived from a frozen evaluation: a create-only document under
  the round's `evaluations/<id>/` directory holding the candidate observations and the
  disposition inputs. A second evaluation with a different identifier is the only way to take
  newer evidence into account. Only `round evaluate` creates an evaluation; `round report` reads
  one and fails with exit code 4 when it does not exist.
  Rationale: IR-5 requires that replaying a frozen round must not substitute newer history,
  catalog definitions, or owner claims without recording a separately identified evaluation.
  The first draft let `round report` create the evaluation when it was missing. Because an
  evaluation can never be rewritten, a mistyped identifier or a forgotten source option would
  then have frozen an empty evaluation for good; a separate command makes creating one a
  deliberate act.
  Date: 2026-11-17 (creation moved to `round evaluate` on 2026-11-18)

- Decision: `round report` exits 1 when the candidate arm has a regression, a defect that still
  reproduces on a version the owner calls fixed, or a new failure; 3 when there is none of
  those but coverage is missing, evidence is incomplete, or infrastructure failed; and 0
  otherwise.
  Rationale: IR-5 states that a lack of comparable evidence is not a pass. The codes follow the
  protocol's existing meanings (1 failed, 3 inconclusive) in ADR-3.
  Date: 2026-11-17

- Decision: The round report links existing comparison artifacts by reference and does not
  state a performance verdict.
  Rationale: IR-5 and ADR-5 keep functional and owner conclusions separate from performance
  verdicts, which require paired, interleaved, calibrated benchmark evidence.
  Date: 2026-11-17

- Decision: The round logic (definition, opening, planning, evaluation, report) is a library in
  `kenshou-evidence` with no command-line parsing. The `round` command lives in `kenshou-cli`,
  in `Kenshou.Cli.Command.Round`, beside the `plan` command.
  Rationale: `round plan` must accept the same policy options as `plan` and turn them into a
  `PlanPolicy` the same way. That parser and `makePolicy` are in
  `Kenshou.Cli.Command.Plan` in `kenshou-cli`, and `kenshou-cli` depends on `kenshou-evidence`,
  so a command defined in `kenshou-evidence` could not share them. Placing the command in
  `kenshou-cli` needs no code to move between packages.
  Date: 2026-11-18

- Decision: A scope override replaces, for this round's derivation only, the scope of one
  declaration, identified by scenario and reference. It cannot change labels. Every conclusion
  that rests on an overridden declaration says so.
  Rationale: IR-5 requires reports to trace explicit scope overrides. The first draft recorded
  overrides but gave them no effect, while also promising to list the conclusions they affect.
  An override exists for the interval between a consumer learning that a declared scope is
  wrong and its source being corrected; applying it to the catalog handed to the derivation,
  visibly, is what makes the round usable in that interval. ADR-11 forbids widening labels, so
  an override may carry only a scope.
  Date: 2026-11-18

- Decision: A planned run counts as covered when any attempt recorded for it in the execution's
  `plan-summary.json` has a candidate observation.
  Rationale: `Kenshou.Plan.Execute` gives a retried run a fresh run identifier, so matching the
  planned identifier alone would report a run that succeeded on its second attempt as missing.
  The summary is the executor's own record of which attempts belong to which planned run.
  Date: 2026-11-18

- Decision: This plan is a major version step under the Haskell Package Versioning Policy for
  `kenshou-core` (to 0.2.0.0) and a minor step for `kenshou-evidence` and `kenshou-cli`. It does
  not tag or publish.
  Rationale: `ChangeSource` is exported with its constructors, so adding `OwnerReproduction`
  breaks any exhaustive match on it. All eight other packages bound `kenshou-core` with
  `^>=0.1.0.0`, which excludes 0.2.0.0, so every one of them needs its bound raised.
  Date: 2026-11-18


- Decision: Publish the plan and coverage together by renaming a directory under
  `plans/NAME/`. The two flat paths are relative links to the pair.
  Rationale: An interrupted or concurrent writer cannot publish either document
  independently. A retry can reuse links left before publication.
  Date: 2026-11-19

- Decision: Report a missing baseline control per candidate scenario. When both
  arms have the same plan hash, only evaluation observations can satisfy candidate
  coverage.
  Rationale: The disposition engine groups by plan hash. Letting a frozen baseline
  pass satisfy candidate coverage could certify a rerun without candidate evidence.
  Date: 2026-11-19


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Kenshou is a Haskell verification harness in one cabal project of nine packages, each in a
directory `kenshou-<name>/`. Work inside `nix develop` at the repository root; `just verify`
runs every repository check. The `kenshou` executable is built from `kenshou-synthetic/app`,
which registers a reference suite for a made-up layer called `synthetic`.

This plan depends on [plan 10](10-derive-fix-verification-dispositions-from-immutable-evidence.md),
and through it on plans [8](8-resolve-owner-records-through-consumer-supplied-sources.md) and
[9](9-reconcile-known-defect-scopes-with-owner-version-claims.md). All three must be complete.
What they provide, in the words this plan uses:

An owner record is a bug report or improvement request in the repository that owns a broken
behavior. An owner snapshot (plan 8) is a create-only directory holding the exact bytes of the
cited records with digests; `owners snapshot` writes one and
`Kenshou.Evidence.Owner.Snapshot.readSnapshot` reads one. The catalog is the JSON list of
registered scenarios (`kenshou list --json`, schema `kenshou.scenario-list/v1`); after plan 9
it carries each scenario's complete known-defect declaration, and
`Kenshou.Plan.Catalog.decodeCatalog` reads it back. A package map (plan 9,
`kenshou.owner-package-map/v1`) is the consumer's statement of which cabal packages an owner's
defect lives in. An observation (plan 10, `Kenshou.Evidence.Observation`) is one run reduced to
its identifier, scenario, revision, outcome, digest-verified failure labels, resolved packages,
cohort plan hash, and trust (`human-reviewed`, `machine-confirmed`, `unverified`, or
`local-sealed`; the first two are "confirmed"). `Kenshou.Evidence.Disposition.deriveDispositions`
is a pure function from a `DispositionInput` (owner status, catalog, package map, coverage, and
observations) to one conclusion per owner and cohort: `verified-fixed`, `still-reproduces`,
`reproduces-as-expected`, `not-reproduced`, `regressed`, `different-failure`,
`not-yet-released`, `not-run`, or `unverifiable`.

The existing code this plan connects:

A cohort is the exact set of package versions a run was built against. `kenshou cohort show
--json` prints the resolved identity (`kenshou.cohort-identity/v1`,
`Kenshou.Core.Cohort.CohortIdentity`), which includes a cohort name, a plan hash, and every
component's resolved packages; `--identity FILE` reads a captured one instead of a build.
Switching the active cohort is a deliberate operator action
([ADR-2](../adr/0002-every-result-carries-a-resolved-cohort-identity.md)).

The planner is in `kenshou-core/src/Kenshou/Plan/`. `Change.hs` defines `Change` (a changed
component with a `ChangeSource` of `Named`, `CohortDiff`, `Since`, `UpstreamDiff`, or
`Everything`), `Reason`, `Selected`, `selectScenarios` (which follows the component graph from
changes to affected scenarios), `selectAll`, and `selectBySelectors`. `Change/Cohort.hs` has
`diffCohorts`, which turns two cohorts' package sets into changes and warnings; a warning is
produced for a changed package that no component in the graph owns. `Components.hs` loads the
component graph, a checked-in JSON document mapping components to packages and scenario
selectors ([ADR-4](../adr/0004-select-runs-from-a-checked-in-component-graph.md)). `RunPlan.hs`
has `PlanContext` (which holds `cohortName` and `cohortPlanHash`), `buildPlan`, which expands
selections into runs and records `Skipped` entries with a `SkipReason` (`SkipTier`, `SkipKind`,
`SkipPlacement`, `SkipExcluded`, `SkipUnsupportedDimension`, `SkipBenchmarkWithoutDurable`,
`SkipUnsupportedKnob`, `SkipOverBudget`), and `stampPlan`. Every planned run's spec gets a
`cohortExpectation` from the context, and `Kenshou.Core.Run` refuses to treat a run as valid
when the actual cohort's plan hash differs. `kenshou-cli/src/Kenshou/Cli/Command/Plan.hs` is the
`plan` command; its `writeRunPlan` resolves the cohort from the working tree. `kenshou execute
--plan FILE --out DIR` (`Kenshou.Plan.Execute.executePlan`) runs a plan and writes sealed run
directories and a summary.

Commands are values of `Kenshou.Core.Cli.CliCommand` collected in
`Kenshou.Cli.Registry.standardCommands`; plan 8 adds `withCommand` to replace one by name and
the `OwnerConfig` record through which a consumer supplies owner sources, a resolver, and
evidence locations.

The decisions that constrain this plan:
[ADR-3](../adr/0003-kenshou-owns-the-verification-protocol.md) (one protocol, explicit schema
identifiers, hand-written codecs, standard output for documents and standard error for
diagnostics, and exit codes 0 passed, 1 failed, 2 usage, 3 inconclusive, 4 errored);
[ADR-12](../adr/0012-keep-verification-records-immutable-and-derive-baselines.md) (records are
immutable, and nothing stores a baseline flag: a round's baseline is therefore a list kept in
the round, not a mark on a record);
[ADR-5](../adr/0005-comparison-verdicts-require-controlled-benchmark-evidence.md) (performance
verdicts come only from `kenshou compare` over paired benchmark-grade runs);
[ADR-1](../adr/0001-toolkit-packages-never-depend-on-a-layer-bundle.md) (no consumer names in
generic packages; `scripts/coupling-guard.sh` enforces it).

The request originates from
`mori://shinzui/keiro-runtime-kenshou/masterplans/2-close-the-verification-and-repair-loop-for-the-keiro-runtime-in-rounds`.
The consumer's integration is
`mori://shinzui/keiro-runtime-kenshou/plans/23-define-the-round-protocol-and-its-report`, and
its first manual refresh is
`mori://shinzui/keiro-runtime-kenshou/plans/24-run-the-first-repair-verification-round-against-a-fixed-cohort`.
That refresh happens without this tooling; this plan must be able to adopt its captured inputs.

A constraint from IR-1: a package's tests may read only files inside that package, listed under
`extra-source-files`.


## Plan of Work

### Milestone 1: opening a round

Create `kenshou-evidence/src/Kenshou/Evidence/Round.hs` (the definition, its codec, and the
opening logic), a library module with no command-line parsing, and
`kenshou-cli/src/Kenshou/Cli/Command/Round.hs` (the `round` command, which only parses options
and calls the library). Add `roundCommand` to `standardCommands` and export `roundCommandWith`
and `RoundConfig` from `Kenshou.Cli` for consumers. The command is in `kenshou-cli` because it
shares option parsing with the `plan` command there (see Milestone 2 and the Decision Log).

A round directory has this layout:

```text
<round>/
  round.json                      kenshou.round/v1
  inputs/
    owners/                       an owner snapshot directory (plan 8)
    catalog.json                  kenshou.scenario-list/v1 with declarations
    package-map.json              kenshou.owner-package-map/v1
    graph.json                    the component graph
    baseline-identity.json        kenshou.cohort-identity/v1
    candidate-identity.json       kenshou.cohort-identity/v1
    baseline-observations.json    the frozen baseline observations
    coverage.json                 optional coverage policy
    scope-overrides.json          optional, kenshou.round-scope-overrides/v1
  plans/                          named plans and links written by round plan
  evaluations/<id>/               written by round evaluate
```

`round.json` records the round identifier, when it was opened, the mode (`release` or
`change`), and for every file under `inputs/` its path and SHA-256. For the two identities it
also records the cohort name and plan hash. For the baseline it records the observation index:
for each baseline run, the run identifier, its source (the evidence concept reference or the
sealed run path), its scenario, and its trust at the time of opening. It records by reference
(path or URI plus digest) any plan, run spec, suite, and policy documents the caller names with
`--reference KIND=PATH`. An adopted capture may also contain `references.json`,
an array of `kind`, `path`, and `sha256` entries. Each path is relative to the
captured input directory and is checked against its stated digest. A scope override is a consumer's explicit statement, given in a file
passed with `--scope-overrides` and frozen as `inputs/scope-overrides.json`, that for this round
one declaration's scope is to be read differently:

```json
{
  "schema": "kenshou.round-scope-overrides/v1",
  "overrides": [
    {
      "scenario": "consumer/table/correctness/lease-release",
      "reference": "mori://fixture/owner-a/okf/bug-reports/concepts/BUG-2",
      "appliesTo": {
        "kind": "only-when",
        "conditions": [{"kind": "version-below", "package": "fixture-store", "version": "1.3.0"}]
      },
      "reason": "The owner released the fix in 1.3.0; the source still says 1.4.0."
    }
  ]
}
```

`appliesTo` uses plan 9's scope encoding. An override names one individual defect by scenario
and reference and carries only a scope and a non-empty reason; it has no field for labels.
`round open` refuses, with exit code 4, a file in which an override names a scenario or
reference that the frozen catalog does not declare, or in which two overrides name the same
declaration. Overrides change no source file: they are applied only to the copy of the catalog
that Milestone 3 hands to the derivation.

`round open` has two ways to obtain inputs. With `--from-inputs DIR`, it copies an already
captured directory that has the layout of `inputs/` above, verifies that the owner snapshot
passes its own digest check, that both identities decode, that every baseline observation's
run identifier is unique, that any scope overrides are valid against the catalog, and that
every referenced artifact exists with the stated digest, and it performs no history query and
no owner resolution. Without it, the caller passes `--owners
DIR` (an existing snapshot; opening does not take one implicitly, so that the capture time of
owner claims is always a deliberate act), `--package-map FILE`, `--baseline-identity FILE`,
`--candidate-identity FILE`, `--baseline-runs FILE` (a JSON array of run identifiers or
evidence concept references), and optionally `--catalog FILE` and `--graph FILE` (defaulting to
the registered scenarios and the program's component graph), `--coverage FILE`, and the
evidence locations plan 10's loader uses. It loads exactly the listed baseline runs with plan
10's loader and fails with exit code 4, naming the run, if one cannot be found. In both cases
`--id` and `--out` are required, the round directory is assembled in a temporary sibling and
renamed into place, and an existing round directory is refused with exit code 2.

Tests in `kenshou-evidence/test/Main.hs` open a round from generated inputs in a temporary
directory, then add a newer record to the evidence bundle and edit an owner file, and assert
that `round.json` and every file under `inputs/` are byte-identical; they open a second round
with `--from-inputs` from a captured directory and assert that no evidence bundle or owner
bundle path was read (use directories that do not exist); and they assert that a tampered input
digest, a missing baseline run, and an existing round directory are each refused.

### Milestone 2: planning reruns

`round plan --round DIR --arm baseline|candidate --out NAME` writes
`plans/NAME.run-plan.json` (an ordinary `kenshou.run-plan/v1`) and `plans/NAME.coverage.json`
(`kenshou.round-coverage/v1`). It accepts the planner's policy options that the `plan` command
has (`--max-tier`, `--kind`, `--placement`, `--dimension-policy`, `--knob-policy`, `--trials`,
`--budget-minutes`, `--seed`, `--set`, `--dim`, `--select`, `--exclude`). Move the parsing of
those options, together with `makeSeed` and `makePolicy`, out of
`Kenshou.Cli.Command.Plan` into a new `kenshou-cli/src/Kenshou/Cli/PlanOptions.hs`, so that both
commands use one parser and build a `PlanPolicy` one way (selectors are applied with the
existing `Kenshou.Plan.Change.applySelectors`); `kenshou plan --help` and the help
golden files must be unchanged by the move. In the `plan` command `--select` keeps only matching
scenarios and `--exclude` removes them, and `round plan` gives them the same meaning: they are
applied after the selection below, and a reproduction scenario they remove is an omission with
the reason `excluded`. The command refuses to overwrite an existing plan name.

Selection is the union of two sets. The first is owner-reproduction coverage: every scenario in
the frozen catalog whose declaration cites an owner record in the frozen snapshot, whatever the
record's resolution. Add a `ChangeSource` constructor `OwnerReproduction` in
`kenshou-core/src/Kenshou/Plan/Change.hs`, with its text `owner-reproduction` in the run-plan
codec and `schemas/run-plan.v1.schema.json`, and select these scenarios with
`selectBySelectors OwnerReproduction` using the owner's canonical reference as the detail. The
second set depends on the round's mode. In `change` mode it is `selectScenarios graph catalog
changes`, where the changes come from `diffCohorts` over the baseline and candidate identities'
packages; in `release` mode it is `selectAll catalog`. A scenario in both sets carries both
reasons. Change mode must never be presented as a release refresh: the coverage document states
the mode and, in change mode, lists the catalog scenarios that were not selected.

The plan's `PlanContext` takes `cohortName` and `cohortPlanHash` from the frozen identity of
the requested arm, so every run's cohort expectation names that arm. The command does not
resolve, switch, or build a cohort. It prints to standard error which cohort the plan is for and
that the operator must have that cohort active when executing.

The coverage document accounts for every reproduction scenario and every selected scenario. For
each owner it lists the reproduction scenarios that are planned and those that are not, each
with a reason: a `SkipReason` from `buildPlan` (rendered as in the run plan, including
`over-budget` and `placement`), `excluded` by an explicit selector, or `not-in-catalog`. It
lists the `diffCohorts` warnings as `unmapped-change` entries, lists every `Skipped` entry of
the plan, and gives the estimate. A reproduction scenario that is omitted is never silently
dropped: it is in the coverage document and later in the report.

Tests in `kenshou-core/test/Kenshou/PlanSpec.hs` cover the new change source. Tests in
`kenshou-evidence/test/Main.hs` call the library's `planRound` with a `PlanPolicy` and a
synthetic catalog, graph, and identities to show: release
mode selects everything; change mode selects only reproductions and affected scenarios; a
package change that no component owns appears as `unmapped-change`; a `--placement` that a
reproduction scenario does not support yields a placement omission; a small `--budget-minutes`
yields over-budget omissions; a `--select` that leaves out a reproduction scenario yields an
`excluded` omission; and the candidate plan's cohort expectation equals the candidate
identity's plan hash while the baseline plan's equals the baseline's. A test in
`kenshou-cli/test/Main.hs` runs `plan` and `round plan` with the same policy options and asserts
that the two emitted plans carry equal policies.

### Milestone 3: reporting

Reporting is two commands. `round evaluate --round DIR --id ID` creates
`evaluations/ID/evaluation.json` and refuses, with exit code 2, an identifier that already
exists. It loads the candidate observations from the locations given (`--candidate-runs FILE`, a
JSON array of run identifiers or concept references resolved with plan 10's loader; and `--runs
DIR`, repeatable, for sealed local run directories such as the output of `kenshou execute`),
records the plan and coverage documents named with `--plan NAME`, copies the `plan-summary.json`
of every `--runs` directory that has one (it lists, for each planned run, the run identifiers of
its attempts), records any comparison artifacts named with `--comparison PATH` by path and
digest, and writes the evaluation with a digest of `round.json`. It requires at least one of
`--candidate-runs` and `--runs`, so that an evaluation is never frozen empty by accident; to
record deliberately that nothing was run, pass `--allow-empty`. It prints the number of
observations it froze, by trust, to standard error.

`round report --round DIR --evaluation ID` reads an existing evaluation and accepts no source
option. It fails with exit code 4 when the evaluation does not exist, naming `round evaluate`.
The report is derived only from `round.json`, `inputs/`, and the evaluation.

Observations loaded from `--runs` have the trust `local-sealed`, which is not confirmed, so an
evaluation built only from an execution's output can show a defect as `not-reproduced` but never
as `verified-fixed`. To reach `verified-fixed`, the consumer publishes the runs with `kenshou
record`, has them attested, and creates a second evaluation from them with `--candidate-runs`.
The guide section this milestone adds must say so.

Create `kenshou-evidence/src/Kenshou/Evidence/Round/Report.hs` with a pure function from the
round definition, its inputs, and an evaluation to a report. It calls `deriveDispositions`
twice, once with the baseline observations and once with the baseline and candidate
observations together, so that a candidate reproduction after a baseline confirmed pass can be
recognised as a regression; both calls use the frozen owner status, catalog, package map, and
coverage. Before either call, each scope override is applied to the frozen catalog in memory: the
named declaration's `appliesTo` is replaced by the override's, and nothing else changes. Both
calls see the overridden catalog, so baseline and candidate are judged by the same scopes. The
report has these parts.

Owner conclusions: for each owner, the baseline conclusion per baseline cohort and the
candidate conclusion for the candidate cohort (the one whose plan hash equals the candidate
identity's), with the transition between them, the observations and trust each rests on, and
the scope evaluation. A known defect that reproduced is listed even though its run was not
blocking.

New failures: every candidate observation whose outcome is `failed` and that has a verified
label not covered by any declaration applicable to it, with the label and run identifier. A
failed candidate observation whose labels are unavailable is listed under incomplete evidence,
not here.

Missing coverage: every scenario the coverage document marks as omitted, with its reason, and
every planned run that is not covered. A planned run is covered when the candidate observations
include the run identifier of any of its attempts, as listed for its ordinal in the frozen
`plan-summary.json`; when the evaluation has no summary for the plan, only the planned run
identifier itself is looked for. A run that failed once and passed on a retry is therefore
covered, and both attempts are listed.

Infrastructure failures and inconclusive runs: candidate observations with those outcomes.

Incompatible controls: scenarios whose baseline and candidate observations have different
scenario revisions, observations incompatible with the frozen catalog, and candidate
scenarios with no baseline control.

Scope overrides: each override recorded in the round, with its reason, the declared scope, the
overriding scope, and the owner conclusions that rest on that declaration. Each of those
conclusions also carries the reason `scope-override`, so a reader of the owner section alone
cannot mistake an overridden reading for the declared one.

Linked comparisons: the comparison artifacts recorded in the evaluation, by path and digest,
under a heading that states they are separate performance evidence.

Counts: the number of owners in each candidate disposition, with `verifiedFixed` counting only
`verified-fixed`; new failures; missing scenarios; infrastructure failures; and incomplete
evidence.

The command prints the text report, or `kenshou.round-report/v1` JSON with `--json`. With
`--write-report PATH` it also writes a Markdown rendering; a consumer's `RoundConfig` can
supply a function from the round identifier and the evaluation's date to a default path, so a
consumer can have dated reports land in its own documentation directory. The Markdown file is
the only file the command writes outside the round directory, and it refuses to overwrite one.
The exit code follows the Decision Log: 1, 3, or 0 as defined there; 2 for usage errors; 4 when
an input is missing or fails a digest check.

Build the fixture round under `kenshou-evidence/test/fixtures/round/r1/` with a frozen
evaluation `e1`, using made-up owners and packages, containing: a fixed defect with a confirmed
candidate pass and a baseline reproduction; an unrelated runtime failure with a label no
declaration covers; an expected defect on an affected candidate package that exited 0; a
planned scenario with no candidate observation; a candidate infrastructure failure; and a
failed candidate run whose run data is absent. It also contains one scope override, and a
planned run whose first attempt was an infrastructure failure and whose retry passed. Tests
assert the counts, the conclusion and transition for each owner, the run identifiers, the
`scope-override` reason on the affected conclusion (and that removing the override from a copy of
the round changes that conclusion), that the retried run is not listed as missing, and the exit
code 1; they assert that the JSON
report is byte-identical when produced twice, and unchanged after files are added beside the
round (a newer evidence record and a changed owner file) since the report reads neither.

The end-to-end acceptance is a test in `kenshou-cli/test/Main.hs` that assembles a synthetic
consumer: a `LayerBundle` for a made-up layer with a scenario whose known defect cites a fixture
owner record and that fails with the declared label, a second scenario that passes, a component
graph, and a `Program` built from `selfTestAssembly` with `withCommand (roundCommandWith
config)` and plan 8's `ownersCommandWith`. Entirely through `runWithArgsWith`, the test takes an
owner snapshot, captures the cohort identity with `cohort show --json` for both arms, opens a
round, plans the candidate arm, runs `execute` on the emitted plan, creates an evaluation with
`round evaluate --runs` pointing at the execution's output, and reports on it. It asserts that
the report shows the defect as `reproduces-as-expected`, that `round report` on an evaluation
identifier that was never created exits 4 and creates nothing, that a second `round open`, a
second `round plan`, and a second `round evaluate` with the same names are refused, and that every owner file and every sealed run directory has the same
digests afterwards. Using the same identity for both arms is acceptable here: the test proves
the protocol runs end to end without a second cohort build, and the change-mode differences are
covered by Milestone 2's tests.

Add schema files `schemas/kenshou.round.v1.schema.json`,
`schemas/kenshou.round-coverage.v1.schema.json`,
`schemas/kenshou.round-scope-overrides.v1.schema.json`, and
`schemas/kenshou.round-report.v1.schema.json` with `check-jsonschema` lines in the
`schemas-check` recipe of `justfile`. Add a help topic `kenshou-cli/help/rounds.md`, terminology
concepts for "round" and "round evaluation" under `docs/terminology/`, a section in
`docs/guides/adopting-kenshou-in-a-project.md` that walks a consumer through one round, and an
ADR (allocate with `okf id next docs/adr --profile docs/adr/profile.dhall ADR`) recording that
a round freezes its baseline and inputs, that plans are bound to an arm's identity, and that
reports derive from frozen evaluations. Regenerate indexes with `okf index docs/<bundle>
--write`, add CHANGELOG entries for `kenshou-core`, `kenshou-evidence`, and `kenshou-cli`, and
note the implementation in IR-5 and its bundle log within what the profile allows. Set
`kenshou-core`'s `version` to 0.2.0.0, naming the new `ChangeSource` constructor as the breaking
change in its CHANGELOG, and raise the bound on it to `^>=0.2.0.0` in all eight packages that
depend on it (`kenshou-check`, `kenshou-cli`, `kenshou-diagnose`, `kenshou-evidence`,
`kenshou-measure`, `kenshou-remote`, `kenshou-synthetic`, and `kenshou-telemetry`); `just
plan-check` and `cabal build all` confirm that none was missed. Give `kenshou-evidence` and
`kenshou-cli` a minor step each. The `kenshou-cli` entry states that `standardCommands` now
includes a command named `round`. Do not tag or publish.


## Concrete Steps

All commands run from the repository root inside `nix develop`.

```bash
cabal build kenshou-core kenshou-evidence kenshou-cli
cabal test kenshou-core:tests
cabal test kenshou-evidence:test:kenshou-evidence-test
cabal test kenshou-cli:test:kenshou-cli-test
```

Replay the fixture round:

```bash
K=$(cabal list-bin kenshou)
F=kenshou-evidence/test/fixtures/round
"$K" round report --round "$F/r1" --evaluation e1; echo "exit=$?"
```

The report identifies both owner transitions and includes the failed label,
the missing planned run, both retry attempts, and the failed run whose data is
missing. The main fixture counts are:

```text
verifiedFixed=1 reproducesAsExpected=1 newFailures=1 missing=1 infrastructure=1 incomplete=1
exit=1
```

Walk through a round by hand against the synthetic program, in a scratch directory:

```bash
tmp=$(mktemp -d)
"$K" owners snapshot --out "$tmp/owners"
"$K" cohort show --json > "$tmp/identity.json"
"$K" list --json > "$tmp/catalog.json"
printf '{"schema":"kenshou.owner-package-map/v1","owners":[]}\n' > "$tmp/map.json"
printf '[]\n' > "$tmp/baseline.json"
"$K" round open --id demo --out "$tmp/demo" --mode release --owners "$tmp/owners" \
  --package-map "$tmp/map.json" --catalog "$tmp/catalog.json" \
  --baseline-identity "$tmp/identity.json" --candidate-identity "$tmp/identity.json" \
  --baseline-runs "$tmp/baseline.json"
"$K" round plan --round "$tmp/demo" --arm candidate --out smoke --max-tier smoke --placement local \
  --select 'selftest/kernel/correctness/*'
"$K" execute --plan "$tmp/demo/plans/smoke.run-plan.json" --out "$tmp/exec"
"$K" round report --round "$tmp/demo" --evaluation first; echo "exit=$?"
"$K" round evaluate --round "$tmp/demo" --id first --plan smoke --runs "$tmp/exec"
"$K" round report --round "$tmp/demo" --evaluation first; echo "exit=$?"
"$K" round open --id demo --out "$tmp/demo" --mode release --owners "$tmp/owners" \
  --package-map "$tmp/map.json" --baseline-identity "$tmp/identity.json" \
  --candidate-identity "$tmp/identity.json" --baseline-runs "$tmp/baseline.json"; echo "exit=$?"
```

The first `round report` runs before the evaluation exists and must print `exit=4`. The last
command must print a refusal and `exit=2`. The self-test suite contains scenarios that fail on
purpose, so the second report's exit code is expected to be 1; what to check is that
each of those failures appears under new failures with its run identifier and that the
self-test known-defect scenario's reference appears as an owner that is not a record.

Finish with:

```bash
just verify
```

Commit at each milestone with Conventional Commits and both trailers:

```text
feat(evidence): open verification rounds over frozen inputs

ExecPlan: docs/plans/11-run-verification-rounds-against-frozen-baseline-evidence.md
Intention: intention_01m7neca9webwsp5sb4sne1932
```


## Validation and Acceptance

For AC-1, the opening tests pass: the round definition records baseline run identifiers with
trust, both identities, the owner and catalog digests, and the selection inputs; adding history
and changing owner data afterwards changes neither the definition nor a report; and a round
opened with `--from-inputs` reads no live source.

For AC-2, the planning tests pass and the end-to-end test executes an emitted plan with the
existing executor. The plans for the two arms carry different cohort expectations, release and
change modes select as specified, and unmapped changes, unsupported placement, and exhausted
budget each appear as explicit omissions.

For AC-3, the fixture replay test passes with the expected counts for the confirmed fix, the
unrelated runtime failure, the expected defect that exited 0, the missing run, the
infrastructure failure, and the incomplete evidence; every entry names its run and trust; the
scope override is applied, listed, and marked on the conclusion it affects; a retried run is not
reported as missing; and the JSON is identical on replay after newer observations appear.

For AC-4, the synthetic end-to-end test passes using only public command contributions; `just
coupling-check` prints `coupling-guard: clean`; owner files and sealed runs keep their digests;
repeated `round open`, `round plan`, and `round evaluate` commands are refused rather than
overwriting; and `round report` never creates an evaluation.

`just verify` exits 0.


## Idempotence and Recovery

Every write in this plan is create-only: a round directory, a plan name within it, an
evaluation identifier within it, and a Markdown report path are each written once and refused
thereafter. A round and an evaluation are assembled in temporary sibling directories and
published by rename. A plan publishes its paired documents in a single directory
rename, with the flat execution and coverage paths pointing into it. An interrupted
plan write may leave unresolved links that the next attempt reuses. Markdown uses an
exclusive hard link to a completed temporary file. To redo a step, use a new identifier or name, or
delete the abandoned directory by hand; nothing else depends on it. `round report` is a pure
replay of an existing evaluation, writes nothing inside the round, and can be repeated freely. No command modifies owner
records, evidence records, sealed run directories, cohort files, or the active cohort.
`execute` is the existing command and keeps its own resume behavior (`--resume`).


## Interfaces and Dependencies

The CLI declares a direct dependency on `transformers`, already used by evidence. Prerequisites: plan 8's snapshot functions, `OwnerConfig`,
and `withCommand`; plan 9's catalog declarations and `PackageMap`; plan 10's `Observation`,
loader functions, `DispositionInput`, `Conclusion`, and `deriveDispositions`. From
`kenshou-core`: `Kenshou.Plan.Change` (`selectScenarios`, `selectAll`, `selectBySelectors`,
`ChangeSource`), `Kenshou.Plan.Change.Cohort.diffCohorts`, `Kenshou.Plan.RunPlan` (`PlanContext`,
`buildPlan`, `stampPlan`), `Kenshou.Plan.Components`, and `Kenshou.Core.Cohort.CohortIdentity`.

In `kenshou-core/src/Kenshou/Plan/Change.hs`, `ChangeSource` gains `OwnerReproduction`.

In `kenshou-evidence/src/Kenshou/Evidence/Round.hs`:

```haskell
data RoundMode = ReleaseRefresh | ChangeOnly

data Arm = Baseline | Candidate

data BaselineEntry = BaselineEntry
  { runId :: Text,
    source :: ObservationSource,
    scenario :: ScenarioId,
    trust :: Trust
  }

data RoundDefinition = RoundDefinition
  { roundId :: Text,
    openedAt :: UTCTime,
    mode :: RoundMode,
    inputs :: Map FilePath Text,
    baselineCohort :: (Text, Text),
    candidateCohort :: (Text, Text),
    baseline :: [BaselineEntry],
    references :: [ArtifactReference],
    scopeOverrides :: [ScopeOverride]
  }

data ScopeOverride = ScopeOverride
  { scenario :: ScenarioId,
    reference :: Text,
    appliesTo :: CohortScope,
    reason :: Text
  }

applyScopeOverrides :: [ScopeOverride] -> [ScenarioInfo] -> Either RoundError [ScenarioInfo]

openRound :: OpenOptions -> IO (Either RoundError RoundDefinition)
readRound :: FilePath -> IO (Either RoundError (RoundDefinition, RoundInputs))
```

`readRound` verifies every input against the digest in `round.json`.

The planner in `kenshou-evidence/src/Kenshou/Evidence/Round/Plan.hs` builds the
ordinary run-plan skeleton and coverage. The evaluation codec in
`kenshou-evidence/src/Kenshou/Evidence/Round/Evaluation.hs` stores the original JSON
text and digest of each captured plan, coverage document, and
`Kenshou.Plan.Summary.PlanSummary`. Its replay checks the evaluation against the
verified definition and digest.

```haskell
planRound :: RoundDefinition -> RoundInputs -> Arm -> PlanPolicy -> (PlanSkeleton, RoundCoverage)
createEvaluation :: EvaluationOptions -> IO (Either RoundError Evaluation)
readEvaluation :: FilePath -> Text -> RoundDefinition -> Text -> IO (Either RoundError Evaluation)
roundReport :: RoundDefinition -> RoundInputs -> Evaluation -> Either RoundError RoundReport
reportExitCode :: RoundReport -> ExitCode
```

`Kenshou.Evidence.Round.Report.roundReport` is pure and validates scope
overrides when called directly.

In `kenshou-cli/src/Kenshou/Cli/PlanOptions.hs`, the policy option parser, `makeSeed`, and
`makePolicy`, moved from `Kenshou.Cli.Command.Plan` without change.

In `kenshou-cli/src/Kenshou/Cli/Command/Round.hs`, re-exported from `Kenshou.Cli`:

```haskell
data RoundConfig = RoundConfig
  { owners :: OwnerConfig,
    reportPath :: Maybe (Text -> Day -> FilePath)
  }

defaultRoundConfig :: RoundConfig
roundCommand :: CliCommand
roundCommandWith :: RoundConfig -> CliCommand
```

The documents this plan introduces are `kenshou.round/v1`, `kenshou.round-coverage/v1`, and
`kenshou.round-report/v1`; the evaluation document is internal to a round directory and carries
the schema identifier `kenshou.round-evaluation/v1`. The scope override file is
`kenshou.round-scope-overrides/v1`. The document it extends is `kenshou.run-plan/v1`, with one
added change-source text.


## Revision Notes

2026-11-18: Revised after review, before implementation began. The `round` command moved to
`kenshou-cli`, because the plan-option parser it must share lives there and `kenshou-evidence`
cannot import it; the round logic stays a library in `kenshou-evidence`. Evaluations are now
created only by a new `round evaluate` subcommand, so that `round report` can never freeze an
empty evaluation by mistake. Scope overrides gained a file format and a defined effect on the
derivation. Missing coverage is now judged through the execution's attempt list, because a
retried run gets a new run identifier. The plan also states that sealed local runs cannot yield
`verified-fixed`, what `--select` means in `round plan`, and its version step.
