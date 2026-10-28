---
id: 6
slug: carry-the-harness-decisions-vocabulary-and-adoption-guide-into-kenshou-documentation
title: "Carry the harness decisions, vocabulary, and adoption guide into kenshou documentation"
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
      at: 2026-10-28T17:14:50Z
      mode: "implement"
      note: "EP-6 completed: ADR, terminology, guides, improvement-request, and friction-log bundles; adoption guide walked end to end"
---

# Carry the harness decisions, vocabulary, and adoption guide into kenshou documentation

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

The harness packages this repository publishes were written under a set of decisions that
live in another repository, `mori://shinzui/keiro-runtime-kenshou`: why a toolkit never
depends on a layer package, why every result carries a resolved cohort identity, why a
crash means killing a process rather than throwing an exception, how a heap leak is judged,
why sealed runs are never mutated. A consumer who depends on `kenshou-core` cannot be sent
to the Keiro suite's `docs/adr/` to learn those rules, and an implementer of this
repository cannot be expected to remember that the rules exist. The same is true of the
vocabulary (scenario, cohort, run, verdict, oracle, evidence record) and of the one thing a
new consumer needs most: a page that says how to add the packages to a project, register a
layer bundle, assemble an executable, and run a first scenario.

After this plan, this repository has its own governed documentation. `docs/adr/` holds the
harness decisions as this repository's own records, each citing its origin, plus the three
new decisions this initiative makes: the layer-bundle registration contract, the one-ledger
rule with suite-supplied migration sets, and the unchanged package and module names.
`docs/terminology/` holds the controlled vocabulary with layer-specific wording removed.
`docs/improvement-requests/` and `docs/friction-log/` exist so later work has somewhere to
record what it finds. `docs/guides/` holds the operator guide "Adopt kenshou in a project".
Every bundle validates strictly against a pinned shared profile from
`mori://shinzui/okf-profiles`, `just verify` runs those validations, and `mori register`
indexes the bundles so other repositories can cite a kenshou decision as
`mori://shinzui/kenshou/okf/adrs/concepts/ADR-N`.

You can see it working by running `just verify` in the repository root and watching every
`okf validate` step exit 0, by running `mori path mori://shinzui/kenshou/okf/adrs/concepts/ADR-1`
and getting a file path back, and by following the adoption guide from a fresh cabal project
to a passing synthetic scenario.


## Progress

Use checkboxes for verifiable milestones or substantial deliverables, not individual
edits, commands, tests, commits, or session activity. Update this section when a milestone
is accepted, a material blocker or change of course arises, or work is handed off. For a
handoff during a milestone, add a short prose note stating the remaining outcome.

- [x] M1: `docs/adr/` exists with the pinned architecture-decisions descriptor, the
  carried-over harness decisions as kenshou ADRs with origin citations, and strict
  validation exits 0.
  (2026-10-28; the bundle pins okf-profiles v0.25.0; the consumer's ADR-1, 2, 3, 5, 6, 7, 8,
  9, 10, 11, 14, 18, 19, 20, and 21 are ADR-1 to ADR-15 here, each restated for a harness
  that verifies no particular runtime and ending with an Origin paragraph; strict validation
  reports `OK: 15 concepts`.)
- [x] M2: The three initiative ADRs (layer-bundle registration contract, one ledger per
  database with suite-supplied migration sets, unchanged package and module names) are
  recorded, the one-ledger ADR names the consumer decision it supersedes, and strict
  validation still exits 0.
  (2026-10-28; ADR-16 registration contract, ADR-17 one ledger (citing the superseded
  consumer ADR-4 in its body), ADR-18 unchanged names, plus ADR-19 named resources and
  ADR-20 harness cohort and confined consumer data, which EP-1 to EP-4 asked this plan to
  record; strict validation reports `OK: 20 concepts`. All five are Accepted because their
  interfaces are merged.)
- [x] M3: `docs/terminology/`, `docs/improvement-requests/`, and `docs/friction-log/` exist
  with pinned descriptors, the terminology carries the generalized vocabulary, and all three
  validate strictly.
  (2026-10-28; the terminology carries the consumer's thirty terms as TERM-1 to TERM-30,
  generalized where they named one runtime, plus TERM-31 layer identifier, TERM-32 layer
  bundle, and TERM-33 named resource; the improvement-requests bundle is empty; the friction
  log moved from okf-profiles v0.23.0 to v0.25.0. Strict validation reports `OK: 33
  concepts`, `OK: 0 concepts`, and `OK: 1 concepts`.)
- [x] M4: `docs/guides/adopting-kenshou-in-a-project.md` validates strictly, every bundle is
  declared in `mori.dhall` and registered, `README.md` points at the bundles and the guide,
  and `just verify` runs every bundle validation and the index drift check.
  (2026-10-28; DOC-1 validates strictly; the five bundles and a `Guide` doc entry are in
  `mori.dhall`, `mori register` succeeds, and `mori path` resolves ADR-1, TERM-32, and
  DOC-1. A scratch cabal project outside the checkout, laid out as the guide says, built an
  executable that registers `syntheticBundle` next to the self-test bundles. In that project,
  `cohort check` exited 0, and `run` passed both
  `synthetic/echo/correctness/resource-roundtrip` and
  `synthetic/table/correctness/append-survives-kill-restart`. `just verify` gained
  `adr-validate`, `terminology-validate`, `guides-validate`,
  `improvement-requests-validate`, `friction-log-validate`, and `docs-index-check`.)


