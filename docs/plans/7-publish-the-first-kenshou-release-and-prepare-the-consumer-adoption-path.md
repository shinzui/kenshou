---
id: 7
slug: publish-the-first-kenshou-release-and-prepare-the-consumer-adoption-path
title: "Publish the first kenshou release and prepare the consumer adoption path"
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
      at: 2026-10-28T17:31:09Z
      mode: "implement"
      note: "M1 readiness (audit, metadata, bounds, sdists) and DOC-2; tag and publication await user confirmation"
---

# Publish the first kenshou release and prepare the consumer adoption path

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

After this plan, the nine `kenshou-*` packages exist on Hackage at version `0.1.0.0`, tagged
`v0.1.0.0` in this repository, and a fresh cabal project that depends on `kenshou-core ==0.1.0.0`
resolves and builds them from Hackage without any checkout of this repository. The Mori registry
describes the project as a released library set. A checked-in adoption guide tells the first
consumer, `mori://shinzui/keiro-runtime-kenshou`, exactly how to replace its local copies of the
harness with the published release and how to prove that nothing changed in its verdicts.

The adoption itself is not performed here. By the user's direction the consumer does not use
kenshou until the release is published, and the adoption is executed by a plan created in the
consumer repository. This plan ends when the release is resolvable and the adoption guide has been
verified to the point where every command it gives has been run once against the consumer's
working tree in read-only form.

You can see the outcome working by running, in an empty directory, a two-file cabal project that
depends on `kenshou-core` and watching `cabal build` download `kenshou-core-0.1.0.0.tar.gz` from
Hackage and compile it.


## Progress

- [x] M1: Release readiness. Every package passes `cabal check` with no warnings about missing
  license or changelog files, every package has a `CHANGELOG.md` with a `0.1.0.0` entry,
  `cabal sdist all` produces nine tarballs, the divergence audit against the consumer at commit
  `a1648293443ad88ff1695ed800ff44c99993574e` has been run and any generic-package change found
  has been ported, and the commit is tagged `v0.1.0.0`.
  Progress (2026-10-28): the divergence audit is clean and nothing needed porting. The
  release metadata is in place:
  - a `LICENSE` and a `CHANGELOG.md` in each package;
  - `license-file`, `extra-doc-files`, `homepage`, `bug-reports`, and a
    `source-repository` in each cabal file;
  - `^>=0.1.0.0` on every internal dependency;
  - PVP upper bounds on every dependency that `cabal check` named.

  `cabal check` reports no errors or warnings in all nine packages, and `cabal sdist all`
  writes nine tarballs. `just verify` passes. The user confirmed candidate uploads, so
  `v0.1.0.0` is an annotated tag on `78f1f7a`. It is local and not pushed.
- [ ] M2: Publication. The nine packages are published on Hackage (not candidates) with
  documentation uploaded, in dependency order, and a fresh cabal project outside this checkout
  builds against `kenshou-core ==0.1.0.0` at a recorded `index-state`.
  Progress (2026-10-28): all nine packages are uploaded as Hackage candidates, in dependency
  order, from tarballs built at `v0.1.0.0`. They are at
  `https://hackage.haskell.org/package/<name>-0.1.0.0/candidate`. Next, the user reviews the
  candidate pages and confirms publication. Then come `just publish`, the documentation
  uploads, the recorded `index-state`, and the resolvability proof.
- [ ] M3: Registration. `mori.dhall` keeps lifecycle `Experimental`, records the release and
  the nine packages,
  `mori validate` and `mori register` succeed, and an improvement request for a `kenshou` family
  has been filed in `mori://shinzui/haskell-nix`.
