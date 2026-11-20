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
    - model: "gpt-6.2-astra"
      harness: "codex-cli"
      at: 2026-11-20T18:51:57Z
      mode: "update"
      note: "Reassess the October candidates against Hackage, current package versions, the release gate and the consumer Git pin."
    - model: "gpt-6.2-sol"
      harness: "codex-cli"
      at: 2026-11-20T19:48:03Z
      mode: "implement"
      note: "Restore the October release fixture, qualify the committed artifacts, and prepare the Git-to-Hackage handoff."
  reviews:
    - model: "gpt-6.2-astra"
      harness: "codex-cli"
      at: 2026-11-20T18:58:16Z
      verdict: "changes-requested"
      note: "Hold publication until the tested fixture repair is committed and tagged. All nine October candidates reproduce, and master produces a different release set."
---

# Publish the first kenshou release and prepare the consumer adoption path

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

Publish the nine reviewed October packages at `0.1.0.0` so a fresh Cabal project can
build against them from Hackage. The first consumer already uses the same package sources
through a Git pin. Publication gives it a package-index pin and a reproducible source for
its Nix builds. The published release, a matching Git tag and a working consumer build
are the observable outcomes.

The release target is commit `599f6b43a9e0aaeab9fdf2aa35f2fc0ab3c8ae93`, based on
the reviewed October candidate commit `78f1f7abf1737c99a3144d6469766aa4f073cf54`.
It restores the run records referenced by the repository's verification fixtures.

## Progress

- [x] **M1. Qualify a reproducible release commit (2026-11-20).** The fixture repair is committed at
  `599f6b43a9e0aaeab9fdf2aa35f2fc0ab3c8ae93` on the October source line, in a
  detached local worktree. On 2026-11-20 a fresh clone at that commit passed
  `nix develop --no-write-lock-file -c just verify` on GHC 9.12.4. It reported
  496 examples, zero failures and two pending. All nine packages passed
  `cabal check` and all nine rebuilt source archives matched the Hackage candidates
  byte for byte. The published annotated tag `v0.1.0.0` peels to that exact commit.
- [x] **M2. Publish and prove installation (2026-11-20).** All nine `0.1.0.0` package pages and
  their rendered module pages went live on 2026-11-20 at 20:48 UTC. Every public
  tarball matches its staged source byte for byte. All nine appear at Hackage
  index-state `2026-11-20T20:48:12Z`. The core and CLI probes printed
  `"0.1.0.0"` and `6`, respectively, on GHC 9.12.4. Both solver plans confirm
  Hackage tarball sources for all Kenshou packages.
  Haddock reported missing comments and unresolved cross-module links during generation.
- [x] **M3. Register the release (2026-11-20).** The validated Mori registration
  reports `First release: v0.1.0.0.`, nine packages and lifecycle
  `Experimental`. The registry owner checkout contains
  `mori://shinzui/haskell-nix/okf/improvement-requests/concepts/IR-6` at local commit
  `bb9ab1b`. The request passed strict validation in isolation and its canonical URI
  resolves after local Mori registration.
- [x] **M4. Verify the consumer handoff (2026-11-20).** The [adoption guide](../guides/adopt-in-keiro-runtime-kenshou.md)
  now documents the Git-to-Hackage switch and passed `just guides-validate` (two
  concepts). The 2026-11-20 read-only audit found no imported path changes before
  `481c1e0` and only the migration through consumer head `62a5648`.
  Comparing `cabal get kenshou-cli-0.1.0.0` with the pre-migration consumer tree
  left the expected twelve consumer-only modules. All eight unpacked source hashes
  were verified against Hackage. DOC-2 records the index-state and links to the hashes.
  The consumer owns the switch and its smoke, change-suite and baseline comparison runs.

## Surprises & Discoveries

- The clean October checkout passed the build and boundary checks, then failed one
  comparison test and two attestation tests in `kenshou-evidence/test/Main.hs`.
  Each reported `BundleInvalid` with a `DanglingReference` from an attestation to
  `runs/selftest/2026/09/`. Git tracks no run records under
  `fixtures/consumer-baseline/docs/verification/` at that revision. The `runs/` rule
  in `.gitignore` matches the nested fixture directory too. This failure occurs in
  the repository checkout, so the IR-1 exception for tests in unpacked tarballs does
  not cover it. Restoring the seven referenced self-test run records with their indexes
  in a disposable checkout moved the evidence suite from 29 examples with three failures
  to 29 with zero. The full `nix develop -c just verify` then passed. All nine rebuilt
  sdists still matched Hackage byte for byte.
  On master, [Plan 10](10-derive-fix-verification-dispositions-from-immutable-evidence.md)
  already moved these tests to package-local fixtures.