## Surprises & Discoveries

Document unexpected behaviors, bugs, optimizations, or insights discovered during
implementation. Provide concise evidence. Friction with the tools, documents, and processes
used to do the work belongs in the friction log (see FRICTION.md); cite an entry's FRIC-N
handle here only when it also changed the plan.

- The first draft of the adoption guide did not mention the cohort layout, and the
  walkthrough caught it. In the scratch project, `run` exited 2 with
  `unable to resolve cohort identity: ... ./cohort/active.project: does not exist`. The
  run path resolves a cohort identity from `cohort/active.project`, `cohort/<name>.json`, and
  `dist-newstyle/cache/plan.json`, or from `KENSHOU_COHORT_IDENTITY`. An adopting project
  therefore carries the same `cohort/` layout this repository does. The guide now says so,
  and the rerun passed.
- `kenshou-cli/help/evidence.md` did not list the `evidence.default-subject` and
  `evidence.bundle-uri` keys or their environment variables, which EP-4 added. The guide
  points readers at that help topic, so the topic now lists them.
- `okf` is not part of the development shell; it comes from the user's Nix profile. CI
  therefore wraps `just verify` in
  `nix shell github:shinzui/okf/v0.10.0.0#okf-cli nixpkgs#dhall`, the same release that is
  installed locally. That CI step has not run yet, because nothing has been pushed.


## Decision Log

Record decisions that change scope, architecture, interfaces, acceptance, or the path a
future contributor should follow. Omit routine implementation choices.

- Decision: Pin every bundle to okf-profiles `v0.25.0` (semantic hash
  `sha256:ec74cc6f7b8ee1a5af81ee7fc8804f35cf2c9ba4010671d9e881da72eb6719d3`) rather than
  copying the consumer's mixed `v0.18.0`, `v0.19.0`, and `v0.20.0` pins.
  Rationale: `v0.25.0` is the newest published tag, it exports all five profiles this plan
  uses (the friction-log profile first appeared in `v0.23.0`), and one version means one
  hash to re-freeze when the registry moves.
  Date: 2026-10-28

- Decision: A carried-over ADR is a new kenshou decision dated on the day it is adopted
  here, with a body paragraph citing the consumer's record by Mori handle and its original
  date. It does not copy the consumer's `docId`, `date`, or `generated` values.
  Rationale: Handles are bundle-scoped and allocated by `okf id next`; the consumer's
  history stays in the consumer. Citing the origin keeps the lineage without pretending
  this bundle existed in September.
  Date: 2026-10-28

- Decision: The canonical term for what a consumer registers is "layer bundle"; "layer
  suite" is recorded as discouraged wording in the terminology bundle.
  Rationale: The consumer's vocabulary already defines "suite" as a named planning policy
  (`suites/smoke.json` and its kin). Reusing the word for the registration unit would make
  the adoption guide ambiguous; `LayerBundle` is also the type's name in
  `kenshou-core/src/Kenshou/Core/Bundle.hs`.
  Date: 2026-10-28

- Decision: The registration-contract ADR is written with `status: Proposed` if EP-2, EP-3,
  or EP-4 is still in progress when M2 is reached, and promoted to `Accepted` with an
  `amended` entry once the fields are final.
  Rationale: The plan's hard dependency is only EP-1. Writing the record early lets the
  implementers of EP-2 to EP-4 check their work against it; the status marks it as not yet
  binding.
  Date: 2026-10-28


## Outcomes & Retrospective

Summarize outcomes, gaps, and lessons learned at major milestones or at completion.
Compare the result against the original purpose. Cite the friction entries recorded under
this plan by handle with their triage outcome. Before marking the plan complete,
distill durable project context from the Decision Log, Surprises & Discoveries, and
this section into docs/adr/. Keep task-local execution details here.

The kenshou repository now documents itself as a harness rather than as a part of the
consumer. Five OKF bundles validate strictly and are registered with Mori:
- twenty decisions, fifteen of them carried from the consumer with Origin citations;
- thirty-three terms;
- one guide;
- an empty improvement-request bundle;
- the friction log.

`just verify` validates all five and fails on a stale index. The adoption guide was checked
end to end: a scratch project outside the checkout, laid out as the guide says, assembled
its own executable from `kenshou-cli` and `kenshou-synthetic` and passed two synthetic
scenarios. That walkthrough found the one gap in the first draft, the cohort layout. A
reader without that section would have stopped at exit 2.

Gaps:
- The CI step that fetches `okf` has not run yet, because nothing has been pushed.
- The guide's `source-repository-package` stanza cannot be followed literally until the
  commits reach GitHub. The walkthrough used the local-checkout form the guide also gives.