- [ ] M4: Adoption guide. `docs/guides/adopt-in-keiro-runtime-kenshou.md` is checked in, validates
  under the guides bundle profile, and every read-only command it contains (the divergence audit,
  the inventory listing, the cohort pin shape) has been executed once against the consumer
  checkout with the transcript recorded in the plan.
  Progress (2026-10-28): DOC-2 is checked in and `just guides-validate` reports
  `OK: 2 concepts`. Three of its commands ran against the consumer:
  - the divergence audit;
  - the inventory listing;
  - a read of the cohort pin shape. `cohort/released.project` has its `extra-packages`
    block at line 8 and `constraints` at line 52. `cohort/released.json` is
    `kenshou.cohort/v1`, and its components have the `id`, `moriUri`, `source`, and
    `packages` shape that DOC-2 adds.

  The `cabal get` form of the inventory listing and the Nix prefetch need the published
  release, so they remain.


## Surprises & Discoveries

- Divergence audit, 2026-10-28, run in the consumer checkout after `git fetch origin`.
  `origin/master` was `2129bb9`, three commits past the pin: `9ea967a` (seihou modules),
  `6514438` (nix-haskell-flake update), and `2129bb9` (a research document). None touches an
  imported path. Both of these printed nothing:

  ```bash
  git diff --stat "$PIN"..origin/master -- $GENERIC
  git log --oneline --no-merges "$PIN"..origin/master -- $GENERIC
  ```

  `GENERIC` was the complete imported set from `docs/import-provenance.md`. That set also
  includes `suites` and `policies/selftest.json`, which this plan's Concrete Steps omitted;
  DOC-2 gives the complete list.
- `cabal check` found three errors that Hackage rejects:
  - `kenshou-core` and `kenshou-cli` use `Paths_*` modules without listing them in
    `autogen-modules`;
  - `kenshou-diagnose` used extension-less `**/*` globs for its run fixtures.

  It also found that `kenshou-remote` had no `description`, and that sixty-five library
  dependencies had no upper bound. Each bound is the PVP major of the version in the
  resolved `plan.json`.
- The changelogs' provenance line names the consumer's Mori URI, so the coupling guard
  flagged it. Those eight exact lines are in `scripts/coupling-allowlist.txt`, under a
  header sentence that names this exception.
- Inventory listing for DOC-2, run against this checkout's `kenshou-cli/src` (the published
  tarball does not exist yet). The consumer-only modules are exactly the twelve
  `Kenshou.Cli.Attest.Keiro*` modules. The released `kenshou-cli` also exports
  `Kenshou.Cli.Registry` and `Kenshou.Cli.Attest`, so the consumer must rename its own
  modules of those names; DOC-2 says so.
- The cohort-pin and Nix-prefetch commands in DOC-2 need the published release. They have
  not run yet.
- The nine tarballs, unpacked into an empty project with the harness cohort, build every
  library, executable, and test suite. This proves every Template Haskell embed is shipped.
  Their test suites still fail there:
  - At first, 260 cases failed, because only some packages listed their fixtures in
    `extra-source-files`. Each package now ships its own fixtures, which leaves 84 failures.
  - Every remaining failure reads a path outside the package: `../fixtures/consumer-baseline/`,
    `../policies/`, `../suites/`, or a sibling package's goldens.
  - `kenshou-check` and `kenshou-telemetry` pass from their tarballs.

  This is recorded as
  [IR-1](../improvement-requests/run-every-package-test-suite-from-its-source-distribution.md).


## Decision Log

- Decision: Release all nine packages at the shared version `0.1.0.0` and tag the repository
  `v0.1.0.0`.
  Rationale: Every imported cabal file already declares `0.1.0.0`, the packages have never been
  published, and a shared version lets the consumer pin the whole set with one constraint block,
  the same way `hinagata` released its three packages at one version on 2026-10-18. Internal
  dependencies are bounded `^>=0.1.0.0` so a later patch release of one package does not force a
  lock-step bump of the others.
  Date: 2026-10-28

- Decision: Publish to Hackage with `cabal upload --publish`; do not add a `kenshou` family to the
  `haskell-nix` registry in this plan.
  Rationale: Every first-party package the consumer pins (`pg-migrate`, `ephemeral-pg`,
  `pgmq-*`, `keiro-*`) is consumed from Hackage at an exact `index-state`, which is what
  `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-2` requires of a released cohort.
  The `haskell-nix` registry's generated lock is schema version 2, whose documentation states that
  adding a family "requires a separately designed migration"; that design belongs to that
  repository and is requested from it rather than done here.
  Date: 2026-10-28

