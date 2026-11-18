---
id: 10
slug: derive-fix-verification-dispositions-from-immutable-evidence
title: "Derive fix-verification dispositions from immutable evidence"
kind: exec-plan
created_at: 2026-11-17T19:05:20Z
intention: "intention_01m7nec997edsr5djrs51nzrzs"
provenance:
  created_by:
    model: "claude-fable-5-2"
    harness: "claude-code"
    at: 2026-11-17T19:05:20Z
---

# Derive fix-verification dispositions from immutable evidence

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

This plan implements improvement request IR-4
([docs/improvement-requests/derive-fix-verification-dispositions-from-immutable-evidence.md](../improvement-requests/derive-fix-verification-dispositions-from-immutable-evidence.md)).

When the owner of a bug marks its report fixed, that says a repair was delivered. It does not
say that anyone ran the reproduction against a version containing the repair and saw it pass.
Kenshou already keeps immutable records of every run, and plan 8 reads what owners claim, but
nothing joins the two. A consumer who wants to say "this fix is verified" has to work it out by
hand, and the obvious shortcuts are wrong: a process that exits 0 may have reproduced an
expected defect, and a passing run on a fixed version usually does not mention the defect at
all, because the defect's scope no longer applies to it.

After this plan, `owners dispositions` derives, for every owner record and every resolved
cohort that has evidence, one of nine conclusions: `verified-fixed`, `still-reproduces`,
`reproduces-as-expected`, `not-reproduced`, `regressed`, `different-failure`,
`not-yet-released`, `not-run`, or `unverifiable`. Each conclusion lists the exact runs it rests
on, how much each run can be trusted, the scope evaluation, the owner's claim, and the reasons.
Only confirmed evidence covering every required scenario can produce `verified-fixed`. The
derivation is a pure function of a frozen input document, so replaying it later gives the same
answer even after owners edit their records or new runs are published. It writes nothing to
owner records or to evidence.

Someone can see it working by running, inside `nix develop`:

```bash
K=$(cabal list-bin kenshou)
F=kenshou-evidence/test/fixtures/dispositions
"$K" owners dispositions --input "$F/input.json"
```

and reading a report in which a fixed bug with confirmed passes on the fixed version is
`verified-fixed`, the same bug with only an unconfirmed local pass is `not-reproduced`, and a
run that exited 0 while reproducing an expected defect is `reproduces-as-expected`.


## Progress

- [ ] M1: the observation loader turns published evidence records and sealed local run
  directories into observations with trust and digest-verified failure labels; a failed run
  whose labels cannot be verified is kept and marked as such; loader tests pass.
- [ ] M2: `deriveDispositions` is a pure function over a `kenshou.disposition-input/v1`
  document; the rule-matrix tests cover every disposition, the precedence rules, duplicate
  attribution, groups, Git cohorts, and unparseable claims; a pass that does not mention the
  defect is attributed through the catalog.
- [ ] M3: `owners dispositions` captures a frozen input, derives from it, and prints text and
  `kenshou.dispositions/v1` JSON; replaying a frozen input twice yields equal JSON after newer
  evidence and changed owner files appear; a synthetic consumer drives it through the public
  extension points; `just verify` passes.


## Surprises & Discoveries

(None yet.)


## Decision Log

- Decision: Conclusions are per canonical owner record and per resolved cohort, where a cohort
  is identified by its plan hash.
  Rationale: IR-4 asks for per-owner, per-cohort conclusions. The plan hash is the identity
  every run result and evidence record already carries (ADR-2), and it distinguishes two
  cohorts that share a name but resolved different packages.
  Date: 2026-11-17

- Decision: Whether a run reproduced a defect is decided only from the run's failure labels,
  taken from a `run-result.json` whose bytes match the digest recorded in the evidence record
  or covered by the sealed run's manifest. The process exit code and the record's
  `knownDefects` list are never used for this.
  Rationale: IR-4 states that an exit code of 0 may mean an expected defect reproduced, and
  that a passing run outside a defect's scope omits the defect from its result. Published
  evidence records store the outcome and the data links but not the failure labels, so the
  labels must come from the linked result document, and the digest is what makes that
  trustworthy.
  Date: 2026-11-17