- The consumer's other operator guides (measurement, diagnosis, evidence, cells,
  telemetry) were not carried. They describe Keiro scenarios and belong in the consumer;
  a harness version of them would be a later guide, recorded here as a possible
  improvement request.

No friction was recorded under this plan. The ADR distillation produced nothing new beyond
ADR-16 to ADR-20: the cohort-layout requirement is already ADR-2's decision, and the guide
now states its consequence for adopters.


## Context and Orientation

This repository, `mori://shinzui/kenshou`, is at `/Users/shinzui/Keikaku/bokuno/kenshou`;
every path below is relative to that root unless it starts with `/`. The consumer whose
documentation this plan carries over is `mori://shinzui/keiro-runtime-kenshou`, checked out
at `/Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou`; confirm the path with
`mori path mori://shinzui/keiro-runtime-kenshou` rather than assuming it.

An OKF bundle is a directory of Markdown files, one concept per file, each with YAML
frontmatter, plus two reserved files: `index.md`, generated by `okf index`, and `log.md`, a
dated change log kept by `okf log add`. A profile is a Dhall description of which
frontmatter fields a bundle's concepts must carry; the shared profiles are published by
`mori://shinzui/okf-profiles` and imported into a bundle through a small `profile.dhall`
descriptor whose import carries a semantic hash. `okf validate --strict --profile-enforce
--log-enforce` is the gate: it fails when a required field is missing, when a handle is
malformed, or when a concept is newer than the latest `log.md` entry. The `okf` binary on
PATH is `v0.10.0.0`, which understands OKF v0.2 and the `generated` actor fields. Read
`okf --help`, `okf validate --help`, `okf profile init --help`, `okf id --help`, and
`okf log add --help` before starting.

No `docs/adr/` exists here yet; this plan creates it, and it is the first ADR bundle in this
repository. The consumer's bundles are the models. Its `mori.dhall` (section `okfBundles`)
shows how a bundle is declared to Mori with a `Published` profile binding naming the
publisher, export, version, and pin; its descriptors `mori/terminology-profile.dhall`,
`mori/improvement-requests-profile.dhall`, `mori/user-documentation-profile.dhall`, and
`docs/adr/profile.dhall` show the two-line pinned-import shape; its `justfile` recipes
`adr-validate`, `terminology-validate`, `guides-validate`, and
`improvement-requests-validate` show the validation commands; and its `docs/adr/index.md`,
`docs/terminology/index.md`, and `docs/guides/index.md` show what generated indexes look
like. Read those files first.

The profiles this plan uses, with the fields they require, are these.
`documentation.architectureDecisions` requires `type: Architecture Decision Record`,
`title` (without the number), `docId` in the form `ADR-N`, `status`, `date` (a calendar
date), a one-sentence `description`, and `generated` with an actor `by` and an RFC3339 UTC
`at`; it allows optional `supersedes`, `supersededBy`, `originatingPlan`, `amended`, and
`verified`. `documentation.terminology` requires `type: Term`, `title` (the canonical
spelling), a one-sentence `description`, `termId` in the form `TERM-N`, `status`, and
`generated`; the consumer's terms also carry `tags`, `related`, and `anchors`, and the
profile has fields for accepted and discouraged wording, so run
`okf profile show --registry "$(mori path mori://shinzui/okf-profiles)/package.dhall" --no-local documentation.terminology`
and read the full field list before writing a term. `documentation.userDocumentation`
requires `type` (the reader intent; the consumer uses `Guide`), `title`, `description`,
`docId` in the form `DOC-N`, `tags`, and `generated`. `coordination.improvementRequests`
requires `requestId` in the form `IR-N` and the fields visible in the consumer's
`docs/improvement-requests/extract-a-layer-agnostic-verification-harness-from-kenshou.md`.
`coordination.frictionLog` requires `frictionId` in the form `FRIC-N` and is written only
through `agents/skills/exec-plan/record-friction.ts`, whose contract is
`agents/skills/exec-plan/FRICTION.md`.

The `generated.by` value is an actor: `human:<id>` for a person, `process:<id>` for an
agent harness, or `<producer>/<version>`. The consumer uses `human:nadeem`,
`process:codex`, and `process:claude-code`. Use the actor that matches who writes each
file. The `at` value is the UTC time of the last meaningful content revision, ending in
`Z`.

Handles are allocated, never chosen. `okf id next docs/adr --profile docs/adr/profile.dhall
ADR` prints the next unused `ADR-N`; the same command with `TERM`, `DOC`, `IR`, or `FRIC`
and the matching bundle does the same for the other prefixes. Never derive a number by
counting files. Within this repository, cite a record by repository-relative link; across
repositories, cite only the handle-form URI that Mori prints, for example
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-3`, and check it with
`mori path <uri>` before writing it down. Mori resolves terminology handles the same way,
for example `mori://shinzui/keiro-runtime-kenshou/okf/terminology/concepts/TERM-1`.