- Decision: Run the divergence audit twice, once before the release and once at adoption.
  Rationale: The import in EP-1 pinned the consumer at `a1648293443ad88ff1695ed800ff44c99993574e`
  and the consumer may have changed its generic packages since. A change ported before `0.1.0.0`
  reaches the consumer in the first release; a change found only at adoption needs a patch
  release, so the earlier audit is cheaper.
  Date: 2026-10-28


- Decision: Tag `v0.1.0.0` only when publication is confirmed, immediately before the
  candidate uploads, rather than at the end of M1.
  Rationale: Publishing is irreversible and waits on the user. A candidate review may still
  require a fix commit. An unpushed tag could be moved, but tagging only the commit that is
  actually uploaded keeps the tag honest without relying on that.
  Date: 2026-10-28

- Decision: Release 0.1.0.0 with test suites that pass only in the repository checkout, and
  tell Nix builders to use `dontCheck`. Do not restructure the imported tests in this plan.
  Rationale: Hackage does not run test suites, so publication is unaffected. About eighty
  cases read repository-level data. Some of it is the consumer baseline, which ADR-20 keeps
  outside the packages. Making those cases tarball-safe would rework imported tests well
  beyond release readiness. The work is filed as IR-1, so it is visible and has acceptance
  criteria. DOC-2's Nix overrides carry `dontCheck` until it lands.
  Date: 2026-10-28

- Decision: `docs-index-check` compares each index before and after regeneration instead of
  running `git diff --exit-code`.
  Rationale: The `git diff` form, written by EP-6, failed `just verify` whenever any
  documentation edit was uncommitted, including correct ones. Comparing before and after
  catches exactly a stale index.
  Date: 2026-10-28


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

This repository holds nine cabal packages under `kenshou-core/`, `kenshou-check/`,
`kenshou-measure/`, `kenshou-diagnose/`, `kenshou-telemetry/`, `kenshou-evidence/`,
`kenshou-remote/`, `kenshou-cli/`, and `kenshou-synthetic/`, created by EP-1 and generalized by
EP-2 to EP-5. They were copied from `mori://shinzui/keiro-runtime-kenshou` (local checkout
`/Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou`, called "the consumer" below) at commit
`a1648293443ad88ff1695ed800ff44c99993574e`. The consumer still carries its own copies of the first
eight of those packages and builds them from source; the ninth, `kenshou-synthetic`, exists only
here. EP-5's coupling guard in `justfile` proves that nothing in the nine packages names a Keiro
runtime layer. EP-6 created `docs/adr/` and `docs/guides/` as OKF bundles; read
`docs/adr/index.md` and cite by path any record about the suite registration contract or the
protocol documents when the adoption guide refers to them.

A "release" here is three things that must agree: a git tag, a set of source distributions
(sdists, the `.tar.gz` files `cabal sdist` writes under `dist-newstyle/sdist/`), and the Hackage
packages built from those sdists. Hackage is the public Haskell package index at
`https://hackage.haskell.org`; `cabal upload` without `--publish` creates a *candidate* that can be
inspected and replaced, and `cabal upload --publish` creates the permanent package. A Hackage
`index-state` is a timestamp that freezes which package versions a cabal solver can see; the
consumer records one in `cohort/released.project` and in `cohort/released.json` so that every
verification result identifies the exact cohort it ran against.

Three cross-repository decisions constrain this plan. `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-2`
(Every result carries a resolved cohort identity) requires the consumer's released cohort to be a
complete, exactly constrained pin set at a reachable `index-state`, with every member listed in
`extra-packages`; the pin shape in the adoption guide follows it. `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-20`
(Pin cell payloads to verified cohort identities) means the consumer's Nix payload build under
`nix/kenshou/` must obtain the published packages from Hackage rather than from local paths once
the local copies are deleted. `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-18`
(Keep verification records immutable and derive baselines) is why the adoption check compares
against the last pre-adoption baseline instead of regenerating records.

