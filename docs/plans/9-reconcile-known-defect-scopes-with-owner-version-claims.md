---
id: 9
slug: reconcile-known-defect-scopes-with-owner-version-claims
title: "Reconcile known-defect scopes with owner version claims"
kind: exec-plan
created_at: 2026-11-17T19:05:20Z
intention: "intention_01m7nec8bee2qbp37b37yv105q"
provenance:
  created_by:
    model: "claude-fable-5-2"
    harness: "claude-code"
    at: 2026-11-17T19:05:20Z
  reviews:
    - model: "claude-fable-5-2"
      harness: "claude-code"
      at: 2026-11-18T01:45:47Z
      verdict: "changes-requested"
      note: "Same model as author. Checked against IR-3 and source; the reconciliation finding table is neither total nor disjoint, and the checked-in snapshot fixture would embed machine paths."
  revisions:
    - model: "claude-fable-5-2"
      harness: "claude-code"
      at: 2026-11-18T01:55:31Z
      mode: "update"
      note: "Addressed the 2026-11-18 review: ordered finding rules, versionsApplyTo in the package map, fixed evaluator home, version step."
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-11-19T04:56:50Z
      mode: "implement"
      note: "Milestones 1 to 3 implemented"
---

# Reconcile known-defect scopes with owner version claims

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

This plan implements improvement request IR-3
([docs/improvement-requests/reconcile-known-defect-scopes-with-owner-version-claims.md](../improvement-requests/reconcile-known-defect-scopes-with-owner-version-claims.md)).

A scenario's known defect says which failures are excused and on which resolved package
versions. That statement is written by hand in the consumer's Haskell source, and it goes
stale. If the owner fixed the bug in version 1.3.0 but the scenario still excuses the failure
below 1.4.0, a real regression in 1.3.0 is silently excused. If the scenario excuses it only
below 1.2.0, a release the owner says is still affected looks unexpectedly broken. Today the
scope is not even visible outside the program: `kenshou list --json` prints only the defect's
reference.

After this plan, three things are true. First, `kenshou list --json` and the planning catalog
carry each scenario's complete defect declaration: every reference, summary, excused failure
label, group, and cohort condition, in a field that older readers ignore. Second, one evaluator
decides whether a scope applies to a set of resolved packages; scenario execution uses it, and
it can explain its answer condition by condition, so later analysis can never disagree with
what a run did. Third, `owners reconcile` compares each declaration with the owner's version
claims from an owner snapshot and prints reviewable proposals: for example "the owner fixed
this in 1.3.0; the scope's bound is 1.4.0; propose 1.3.0". It exits 1 when a declaration
contradicts an owner claim, and it never edits source or owner records.

Someone can see it working by running, inside `nix develop`:

```bash
K=$(cabal list-bin kenshou)
"$K" list --json | jq '.scenarios[] | select(.knownDefectDeclaration != null) | {id, knownDefect, knownDefectDeclaration}'
```

and, against the fixtures this plan adds:

```bash
F=kenshou-evidence/test/fixtures/reconcile
"$K" owners reconcile --snapshot "$F/snapshot" --catalog "$F/catalog.json" --package-map "$F/package-map.json"
echo "exit=$?"
```

which prints one finding per declaration and `exit=1` because the fixture contains
contradictions.


## Progress

- [x] M1 (2026-11-18): `kenshou.scenario-list/v1` documents carry `knownDefectDeclaration`
  beside the unchanged `knownDefect` field; `Kenshou.Plan.Catalog` reads it back; round-trip
  tests cover every scope constructor and a nested group; the golden list and the planning
  fixture catalog still decode. Evidence: `kenshou-core/test/Kenshou/DefectSpec.hs`, 7
  examples, 0 failures; `kenshou list --json` shows the self-test declaration.
- [x] M2 (2026-11-18): `evaluateScope` in `kenshou-core` is the only scope evaluator;
  `cohortScopeApplies` is defined through it; `kenshou-core/test/Kenshou/ScopeSpec.hs` compares
  it with a verbatim copy of the old function over a 21-case table and a Hedgehog property, and
  reports missing and malformed cases separately. `classifyVersion` uses `parseScopeVersion`;
  `grep -rln readP_to_S kenshou-*/src` prints only `Scenario.hs`; `just selftest` passes.
- [x] M3 (2026-11-18): `owners reconcile` prints text and `kenshou.scope-reconciliation/v1`
  JSON for the fixture matrix under `kenshou-evidence/test/fixtures/reconcile/` (24 scenarios,
  26 findings: 9 contradictions, 12 warnings, 5 consistent), exits 1 on contradictions and 0
  once they are removed, and leaves every input file byte-identical. Evidence:
  `ReconcileSpec` 9 examples and `owners command` 4 examples, 0 failures; the property test
  passes 100 generated cases. `just verify` runs every recipe; the only failures are the three
  pre-existing `kenshou-evidence` tests of FRIC-2 (see Surprises & Discoveries).


## Surprises & Discoveries