- On 2026-11-20, local and remote `master` were `bd1cc07`, 14 commits beyond the
  candidate source. On this revision, `nix develop -c just verify`, all nine
  `cabal check` runs and `cabal sdist all` passed. GitHub Actions listed no run
  for either exact commit.
  The artifacts differ for all nine packages.

  | Package(s) | Candidate version | Version on master |
  | --- | --- | --- |
  | kenshou-core | 0.1.0.0 | 0.2.0.0 |
  | kenshou-evidence | 0.1.0.0 | 0.2.1.0 |
  | kenshou-cli | 0.1.0.0 | 0.1.4.0 |
  | kenshou-check, kenshou-measure, kenshou-diagnose, kenshou-telemetry, kenshou-remote, kenshou-synthetic | 0.1.0.0 | 0.1.0.0, with changed dependency bounds |

  The three newer candidate URLs returned 404. The `upload-candidate` and `publish`
  recipes in `justfile` still construct every filename with `-0.1.0.0`. On a fresh
  master build the core file with that name is absent. A reused output directory could
  supply stale archives. The publish recipe also obtains a docs filename from the last
  line of a second Haddock invocation. Use an explicit archive path for each upload.

- Consumer commit `62a5648` removed the generic copies. The imported paths have no diff
  from the extraction pin through `481c1e0`, the parent of the migration. The only
  subsequent commit touching them through `62a5648` is the migration itself. The eight
  packages in its Cabal pin and its Nix fixed-hash source come from `b90da77`, which
  differs from `78f1f7a` only in this plan. The consumer recorded 350 examples and
  34 isolated-lane examples passing. Broker-backed smoke/change and comparison against
  the published release remain open. See
  `mori://shinzui/keiro-runtime-kenshou/plans/26-adopt-the-extracted-kenshou-harness`
  and `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-24`.

- The consumer's released and head payloads already use a lock-backed overlay that
  calls `callHackageDirect` and applies `dontCheck`. Adding the harness component
  to the descriptors lets the consumer regenerate its locks and remove the separate
  Git overlay. The 0.1.0.0 comparison key omits the cohort plan hash. The series key
  includes it, so a source change can affect the series key while preserving comparisons.

- [FRIC-5](../friction-log/5-existing-request-blocks-strict-validation-of-the-registry-bundle.md)
  records the full upstream improvement-request bundle's strict failure on the
  existing IR-5 review metadata. IR-6 passed strict profile and log enforcement in
  isolation. The full bundle passed profile and log enforcement in standard mode.

- [FRIC-6](../friction-log/6-published-packages-take-time-to-reach-the-signed-hackage-index.md)
  records that Cabal initially received a pre-release index and then one containing
  only the first upload. The package pages, tarballs and documentation were already
  accessible. Check that all nine versions are indexed before pinning the timestamp.

- Divergence audit, 2026-10-28, run in the consumer checkout after `git fetch origin`.
  `origin/master` was `2129bb9`, three commits past the pin: `9ea967a` (seihou modules),
  `6514438` (nix-haskell-flake update), and `2129bb9` (a research document). None touches an
  imported path. Both of these printed nothing:

  ```bash
  git diff --stat "$PIN"..origin/master -- $GENERIC
  git log --oneline --no-merges "$PIN"..origin/master -- $GENERIC
  ```

  `GENERIC` was the complete imported set from `docs/import-provenance.md`. That set includes
  `suites` and `policies/selftest.json`.
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
- Inventory listing for DOC-2, run against the October checkout's `kenshou-cli/src` and repeated on
  2026-11-20 against the downloaded CLI candidate and consumer tree at `481c1e0`. The consumer-only modules are exactly the twelve
  `Kenshou.Cli.Attest.Keiro*` modules. The candidate `kenshou-cli` also exports
  `Kenshou.Cli.Registry` and `Kenshou.Cli.Attest`, so the consumer migration relocated its own
  modules of those names.