The publication route was determined from the user's other first-party packages. The consumer's
`cohort/released.project` pins `pg-migrate ==1.1.0.0`, `ephemeral-pg ==0.3.1.0`, and the
`pgmq-*`, `keiro-*`, `kiroku-*`, and `shibuya-*` packages from Hackage at
`index-state: 2026-09-20T13:44:47Z`. `/Users/shinzui/Keikaku/bokuno/ephemeral-pg-project/ephemeral-pg/Justfile`
defines `sdist`, `sdist-check` (`cabal check`), `upload-candidate`, `publish`
(`cabal upload --publish`), and `upload-docs` recipes, and every first-party repository tags
releases `vMAJOR.MINOR.PATCH.BUILD` (`v1.2.0.0` in pg-migrate, `v0.3.1.0` in ephemeral-pg,
`v0.1.0.0` in hinagata). The `haskell-nix` registry at `/Users/shinzui/Keikaku/bokuno/haskell-nix`
catalogs fourteen families in `config/first-party-families.json` and records their Hackage releases
in `packages/first-party-lock.json`, but its `docs/user/updating-first-party-packages.md` states that
schema version 2 "fixes the family inventory" and that adding a family "requires a separately
designed migration". Hackage is therefore the release channel; the registry family is a follow-up
owned by that repository.

Hackage credentials already exist in `/Users/shinzui/.cabal/config` (one credential key is set;
do not print it). `cabal upload` reads them from there and prompts only if they are absent.

At the pinned consumer commit no package directory contains a `LICENSE` file and no cabal file
declares `license-file` or `extra-doc-files`, although each declares `license: BSD-3-Clause`.
`cabal check` reports both as warnings, and Hackage rejects a package whose declared license file is
missing, so M1 adds them.


## Plan of Work

The work is four milestones. M1 makes the tree releasable, M2 publishes, M3 registers, and M4
writes and verifies the adoption guide. M1 and M4's audit commands are independent of each other
and may be done in either order, but M2 must follow M1 and M3 must follow M2.

M1 starts with the divergence audit against the consumer so that any change the consumer made to
its generic packages after `a1648293443ad88ff1695ed800ff44c99993574e` is ported before the first
release. The audit is a `git diff --stat` and `git log` over the seven generic package
directories, `schemas/`, the generic policy files, and the generic part of `kenshou-cli/`, excluding
`kenshou-cli/src/Kenshou/Cli/Attest/`, which holds the Keiro attestations that stay in the consumer.
For each commit found, read its diff, decide whether it touches generic behavior, and port it by
hand into the corresponding file here (paths are identical between the two repositories, so
`git format-patch` from the consumer and `git am --3way` here is the fast path when the file has not
diverged; resolve conflicts by hand where EP-2 to EP-4 rewrote the surrounding code). Record every
ported commit hash in this plan's Surprises & Discoveries.

M1 then adds release metadata to each of the nine packages. Create a `LICENSE` file holding the
BSD-3-Clause text with "Nadeem Bitar" as the copyright holder in every package directory, add
`license-file: LICENSE` and `extra-doc-files: CHANGELOG.md` to every cabal file, and write each
package's `CHANGELOG.md` with a single `## 0.1.0.0 - <date>` entry in the format
`hinagata/CHANGELOG.md` uses (New Features, Bug Fixes, Other Changes). The first entry says the
package was extracted from `mori://shinzui/keiro-runtime-kenshou` at the pinned commit and lists
the generalization that EP-2 to EP-5 made to that package. Confirm the internal dependency bounds:
every `build-depends` line naming another `kenshou-*` package must read `kenshou-<name> ^>=0.1.0.0`
so that `cabal check` does not warn about unbounded dependencies and so a later patch release does
not break the set. Add `justfile` recipes `sdist`, `sdist-check`, `upload-candidate`, and
`publish`, modelled on the ephemeral-pg Justfile but iterating over the nine package names in
dependency order. Run `cabal check` inside each package directory and `cabal sdist all` at the
root. Tag the resulting commit `v0.1.0.0`.