The cross-repository decisions this plan carries are all in the consumer's `docs/adr/`.
Read each one in full before carrying it. Their handles, verified with `mori path`, are
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-1` through `ADR-23`. The
MasterPlan at `docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md`
explains which of them matter to the initiative and why ADR-4 must be superseded rather
than carried; its Integration Points section describes the layer-bundle registration
contract that M2 records.

Two other plans shape this one. EP-1
(`docs/plans/1-import-the-harness-packages-from-keiro-runtime-kenshou-and-build-them-standalone.md`)
creates the cabal workspace, the `justfile`, and its `verify` recipe; this plan adds
recipes to that file and must not start before EP-1 is Complete. EP-2, EP-3, and EP-4
define the fields of `Kenshou.Core.Bundle.LayerBundle` that the registration-contract ADR
and the adoption guide describe; EP-5 adds the `kenshou-synthetic` package the guide uses
as its example. Those are soft dependencies: start the carried-over records and the
vocabulary as soon as EP-1 is done, and finish the registration-contract ADR and the guide
against the merged code.

The friction-log bundle is bootstrapped by the exec-plan skill's script, not by hand.
`agents/skills/exec-plan/FRICTION.md` says the script pins okf-profiles `v0.23.0` by
default and accepts `--registry` to pin another source; this plan pins `v0.25.0` to match
the other bundles.


## Plan of Work

The work has four milestones. M1 and M3 are mechanical carrying with judgment about what is
generic; M2 and M4 are new writing against interfaces other plans own.

M1 creates `docs/adr/` and fills it with the harness decisions. Bootstrap the bundle with
`okf profile init`, pinning the `v0.25.0` package, then freeze the descriptor so the import
carries its hash. Then carry the consumer's records in their original order, one file per
decision, each named `<NNNN>-<slug>.md` after the handle `okf id next` returns, with the
body restated for a harness that knows no particular runtime. The disposition of the
consumer's twenty-three records is as follows.

Carry ADR-1 restated as "Toolkit packages never depend on a layer bundle": the kernel
(`kenshou-core`) and the toolkits (`kenshou-check`, `kenshou-measure`, `kenshou-diagnose`,
`kenshou-telemetry`, `kenshou-evidence`, `kenshou-remote`) depend only on each other in
the order the cabal files declare, a consumer's layer packages depend on them, and layer
packages never depend on one another; this is the boundary the whole initiative relies on.
Carry ADR-2 (every result carries a resolved cohort identity) because
`Kenshou.Core.Cohort` is generic; note that the cohort descriptor files belong to the
consumer. Carry ADR-3 (the kernel owns the verification protocol) with the document
identifiers `kenshou.*/v1` and the exit-code meanings unchanged. Carry ADR-5 (select runs
from a checked-in component graph) because `Kenshou.Plan.Components` and the over-selection
rule are generic. Carry ADR-6 (comparison verdicts require controlled benchmark evidence)
because it governs `Kenshou.Measure.Compare`. Carry ADR-7, ADR-8, ADR-9, ADR-10, and ADR-11
(independent measurement, invariant classes, crash definition, heap-leak basis, sealed-run
immutability); when carrying ADR-8, drop its final paragraph that classifies Kiroku's
invariants, because that classification is the consumer's, and say instead that each layer
bundle classifies its own invariants under the same rule. Carry ADR-14 (documented
limitations versus known defects) because the known-defect mechanism lives in
`Kenshou.Core.Scenario`. Carry ADR-18, ADR-19, ADR-20, and ADR-21 (immutable records and
derived baselines, relax-only evidence profile, payloads pinned to verified cohort
identities, cell runs addressed by submission and nested run); when carrying ADR-18 and
ADR-20, say that the harness owns the record shapes and the identity check while the
narrowed `layer` vocabulary and the cohort descriptor are the consumer's.

Do not carry ADR-4; M2 supersedes it. Do not carry ADR-12, ADR-13, ADR-15, ADR-16, ADR-17,
ADR-22, or ADR-23: they decide how the PGMQ, Kiroku, Keiro, Kafka, and assembled-runtime
suites behave, or how the consumer calibrates its performance gates, and a harness consumer
makes those decisions in its own repository. ADR-13's advice that a layer without a metrics
endpoint polls its native SQL surface is worth one sentence in the adoption guide, not a
record here.

Every carried record ends with a paragraph headed "Origin" that cites the consumer's
record by handle-form URI and gives its original date, for example "Adopted from
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-9`, decided 2026-09-21". The
record's own `date` is the kenshou adoption date. After writing the files, regenerate the
index with `okf index docs/adr --write --okf-version 0.2`, add one `log.md` entry with
`okf log add`, and validate strictly. M1 is accepted when validation exits 0 and the index
lists every carried record.