- Decision: There are four trust levels: the three that `Kenshou.Evidence.History` already
  derives for published records (`human-reviewed`, `machine-confirmed`, `unverified`) and a new
  `local-sealed` for a sealed run directory that was never published. Only the first two count
  as confirmed.
  Rationale: IR-4 requires unverified records and unpublished sealed local runs to remain
  explicitly weaker evidence. Reusing the existing strings avoids a second trust vocabulary.
  Date: 2026-11-17

- Decision: A cohort whose mapped package was resolved from Git cannot be `verified-fixed`
  against a released-version claim.
  Rationale: A Git revision's version number does not show whether the revision contains the
  fix. Such evidence is reported under `not-yet-released` or `not-reproduced` with the reason
  `git-cohort`, which keeps the observation visible without overstating it.
  Date: 2026-11-17

- Decision: When several scenarios are required for one owner and their results differ, the
  conclusion is the most severe one, in the order `regressed`, `still-reproduces`,
  `different-failure`, `not-reproduced`, `verified-fixed`.
  Rationale: IR-4 requires conflicting scenario results to aggregate conservatively and forbids
  counting a partially tested multi-scenario fix as wholly verified.
  Date: 2026-11-17

- Decision: The command is a subcommand of `owners`, and the derivation always runs from an
  input document; a live run first builds that document and can save it.
  Rationale: Making the frozen document the only path into the derivation guarantees that a
  replay and a live run execute the same code, which is what IR-4's deterministic-replay
  criterion needs.
  Date: 2026-11-17


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Kenshou is a Haskell verification harness in one cabal project of nine packages, each in a
directory `kenshou-<name>/`. Work inside `nix develop` at the repository root; `just verify`
runs every repository check. The `kenshou` executable is built from `kenshou-synthetic/app`.

This plan depends on two earlier plans, both of which must be complete.

[Plan 8](8-resolve-owner-records-through-consumer-supplied-sources.md) adds
`Kenshou.Evidence.Owner` in `kenshou-evidence`. An owner record is a bug report or improvement
request in the repository that owns a broken behavior. It has a raw `status` (for a bug report:
`reported`, `confirmed`, `in-progress`, `fixed`, `wont-fix`, `duplicate`, `not-a-bug`,
`cannot-reproduce`) and three version fields, each classified as a `VersionClaim`:
`ClaimAbsent`, `ClaimUnreleased`, `ClaimUnknown`, `ClaimReleased version text`, or
`ClaimUnparseable text`. An owner snapshot is a directory holding the exact bytes of the records
with their digests. `canonicalOwners` maps every cited reference, including a duplicate's, to
the entry of its canonical record. The `owners` command lives in
`kenshou-evidence/src/Kenshou/Evidence/Owner/Cli.hs`.

[Plan 9](9-reconcile-known-defect-scopes-with-owner-version-claims.md) adds, in
`kenshou-core/src/Kenshou/Core/Defect.hs`, the catalog encoding of a complete known-defect
declaration (`defectValue`, `parseDefect`), the neutral `ScopePackage` (package name, version
text, and a source of `ScopeHackage`, `ScopeGit revision`, or `ScopeOther`), and the single
scope evaluator `evaluateScope :: [ScopePackage] -> CohortScope -> ScopeEvaluation` with
`scopeApplies`. It makes `Kenshou.Plan.Catalog.decodeCatalog` keep declarations when reading a
catalog file, and adds `PackageMap` and `ownerPackages` in
`Kenshou.Evidence.Owner.Reconcile`: the consumer's statement of which cabal packages an owner's
defect lives in.

The terms and existing code this plan builds on:

A scenario (`Kenshou.Core.Scenario.Scenario`) may carry a `KnownDefect`: a `reference` to an
owner record, the `expectedFailures` labels it excuses, and an `appliesTo` scope saying on which
resolved packages the defect is expected. A scenario also has an integer `revision`, raised
when its meaning changes.