- In the October rehearsal the nine tarballs, unpacked into an empty project with the harness cohort, build every
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

- The 2026-11-20 review retains the October candidate set as the default for this plan.
  All nine archives are reproducible, and the consumer already validates these package
  sources. Selecting the November features would change the version set and the expected
  consumer compatibility results. The maintainer owns that release choice.

- Decision: Release all nine packages at the shared version `0.1.0.0` and tag the repository
  `v0.1.0.0`.
  Rationale: Every imported cabal file already declares `0.1.0.0`, the packages have never been
  published, and a shared version lets the consumer pin the whole set with one constraint block,
  as it did for its other released dependencies. Internal dependencies are bounded `^>=0.1.0.0` so a later patch release of one package does not force a
  lock-step bump of the others.
  Date: 2026-10-28

- Decision: Publish to Hackage with `cabal upload --publish`; do not add a `kenshou` family to the
  `mori://shinzui/haskell-nix` registry in this plan.
  Rationale: Every first-party package the consumer pins (`pg-migrate`, `ephemeral-pg`,
  `pgmq-*`, `keiro-*`) is consumed from Hackage at an exact `index-state`, which is what
  `mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-2` requires of a released cohort.
  At the time of this decision the registry had a fixed family inventory. Its owner now
  documents an additive migration. M3 still files the request with that owner.
  Date: 2026-10-28

- Decision: Run the divergence audit twice, once before the release and once at adoption.
  Rationale: The import in EP-1 pinned the consumer at `a1648293443ad88ff1695ed800ff44c99993574e`
  and the consumer may have changed its generic packages since. A change ported before `0.1.0.0`
  reaches the consumer in the first release; a change found only at adoption needs a patch
  release, so the earlier audit is cheaper.
  Date: 2026-10-28


- On 2026-10-28 the user authorized candidate uploads. The plan recorded an annotated local
  tag at `78f1f7a` and reserved permanent publication for a separate confirmation.

- On 2026-11-20 the maintainer authorized tagging and publication of the qualified
  October release commit `599f6b43a9e0aaeab9fdf2aa35f2fc0ab3c8ae93`.

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

The release commit restores seven evidence records and their five index or log
files outside the package tarballs. The Git-pinned consumer uses the same package
sources, and the maintained guide describes the remaining source switch.
The first release and its documentation are public. Both clean Cabal projects
build and run at the recorded index-state. The remaining adoption tests belong
to the consumer and are tracked by the parent MasterPlan.

[FRIC-5](../friction-log/5-existing-request-blocks-strict-validation-of-the-registry-bundle.md)
was accepted after isolating strict validation of IR-6 and confirming the
pre-existing diagnostic on IR-5.

[FRIC-6](../friction-log/6-published-packages-take-time-to-reach-the-signed-hackage-index.md)
was accepted after the signed index caught up. The release procedure now checks
that it contains all nine versions before pinning the timestamp.

### Published source hashes

All entries identify the unpacked Hackage `0.1.0.0` sources used in Nix. Each
public archive also matched its reviewed candidate byte for byte.

| Package | Unpacked source hash |
| --- | --- |
| `kenshou-core-0.1.0.0` | `sha256-04mq0i04uwxd1hoG6uL5X3WgTbUGzK6CR4Dht/yDTlI=` |
| `kenshou-check-0.1.0.0` | `sha256-cZxQRn3XrvqnmAbTu/oiPMZo5Aa+AcoRWL2PAL40DVg=` |
| `kenshou-measure-0.1.0.0` | `sha256-qLRAww1eAnMz17I7R9sEo/tP+l7KFHm3WtSrUxPaSXo=` |
| `kenshou-diagnose-0.1.0.0` | `sha256-WG1Ls6vgccGAkhqQkDbxuDfADG0ci5E4p7ItCFGPHw0=` |
| `kenshou-telemetry-0.1.0.0` | `sha256-xE/AiB4P/J34Fitx/5Fu2yTZw3aT4XcrJgML0DDp5cQ=` |
| `kenshou-evidence-0.1.0.0` | `sha256-j9CBBqNPYbAKXPnKb+2sV9n1KE3j+tBHr+6S7iCNCU0=` |
| `kenshou-remote-0.1.0.0` | `sha256-kb8hKXfwGtAPKQhqtSCQbhNA90OScze2Xmei4Xtp8Cg=` |
| `kenshou-cli-0.1.0.0` | `sha256-figP9Dsd+Uolotz9GwT2N+KQg9a0LnVTkUh+txxSxAU=` |