M2 adds the three decisions this initiative makes. The first records the layer-bundle
registration contract: a consumer registers a `Kenshou.Core.Bundle.LayerBundle` carrying
an open layer identifier (EP-2), scenarios and worker roles (already present), a migration
set composed into one ledger per database (EP-2), named extra resources with local and cell
provisioners (EP-3), oracles, diagnostic lock labels, and a default evidence subject
(EP-4), and the registry validates the bundle set with `mkRegistry`. Read the merged code
in `kenshou-core/src/Kenshou/Core/Bundle.hs` and the sibling modules those plans name, and
describe the fields that actually exist, with the file paths. The second supersedes the
consumer's ADR-4: scenarios still receive database handles from the harness and one
`pg-migrate` ledger per database still applies every migration, but the migration sets are
supplied by the registered bundles instead of being named in the kernel; cite the consumer's
record by handle in the body and in a `supersedes` field only if the profile accepts a
cross-repository value there (it is defined for bundle-local handles, so prefer the body
citation and leave `supersedes` out). The third records that the package names
`kenshou-core`, `kenshou-check`, `kenshou-measure`, `kenshou-diagnose`, `kenshou-telemetry`,
`kenshou-evidence`, `kenshou-remote`, and `kenshou-cli` and the `Kenshou.*` module namespace
are kept so the first consumer adopts the release by deleting its local packages, with the
rationale from the MasterPlan's Decision Log. Each new record cites the MasterPlan by path
in `originatingPlan`. M2 is accepted when the three records validate strictly and, if the
registration contract is still `Proposed`, the plan's Progress note says which plan's
completion will promote it.

M3 creates the other three bundles. For `docs/terminology/`, bootstrap with `okf profile
init`, then carry every term from the consumer's catalog, allocating `TERM-N` handles in
the consumer's order so the `related` lists can be rewritten by a stable mapping. Rewrite
wording that names a runtime: the oracle term says "the system's durable tables" rather
than Kiroku, Keiro, or PGMQ; the cohort term describes the resolved package set without
naming `released` and `head` descriptors as the harness's own; any `anchors` entry
pointing at a consumer-only file is dropped or redirected to the kenshou file with the same
module. Add new terms for "layer identifier" (the open identifier EP-2 introduces), "layer
bundle" (the registration unit, with "layer suite" as discouraged wording), and "extra
resource" (the named resource EP-3 introduces), each anchored to its module. Write
`docs/terminology/index.md` by hand in the consumer's grouped style if `okf index` cannot
reproduce the groups, and check with `okf index docs/terminology` that the generated form
lists the same files. For `docs/improvement-requests/`, bootstrap the bundle empty; its
first request arrives when someone has one. For `docs/friction-log/`, run the exec-plan
skill's init with the `v0.25.0` registry and re-freeze the descriptor. M3 is accepted when
all three bundles validate strictly.

M4 writes the adoption guide and closes the loop. Bootstrap `docs/guides/` with the
user-documentation profile, allocate `DOC-1`, and write
`docs/guides/adopting-kenshou-in-a-project.md` as a `Guide` for a Haskell developer who has
a system to verify and has never seen kenshou. It walks through adding the published
packages to `cabal.project` (or the `kenshou` git source until the release in EP-7 exists),
declaring a layer bundle with its identifier, scenarios, roles, migration set, resources,
oracle, lock labels, and evidence subject, assembling the executable by passing the bundle
list to the entry point `kenshou-cli` exposes after EP-1, running `kenshou list` and
`kenshou run <scenario>` against a locally provisioned PostgreSQL, configuring the evidence
bundle URI and subject, and where to read next. Every snippet is taken from
`kenshou-synthetic` so it compiles; name the files it comes from. Then add the `okfBundles`
declarations and a `docs` entry for the guide to `mori.dhall` in the consumer's shape, run
`mori validate` and `mori register`, add the `justfile` recipes and wire them into
`verify`, and refresh `README.md` so it names the bundles, the guide, and the validation
command. M4 is accepted when the guide validates strictly, `mori register` succeeds,
`mori path mori://shinzui/kenshou/okf/adrs/concepts/ADR-1` prints a file path, and
`just verify` runs every validation.


## Concrete Steps

All commands run in the repository root, `/Users/shinzui/Keikaku/bokuno/kenshou`, inside
`nix develop` so `okf`, `dhall`, `mori`, `bun`, and `just` are on PATH. Check the tools
first:

```bash
okf --version && dhall version && mori --version && bun --version && just --version
```

Bootstrap the ADR bundle, pinning the published registry, then freeze the import so it
carries the semantic hash:

```bash
okf profile init \
  --registry 'https://raw.githubusercontent.com/shinzui/okf-profiles/v0.25.0/package.dhall' \
  --no-local documentation.architectureDecisions --bundle docs/adr --write
dhall freeze --inplace docs/adr/profile.dhall
cat docs/adr/profile.dhall
```

The descriptor should read, apart from comments, as a pinned import and one export:

```dhall
let Profiles =
      https://raw.githubusercontent.com/shinzui/okf-profiles/v0.25.0/package.dhall
        sha256:ec74cc6f7b8ee1a5af81ee7fc8804f35cf2c9ba4010671d9e881da72eb6719d3

in  Profiles.documentation.architectureDecisions
```