- There is no scenario-list catalog under `fixtures/consumer-baseline`; that directory holds
  cohort, performance, and verification fixtures only. Milestone 1's "existing catalogs still
  decode" check therefore covers `kenshou-core/test/golden/scenario-list.json`, the same file
  with the new field stripped, and `kenshou-core/test/fixtures/plan/catalog-planned.json`.

- `kenshou list --json` encodes objects with Aeson's key order (alphabetical), so the
  declaration prints as `{"appliesTo":…,"expectedFailures":…,"kind":"single",…}` rather than
  in the order shown in Concrete Steps. Readers must not depend on key order.

- Three `kenshou-evidence` tests fail on the unmodified tree because the vendored verification
  bundle lacks its run records (FRIC-2, recurrence recorded as FRIC-3). They are unrelated to
  this plan, but `just verify` cannot exit 0 until that fixture is repaired.

- `suiteVersion` (`Kenshou.Core.Version`) is kenshou-core's cabal version, and it is a field
  of comparison and series keys (`Kenshou.Core.Compat`). The planned 0.1.1.0 step therefore
  makes runs made after this plan non-comparable with runs made with 0.1.0.0. That is the
  compatibility rule working as designed, so the step stands; the kenshou-core CHANGELOG says
  so. A consumer comparing against older baselines must re-record them.

- With `DuplicateRecordFields`, a record update of a field shared by two types in scope is
  ambiguous, so `Reconcile.hs` rebuilds `Verdict` and `KnownDefect` values explicitly rather
  than using update syntax. The scenario identifiers in tests must be valid segments; digits
  in a name segment such as `defect-bug-1` are rejected by `parseScenarioId`.

- Cabal rejects `extra-source-files` wildcards without an extension (`invalid file glob
  'test/fixtures/reconcile/snapshot/records/*'`), and snapshot record files are named by their
  bare SHA-256. `kenshou-evidence.cabal` therefore lists each record file explicitly; a
  regenerated fixture snapshot must update that list. `cabal build` does not report the bad
  glob; `cabal sdist` does.


## Decision Log

- Decision: The complete declaration is a new field, `knownDefectDeclaration`, added to each
  scenario entry of the existing `kenshou.scenario-list/v1` document. The existing
  `knownDefect` field (a reference string, or an array of references for a group) is unchanged,
  and the schema identifier stays `v1`.
  Rationale: IR-3 requires existing catalog readers to keep working. The schema file
  `schemas/scenario-list-v1.schema.json` lists required fields and does not forbid others, and
  the reader in `Kenshou.Plan.Catalog` ignores unknown fields, so an added field is compatible.
  A `v2` document would force every consumer and external runner to change at once for no
  benefit.
  Date: 2026-11-17

- Decision: The declaration encoding is recursive and preserves groups exactly, rather than
  flattening them.
  Rationale: IR-3's first criterion requires grouped defects to round-trip. Flattening loses
  the group, and a reader that wants the flat list can flatten.
  Date: 2026-11-17

- Decision: The evaluator works on a neutral package description, `ScopePackage`, to which both
  a run's resolved cohort and an evidence record's component list convert.
  Rationale: Execution holds a `CohortIdentity`; published evidence records hold a list of
  package, version, source, and revision. IR-3 requires one semantic implementation that also
  supports later evidence analysis (plan 10). A shared input type is what makes one
  implementation serve both.
  Date: 2026-11-17

- Decision: Reconciliation proposes only two kinds of correction: set or correct a
  `VersionBelow` bound to the owner's released fixed version, and remove a `VersionBelow` bound
  that no owner claim supports. It never proposes a change to labels, source kinds, or
  revisions, and never proposes a bound from a status alone.
  Rationale: IR-3 states that an absent owner fix cannot justify a speculative upper bound, that
  an owner status alone is insufficient to narrow a scope, and that no command may broaden
  covered failure labels.
  Date: 2026-11-17

- Decision: `owners reconcile` exits 1 when at least one finding is a contradiction, and 0 when
  findings are only warnings or there are none.
  Rationale: IR-3 asks for a machine-detectable error status for contradictions and distinct
  ambiguity warnings. Exit code 1 is the protocol's "failed" and lets a consumer gate on it;
  ambiguity is a request for consumer input, not a failure.
  Date: 2026-11-17

- Decision: Each declaration gets exactly one primary finding, chosen by the first matching
  rule of an ordered list. A `fixedVersion` is read as a fix claim only when the owner's status
  is `fixed`. A `fixed` record whose `fixedVersion` is absent, `unknown`, or unparseable is
  always `unsupported-claim`, whether or not the scope has a bound.
  Rationale: The first draft's finding kinds overlapped (a `fixed` record with no `fixedVersion`
  and a bound was both a contradiction and a warning, which have different exit codes) and left
  some inputs with no finding at all. An ordered list makes the result total and
  deterministic. The bug-report profile defines `fixedVersion` only for the `fixed` status, so a
  value on any other status is not a claim. When the owner says a fix exists but not where, a
  bound can be neither confirmed nor called speculative, so nothing is proposed.
  Date: 2026-11-18