M2 publishes in dependency order so that each candidate's Hackage build can resolve its
dependencies: `kenshou-core`, then `kenshou-measure` and `kenshou-check`, then `kenshou-diagnose`,
`kenshou-telemetry`, and `kenshou-remote`, then `kenshou-evidence`, then `kenshou-cli`, then
`kenshou-synthetic`. For each package, upload a candidate first, open the candidate page, confirm
the metadata renders and no dependency is unresolvable, then publish and upload documentation.
After the last publish, run `cabal update` and record the printed `index-state`; that timestamp is
the earliest state at which the consumer can pin the release. Prove resolvability by building a
throwaway consumer package in a fresh directory outside this checkout.

M3 edits `mori.dhall`: lifecycle stays `Schema.Lifecycle.Experimental` until the consumer's
adoption gate in the master plan's Progress section passes (that gate owns the flip to
`Active`), the nine package entries stay with their paths, and `description` gains the
sentence `First release: v0.1.0.0.`. Run `mori validate` and `mori register`, then
`mori registry show shinzui/kenshou --full` to confirm. File the registry follow-up as an OKF
improvement request in `/Users/shinzui/Keikaku/bokuno/haskell-nix/docs/improvement-requests/`
using that bundle's profile, requesting a `kenshou` family whose `moriProject` is
`shinzui/kenshou`, `github` is `shinzui/kenshou`, and `githubInput` is `kenshou-src`; cite this plan
by its Mori URI, `mori://shinzui/kenshou/plans/7-publish-the-first-kenshou-release-and-prepare-the-consumer-adoption-path`.

M4 writes `docs/guides/adopt-in-keiro-runtime-kenshou.md` inside the guides bundle that EP-6
created. If that bundle is profile-governed, allocate its handle with `okf id next` and fill the
frontmatter the profile requires; validate with `okf validate docs/guides --strict --profile
mori/user-documentation-profile.dhall --profile-enforce --log-enforce` and append a log entry with
`okf log add`. The guide contains, in order: the divergence audit and how to port a change; the
inventory of what the consumer deletes (`kenshou-core/`, `kenshou-check/`, `kenshou-measure/`,
`kenshou-diagnose/`, `kenshou-telemetry/`, `kenshou-evidence/`, `kenshou-remote/`, and the generic
modules of `kenshou-cli/`) and what it keeps; the relocations (`Kenshou.Check.Oracle.Keiro` to
`kenshou-keiro`, `Kenshou.Check.Oracle.Kiroku` to `kenshou-kiroku`, `Kenshou.Check.Oracle.Pgmq` to
`kenshou-pgmq`, and every `Kenshou.Cli.Attest.Keiro*` module plus the Keiro-specific recomputers in
`Kenshou.Cli.Attest` to `kenshou-keiro`); the cohort pin edit; the executable assembly through the
EP-1 entry point; the Nix payload change; and the AC-4 acceptance check. The three oracle modules
currently have no importer outside `kenshou-check` in the consumer, so each relocation is a file
move plus an `exposed-modules` edit. State in the guide, in its first paragraph, that the guide is
executed by a plan created in the consumer repository and that this repository's plan stops at
verifying the guide's read-only commands.


## Concrete Steps

All commands below run inside `nix develop` from the repository root
`/Users/shinzui/Keikaku/bokuno/kenshou` unless a different working directory is shown.

Divergence audit (M1, repeated at adoption). Run in the consumer checkout:

```bash
cd /Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou
git fetch origin
PIN=a1648293443ad88ff1695ed800ff44c99993574e
GENERIC='kenshou-core kenshou-check kenshou-measure kenshou-diagnose kenshou-telemetry kenshou-evidence kenshou-remote schemas policies/default.json policies/leak-default.json policies/telemetry-overhead.json kenshou-cli :(exclude)kenshou-cli/src/Kenshou/Cli/Attest'
git diff --stat "$PIN"..HEAD -- $GENERIC
git log --oneline --no-merges "$PIN"..HEAD -- $GENERIC
```

