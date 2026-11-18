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

- [ ] M1: `kenshou.scenario-list/v1` documents carry `knownDefectDeclaration` beside the
  unchanged `knownDefect` field; `Kenshou.Plan.Catalog` reads it back; round-trip tests cover
  every scope constructor and a nested group; existing golden files and consumer-baseline
  fixtures still decode.
- [ ] M2: `evaluateScope` in `kenshou-core` is the only scope evaluator; `cohortScopeApplies`
  is defined through it; a test comparing it with a frozen copy of today's `cohortScopeApplies`
  passes for Hackage and Git sources, exact revisions, version boundaries, groups, missing
  packages, and malformed versions.
- [ ] M3: `owners reconcile` prints text and `kenshou.scope-reconciliation/v1` JSON for the
  fixture matrix (released fix boundary, unreleased fix, no fixed version, stale speculative
  bound, duplicate record, project affecting several packages), exits 1 on contradictions, and
  leaves every input file byte-identical; `just verify` passes.


## Surprises & Discoveries

(None yet.)


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


## Outcomes & Retrospective

(To be filled during and after implementation.)


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

In `Kenshou.Core.Defect`, define the neutral input and the explained result (see Interfaces
and Dependencies). `evaluateScope` returns, for each condition, whether it holds, fails because
a named package is present but does not satisfy it, fails because no package of that name is
present, or is malformed because a version did not parse (naming which text). `scopeApplies`
reduces the result to a Boolean with exactly today's meaning: `AllCohorts` applies; `OnlyWhen`
applies when every condition holds; a missing package or a malformed version does not hold.

Move the condition logic out of `Kenshou.Core.Scenario` so that
`cohortScopeApplies cohort scope = scopeApplies (evaluateScope (cohortScopePackages cohort)
scope)`, and delete the old private `conditionApplies`. Keep `cohortScopeApplies` exported with
its current type, because consumers and `Kenshou.Core.Run` call it. If importing
`Kenshou.Core.Defect` from `Kenshou.Core.Scenario` would create an import cycle, keep the
evaluator in `Kenshou.Core.Scenario` and re-export it from `Kenshou.Core.Defect`; what matters
is that only one implementation of the condition semantics exists.

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
    {"affects": "mori://fixture/owner-a", "packages": ["fixture-store"]},
    {"affects": "mori://fixture/owner-b", "packages": ["fixture-queue", "fixture-queue-client"]},
    {"reference": "mori://fixture/owner-b/okf/bug-reports/concepts/BUG-3", "packages": ["fixture-queue-client"]}
  ],
  "sources": [
    {"scenario": "consumer/table/correctness/lease-release", "path": "consumer/src/Lease.hs", "line": 41}
  ]
}
```

An entry keyed by `reference` overrides the entry keyed by the record's `affects` value.
`sources` is optional and only lets a proposal point at the line a reviewer must edit.

For each individual defect of each scenario, find its canonical owner through
`canonicalOwners`, find the packages for that owner, and compare. The package the comparison is
about is chosen as follows: if the map gives exactly one package, that one; if it gives several
and exactly one of them is named by a condition in the scope, that one; otherwise the finding is
the warning `ambiguous-package-mapping` and nothing is proposed. A project with several
packages is never resolved by picking the first. The findings, with their severity, are:

`bound-above-fixed-version` (contradiction): the owner's `fixedVersion` is a released version V
and the scope has `VersionBelow p B` with B greater than V. Failures on releases from V up to B
are being excused although the owner says they are fixed. Proposal: change the bound to V.

`bound-below-fixed-version` (contradiction): the same with B less than V. Releases the owner
says are still affected are not covered. Proposal: change the bound to V.

`missing-upper-bound` (contradiction): the owner's `fixedVersion` is a released version V and
the scope is `AllCohorts` or has no `VersionBelow` for the package. Proposal: add `VersionBelow
p V`, keeping every existing condition.

`speculative-bound` (contradiction): the scope has a `VersionBelow` for the package but the
owner's `fixedVersion` is absent or `unreleased`. No owner claim supports the bound. Proposal:
remove that condition.

`fix-unreleased` (warning): the owner's status is `fixed`, `fixedVersion` is `unreleased`, and
the scope has no version bound. Nothing can be proposed until a release exists.

`unsupported-claim` (warning): the status is `fixed` but `fixedVersion` is absent, `unknown`,
or unparseable; or a bound in the scope does not parse. The raw text is shown and nothing is
proposed.

`no-owner-claim` (warning): the reference is unresolved, is not an owner record, or is in a
duplicate cycle. `unmapped-owner` (warning): the map has no entry. `scope-package-not-mapped`
(warning): a condition names a package the map does not list for this owner.

`consistent` (no severity): the bound equals V, or the owner has not fixed the defect and the
scope has no version bound. When a reference is an alias, the finding uses the canonical
record's claims and reports the alias and the canonical reference together.

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
produced with plan 8's `owners snapshot` from small made-up bundles, `catalog.json` with one
scenario per case, and `package-map.json`. The cases are a released fix with a correct bound, a
bound above it, a bound below it, no bound, an unreleased fix with and without a bound, no
fixed version with a speculative bound, a duplicate record whose canonical record supplies the
claim, a project mapped to two packages with and without a disambiguating condition, an
unparseable `fixedVersion`, and a scope that mixes a Git revision condition with a version
bound. Add tests to `kenshou-evidence/test/Main.hs` asserting each case's finding code,
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
its bundle log within what the improvement-request profile allows.


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
{"knownDefect":"mori://shinzui/kenshou/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites","knownDefectDeclaration":{"kind":"single","reference":"mori://shinzui/kenshou/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites","summary":"Seeded harness defect","expectedFailures":["seeded-defect"],"appliesTo":{"kind":"all-cohorts"}}}
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
  owner     mori://fixture/owner-a/okf/bug-reports/concepts/BUG-2  (status=fixed, fixedVersion=1.3.0)
  finding   bound-above-fixed-version  [contradiction]
  current   version-below fixture-store 1.4.0
  proposed  version-below fixture-store 1.3.0
  because   the owner records the fix in released version 1.3.0
  source    consumer/src/Lease.hs:41

4 contradictions, 5 warnings
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
packages, and no test case yields a proposal whose version or package does not appear in an
owner record or the package map.

For AC-3, the oracle-comparison test passes, and `git grep -n "VersionBelow" -- 'kenshou-*/src'`
shows the condition semantics implemented in one place only.

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
data PackageMap = PackageMap
  { byAffects :: Map Text [Text],
    byReference :: Map Text [Text],
    sources :: Map ScenarioId (FilePath, Maybe Int)
  }

decodePackageMap :: ByteString -> Either Text PackageMap
ownerPackages :: PackageMap -> OwnerEntry -> Maybe [Text]

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

`PackageMap` and `ownerPackages` are reused by plan 10. The documents this plan introduces are
`kenshou.owner-package-map/v1` and `kenshou.scope-reconciliation/v1`; the document it extends is
`kenshou.scenario-list/v1`.