- Decision: The package map states, per owner, which packages' version numbers the owner's
  version fields denote (`versionsApplyTo`). A version bound is proposed or judged only for a
  package in that list.
  Rationale: An owner record's `affects` names a project, and its versions are that project's
  release versions. The packages of one project can carry unrelated version numbers, so
  comparing an owner's `fixedVersion` with an arbitrary mapped package's bound would be a guess,
  which IR-3 forbids. Only the consumer knows the correspondence, so it says so explicitly and
  the field has no default.
  Date: 2026-11-18

- Decision: The evaluator, its input and result types, and the version parser live in
  `Kenshou.Core.Scenario`, next to the scope types. `Kenshou.Core.Defect` holds the catalog
  codec and re-exports the evaluator.
  Rationale: `Kenshou.Core.Defect` must import the declaration types from
  `Kenshou.Core.Scenario`, and `cohortScopeApplies` in `Kenshou.Core.Scenario` must call the
  evaluator, so putting the evaluator in `Kenshou.Core.Defect` would be an import cycle. This is
  certain, not a possibility to discover during implementation.
  Date: 2026-11-18

- Decision: This plan is a minor version step under the Haskell Package Versioning Policy for
  `kenshou-core` (0.1.0.0 to 0.1.1.0) and for `kenshou-evidence` and `kenshou-cli` (one minor
  step above whatever plan 8 left). It does not tag or publish.
  Rationale: Everything added is a new module, export, optional JSON field, or subcommand, and
  `cohortScopeApplies` keeps its type and meaning. `kenshou-evidence` and `kenshou-cli` use the
  new `kenshou-core` exports, so their lower bounds on it rise to 0.1.1.0.
  Date: 2026-11-18


- Decision: `ScopeFinding` carries, beyond the fields listed in Interfaces and Dependencies,
  `snapshot`, `ownerStatus`, `ownerFixedVersion`, `package`, `primary`, and `notes`. `current`
  and `proposed` are the individual defect (not the whole group) with its present and proposed
  scope. `conditionPackage` is exported from `Kenshou.Core.Scenario`.
  Rationale: The text and JSON reports must show the owner's raw claim, the compared package,
  and the snapshot digest per finding, and the `fixed-version-without-fixed-status` remark
  needs a machine-readable home; a finding is about one individual defect, so its proposal is
  that defect's corrected declaration.
  Date: 2026-11-18

- Decision: A `reference`-keyed package-map entry is looked up first for the cited reference,
  then for its canonical record, and only then is the canonical record's `affects` used. When
  a scope has several bounds for the compared package, a proposal replaces them with one bound
  at the position of the first. Removing the last condition of a scope yields `all-cohorts`.
  Rationale: An alias may need its own mapping; collapsing redundant bounds keeps the proposal
  equal in meaning to "the bound is V".
  Date: 2026-11-18

## Outcomes & Retrospective

All three milestones are implemented. `kenshou list --json` and the planning catalog carry
complete declarations beside the unchanged reference field; `evaluateScope` is the only scope
evaluator and agrees with a frozen copy of the old one on a 21-case table and generated
cohorts; `owners reconcile` produces one primary finding per individual defect, proposes only
the two permitted corrections, exits 1 on contradictions, and writes nothing. The design held:
the ordered rule list made the fixture expectations and the property test straightforward to
state, and no rule needed changing once implemented.

What remains outside this plan: `just verify` still fails on the three FRIC-2 tests until the
vendored verification bundle's run records are restored, and IR-3 stays `in-progress` until
the consumer's integration
(`mori://shinzui/keiro-runtime-kenshou/plans/21-reconcile-known-defect-cohort-scopes-with-owner-records`)
confirms it. Plan 10 can now convert evidence components to `ScopePackage` and reuse
`PackageMap`, `ownerPackages`, and `choosePackage`.

Friction recorded under this plan: FRIC-3 in `docs/friction-log/` (the FRIC-2 evidence
failures recurred) is left `logged`: it is a second occurrence of FRIC-2's cause, not a
duplicate, and the remedy, restoring the vendored bundle's run records from the consumer
repository, is not decided here. Its recurrence across plans 8 and 9 is the case for promoting
the cause to a bug report.

ADR distillation: ADR-22 records the single evaluator and proposals-only reconciliation. The
`suiteVersion` consequence of a kenshou-core version step is recorded in the kenshou-core
CHANGELOG; it follows from the existing compatibility rule rather than a new decision.


## Context and Orientation

Kenshou is a Haskell verification harness in one cabal project of nine packages, each in a
directory `kenshou-<name>/`. Work inside `nix develop` at the repository root; `just verify`
runs every repository check. The `kenshou` executable is built from `kenshou-synthetic/app`.