When both commands print nothing, the consumer's generic packages have not moved and no port is
needed. Otherwise, for each listed commit:

```bash
git format-patch -1 --stdout <commit> -- $GENERIC > /tmp/port-<commit>.patch
cd /Users/shinzui/Keikaku/bokuno/kenshou
git am --3way /tmp/port-<commit>.patch   # resolve conflicts by hand, then: git am --continue
```

Release metadata and checks (M1):

```bash
cd /Users/shinzui/Keikaku/bokuno/kenshou
for p in kenshou-core kenshou-measure kenshou-check kenshou-diagnose kenshou-telemetry kenshou-remote kenshou-evidence kenshou-cli kenshou-synthetic; do
  (cd "$p" && cabal check) || exit 1
done
cabal sdist all
ls dist-newstyle/sdist/
```

Expected tail of the listing, nine files:

```text
kenshou-check-0.1.0.0.tar.gz
kenshou-cli-0.1.0.0.tar.gz
kenshou-core-0.1.0.0.tar.gz
kenshou-diagnose-0.1.0.0.tar.gz
kenshou-evidence-0.1.0.0.tar.gz
kenshou-measure-0.1.0.0.tar.gz
kenshou-remote-0.1.0.0.tar.gz
kenshou-synthetic-0.1.0.0.tar.gz
kenshou-telemetry-0.1.0.0.tar.gz
```

`cabal check` must print `No errors or warnings could be found in the package.` for each package.
A warning naming `license-file`, `extra-doc-files`, or an unbounded `kenshou-*` dependency means
the metadata step is incomplete. Then run the full gate and tag:

```bash
just verify
git tag -a v0.1.0.0 -m "kenshou 0.1.0.0"
git push origin master v0.1.0.0
```

Publication (M2), one package at a time in the order shown, from the repository root:

```bash
for p in kenshou-core kenshou-measure kenshou-check kenshou-diagnose kenshou-telemetry kenshou-remote kenshou-evidence kenshou-cli kenshou-synthetic; do
  echo "== $p candidate"
  cabal upload "dist-newstyle/sdist/$p-0.1.0.0.tar.gz"
done
```

Open `https://hackage.haskell.org/package/kenshou-core-0.1.0.0/candidate` and the other eight
candidate pages, confirm the synopsis, license, and dependency list render, then publish and upload
documentation in the same order:

```bash
for p in kenshou-core kenshou-measure kenshou-check kenshou-diagnose kenshou-telemetry kenshou-remote kenshou-evidence kenshou-cli kenshou-synthetic; do
  echo "== $p publish"
  cabal upload --publish "dist-newstyle/sdist/$p-0.1.0.0.tar.gz"
  (cd "$p" && cabal haddock --haddock-for-hackage --haddock-hyperlink-source --haddock-quickjump \
    && cabal upload --publish --documentation "$(cabal haddock --haddock-for-hackage 2>&1 | tail -1)")
done
cabal update
```

`cabal update` ends with a line of the form `The index-state is set to 2026-11-DDTHH:MM:SSZ.`;
copy that timestamp into this plan's Progress entry for M2 and into the adoption guide as the
minimum `index-state`.

Resolvability proof (M2), in a fresh directory outside this checkout:

```bash
dir=$(mktemp -d)
cd "$dir"
cat > cabal.project <<'EOF'
packages: .
index-state: 2026-11-DDTHH:MM:SSZ
EOF
cat > kenshou-consumer-check.cabal <<'EOF'
cabal-version: 3.0
name: kenshou-consumer-check
version: 0.1.0.0
build-type: Simple

executable kenshou-consumer-check
  main-is: Main.hs
  build-depends: base, kenshou-core ==0.1.0.0
  default-language: GHC2024
EOF
cat > Main.hs <<'EOF'
module Main (main) where

import Kenshou.Core.Version (suiteVersion)

main :: IO ()
main = print suiteVersion
EOF
cabal build
cabal run kenshou-consumer-check
```