## Context and Orientation

Each package lives under a directory of the same name. `cabal.project` selects
`kenshou-*/*.cabal` and imports the compiler and dependency environment represented
by `cohort/active.project` and `cohort/harness.project`. A source distribution
(sdist) is the gzip-compressed tar archive Cabal produces. Hackage lets maintainers
replace candidates, then publish a version permanently. An index-state is a UTC
timestamp that lets Cabal solve against a particular snapshot of Hackage.

The [extraction record](../import-provenance.md) lists the imported paths. The
[assembly contract](../adr/0016-register-a-suite-as-layer-bundles-assembled-into-a-program.md)
defines how the consumer calls `Kenshou.Cli.mainWith` with its own program and layer
bundles. The [cohort and fixture decision](../adr/0020-verify-the-harness-against-its-own-cohort-and-confine-consumer-data.md)
explains which data belongs outside the packages. [IR-1](../improvement-requests/run-every-package-test-suite-from-its-source-distribution.md)
records the separate tarball-test limitation accepted in October.

The parent [MasterPlan](../masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md)
marks EP-5 and EP-6 complete and assigns the released-cohort adoption gate to the
consumer. Its lifecycle rule remains in force. The consumer's cohort, payload and
evidence requirements are recorded in
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-2`,
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-20` and
`mori://shinzui/keiro-runtime-kenshou/okf/adrs/concepts/ADR-18`.

## Plan of Work

M1 retains the shared October release as the working target. On that source line,
restore the tracked self-test run records and their indexes from the immutable consumer
import pin into the repository fixture. Keep the root run index limited to the self-test
subdirectory, as required by `fixtures/consumer-baseline/README.md`, and explicitly
include the fixture in Git despite the ignore rule. Record the resulting release commit,
run the full gate from a fresh checkout and compare all nine archives with Hackage. If a
package changes, replace its candidate and review it again.

If the owner selects the newer functionality for the first release, use the actual Cabal manifest
versions, correct the release recipes and consumer pins, choose a tag identifying that
cohort, and review all nine regenerated candidates. The six identical filenames already
refer to different content. Publishing October first would require new version numbers
for those six before distributing their November sources. The current core changelog also
records a change to the cohort compatibility key, relevant to the consumer comparison.

M2 stages source and documentation together before the first permanent upload. Once the
maintainer confirms the exact revision and publication, tag it, publish in dependency
order and prove both installations from Hackage. M3 then records the release in Mori.
The family request was filed in the registry checkout ahead of publication.
M4 can update the guide before M2, but the final hash and inventory checks require the
published versions.

## Concrete Steps

For the October target, prepare the following repair in a checkout based on
`78f1f7a`. Run in Bash at that checkout's root. The source project is
`mori://shinzui/keiro-runtime-kenshou`, path `docs/verification/runs/` at
the import pin (artifact-level URI for this fixture tree is pending).

```bash
set -euo pipefail
consumer=$(mori path mori://shinzui/keiro-runtime-kenshou | tail -1)
pin=a1648293443ad88ff1695ed800ff44c99993574e
fixture=fixtures/consumer-baseline/docs/verification
git -C "$consumer" archive "$pin" docs/verification/runs/selftest |
  tar -xf - --strip-components=2 -C "$fixture"
git -C "$consumer" show "$pin:docs/verification/runs/index.md" |
  sed '/^- \[kafka\//d; /^- \[keiro\//d' > "$fixture/runs/index.md"
git add -f -- "$fixture/runs"
git diff --cached --stat
```

Expect twelve files under the fixture directory. Commit the reviewed fixture repair
and ensure its revision is available to the primary clone for qualification and tagging.

Run the release checks in Bash inside the repository's Nix development environment with
GHC 9.12.4, Cabal, Git, curl, jq and OKF available. From the current repository root,
set `release_commit` to the full fixture-repair commit ID. Using the original
October commit instead reproduces the three failures.