This plan depends on [plan 8](8-resolve-owner-records-through-consumer-supplied-sources.md),
which must be complete first. Plan 8 adds, in `kenshou-evidence`, the module
`Kenshou.Evidence.Owner` and its submodules: an owner record is a bug report or improvement
request in the repository that owns a broken behavior, with a `status` and the version fields
`affectedVersion`, `fixedVersion`, and `lastWorkingVersion`; each version field is classified as
a `VersionClaim` (`ClaimAbsent`, `ClaimUnreleased`, `ClaimUnknown`, `ClaimReleased`, or
`ClaimUnparseable`); an owner snapshot is a directory of the exact record bytes with digests,
read with `readSnapshot`; and `canonicalOwners` maps every cited reference to its canonical
record after following duplicates. Plan 8 also adds the `owners` command in
`kenshou-evidence/src/Kenshou/Evidence/Owner/Cli.hs`, which this plan extends with a
subcommand. If those names are missing from the working tree, plan 8 is not done.

The code this plan changes is the following.

`kenshou-core/src/Kenshou/Core/Scenario.hs` defines the declaration:

```haskell
data KnownDefect
  = KnownDefect {reference :: Text, summary :: Text, expectedFailures :: [Text], appliesTo :: CohortScope}
  | KnownDefectGroup (NonEmpty KnownDefect)

data CohortScope = AllCohorts | OnlyWhen (NonEmpty PackageCondition)

data PackageCondition
  = ResolvedFromHackage Text
  | ResolvedFromGit Text
  | VersionBelow Text Text
  | RevisionIs Text Text

cohortScopeApplies :: CohortIdentity -> CohortScope -> Bool
```

A cohort is the exact set of package versions a run was built against;
`Kenshou.Core.Cohort.CohortIdentity` holds it as components, each with `ResolvedPackage` values
(name, version text, and a `PackageSource` of `FromHackage`, `FromGit location revision subdir`,
`FromBoot`, or `FromLocalPath`). `cohortScopeApplies` is true for `AllCohorts`, and for
`OnlyWhen` when every condition is satisfied by at least one package in the cohort.
`VersionBelow name bound` holds when a package of that name has a version that parses (with
`Data.Version.parseVersion`) and is strictly less than the parsed bound; if either fails to
parse, the condition is silently false. `RevisionIs` holds only for a Git-sourced package at
exactly that revision. `kenshou-core/src/Kenshou/Core/Run.hs` calls `cohortScopeApplies` in
`defectDisposition` to decide which defects apply to a run.

The catalog is the JSON list of scenarios. Two places encode it, and both emit only references
under `knownDefect`: `scenarioListDocumentFor` in `kenshou-core/src/Kenshou/Core/Bundle.hs`
(used by `kenshou list --json`) and the `ToJSON ScenarioInfo` instance in
`kenshou-core/src/Kenshou/Plan/Catalog.hs` (used by planning). The `FromJSON ScenarioInfo`
instance discards the defect entirely (`pure Nothing`). The schema is
`schemas/scenario-list-v1.schema.json` and a golden file is
`kenshou-core/test/golden/scenario-list.json`.

The relevant architecture decisions:
[ADR-3](../adr/0003-kenshou-owns-the-verification-protocol.md) requires explicit schema
identifiers and hand-written codecs for protocol documents.
[ADR-11](../adr/0011-distinguish-documented-limitations-from-known-defects.md) requires a known
defect to be attached only to specific failure labels and affected cohorts, so that any other
failure stays blocking; this is why reconciliation may tighten a version bound but never widen
labels. [ADR-1](../adr/0001-toolkit-packages-never-depend-on-a-layer-bundle.md) forbids generic
packages from naming a consumer's layers; `scripts/coupling-guard.sh` enforces it, so fixtures
use made-up package names. [ADR-2](../adr/0002-every-result-carries-a-resolved-cohort-identity.md)
explains the cohort identity.

The request originates from
`mori://shinzui/keiro-runtime-kenshou/masterplans/2-close-the-verification-and-repair-loop-for-the-keiro-runtime-in-rounds`;
the consumer's integration is
`mori://shinzui/keiro-runtime-kenshou/plans/21-reconcile-known-defect-cohort-scopes-with-owner-records`.
The version numbers that consumer found stale are examples for it to recheck; none belongs in
this repository.

A constraint from IR-1: a package's tests may read only files inside that package, listed under
`extra-source-files` in its cabal file.


## Plan of Work

### Milestone 1: complete declarations in the catalog

Create `kenshou-core/src/Kenshou/Core/Defect.hs` with hand-written `defectValue ::
KnownDefect -> Value` and `parseDefect :: Value -> Parser KnownDefect`, and add it to
`exposed-modules` in `kenshou-core/kenshou-core.cabal`. The encoding is:

```json
{
  "kind": "group",
  "defects": [
    {
      "kind": "single",
      "reference": "mori://fixture/owner-a/okf/bug-reports/concepts/BUG-2",
      "summary": "Lease is not released after a cancelled write",
      "expectedFailures": ["lease-held"],
      "appliesTo": {
        "kind": "only-when",
        "conditions": [
          {"kind": "resolved-from-hackage", "package": "fixture-store"},
          {"kind": "version-below", "package": "fixture-store", "version": "1.3.0"}
        ]
      }
    }
  ]
}
```