`cabal build` must show `Downloading  kenshou-core-0.1.0.0` and compile it; the run must print a
version value. Replace the `index-state` with the timestamp recorded above. Repeat once with
`build-depends: base, kenshou-cli ==0.1.0.0` to prove the whole dependency chain resolves.

Registration (M3):

```bash
cd /Users/shinzui/Keikaku/bokuno/kenshou
# Leave lifecycle Experimental; append 'First release: v0.1.0.0.' to the description by hand.
"${EDITOR:-vi}" mori.dhall
mori validate
mori register
mori registry show shinzui/kenshou --full | head -40
```

Expected: `Configuration is valid.`, `Project registered: shinzui/kenshou`, and a Packages section
listing nine packages. Then, in `/Users/shinzui/Keikaku/bokuno/haskell-nix`, read
`docs/improvement-requests/index.md` and an existing request to copy the frontmatter shape, write
the `kenshou` family request, and validate with that repository's `just` recipe or with
`okf validate docs/improvement-requests --strict --profile <its profile> --profile-enforce --log-enforce`.
Do not commit in that repository unless the user asks; leave the file and report its path.

Adoption guide (M4):

```bash
cd /Users/shinzui/Keikaku/bokuno/kenshou
okf id list docs/guides --profile mori/user-documentation-profile.dhall
okf id next docs/guides --profile mori/user-documentation-profile.dhall DOC
# write docs/guides/adopt-in-keiro-runtime-kenshou.md with the allocated DOC-N
okf validate docs/guides --strict --profile mori/user-documentation-profile.dhall --profile-enforce --log-enforce
okf index docs/guides --write
```

If EP-6 placed the guides profile at a different path, use the path recorded in `mori.dhall` under
the `guides` bundle. The guide's cohort section must show this exact shape for the consumer's
`cohort/released.project`, added to both the `extra-packages` and `constraints` blocks, with the
`index-state` raised to at least the recorded timestamp:

```text
extra-packages:
  kenshou-core,
  kenshou-check,
  kenshou-measure,
  kenshou-diagnose,
  kenshou-telemetry,
  kenshou-evidence,
  kenshou-remote,
  kenshou-cli

constraints:
  kenshou-core ==0.1.0.0,
  kenshou-check ==0.1.0.0,
  kenshou-measure ==0.1.0.0,
  kenshou-diagnose ==0.1.0.0,
  kenshou-telemetry ==0.1.0.0,
  kenshou-evidence ==0.1.0.0,
  kenshou-remote ==0.1.0.0,
  kenshou-cli ==0.1.0.0
```

and a matching `components` entry in `cohort/released.json` with `"id": "kenshou"`,
`"moriUri": "mori://shinzui/kenshou"`, `"source": { "type": "hackage" }`, and the eight packages at
`0.1.0.0`. The guide reminds the reader that `cohort/active.project` is switched only with
`just use-cohort released` and that `cabal run kenshou -- cohort check` must pass afterwards. The
Nix section tells the reader that `flake.module.nix` and `nix/kenshou/packages.nix` currently build
`kenshou-*` with `callCabal2nix` from local directories, and that until the `haskell-nix` family
exists each must become `haskellPackages.callHackageDirect { pkg = "kenshou-core"; ver = "0.1.0.0";
sha256 = "<sri>"; } { }` with the hash from:

```bash
nix store prefetch-file --json --unpack https://hackage.haskell.org/package/kenshou-core-0.1.0.0/kenshou-core-0.1.0.0.tar.gz | jq -r .hash
```

The executable section shows the consumer's `kenshou-cli/app/Main.hs` replacement: it imports the
EP-1 entry point from the published `kenshou-cli` library (the function that takes the list of
layer bundles, commands, and help topics, named in `docs/adr/` by EP-6) and passes the consumer's
own `Kenshou.Suite.{Pgmq,Kiroku,Keiro,Shibuya,Kafka,Runtime}` bundles, its relocated Keiro
recomputers, and the generic commands. The AC-4 section states the acceptance exactly: in the
consumer, `just verify` passes on the released cohort; the smoke and change suites run to
completion; and `kenshou compare` between a run on the last pre-adoption baseline and a run on the
adopted build reports no verdict change and no comparison-key change, following the consumer's
`docs/planning.md` and runbook RB-1 for the exact invocations.