```bash
set -euo pipefail
primary=$(git rev-parse --show-toplevel)
: "${release_commit:?set the full commit ID to qualify}"
scratch=$(mktemp -d)
git clone --quiet --no-checkout . "$scratch/source"
git -C "$scratch/source" checkout --quiet --detach "$release_commit"
cd "$scratch/source"
nix develop -c just verify
just sdist-check
mkdir "$scratch/sources" "$scratch/candidates"
cabal sdist all --output-directory="$scratch/sources"
packages=(kenshou-core kenshou-measure kenshou-check kenshou-diagnose kenshou-telemetry
          kenshou-remote kenshou-evidence kenshou-cli kenshou-synthetic)
for p in "${packages[@]}"; do
  id="$p-0.1.0.0"
  curl -fsSL "https://hackage.haskell.org/package/$id/candidate/$id.tar.gz" \
    -o "$scratch/candidates/$id.tar.gz"
  cmp "$scratch/sources/$id.tar.gz" "$scratch/candidates/$id.tar.gz"
done
```

All nine comparisons must exit zero. Rehearse the documentation build from the same
source and verify each named archive contains rendered Kenshou module pages.

```bash
cabal haddock all --builddir="$scratch/docs" --haddock-for-hackage \
  --haddock-hyperlink-source --haddock-quickjump
for p in "${packages[@]}"; do
  archive="$scratch/docs/$p-0.1.0.0-docs.tar.gz"
  tar -tzf "$archive" > "$scratch/doc-members"
  grep -Eq '/Kenshou[^/]*\.html$' "$scratch/doc-members"
done
```

After the qualification checks pass and the maintainer authorizes publication, create the
annotated tag on the **final qualified commit** in the primary clone. Check the local
and remote refs first. An existing tag must peel to the same commit. Push only the
release tag to the project's origin. From the staging shell above, publish the files
that passed comparison and the documentation archives. For a partial release, use
the recovery procedure below before resuming.

```bash
# In the staging shell, when the tag is absent:
git -C "$primary" tag -a v0.1.0.0 "$release_commit" -m "kenshou 0.1.0.0"
git -C "$primary" push origin refs/tags/v0.1.0.0
git -C "$primary" ls-remote origin 'refs/tags/v0.1.0.0*'
```

```bash
# In the staging shell, with set -e still active:
for p in "${packages[@]}"; do
  id="$p-0.1.0.0"
  cabal upload --publish "$scratch/sources/$id.tar.gz"
  cabal upload --publish --documentation "$scratch/docs/$id-docs.tar.gz"
done
cabal update
```

Wait for `cabal update` and `cabal list --simple-output '^kenshou-'` to show all
nine `0.1.0.0` packages. Record the index-state that includes the last upload.
Open all nine versioned pages and a module documentation link on each. Run the
following outside this checkout in the same development environment, setting
`release_index` to the recorded UTC timestamp. Each small executable imports a
module from its direct dependency.

```bash
: "${release_index:?set the recorded Hackage index-state}"
probe=$(mktemp -d)
cd "$probe"
printf 'packages: .\nindex-state: %s\n' "$release_index" > cabal.project
for p in core cli; do
  cat > probe.cabal <<EOF
cabal-version: 3.0
name: probe
version: 0.1.0.0
build-type: Simple
executable probe
  main-is: Main.hs
  build-depends: base, kenshou-$p ==0.1.0.0
  default-language: GHC2024
EOF
  if [ "$p" = core ]; then
    printf '%s\n' 'import Kenshou.Core.Version (suiteVersion)' \
      'main :: IO ()' 'main = print suiteVersion' > Main.hs
  else
    printf '%s\n' 'import Kenshou.Cli (selfTestBundles)' \
      'main :: IO ()' 'main = print (length selfTestBundles)' > Main.hs
  fi
  cabal run --builddir="dist-$p" exe:probe
  jq -er '[."install-plan"[] | select(."pkg-name" | startswith("kenshou-"))] |
    length > 0 and all(.[]; ."pkg-version" == "0.1.0.0" and
      ."pkg-src".type == "repo-tar" and (."pkg-src".repo.uri | test("hackage[.]haskell[.]org")))' \
    "dist-$p/cache/plan.json"
done
```

The first probe prints the suite version. The second prints the number of registered
self-test bundles. A populated Cabal cache can satisfy downloads. The solver plans
record the source independently of the cache.