If `okf profile init` writes a descriptor of a different shape, keep what it writes and
only confirm that the import URL names `v0.25.0` and that the hash matches the one above;
never type a hash by hand. If the hash differs after `dhall freeze`, stop: the published
tag has moved, and the MasterPlan's Decision Log needs a new entry before you pin it.

Allocate the first handle and write the first carried record:

```bash
okf id next docs/adr --profile docs/adr/profile.dhall ADR
```

```text
ADR-1
```

Create `docs/adr/0001-toolkit-packages-never-depend-on-a-layer-bundle.md` with frontmatter
of this shape, then the body sections Context, Decision, Consequences, and Origin:

```yaml
---
type: Architecture Decision Record
title: Toolkit packages never depend on a layer bundle
description: The kernel and toolkits depend only on one another; layer bundles depend on them and never on each other, so a failing layer is attributable and layers build independently.
docId: ADR-1
status: Accepted
date: 2026-11-04
generated:
  by: process:claude-code
  at: "2026-11-04T10:00:00Z"
---
```

Repeat for each carried record in the order given in Plan of Work, running `okf id next`
before each file. After the last one, generate the index, log the adoption, and validate:

```bash
okf index docs/adr --write --okf-version 0.2
okf log add docs/adr --kind Decision -m "Adopt the harness decisions carried from mori://shinzui/keiro-runtime-kenshou as ADR-1 through ADR-N."
okf validate docs/adr --strict --profile docs/adr/profile.dhall --profile-enforce --log-enforce
```

The validation prints one line per concept and exits 0. A failure names the file and the
field; fix the file, never the flags.

For M2, allocate three more handles the same way and write the records described in Plan
of Work. Then run the same index, log, and validate commands. The one-ledger record's body
contains a sentence of the form "This supersedes
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-4` for this repository".

For M3, bootstrap the terminology and improvement-request bundles with the same
`okf profile init` form, substituting the export and bundle:

```bash
okf profile init \
  --registry 'https://raw.githubusercontent.com/shinzui/okf-profiles/v0.25.0/package.dhall' \
  --no-local documentation.terminology --bundle docs/terminology --write
dhall freeze --inplace docs/terminology/profile.dhall
okf profile init \
  --registry 'https://raw.githubusercontent.com/shinzui/okf-profiles/v0.25.0/package.dhall' \
  --no-local coordination.improvementRequests --bundle docs/improvement-requests --write
dhall freeze --inplace docs/improvement-requests/profile.dhall
```

List the consumer's terms to carry, in handle order, with the file each lives in:

```bash
okf concepts "$(mori path mori://shinzui/keiro-runtime-kenshou)/docs/terminology" --show termId --show title
```

Carry each term, allocating with `okf id next docs/terminology --profile
docs/terminology/profile.dhall TERM`, then add the three new terms, regenerate the index,
log, and validate:

```bash
okf index docs/terminology --write --okf-version 0.2
okf log add docs/terminology --kind Addition -m "Bootstrap the harness vocabulary from mori://shinzui/keiro-runtime-kenshou with layer-specific wording generalized; add layer identifier, layer bundle, and extra resource."
okf validate docs/terminology --strict --profile docs/terminology/profile.dhall --profile-enforce --log-enforce
okf validate docs/improvement-requests --strict --profile docs/improvement-requests/profile.dhall --profile-enforce --log-enforce
```

Bootstrap the friction log through the skill's script, pointing it at the published
registry, then re-freeze and validate:

```bash
bun agents/skills/exec-plan/record-friction.ts init \
  --registry 'https://raw.githubusercontent.com/shinzui/okf-profiles/v0.25.0/package.dhall'
dhall freeze --inplace docs/friction-log/profile.dhall
okf validate docs/friction-log --strict --profile docs/friction-log/profile.dhall --profile-enforce --log-enforce
```

If the script rejects a URL for `--registry`, pass the local checkout instead,
`"$(mori path mori://shinzui/okf-profiles)/package.dhall"`, and then replace the relative
import it writes with the `v0.25.0` URL above before freezing, as
`agents/skills/exec-plan/FRICTION.md` instructs.

For M4, bootstrap the guides bundle and allocate its handle:

```bash
okf profile init \
  --registry 'https://raw.githubusercontent.com/shinzui/okf-profiles/v0.25.0/package.dhall' \
  --no-local documentation.userDocumentation --bundle docs/guides --write
dhall freeze --inplace docs/guides/profile.dhall
okf id next docs/guides --profile docs/guides/profile.dhall DOC
```

Write `docs/guides/adopting-kenshou-in-a-project.md` with this frontmatter shape and the
sections named in Plan of Work:

```yaml
---
type: Guide
title: Adopt kenshou in a project
description: Add the kenshou packages to a cabal project, register a layer bundle, assemble the verification executable, and run a first scenario.
docId: DOC-1
tags: [adoption, layer-bundle, cabal, scenario, evidence]
generated:
  by: process:claude-code
  at: "2026-11-05T10:00:00Z"