Verify the guide's read-only commands once by running the divergence audit and the prefetch command
above and pasting their output into this plan under Surprises & Discoveries or Outcomes.


## Validation and Acceptance

M1 is accepted when `cabal check` is clean in all nine package directories, `cabal sdist all`
writes nine tarballs, `just verify` passes, and `git describe --tags` prints `v0.1.0.0` on the
release commit.

M2 is accepted when each of the nine Hackage package pages at
`https://hackage.haskell.org/package/<name>-0.1.0.0` exists as a published (not candidate) package
with rendered documentation, and the throwaway consumer project builds twice, once against
`kenshou-core` and once against `kenshou-cli`, with the recorded `index-state` and no
`source-repository-package` stanza.

M3 is accepted when `mori registry show shinzui/kenshou --full` shows lifecycle `Experimental`,
the release sentence in the description, and nine packages, and the improvement request file exists in the `haskell-nix` checkout and validates.

M4 is accepted when `okf validate docs/guides` passes with the new guide, the guide's audit
commands have been run once against the consumer with their output recorded here, and the guide
states explicitly that adoption is executed from the consumer repository.

Additional scope that is not required here: performing the adoption, adding the `haskell-nix`
family, and cutting a `0.1.1.0` patch release for divergence discovered after publication. Each is
a decision for the user or for the consumer's adoption plan.


## Idempotence and Recovery

The divergence audit is read-only and can be rerun at any time. Porting with `git am --3way` can be
abandoned with `git am --abort`, which restores the tree to the pre-port commit.

`cabal check` and `cabal sdist` are safe to repeat; sdists are overwritten in place. Tagging is
repeatable only before the tag is pushed; if the release commit must change after `v0.1.0.0` was
pushed, do not move the tag. Publish the fix as `0.1.0.1` with a new tag instead.

A Hackage candidate can be re-uploaded and replaces the previous candidate. A published package
cannot be deleted; a mistake after `--publish` is fixed by a new patch version. Documentation
uploads can be repeated. If `cabal upload` fails on authentication, add the credentials to
`/Users/shinzui/.cabal/config` rather than passing them on the command line.

`mori validate` and `mori register` are idempotent. If registration fails after the description edit,
revert it with `git checkout -- mori.dhall` and inspect the validator output.

Writing the adoption guide touches only `docs/guides/`; `okf index --write` regenerates
`index.md` deterministically and can be rerun.


## Interfaces and Dependencies

This plan starts only after EP-5 and EP-6 are Complete in the MasterPlan's registry: the
coupling guard must be part of `just verify`, and `docs/adr/` and `docs/guides/` must exist as OKF
bundles with their profiles recorded in `mori.dhall`.

The release depends on `cabal` (3.12 or newer, from `nix develop`) with Hackage credentials in
`/Users/shinzui/.cabal/config`, on `okf` for the guides bundle, on `mori` for registration, and on
`nix store prefetch-file` and `jq` for the Hackage hashes in the adoption guide.

The interfaces this plan documents for the consumer, by full module path, are: the `kenshou-cli`
entry point established by EP-1 (the replacement for the fixed `Kenshou.Cli.Registry`), the
suite registration record `Kenshou.Core.Bundle.LayerBundle` as extended by EP-2 to EP-4, and the
evidence configuration in `Kenshou.Evidence.Config` from EP-4. The adoption guide must name these
by their final names as they appear in the released `0.1.0.0` sources, not as they appear in this
plan.

The consumer-side artifacts this plan reads but never edits are
`/Users/shinzui/Keikaku/bokuno/keiro-runtime-kenshou/cohort/released.project`,
`cohort/released.json`, `cohort/active.project`, `flake.module.nix`, `nix/kenshou/packages.nix`,
`kenshou-cli/app/Main.hs`, `kenshou-cli/src/Kenshou/Cli/Registry.hs`, and `justfile`
(`use-cohort`, `cohort-check`, `verify`).