A run produces a sealed run directory containing `run-spec.json`, `run-result.json`, and
`manifest.json`, the last of which lists every file with its SHA-256. `run-result.json` (schema
`kenshou.run-result/v1`, written by `kenshou-core/src/Kenshou/Core/RunResult.hs`) contains
`runId`, `scenario`, `scenarioRevision`, `outcome` (`passed`, `failed`, `inconclusive`,
`infrastructure-failure`, or `errored`), `failures` (the failure labels), `exitCode`, and
`cohort` (the resolved cohort identity, with every package's name, version, and source).
`Kenshou.Core.Run.defectDisposition` sets the exit code to 0 when a run failed only with labels
covered by an applicable known defect, which is why an exit code cannot be read as a pass.
`Kenshou.Evidence.Source.loadRunSource` reads a sealed run directory and verifies every file
against the manifest; its `RunResultView` does not yet expose `failures` or `scenarioRevision`.

Publishing a run (`kenshou record`) writes an evidence record: a Markdown file with frontmatter
in an OKF bundle (by default `docs/verification`), of type `Verification Run`. Its frontmatter
(`kenshou-evidence/src/Kenshou/Evidence/Frontmatter.hs`) holds `runId`, `scenario`, `outcome`,
`startedAt`, `cohort`, `solverPlanHash`, `components` (each with `project`, `package`,
`version`, `source`, and optional `revision`), `compatibilityKey`, `knownDefects`, and
`dataLinks`. A data link (`Kenshou.Evidence.Types.DataLink`) names a durable object URI with
its kind (one kind is `RunResultData`), SHA-256, media type, and size. The record holds no
failure labels. Records are never edited; a correction is a new record or an attestation
([ADR-12](../adr/0012-keep-verification-records-immutable-and-derive-baselines.md)).

`kenshou-evidence/src/Kenshou/Evidence/History.hs` walks an evidence bundle and derives each
run record's trust: `human-reviewed` when a human verification entry is present,
`machine-confirmed` when an attestation with verdict `confirmed` exists that no later
attestation refutes, and `unverified` otherwise. Its `history` function requires a scenario
filter; the per-record logic is in the private `runEntry` and `attestationIndex`.

Other decisions that constrain this plan:
[ADR-11](../adr/0011-distinguish-documented-limitations-from-known-defects.md) (a known defect
covers only its labels and cohorts; any other failure is blocking),
[ADR-3](../adr/0003-kenshou-owns-the-verification-protocol.md) (explicit schema identifiers,
hand-written codecs, exit codes 0 passed, 1 failed, 2 usage, 3 inconclusive, 4 errored),
[ADR-1](../adr/0001-toolkit-packages-never-depend-on-a-layer-bundle.md) (no consumer names in
generic packages; `scripts/coupling-guard.sh` enforces it), and
[ADR-2](../adr/0002-every-result-carries-a-resolved-cohort-identity.md) (the cohort identity
and its plan hash).

The request originates from
`mori://shinzui/keiro-runtime-kenshou/masterplans/2-close-the-verification-and-repair-loop-for-the-keiro-runtime-in-rounds`;
the consumer's integration is
`mori://shinzui/keiro-runtime-kenshou/plans/22-derive-fix-verification-dispositions-from-recorded-evidence`.
[Plan 11](11-run-verification-rounds-against-frozen-baseline-evidence.md) calls this plan's
`deriveDispositions` for its round reports.

A constraint from IR-1: a package's tests may read only files inside that package, listed under
`extra-source-files`. This plan does not change the evidence record's shape.


## Plan of Work

### Milestone 1: observations

An observation is one run, reduced to what the derivation needs: its run identifier, where it
came from, its scenario and scenario revision, when it started, its outcome, its failure
labels, the packages it resolved, its cohort name and plan hash, and its trust.

Create `kenshou-evidence/src/Kenshou/Evidence/Observation.hs`. Extend
`Kenshou.Evidence.Source.RunResultView` with `resultFailures :: [Text]` (default empty when the
field is absent) and `resultScenarioRevision :: Maybe Int`. In `Kenshou.Evidence.History`,
export a function that returns every `Verification Run` entry of a bundle with its trust,
without a scenario filter, reusing `runEntry` and `attestationIndex` rather than copying them.

Loading a published record works as follows. Take the entry's trust from the history function.
Read `components` from the frontmatter and convert each to a `ScopePackage` (`hackage` source
to `ScopeHackage`, `git` to `ScopeGit revision`). Find the data link of kind `RunResultData`.
Ask the consumer-supplied run-data locator for that object's bytes; if it returns bytes whose
SHA-256 equals the link's digest, parse them as a run result and take `failures` and
`scenarioRevision` from it. If the locator has no bytes, or the digest differs, the observation
is still produced, with labels marked unavailable and the reason recorded (`run-data-missing`
or `run-data-digest-mismatch`); it must never fall back to the record's outcome to invent
labels. A run-data locator is a function from a run identifier and a data link to optional
bytes. Provide `directoryRunData`, which reads `<root>/<runId>/run-result.json`, and
`objectStoreRunData`, which fetches the link's URI through an existing
`Kenshou.Evidence.Store.ObjectStore`; a consumer can supply its own.

Loading a sealed local run directory uses `loadRunSource`, which already verifies the manifest.
The packages come from the result's cohort identity through plan 9's `cohortScopePackages`. Its
trust is `local-sealed`. If the same run identifier is also present as a published record, the
published observation wins and the local one is dropped.

Tests in `kenshou-evidence/test/Main.hs` build a small bundle and run directories in a
temporary directory (the existing `recordRunWith` and `loadRunSource` tests show how) and
assert: a confirmed record with matching run data yields labels and `machine-confirmed`; the
same record with altered run-data bytes yields unavailable labels with the mismatch reason; a
record with no run data yields unavailable labels; a refuted attestation yields `unverified`; a
local sealed run yields `local-sealed`; and a duplicate run identifier resolves to the published
observation.

### Milestone 2: the derivation

Create `kenshou-evidence/src/Kenshou/Evidence/Disposition.hs` holding the input document, the
pure function `deriveDispositions`, and the encoders for `kenshou.disposition-input/v1` and
`kenshou.dispositions/v1`.

The input document contains everything the derivation reads, by value: `capturedAt`; the owner
status document from the snapshot together with the snapshot's digest; the catalog entries
(scenario identifier, revision, and declaration) with the digest of the catalog bytes; the
package map with its digest; an optional coverage policy; and the list of observations. Nothing
in the derivation performs input or output, reads a clock, or consults anything outside this
document.

The derivation proceeds in four steps.

Step one attributes scenarios to owners. For every scenario in the catalog and every individual
defect in its declaration (a group is treated as its members, each with its own labels and
scope), look up the canonical owner through `canonicalOwners`. The scenarios attributed to an
owner, whether cited directly or through a duplicate alias, are its reproduction scenarios; the
alias is kept for the report. The required scenarios for an owner are all of its reproduction
scenarios unless the coverage policy lists a different set for that owner. This attribution
comes from the catalog, never from a run record's `knownDefects`, so a passing run that does
not mention the defect is still attributed.

Step two classifies each observation of a reproduction scenario, for one owner and one
declaration. It is `incompatible` if its scenario revision differs from the catalog's or is
unknown; incompatible observations are listed in the report and take no further part. Otherwise
its result is `reproduced` if the outcome is `failed`, labels are available, and at least one
label is among the declaration's expected failures; `different-failure` if the outcome is
`failed`, labels are available, and none is; `labels-unavailable` if the outcome is `failed`
and labels are unavailable; `passed` if the outcome is `passed`; and `no-signal` for
`inconclusive`, `infrastructure-failure`, and `errored`. When a run reproduced the defect and
also carries labels outside the declaration, it is `reproduced` and the extra labels are
recorded as other failures. Each observation also records the scope evaluation of the
declaration against its packages.

Step three determines, for each owner and each cohort (plan hash) that has at least one
compatible observation, which side of the owner's claim the cohort is on. Choose the package as
plan 9's reconciliation does: the single mapped package, or the one mapped package the scope
names; if that is not possible the side is `unknown` with reason `ambiguous-package-mapping` or
`unmapped-owner`. Then: if the owner's status is not `fixed`, the side is `open`. If it is
`fixed` and `fixedVersion` is `ClaimUnreleased`, the side is `unreleased-fix`. If `fixedVersion`
is absent, unknown, or unparseable, the side is `unknown` with reason `unsupported-claim`. If it
is a released version V: when the cohort's package is from Git, the side is `unknown` with
reason `git-cohort`; when the package is missing from the cohort or its version does not parse,
`unknown`; otherwise `fixed-side` if the cohort's version is at least V and `affected-side` if
it is below.

Step four concludes, per owner and cohort, by the first rule that matches. "Latest" means the
most recent compatible observation of a scenario in this cohort, ordered by start time and then
run identifier. "Confirmed" means trust `human-reviewed` or `machine-confirmed`.

1. The owner reference is unresolved, not a record, or in a duplicate cycle: `unverifiable`,
   with the snapshot's reason. This conclusion is per owner and has no cohort.
2. On `fixed-side`, some scenario's latest observation is `reproduced`, and an earlier
   confirmed `passed` observation of the same scenario exists on any `fixed-side` cohort of
   this owner: `regressed`. A `lastWorkingVersion` claim alone never produces this.
3. On `fixed-side`, some scenario's latest observation is `reproduced`: `still-reproduces`.
4. On `affected-side`, `open`, or `unreleased-fix`, some scenario's latest observation is
   `reproduced`: `reproduces-as-expected` when the declaration's scope applies to the cohort,
   otherwise `still-reproduces` with reason `outside-declared-scope`.
5. On `unknown`, some scenario's latest observation is `reproduced`: `reproduces-as-expected`
   when the scope applies, otherwise `unverifiable`.
6. Some scenario's latest observation is `different-failure`: `different-failure`.
7. Every required scenario's latest observation is `passed`. On `fixed-side`: `verified-fixed`
   if every one of them is confirmed, otherwise `not-reproduced` with reason
   `insufficient-trust`. On `unreleased-fix`: `not-yet-released`. On `unknown`: `unverifiable`
   with the side's reason, except `not-yet-released` is never inferred. On `affected-side` or
   `open`: `not-reproduced`.
8. Some required scenario has no compatible observation with a result of `passed`,
   `reproduced`, or `different-failure` in this cohort (it was never run, or only produced
   `no-signal`, `labels-unavailable`, or incompatible observations), while others passed: on
   `unreleased-fix`, `not-yet-released`; otherwise `not-reproduced` with reason
   `incomplete-coverage` naming the scenarios. This is the rule that stops a partly tested fix
   from being counted as verified.
9. No required scenario has any usable observation in this cohort: `unverifiable` when
   unusable observations exist (reason `labels-unavailable`, `no-signal`, or
   `incompatible-revision`), and otherwise the cohort is not reported.

An owner with no compatible observation in any cohort gets one cohort-less conclusion:
`not-yet-released` if its side would be `unreleased-fix`, else `not-run`.

Every conclusion carries the owner's canonical reference, raw status and version text, the
cohort name and plan hash, the side and its reason, the required scenarios with each one's
latest observation, every observation considered with its run identifier, source, trust,
result, scope evaluation, and other failures, and the incompatible observations. The document's
summary counts each disposition; the count named `verifiedFixed` counts only `verified-fixed`
conclusions.

Create `kenshou-evidence/test/fixtures/dispositions/input.json`, a hand-written input document
with made-up owners, and tests in `kenshou-evidence/test/Main.hs` asserting the conclusion,
reasons, and run identifiers for each of these cases: confirmed passes on a fixed version
(`verified-fixed`); a reproduction on an affected version whose run exited 0
(`reproduces-as-expected`); a reproduction on a fixed version (`still-reproduces`); a failure
with unrelated labels (`different-failure`); a failed run with unavailable labels
(`unverifiable`); no runs (`not-run`); an unresolved owner (`unverifiable`); a local pass and
an unverified pass on a fixed version (both `not-reproduced`, never counted in
`verifiedFixed`); two required scenarios with one missing (`not-reproduced`,
`incomplete-coverage`); an incompatible scenario revision; a confirmed pass followed by a later
reproduction (`regressed`); a `lastWorkingVersion` claim with no pass evidence (not
`regressed`); two required scenarios where one passes and one reproduces (`still-reproduces`);
an `unreleased` fix with a passing Git cohort (`not-yet-released`); an unparseable
`fixedVersion`; a scenario citing a duplicate alias, attributed to the canonical owner; and a
confirmed fixed-version pass whose observation carries no known-defect reference at all,
attributed through the catalog with the resolved package versions shown.

### Milestone 3: the command and replay

Add the `dispositions` subcommand to the `owners` command. In live mode it takes `--snapshot
DIR` (an owner snapshot), `--package-map FILE`, `--catalog FILE` (optional; otherwise the
registered scenarios), `--bundle DIR` (the evidence bundle; defaults as the `history` command
does through `Kenshou.Evidence.Config`), `--run-data DIR` (a directory for `directoryRunData`),
`--runs DIR` (repeatable; a directory whose subdirectories are sealed local runs),
`--coverage FILE` (optional), and `--write-input FILE`, which saves the assembled input
document and refuses to overwrite an existing file. In replay mode it takes only `--input
FILE` and reads nothing else. Both modes accept `--json`. The text report groups conclusions by
owner and prints, for each, the owner's claim, the cohort, the disposition with its reasons,
and the run identifiers with their trust. Diagnostics go to standard error. The exit code is 0
when the report was produced, 2 for a usage error, and 4 when an input cannot be read or fails
a digest check; the dispositions themselves do not change the exit code, because gating on them
is the job of the round report in plan 11.

Add fields to plan 8's `OwnerConfig` for a default run-data locator and default evidence
locations, so that a consumer can configure where its run data lives in its own program rather
than on every command line. A consumer whose scenarios need a domain-specific replay step
contributes it through this configuration as a function applied to an observation after
loading; the generic loader imports no consumer oracle.

In `kenshou-cli/test/Main.hs`, extend the synthetic consumer from plan 8: generate a bundle, run
directories, a snapshot, a catalog, and a package map in a temporary directory; run `owners
dispositions --write-input`; then publish one more record, change an owner file, and run
`owners dispositions --input` twice. Assert that the two replays are equal as JSON values, that
they equal the first run's output, that a fresh live run differs, and that every owner file and
evidence record has the same digest as before.

Add `schemas/kenshou.disposition-input.v1.schema.json` and
`schemas/kenshou.dispositions.v1.schema.json` with `check-jsonschema` lines in the
`schemas-check` recipe of `justfile` against the fixture input and a golden output. Extend the
`owners` help topic, add a terminology concept for "disposition" and one for "observation"
under `docs/terminology/`, add a section to `docs/guides/adopting-kenshou-in-a-project.md`, and
write an ADR (allocate with `okf id next docs/adr --profile docs/adr/profile.dhall ADR`) that
records the nine dispositions, the trust rule, and that conclusions are derived readings and
never stored in records. Regenerate indexes with `okf index docs/<bundle> --write`, add
CHANGELOG entries, and note the implementation in IR-4 and its bundle log within what the
profile allows.


## Concrete Steps

All commands run from the repository root inside `nix develop`.

```bash
cabal build kenshou-evidence kenshou-cli
cabal test kenshou-evidence:test:kenshou-evidence-test
cabal test kenshou-cli:test:kenshou-cli-test
```

Replay the fixture:

```bash
K=$(cabal list-bin kenshou)
F=kenshou-evidence/test/fixtures/dispositions
"$K" owners dispositions --input "$F/input.json"
```

The report contains blocks of this shape:

```text
mori://fixture/owner-a/okf/bug-reports/concepts/BUG-2   status=fixed  fixedVersion=1.3.0
  cohort released-1.3 (sha256:…)   fixed-side   verified-fixed
    consumer/table/correctness/lease-release   passed   machine-confirmed   run 01997f3a-…
  cohort released-1.2 (sha256:…)   affected-side   reproduces-as-expected
    consumer/table/correctness/lease-release   reproduced [lease-held]   machine-confirmed   run 01997f2b-…

mori://fixture/owner-a/okf/bug-reports/concepts/BUG-3   status=fixed  fixedVersion=2.0.0
  cohort local (sha256:…)   fixed-side   not-reproduced   insufficient-trust
    consumer/table/correctness/reader-restart   passed   local-sealed   run 01997f4c-…

summary: verifiedFixed=1 stillReproduces=1 reproducesAsExpected=2 notReproduced=3 regressed=1 differentFailure=1 notYetReleased=1 notRun=1 unverifiable=3
```

Confirm that replay is deterministic:

```bash
"$K" owners dispositions --input "$F/input.json" --json > /tmp/first.json
"$K" owners dispositions --input "$F/input.json" --json > /tmp/second.json
cmp /tmp/first.json /tmp/second.json && echo "replay identical"
```

Finish with:

```bash
just verify
```

Commit at each milestone with Conventional Commits and both trailers:

```text
feat(evidence): derive fix-verification dispositions from frozen inputs

ExecPlan: docs/plans/10-derive-fix-verification-dispositions-from-immutable-evidence.md
Intention: intention_01m7nec997edsr5djrs51nzrzs
```


## Validation and Acceptance

For AC-1, the rule-matrix tests pass for compatible confirmed passes, matching reproductions,
unrelated failures, an expected defect that exited 0, absent labels, no runs, and unresolved
records, and each conclusion in the JSON links its observations, scope evaluation, owner claim,
labels, and trust. A test asserts that changing only an observation's exit code changes
nothing.

For AC-2, the tests show that local passes, unverified passes, a refuted attestation, a missing
required scenario, and an incompatible scenario revision each leave `verifiedFixed` at zero for
that owner while the observations remain listed.

For AC-3, the catalog-attribution test passes: a confirmed pass with no known-defect reference
yields `verified-fixed` for the right owner and shows the resolved package versions.

For AC-4, the replay test passes: two replays are byte-identical, a later reproduction after a
confirmed pass yields `regressed`, conflicting scenarios aggregate to the more severe
conclusion, `not-yet-released` and `unverifiable` stay distinct, and every source file's digest
is unchanged.

`just verify` exits 0, including `just coupling-check`.


## Idempotence and Recovery

The command reads evidence, owner snapshots, and run directories and writes only when
`--write-input` is given, to a file that must not already exist. Replay reads one file.
Nothing here modifies an evidence record, a run directory, or an owner record, so every step
can be repeated. To recapture an input, choose a new file name. The change to `RunResultView`
adds fields with defaults, so existing sealed runs and consumer records keep loading; if the
`consumer compatibility` tests in `kenshou-evidence/test/Main.hs` fail after that change, the
defaults are wrong and must be fixed rather than the fixtures.


## Interfaces and Dependencies

No new library dependency is needed. Prerequisites are plan 8's `OwnerStatus`, `OwnerEntry`,
`canonicalOwners`, `readSnapshot`, and `OwnerConfig`, and plan 9's `ScopePackage`,
`evaluateScope`, `scopeApplies`, `cohortScopePackages`, `PackageMap`, `ownerPackages`, and the
declaration-preserving `decodeCatalog`.

In `kenshou-evidence/src/Kenshou/Evidence/Observation.hs`:

```haskell
data Trust = HumanReviewed | MachineConfirmed | Unverified | LocalSealed

data ObservationSource = PublishedRecord Text | SealedRun FilePath

data Labels = LabelsVerified [Text] | LabelsUnavailable Text

data Observation = Observation
  { runId :: Text,
    source :: ObservationSource,
    scenario :: ScenarioId,
    scenarioRevision :: Maybe Int,
    startedAt :: Text,
    outcome :: Outcome,
    labels :: Labels,
    packages :: [ScopePackage],
    cohortName :: Text,
    planHash :: Text,
    trust :: Trust
  }

type RunDataLocator = Text -> DataLink -> IO (Maybe ByteString)

directoryRunData :: FilePath -> RunDataLocator
objectStoreRunData :: ObjectStore -> RunDataLocator
loadPublishedObservations :: RunDataLocator -> FilePath -> IO (Either Text [Observation])
loadSealedObservation :: FilePath -> IO (Either Text Observation)
```

In `kenshou-evidence/src/Kenshou/Evidence/Disposition.hs`:

```haskell
data Disposition
  = VerifiedFixed
  | StillReproduces
  | ReproducesAsExpected
  | NotReproduced
  | Regressed
  | DifferentFailure
  | NotYetReleased
  | NotRun
  | Unverifiable

data DispositionInput = DispositionInput
  { capturedAt :: Text,
    owners :: OwnerStatus,
    catalog :: [ScenarioInfo],
    catalogDigest :: Text,
    packageMap :: PackageMap,
    packageMapDigest :: Text,
    coverage :: Map Text [ScenarioId],
    observations :: [Observation]
  }

data Conclusion = Conclusion
  { owner :: Text,
    cohort :: Maybe (Text, Text),
    disposition :: Disposition,
    reasons :: [Text],
    considered :: [ClassifiedObservation],
    incompatible :: [Observation]
  }

deriveDispositions :: DispositionInput -> [Conclusion]
decodeDispositionInput :: ByteString -> Either Text DispositionInput
```

`deriveDispositions` is pure. Plan 11 calls it once for a round's baseline observations and
once for its candidate observations. The disposition texts in JSON are `verified-fixed`,
`still-reproduces`, `reproduces-as-expected`, `not-reproduced`, `regressed`,
`different-failure`, `not-yet-released`, `not-run`, and `unverifiable`. The documents this plan
introduces are `kenshou.disposition-input/v1` and `kenshou.dispositions/v1`.