For M3, append `First release: v0.1.0.0.` to the project description in `mori.dhall`.
From the primary repository root run the following and confirm the description, nine
packages and `Experimental` lifecycle.

```bash
mori validate
mori register
mori registry show shinzui/kenshou --full
```

The family request is
`mori://shinzui/haskell-nix/okf/improvement-requests/concepts/IR-6`.
It requests family `kenshou`, Mori project and GitHub repository
`shinzui/kenshou`, and GitHub input `kenshou-src`. The registry documents the addition in
`mori://shinzui/haskell-nix/okf/user-documentation/concepts/DOC-9`.
The registry owner carries out that migration.

For M4, update [DOC-2](../guides/adopt-in-keiro-runtime-kenshou.md) to identify the
completed migration and describe the remaining Git-to-Hackage switch. The owner is
`mori://shinzui/keiro-runtime-kenshou`. Its `cohort/kenshou.project` supplies eight
packages to the released, head and isolated Shibuya projects. Its
`nix/kenshou/packages.nix` fetches the same Git revision (artifact-level URIs for
these source files are pending). Replace the source stanza with the eight exact Hackage
pins in the relevant cohorts, record matching sources in the cohort identities, and
use published tarball hashes for the Nix overrides. The ninth package,
`kenshou-synthetic`, supplies the example executable and stays outside the consumer.
Retain `dontCheck` as documented in IR-1. Record the observed index-state in the guide.

Check the published CLI inventory against the **pre-migration** consumer tree and record
the module difference. From the consumer checkout, in Bash with the release environment:

```bash
inventory=$(mktemp -d)
cabal get -d "$inventory" kenshou-cli-0.1.0.0
git ls-tree -r --name-only 481c1e0 -- kenshou-cli/src |
  sed -n 's|^kenshou-cli/src/\(.*\.hs\)$|\1|p' | LC_ALL=C sort > "$inventory/consumer"
(cd "$inventory/kenshou-cli-0.1.0.0/src" && find . -name '*.hs') |
  sed 's|^\./||' | LC_ALL=C sort > "$inventory/published"
LC_ALL=C comm -23 "$inventory/consumer" "$inventory/published"
for p in core check measure diagnose telemetry evidence remote cli; do
  id="kenshou-$p-0.1.0.0"
  nix store prefetch-file --json --unpack \
    "https://hackage.haskell.org/package/$id/$id.tar.gz" | jq -er .hash
done
```

Expect the twelve consumer-only Keiro attestation modules and eight source hashes.
Validate the revised guide with `just guides-validate` from the kenshou root, maintaining
its bundle log and index when edited. Consumer acceptance still requires released-cohort
verification, smoke and change suites, and preserved verdicts and comparison keys against
the last pre-adoption baseline. Report the results to the parent plan.

## Validation and Acceptance

M1 closes when a clean checkout of the identified release commit passes `just verify`,
all nine package checks and archive comparisons, and the annotated tag resolves to that
commit. M2 closes when nine published version pages have rendered documentation and both
probes pass with Hackage sources at the recorded index-state. M3 closes when Mori shows
the release and the family request validates in the owning bundle. M4 closes when DOC-2
validates and the read-only audit, inventory, cohort inspection and published hash evidence
are recorded here. The actual consumer switch and the parent plan's lifecycle change have
their own acceptance criteria.

## Idempotence and Recovery

Repeat local builds in a fresh staging directory. A candidate with changed bytes can be
replaced and compared again before publication. Preserve a public tag and any published
source archives. If an upload stops midway, query each versioned Hackage page and compare
each already published tarball with its staged copy. Resume with the first missing source
or documentation upload. A mismatch in a published source requires a new version. Use
Cabal's configured credentials for authorized uploads.

## Interfaces and Dependencies

The public probes exercise `Kenshou.Core.Version.suiteVersion` and
`Kenshou.Cli.selfTestBundles`. The consumer assembles its executable through
`Kenshou.Cli.mainWith` and supplies its own runtime layers. The release requires Hackage,
the repository's Git origin and the development tools named above. Mori registration and
consumer adoption follow publication.

Revision, 2026-11-20. Reconciled the October candidates with both repositories and
the public index. Replaced the blanket publication command and pre-extraction adoption
instructions with a commit-specific release and a Git-to-Hackage handoff.