---
```

Then index, log, and validate the guides bundle with the same commands as the others,
using `--kind Create` for the log entry.

Declare the bundles to Mori by adding an `okfBundles` list to `mori.dhall`, one entry per
bundle in the consumer's shape; the ADR entry looks like this, and the others differ only
in `name`, `path`, `profile`, `export`, and `description`:

```dhall
, Schema.OkfBundle::{
  , name = "adrs"
  , path = "docs/adr"
  , profile = Some "docs/adr/profile.dhall"
  , profileBinding = Some
      ( Schema.ProfileBinding.Published
          Schema.PinnedImport::{
          , publisher = "shinzui/okf-profiles"
          , publisherRef = Some Schema.MoriRef::{ namespace = "shinzui", name = "okf-profiles" }
          , export = Some "documentation.architectureDecisions"
          , version = Some "v0.25.0"
          , pin = Some "sha256:ec74cc6f7b8ee1a5af81ee7fc8804f35cf2c9ba4010671d9e881da72eb6719d3"
          }
      )
  , okfVersion = "0.2"
  , description = Some "Durable harness architecture decisions"
  }
```

The exports are `documentation.architectureDecisions` for `adrs`,
`documentation.terminology` for `terminology`, `documentation.userDocumentation` for
`guides`, `coordination.improvementRequests` for `improvement-requests`, and
`coordination.frictionLog` for `friction-log`. Also add a `docs` entry of kind `Guide`
pointing at the adoption guide. Then validate and register:

```bash
mori validate && mori register
mori path mori://shinzui/kenshou/okf/adrs/concepts/ADR-1
```

```text
Configuration is valid.
Project registered: shinzui/kenshou
mori://shinzui/kenshou/okf/adrs/concepts/ADR-1
/Users/shinzui/Keikaku/bokuno/kenshou/docs/adr/0001-toolkit-packages-never-depend-on-a-layer-bundle.md
```

Add recipes to `justfile` and list them in `verify`. Each recipe is the strict validation
command for one bundle, in the consumer's form; add one more that regenerates every index
and fails on drift:

```just
[group('docs')]
adr-validate:
    okf validate docs/adr --strict --profile docs/adr/profile.dhall --profile-enforce --log-enforce

[group('docs')]
docs-index-check:
    okf index docs/adr --write
    okf index docs/terminology --write
    okf index docs/guides --write
    okf index docs/improvement-requests --write
    okf index docs/friction-log --write
    git diff --exit-code -- docs/adr docs/terminology docs/guides docs/improvement-requests docs/friction-log