The scope kinds are `all-cohorts` and `only-when`; the condition kinds are
`resolved-from-hackage`, `resolved-from-git`, `version-below` (with `version`), and
`revision-is` (with `revision`). The parser rejects an unknown kind and an empty `defects` or
`conditions` array.

In `scenarioListDocumentFor` and in `ToJSON ScenarioInfo`, add `"knownDefectDeclaration" .= fmap
defectValue scenario.knownDefect` beside the existing `knownDefect` pair; do not change the
existing pair. In `FromJSON ScenarioInfo`, replace `pure Nothing` with reading the optional
`knownDefectDeclaration` through `parseDefect`, so that a catalog written to a file and read
back keeps its declarations. A document without the field still yields `Nothing`. Describe the
new field in `schemas/scenario-list-v1.schema.json`, keeping it optional.

In `kenshou-core/test/Kenshou/PlanSpec.hs` (or a new `DefectSpec.hs` registered in the test
suite's `other-modules`), add round-trip tests: one declaration per scope and condition
constructor, a group, and a group nested in a group, each encoded and parsed back to an equal
value; a `ScenarioInfo` with a declaration surviving `encode` then `decodeCatalog`; and the
existing golden and `fixtures/consumer-baseline` catalogs still decoding. Assert that for every
case the `knownDefect` field's value is what it was before this plan. Regenerate
`kenshou-core/test/golden/scenario-list.json` only by adding the new field.

### Milestone 2: one evaluator

In `Kenshou.Core.Scenario`, beside the scope types, define the neutral input and the explained
result (see Interfaces and Dependencies), and re-export them from `Kenshou.Core.Defect`. `evaluateScope` returns, for each condition, whether it holds, fails because
a named package is present but does not satisfy it, fails because no package of that name is
present, or is malformed because a version did not parse (naming which text). `scopeApplies`
reduces the result to a Boolean with exactly today's meaning: `AllCohorts` applies; `OnlyWhen`
applies when every condition holds; a missing package or a malformed version does not hold.

Rewrite the condition logic in place so that
`cohortScopeApplies cohort scope = scopeApplies (evaluateScope (cohortScopePackages cohort)
scope)`, and delete the old private `conditionApplies`. Keep `cohortScopeApplies` exported with
its current type, because consumers and `Kenshou.Core.Run` call it. The evaluator stays in
`Kenshou.Core.Scenario` because `Kenshou.Core.Defect` imports that module for the declaration
types; the reverse import would be a cycle. Export the version parser as `parseScopeVersion ::
Text -> Maybe Version` (today it is the local `parse` inside `conditionApplies`), and change plan
8's `Kenshou.Evidence.Owner.Record` to classify version claims with it instead of calling
`Data.Version.parseVersion` itself, so that an owner's version and a scope's bound are always
parsed by the same function. After this milestone `Kenshou.Core.Scenario` is the only source
module that runs the version parser (`readP_to_S`).

Add a test that carries a verbatim copy of the pre-change `cohortScopeApplies` and
`conditionApplies` as a test-local oracle and checks agreement with the new function over a
table: a Hackage package below, at, and above a bound; a Git package at the named revision and
at another; the same package name resolved from Hackage versus Git under both source
conditions; a scope with several conditions; a cohort missing the package; a version text that
does not parse on either side; and a group whose members have different scopes. Separately
assert that `evaluateScope` reports the missing-package and malformed cases as such rather than
as plain failures. Run `just selftest` to confirm that the self-test known-defect scenario
still exits as before.

### Milestone 3: reconciliation

Create `kenshou-evidence/src/Kenshou/Evidence/Owner/Reconcile.hs` with a pure function
`reconcileScopes` and the encoder for `kenshou.scope-reconciliation/v1`, and add the
`reconcile` subcommand to the `owners` command in `Kenshou/Evidence/Owner/Cli.hs`.

The inputs are an owner snapshot (plan 8), the catalog's declarations, and a package map that
the consumer writes. An owner record says which project is affected (`affects`); a scope names
cabal packages. Only the consumer knows which packages a project's defect lives in, so it says
so explicitly:

```json
{
  "schema": "kenshou.owner-package-map/v1",
  "owners": [
    {"affects": "mori://fixture/owner-a", "packages": ["fixture-store"], "versionsApplyTo": ["fixture-store"]},
    {"affects": "mori://fixture/owner-b", "packages": ["fixture-queue", "fixture-queue-client"], "versionsApplyTo": ["fixture-queue"]},
    {"reference": "mori://fixture/owner-b/okf/bug-reports/concepts/BUG-3", "packages": ["fixture-queue-client"], "versionsApplyTo": []}
  ],
  "sources": [
    {"scenario": "consumer/table/correctness/lease-release", "path": "consumer/src/Lease.hs", "line": 41}
  ]
}
```

An entry keyed by `reference` overrides the entry keyed by the record's `affects` value.
`packages` lists the cabal packages the owner's defect lives in. `versionsApplyTo` is required
and lists those of them whose version numbers are the ones the owner writes in `affectedVersion`
and `fixedVersion`; it must be a subset of `packages` and may be empty. In the example, owner B
releases `fixture-queue` under the project's version number while `fixture-queue-client` is
versioned separately, so a `fixedVersion` of 2.0.0 says nothing about which
`fixture-queue-client` version has the fix. The decoder rejects an entry without the field
rather than assuming an answer. `sources` is optional and only lets a proposal point at the line
a reviewer must edit.

For each individual defect of each scenario, find its canonical owner through
`canonicalOwners`, find the packages for that owner, and compare. The package the comparison is
about is chosen as follows: if the map gives exactly one package, that one; if it gives several
and exactly one of them is named by a condition in the scope, that one; otherwise the finding is
the warning `ambiguous-package-mapping` and nothing is proposed. A project with several
packages is never resolved by picking the first.

In the rules below, "the bound" is the `VersionBelow` condition the scope has for the chosen
package; when a scope has several for that package, it is the smallest, because all of them must
hold. "No bound" covers both `AllCohorts` and a scope with no such condition. Each individual
defect gets exactly one primary finding, from the first rule that matches:

1. The reference is unresolved, is not an owner record, or is in a duplicate cycle:
   `no-owner-claim` (warning).
2. The map has no entry for the owner: `unmapped-owner` (warning).
3. The package cannot be chosen: `ambiguous-package-mapping` (warning).
4. The bound's version text does not parse: `unsupported-claim` (warning), showing the raw
   text.
5. The owner's status is not `fixed`. Whatever `fixedVersion` holds is ignored, and when it
   holds something the rationale says so (`fixed-version-without-fixed-status`). With a bound:
   `speculative-bound` (contradiction), because no owner claim supports it; the proposal removes
   that condition. With no bound: `consistent`.
6. The status is `fixed` and `fixedVersion` is absent, `unknown`, or unparseable:
   `unsupported-claim` (warning), with or without a bound. The owner says a fix exists but not
   where, so the raw text is shown and nothing is proposed.
7. The status is `fixed` and `fixedVersion` is `unreleased`. With a bound: `speculative-bound`
   (contradiction); the proposal removes that condition. With no bound: `fix-unreleased`
   (warning); nothing can be proposed until a release exists.
8. The status is `fixed`, `fixedVersion` is a released version V, and the chosen package is not
   in the map entry's `versionsApplyTo`: `owner-version-not-package-version` (warning). V is a
   version of something else, so nothing is proposed.
9. The status is `fixed`, `fixedVersion` is a released version V, and the package is in
   `versionsApplyTo`. With no bound: `missing-upper-bound` (contradiction); the proposal adds
   `VersionBelow p V`, keeping every existing condition. With a bound B greater than V:
   `bound-above-fixed-version` (contradiction); failures on releases from V up to B are being
   excused although the owner says they are fixed, and the proposal changes the bound to V. With
   B less than V: `bound-below-fixed-version` (contradiction); releases the owner says are still
   affected are not covered, and the proposal changes the bound to V. With B equal to V:
   `consistent`.

Versions are compared after parsing both with `parseScopeVersion`, never as text. Independently
of the primary finding, each condition that names a package the map does not list for the owner
adds a secondary `scope-package-not-mapped` warning for the same declaration. `consistent` has
no severity. When a reference is an alias, the finding uses the canonical record's claims and
reports the alias and the canonical reference together.

`ResolvedFromHackage`, `ResolvedFromGit`, and `RevisionIs` conditions are reported in the
current declaration and carried unchanged into any proposal; reconciliation neither judges nor
alters them. Each finding carries the scenario, the reference and canonical reference, the
snapshot digest, the current declaration (in Milestone 1's encoding), the proposed declaration
when there is one, a one-sentence rationale naming the owner's raw claim, and the source
location when the map supplies it.

`owners reconcile` takes `--snapshot DIR` (required), `--package-map FILE` (required),
`--catalog FILE` (optional; without it the registered scenarios are used), and `--json`. Text
output prints one block per finding and a final count of contradictions and warnings; warnings
are also written to standard error. Exit codes: 1 if any contradiction, otherwise 0; 2 for
usage errors; 4 when an input cannot be read or fails its digest check. The command opens its
inputs read-only and has no output option other than standard output.

Build the fixtures under `kenshou-evidence/test/fixtures/reconcile/`: a snapshot directory
produced with plan 8's `owners snapshot --no-git-provenance` from small made-up bundles (so that
it holds no git revision and, as plan 8 guarantees, no absolute path), `catalog.json` with one
scenario per case, and `package-map.json`. The cases are a released fix with a correct bound, a
bound above it, a bound below it, no bound, an unreleased fix with and without a bound, an open
record with a speculative bound, an open record that carries a stray `fixedVersion`, a `fixed`
record with no `fixedVersion` both with and without a bound (both `unsupported-claim`), a
duplicate record whose canonical record supplies the claim, a project mapped to two packages
with and without a disambiguating condition, a released fix whose chosen package is not in
`versionsApplyTo`, an unparseable `fixedVersion`, an unparseable bound, two bounds for one
package, and a scope that mixes a Git revision condition with a version bound. Add a property
test over generated records and scopes asserting that `reconcileScopes` returns exactly one
primary finding per individual defect. Add tests to `kenshou-evidence/test/Main.hs` asserting each case's finding code,
severity, and proposal, and a golden file for the whole JSON report. Add a CLI test in
`kenshou-cli/test/Main.hs` that runs `owners reconcile` on generated inputs, checks exit code 1
and then 0 after removing the contradicting case, and asserts by digest that every input file
is unchanged.

Add `schemas/kenshou.scope-reconciliation.v1.schema.json` and
`schemas/kenshou.owner-package-map.v1.schema.json` with matching `check-jsonschema` lines in
the `schemas-check` recipe of `justfile`. Extend the `owners` help topic, update
`docs/terminology/known-defect.md` with the scope encoding and add a concept for "scope
reconciliation", add a reconciliation section to `docs/guides/adopting-kenshou-in-a-project.md`,
and record in an ADR (allocate with `okf id next docs/adr --profile docs/adr/profile.dhall ADR`)
that scope semantics have a single evaluator and that corrections are proposals. Regenerate
bundle indexes with `okf index docs/<bundle> --write`, add CHANGELOG entries for
`kenshou-core`, `kenshou-evidence`, and `kenshou-cli`, and note the implementation in IR-3 and
its bundle log within what the improvement-request profile allows. Set `kenshou-core`'s
`version` to 0.1.1.0 and raise `kenshou-evidence`'s and `kenshou-cli`'s bounds on it to
`^>=0.1.1.0`; the other packages' `^>=0.1.0.0` bounds already admit it. Give
`kenshou-evidence` and `kenshou-cli` one further minor step each, with the matching bound
changes in their dependents. Do not tag or publish.


## Concrete Steps

All commands run from the repository root inside `nix develop`.

```bash
cabal build kenshou-core kenshou-evidence kenshou-cli
cabal test kenshou-core:tests
cabal test kenshou-evidence:test:kenshou-evidence-test
cabal test kenshou-cli:test:kenshou-cli-test
```

After Milestone 1, the self-test scenario shows both fields:

```bash
K=$(cabal list-bin kenshou)
"$K" list --json | jq -c '.scenarios[] | select(.id == "selftest/kernel/correctness/known-defect") | {knownDefect, knownDefectDeclaration}'
```

```text
{"knownDefect":"mori://shinzui/kenshou/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites","knownDefectDeclaration":{"appliesTo":{"kind":"all-cohorts"},"expectedFailures":["seeded-defect"],"kind":"single","reference":"mori://shinzui/kenshou/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites","summary":"Seeded harness defect"}}
```

After Milestone 2:

```bash
just selftest
```

must pass unchanged. After Milestone 3:

```bash
F=kenshou-evidence/test/fixtures/reconcile
"$K" owners reconcile --snapshot "$F/snapshot" --catalog "$F/catalog.json" --package-map "$F/package-map.json"; echo "exit=$?"
```

The output contains blocks of this shape and ends with the counts and exit code:

```text
consumer/table/correctness/lease-release
  owner     mori://fixture/owner-a/okf/bug-reports/concepts/BUG-1  (status=fixed, fixedVersion=1.3.0)
  finding   bound-above-fixed-version  [contradiction]
  current   resolved-from-hackage fixture-store, version-below fixture-store 1.4.0
  proposed  resolved-from-hackage fixture-store, version-below fixture-store 1.3.0
  because   the owner records the fix in released version 1.3.0, but the bound 1.4.0 also excuses failures from 1.3.0 up to 1.4.0
  source    consumer/src/Lease.hs:41

9 contradictions, 12 warnings
exit=1
```

Finish with:

```bash
just verify
```

Commit at each milestone with Conventional Commits and both trailers:

```text
feat(core): expose complete known-defect declarations in the catalog

ExecPlan: docs/plans/9-reconcile-known-defect-scopes-with-owner-version-claims.md
Intention: intention_01m7nec8bee2qbp37b37yv105q
```


## Validation and Acceptance

For AC-1, the round-trip tests pass for every scope constructor, a group, and a nested group;
the catalog written by `kenshou list --json` reads back through `decodeCatalog` with equal
declarations; and the tests assert that the `knownDefect` field of every existing golden and
consumer-baseline document is unchanged.

For AC-2, the reconciliation tests pass for the released fix boundary, the unreleased fix, no
fixed version, the stale speculative bound, the duplicate record, and the project with several
packages; the property test shows one primary finding per declaration; and no test case yields
a proposal whose version does not appear in an owner record or whose package is not in the
owner's `versionsApplyTo`.

For AC-3, the oracle-comparison test passes. As a supporting check that no second version
comparison exists, `grep -rln "readP_to_S" kenshou-*/src` prints only
`kenshou-core/src/Kenshou/Core/Scenario.hs`, as it does today. (Searching for `VersionBelow` proves nothing: the
constructor legitimately appears in the codec, the evaluator, and the reconciler.)

For AC-4, the CLI test passes: text and JSON are produced, each proposal carries its scenario,
snapshot digest, current and proposed declaration, rationale, and source location, and every
input file's digest is unchanged.

`just verify` exits 0. Before this plan, `jq '.scenarios[0] | has("knownDefectDeclaration")'`
on `kenshou list --json` prints `false`; after it, `true`.


## Idempotence and Recovery

Everything here is additive or read-only. `owners reconcile` writes nothing, so it can be run
repeatedly. The catalog change adds a field; reverting the commit restores the old output with
no migration. If the Milestone 2 refactoring changes any existing test's result, stop and
compare against the oracle copy before changing a test: a difference means the evaluator's
meaning moved, which this plan forbids. When regenerating a golden file, read the diff and
confirm that only the intended field changed.


## Interfaces and Dependencies

No new library dependency is needed. The prerequisite is plan 8's `Kenshou.Evidence.Owner`,
`Kenshou.Evidence.Owner.Record` (`VersionClaim`, `OwnerRecord`), `Kenshou.Evidence.Owner.Snapshot`
(`readSnapshot`), and `canonicalOwners`.

In `kenshou-core/src/Kenshou/Core/Defect.hs`:

```haskell
defectValue :: KnownDefect -> Value
parseDefect :: Value -> Parser KnownDefect
```

In `kenshou-core/src/Kenshou/Core/Scenario.hs`, re-exported from `Kenshou.Core.Defect`:

```haskell
parseScopeVersion :: Text -> Maybe Version

data ScopeSource = ScopeHackage | ScopeGit Text | ScopeOther

data ScopePackage = ScopePackage
  { name :: Text,
    version :: Text,
    source :: ScopeSource
  }

cohortScopePackages :: CohortIdentity -> [ScopePackage]

data ConditionResult
  = ConditionHolds
  | ConditionFails
  | ConditionPackageMissing
  | ConditionMalformed Text

data ScopeEvaluation
  = AppliesToAll
  | Evaluated (NonEmpty (PackageCondition, ConditionResult))

evaluateScope :: [ScopePackage] -> CohortScope -> ScopeEvaluation
scopeApplies :: ScopeEvaluation -> Bool
```

`Kenshou.Core.Scenario.cohortScopeApplies` keeps its type and is defined through these. Plan 10
converts an evidence record's components to `ScopePackage` and calls `evaluateScope`.

In `kenshou-evidence/src/Kenshou/Evidence/Owner/Reconcile.hs`:

```haskell
data OwnerPackages = OwnerPackages
  { packages :: [Text],
    versionsApplyTo :: [Text]
  }

data PackageMap = PackageMap
  { byAffects :: Map Text OwnerPackages,
    byReference :: Map Text OwnerPackages,
    sources :: Map ScenarioId (FilePath, Maybe Int)
  }

decodePackageMap :: ByteString -> Either Text PackageMap
ownerPackages :: PackageMap -> OwnerEntry -> Maybe OwnerPackages
choosePackage :: OwnerPackages -> CohortScope -> Either Text Text

data Severity = Contradiction | Warning | Consistent

data ScopeFinding = ScopeFinding
  { scenario :: ScenarioId,
    reference :: Text,
    canonical :: Maybe Text,
    code :: Text,
    severity :: Severity,
    current :: KnownDefect,
    proposed :: Maybe KnownDefect,
    rationale :: Text,
    location :: Maybe (FilePath, Maybe Int)
  }

reconcileScopes :: OwnerStatus -> PackageMap -> [ScenarioInfo] -> [ScopeFinding]
```

`choosePackage` implements the package choice described in Milestone 3 and returns the warning
code on the left when no package can be chosen. `PackageMap`, `ownerPackages`, and
`choosePackage` are reused by plan 10. `ScopeFinding` is the primary finding; secondary
`scope-package-not-mapped` warnings are separate `ScopeFinding` values with the same scenario
and reference. The documents this plan introduces are
`kenshou.owner-package-map/v1` and `kenshou.scope-reconciliation/v1`; the document it extends is
`kenshou.scenario-list/v1`.


## Revision Notes

2026-11-18: Revised after review, before implementation began. The reconciliation findings are
now an ordered rule list with one primary finding per declaration, because the earlier kinds
overlapped and left gaps. The package map gained the required `versionsApplyTo` field so that an
owner's project version is never compared with an unrelated package version. The evaluator's
home is fixed as `Kenshou.Core.Scenario` (the alternative was a certain import cycle), the
version parser is shared with plan 8's record parser, the AC-3 supporting check was replaced by
one that can fail, the snapshot fixture is taken without git provenance, and the version step is
stated.