```

Write `terminology-validate`, `guides-validate`, `improvement-requests-validate`, and
`friction-log-validate` the same way, then append all six names to the `verify` recipe's
dependency list that EP-1 created. Run `just verify` and confirm the new steps appear and
exit 0.

Refresh `README.md`: in the layout block add the five `docs/` bundles with one-line
descriptions, and under Getting started add a sentence pointing at the adoption guide and
one naming `just verify` as the check that includes documentation validation.


## Validation and Acceptance

Run the full gate from the repository root:

```bash
just verify
```

It must run the five bundle validations and the index drift check, and exit 0. Then check
each acceptance behavior directly.

For M1, `okf validate docs/adr --strict --profile docs/adr/profile.dhall --profile-enforce
--log-enforce` exits 0, `okf concepts docs/adr --show docId --show title` lists one record
for every carried decision named in Plan of Work and none for the excluded ones, and
`grep -L 'mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-' docs/adr/0*.md`
prints only the files that are new kenshou decisions, because every carried record cites
its origin.

For M2, the same validation exits 0, the one-ledger record contains the sentence
superseding the consumer's ADR-4, and the registration-contract record names every
`LayerBundle` field that exists in `kenshou-core/src/Kenshou/Core/Bundle.hs` at the time
of writing; compare with `grep -n '::' kenshou-core/src/Kenshou/Core/Bundle.hs` over the
`LayerBundle` record. If a field in the code is missing from the record, the record is
wrong, not the code.

For M3, the three validations exit 0, `okf concepts docs/terminology --show termId --show
title` lists every carried term plus `layer identifier`, `layer bundle`, and `extra
resource`, and a case-insensitive search for `kiroku`, `keiro`, `pgmq`, `shibuya`, and
`kafka` across `docs/terminology/*.md` finds only citations of the consumer's Mori URIs:

```bash
grep -il 'kiroku\|keiro\|pgmq\|shibuya\|kafka' docs/terminology/*.md | xargs -I{} grep -L 'mori://shinzui/keiro-runtime-kenshou' {}
```

That command prints nothing when the vocabulary is clean.

For M4, the guides validation exits 0, `mori register` succeeds, `mori path` resolves the
ADR handle as shown in Concrete Steps, and a reader following the guide in a scratch cabal
project that depends on this repository's packages reaches a passing `kenshou run` of the
synthetic scenario the guide names. That last check is the representative producer and
consumer interaction for this plan: the producer is `kenshou-synthetic`, the consumer is
the guide's reader, and the check is owned by this plan. If EP-5 is not complete when the
guide is first written, run the guide against the self-test scenario that EP-1's standalone
executable registers, and note in Progress that the synthetic walkthrough is pending.

Required acceptance is everything above. Proposals beyond it, not required here: a second
guide on contributing a toolkit extension, and a `docs/research/` bundle. Record them as
improvement requests if wanted.


## Idempotence and Recovery

`okf profile init --write` refuses to overwrite an existing descriptor; re-running it on a
bootstrapped bundle is a no-op or an error, never a change. `dhall freeze --inplace` is
idempotent. `okf index --write` regenerates from the files on disk, so it can be run any
number of times; `git diff` shows whether anything changed. `okf log add` appends, so run
it once per batch of changes, not once per retry; if a duplicate entry lands, delete the
duplicate line from `log.md` by hand, since the log is plain Markdown. `okf id next` is
read-only. `mori register` is idempotent.

If a carried record fails validation, the usual causes are a `date` that is not a plain
calendar date, a `generated.at` without a trailing `Z`, or a `docId` that does not match the
file's position in the allocation order. Fix the frontmatter and re-run the validation; do
not renumber other files to make room, and never recycle a handle.

If `mori validate` rejects the `okfBundles` entry, compare field by field with the
consumer's `mori.dhall`, which is known to validate against the same pinned schema. If
`mori path` cannot resolve a kenshou handle after `mori register`, run `mori status` to see
whether the registration is stale and re-register; the Mori URI shape is the one the
consumer's handles already use, so a resolution failure is a registration problem, not a
reason to change the citation form.

Nothing in this plan is destructive. Every file it creates is new; the only existing files
it edits are `mori.dhall`, `justfile`, and `README.md`, all under version control.


## Interfaces and Dependencies

Tools: `okf` 0.10.0.0 or later (OKF v0.2 and profile `generated` actors), `dhall` for
`freeze`, `mori` for `validate`, `register`, and `path`, `bun` for the exec-plan skill
scripts, and `just`. All are in the dev shell that `flake.nix` provides.

Profiles: the five exports of `mori://shinzui/okf-profiles` at `v0.25.0`,
`documentation.architectureDecisions`, `documentation.terminology`,
`documentation.userDocumentation`, `coordination.improvementRequests`, and
`coordination.frictionLog`, imported by hash
`sha256:ec74cc6f7b8ee1a5af81ee7fc8804f35cf2c9ba4010671d9e881da72eb6719d3`. Canonical
profile handles, for citation: `mori://shinzui/okf-profiles/profiles/architecture-decisions`
and `mori://shinzui/okf-profiles/profiles/friction-log` resolve today; find the other three
with `mori path` before citing them.

Scripts: `agents/skills/exec-plan/record-friction.ts` for the friction-log bundle, under
the contract in `agents/skills/exec-plan/FRICTION.md`; `agents/skills/exec-plan/ADR.md` for
handle allocation and citation rules.

Code the documentation describes: `kenshou-core/src/Kenshou/Core/Bundle.hs`
(`LayerBundle`, `mkRegistry`), `kenshou-core/src/Kenshou/Core/Id.hs` (the layer identifier
after EP-2), `kenshou-core/src/Kenshou/Core/Env.hs` and
`kenshou-core/src/Kenshou/Core/Env/Migration.hs` (migration sets after EP-2, resources
after EP-3), `kenshou-check/src/Kenshou/Check/Oracle.hs` and
`kenshou-diagnose/src/Kenshou/Diagnose/Postgres.hs` (oracles and lock labels after EP-4),
`kenshou-evidence/src/Kenshou/Evidence/Config.hs` (evidence configuration after EP-4), the
`kenshou-cli` entry point after EP-1, and the `kenshou-synthetic` package after EP-5.

The names those plans fixed at drafting time, for the registration-contract record:
`Kenshou.Core.Id.LayerId` (`mkLayerId`, `renderLayer`, `parseLayer`);
`Kenshou.Core.Bundle.LayerBundle` built with `mkBundle` and carrying `migrations`, `rules`,
`resources`, `oracles`, `advisoryLabels`, `methodology`, `evidenceSubject`, and
`routingRules`; `Kenshou.Core.Env.MigrationSet`; `Kenshou.Core.Resource.ResourceProvider`;
`Kenshou.Core.Contribution`; `Kenshou.Core.Cli.Program`, also exposed as
`Kenshou.Cli.Registry.CliAssembly`, with `mainWith`; the configuration keys
`evidence.default-subject` and `evidence.bundle-uri`; and the guard files
`scripts/coupling-guard.sh` and `scripts/coupling-allowlist.txt`. Verify each against the
merged code before the record leaves `Proposed`.

Prerequisites from the MasterPlan: EP-1 Complete before any milestone starts, because the
`justfile` and the cabal workspace must exist. EP-2, EP-3, EP-4, and EP-5 are soft: M1 and
M3 do not need them; M2's registration-contract record and M4's guide are finished against
their merged code and are written as `Proposed` or with a pending note until then.
