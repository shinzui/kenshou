---
id: 8
slug: resolve-owner-records-through-consumer-supplied-sources
title: "Resolve owner records through consumer-supplied sources"
kind: exec-plan
created_at: 2026-11-17T19:05:20Z
intention: "intention_01m7nec7ckece87s8pqhkme1py"
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
      note: "Same model as author. Checked against IR-2 and source; git provenance makes goldens and snapshots unstable, and snapshot replay of enrichment links and duplicate-chain targets is unspecified."
  revisions:
    - model: "claude-fable-5-2"
      harness: "claude-code"
      at: 2026-11-18T01:55:31Z
      mode: "update"
      note: "Addressed the 2026-11-18 review: relative provenance, opt-in git state, complete snapshots, version step."
    - model: "claude-opus-5-5"
      harness: "claude-code"
      at: 2026-11-18T03:03:33Z
      mode: "implement"
      note: "Implemented milestones of plan 8"
---

# Resolve owner records through consumer-supplied sources

This ExecPlan is a living document. The sections Progress, Surprises & Discoveries,
Decision Log, and Outcomes & Retrospective must be kept up to date as work proceeds.
If durable project context changes, update or create ADRs in docs/adr/ in the same change.
Record friction met while implementing in the friction-log bundle as it occurs (see FRICTION.md).


## Purpose / Big Picture

This plan implements improvement request IR-2
([docs/improvement-requests/resolve-owner-records-through-consumer-supplied-sources.md](../improvement-requests/resolve-owner-records-through-consumer-supplied-sources.md)).

A verification suite built on Kenshou marks a scenario that fails for an already reported
reason with a known defect, and that known defect cites a record in the repository that owns
the broken behavior: a bug report or an improvement request. Today nothing in Kenshou reads
those records. A consumer who wants to know what the owners currently claim (is it fixed, in
which version, is it a duplicate of another report) keeps a hand-copied register that goes
stale as owners release changes.

After this plan, any consumer's executable has an `owners` command. `owners status` lists every
owner record cited by the registered scenarios and by the consumer's own findings file, with
the record's canonical identity, the owner's raw status and version claims, whether the
reference resolved, and which scenarios and findings cite it. `owners snapshot` writes the
exact bytes it read, with their digests, into a directory, and `owners status --snapshot DIR`
reports from those frozen bytes instead of rereading the owners' repositories. The command
never writes to an owner's files and never claims that a fix was verified: it reports what the
owner said at the time the bytes were captured.

Someone can see it working by running, from the repository root inside `nix develop`:

```bash
K=$(cabal list-bin kenshou)
F=kenshou-evidence/test/fixtures/owners
"$K" owners status \
  --findings "$F/findings.json" \
  --map mori://fixture/owner-a/okf/bug-reports="$F/owner-a/bug-reports" \
  --map mori://fixture/owner-b/okf/bug-reports="$F/owner-b/bug-reports"
```

and reading a report in which two different owners' `BUG-1` records stay distinct, a duplicate
chain ends at its canonical record, a duplicate cycle and a missing record are named as such,
and the self-test scenario's reference to a plan document is reported as a reference that is
not an owner record.


## Progress

- [x] M1: the owner-record model, resolvers, duplicate-chain resolution, and the owner status
  document exist in `kenshou-evidence` as a pure, tested library; the fixture matrix covering
  duplicate chains, cycles, missing records, non-record references, unknown and unparseable
  versions, malformed fields, and two owners sharing a local handle passes in
  `cabal test kenshou-evidence:test:kenshou-evidence-test`.
  Done 2026-11-18: the 15 examples of `describe "owner records"`
  (`kenshou-evidence/test/OwnerSpec.hs`) pass, including the byte-for-byte golden
  `kenshou-evidence/test/fixtures/owners/status.golden.json` and the snapshot round trip. The
  suite as a whole reports 44 examples, 3 failures; the same 3 fail on the untouched tree (see
  Surprises & Discoveries).
- [ ] M2: `owners status` and `owners snapshot` are standard commands; the fixture command
  above prints the expected text and `kenshou.owner-status/v1` JSON, a snapshot replays to a
  semantically identical report after the fixture owner files are changed, and owner files are
  byte-identical before and after every command.
- [ ] M3: a synthetic consumer assembled in the CLI test suite supplies its own source,
  resolver, and enrichment through the public extension points; `just verify` (including the
  coupling guard, schema checks, and the documentation bundles) passes.


## Surprises & Discoveries

- Three `kenshou-evidence` tests fail on a clean master (`loadComparisonSource records a
  comparison only after both arm concepts exist` and two `attest` cases). The vendored bundle
  `fixtures/consumer-baseline/docs/verification/` has attestations but no `runs/` records,
  because the top-level `.gitignore` rule `runs/` kept them out of git. This plan does not
  change that fixture, so `just verify` cannot pass until it is repaired. Recorded as FRIC-2.
  Evidence: `git stash -u` then the suite reports `29 examples, 3 failures`.

- `mori path` canonicalises the URI it is given: a guide cited by its file slug comes back as
  `mori://shinzui/kenshou/okf/guides/concepts/DOC-1`. The Mori resolver therefore relies on
  the record's own handle check. A record kind cited by anything other than its handle is
  reported as `handle-mismatch`, and nothing is guessed.


## Decision Log

- Decision: The owner-record code lives in the existing `kenshou-evidence` package under the
  module prefix `Kenshou.Evidence.Owner`, and no new package is created.
  Rationale: IR-2 leaves package placement to this plan. `kenshou-evidence` already depends on
  `okf-core` (the library that parses the Markdown-with-frontmatter documents owner records are
  written in), already shells out to `mori path` in `Kenshou.Evidence.Attest`, and already sits
  directly below `kenshou-cli` in the dependency order. A new package would change the release
  list, the coupling guard, the plan check, and the Hackage publication order for no gain. The
  later requests IR-3, IR-4, and IR-5 join owner records with evidence history, which is in the
  same package.
  Date: 2026-11-17

- Decision: The command is `owners`, with subcommands `status` and `snapshot`, in the Analysis
  group. `Kenshou.Cli.Registry.standardCommands` includes it with a default configuration, and
  a consumer that needs its own sources, resolver, or enrichment replaces it with
  `ownersCommandWith`.
  Rationale: `standardCommands :: [Recomputer] -> [CliCommand]` is a released signature. Adding
  the default command to its result changes no type, gives every consumer the command without
  work, and follows the existing `attestCommandWith recomputers` pattern for customisation.
  Date: 2026-11-17

- Decision: Whether a reference is an owner record is decided from the reference's shape and
  the record's own `type` field. A canonical reference must have the form
  `mori://<namespace>/<project>/okf/<bundle>/concepts/<HANDLE>`; anything else (a plan URI, an
  `https://` link) is reported as `not-a-record` without being resolved. A resolved concept
  whose `type` is not a configured record kind is also `not-a-record`.
  Rationale: IR-2 requires that a canonical reference to documentation remains visible and is
  never counted as a verified bug. The self-test scenario in
  `kenshou-core/src/Kenshou/Core/Selftest.hs` cites a plan URI, so this case exists in the
  repository today and gives a registry-free demonstration.
  Date: 2026-11-17

- Decision: A snapshot is a directory that is created once and never overwritten. `owners
  snapshot --out DIR` fails with exit code 2 if `DIR` exists.
  Rationale: IR-2 requires that later verification rounds can report from the same bytes. A
  snapshot that can be rewritten in place cannot serve as that evidence.
  Date: 2026-11-17

- Decision: No document this plan writes contains an absolute path. A record's provenance
  carries a `location` that is relative: to the mapped bundle directory for the mapped
  resolver, and to the checkout root (or the bare file name outside a checkout) for the Mori
  resolver. Absolute paths appear only in diagnostics on standard error.
  Rationale: A snapshot's digest must not depend on the machine that took it, and plans 9 and
  11 check snapshots in as fixtures. An absolute path would also commit a contributor's home
  directory.
  Date: 2026-11-18

- Decision: The library resolvers do not read git state. The checkout's `HEAD` revision and
  dirty flag are added by a separate decorator, `withGitProvenance`, which the `owners` command
  applies to live reads unless `--no-git-provenance` is given.
  Rationale: The fixtures live inside this repository's checkout. If `mappedResolver` recorded
  git state, the golden status document would change with every commit and would differ again
  when the tests run from a source distribution, which has no checkout (IR-1). Real consumers
  still get the revision by default, because for them it is useful provenance.
  Date: 2026-11-18

- Decision: A snapshot holds everything a replay prints: every reference reached during
  resolution (including duplicate targets that nothing cites directly) and the enrichment links
  computed when the snapshot was taken. A replay runs no source, no resolver, and no
  enrichment.
  Rationale: IR-2's fourth criterion requires repeatable reports from fixed bytes. An enrichment
  is an arbitrary consumer action; rerunning it on replay could change the report, and a
  duplicate target missing from the snapshot would force a live read.
  Date: 2026-11-18

- Decision: This plan is a minor version step under the Haskell Package Versioning Policy for
  `kenshou-evidence` and `kenshou-cli` (0.1.0.0 to 0.1.1.0). It bumps the `version` fields and
  the dependents' bounds on those two packages, and does not tag or publish.
  Rationale: The plan only adds modules, exports, and one command to the list
  `standardCommands` returns. The one behavior a consumer can notice is a name collision, which
  the CHANGELOG entry must state: a program that already contributes a command named `owners`
  must replace the standard one with `withCommand`. Publishing is a separate, deliberate act.
  Date: 2026-11-18

- Decision: `VersionClaim` has a sixth state, `ClaimMalformed` (JSON state `malformed`, raw
  `null`), for a version field of the wrong YAML type. A record with a malformed field stays
  `resolved` and carries one `malformed-field` reason per field. A malformed text field
  (`status`, `title`, `affects`, `duplicateOf`) is absent from the record, and its reason names
  it. A YAML number such as `fixedVersion: 1.3` counts as malformed because its text was not
  preserved.
  Rationale: Reporting such a field as `absent` would be a guess. The record's identity and
  its other claims are still trustworthy, so it is not made `unresolved`.
  Date: 2026-11-18

- Decision: The library interfaces differ from the plan in four places. (1)
  `ResolvedBytes` also carries the local file it read (`Maybe FilePath`). `withGitProvenance`
  needs that path, and no document ever records it. (2) `ResolveResult` has an `Ambiguous
  [Text]` answer for `ambiguous-handle`. (3) `resolveOwnersObserved` returns the entries
  together with each resolver answer. `writeSnapshot :: FilePath -> [RecordKind] ->
  [OwnerCitation] -> [(Text, ResolveResult)] -> OwnerStatus -> IO (Either SnapshotError Text)`
  stores those answers and returns the snapshot digest. (4) `readSnapshot :: FilePath -> IO
  (Either Text OwnerStatus)` takes no record kinds, because the snapshot stores the kinds it
  was resolved with. A replay therefore cannot change when a consumer later adds a kind.
  `memoryResolver` and `parseConceptReference` are also exported.
  Rationale: With the planned signatures a snapshot could not reproduce `not-found` or
  `ambiguous-handle` answers without reverse-engineering them from reasons. The decorator also
  had no file to inspect.
  Date: 2026-11-18

- Decision: The mapped resolver finds a concept by the handle field of its own type. For a
  concept of an unconfigured type, it uses the first configured handle field the concept has.
  The fixture `triage-guide.md` (`type: Guide`, `bugId: BUG-11`) exercises that path and is
  reported as `not-a-record` with reason `unconfigured-type`. Reason codes are `not-a-concept`,
  `unconfigured-type`, `unreadable-record`, `missing-field`, `malformed-field`,
  `handle-mismatch`, `not-found`, `ambiguous-handle`, `resolver-failed`, `no-mapping`,
  `duplicate-cycle`, `duplicate-target-unresolved`, and `duplicate-target-absent`.
  Rationale: A directory bundle has no registry to say which key identifies a non-record
  concept, and matching on file names is forbidden.
  Date: 2026-11-18


## Outcomes & Retrospective

(To be filled during and after implementation.)


## Context and Orientation

Kenshou is a Haskell verification harness. A consumer (a project that verifies some runtime)
writes scenarios, registers them, and links them into its own executable. The repository is
one cabal project of nine packages, each in a directory `kenshou-<name>/`. The ones this plan
touches are `kenshou-core` (the kernel: scenario, registry, and command types),
`kenshou-evidence` (publishing and reading verification records), `kenshou-cli` (assembles the
standard commands), and `kenshou-synthetic` (a reference suite for a made-up layer called
`synthetic`, whose `app/Main.hs` builds the `kenshou` executable used throughout this plan).
Work inside the development shell: run `nix develop` at the repository root first. `just
verify` runs every repository check.

The terms this plan uses:

A scenario is one registered verification case (`Kenshou.Core.Scenario.Scenario` in
`kenshou-core/src/Kenshou/Core/Scenario.hs`). Its optional `knownDefect` field holds a
`KnownDefect`, which is either a single defect with a `reference` (a text URI), a `summary`,
the `expectedFailures` labels it excuses, and an `appliesTo` cohort scope, or a
`KnownDefectGroup` of several. `individualKnownDefects` flattens a group. `mkRegistry` in
`kenshou-core/src/Kenshou/Core/Bundle.hs` rejects a reference that does not start with
`mori://` or `https://`.

An owner record is a document in the repository that owns the broken behavior. In this
ecosystem owner records are OKF concepts: Markdown files with a YAML frontmatter block, kept
in a directory called a bundle. OKF is the knowledge-file format parsed by the `okf-core`
library (`Okf.Document.parseDocument`, `frontmatterLookup`), which `kenshou-evidence` already
depends on. Two record kinds matter. A `Bug Report` has the frontmatter keys `bugId` (its
handle, such as `BUG-3`), `status` (one of `reported`, `confirmed`, `in-progress`, `fixed`,
`wont-fix`, `duplicate`, `not-a-bug`, `cannot-reproduce`), `affects` (a Mori URI of the project
or artifact whose behavior is wrong), `affectedVersion`, `fixedVersion`, `lastWorkingVersion`,
and `duplicateOf` (a local handle such as `BUG-1`, or a `mori://` URI). An `Improvement
Request` has `requestId` (such as `IR-2`) and `status`. The three version keys take a bare
released version, the word `unreleased`, or the word `unknown`; because they are free text, a
reader must also expect anything else. The file name of a record is not its identity: the
handle in the frontmatter is.

A canonical reference is a Mori URI. Mori is the local project registry; `mori path <uri>`
prints the canonical URI on one line and the file's absolute path on the next, and exits 1
when the artifact is not found. For example:

```text
$ mori path mori://shinzui/kenshou/okf/improvement-requests/concepts/IR-2
mori://shinzui/kenshou/okf/improvement-requests/concepts/IR-2
/…/kenshou/docs/improvement-requests/resolve-owner-records-through-consumer-supplied-sources.md
```

A finding is something the consumer observed and tracks outside a scenario, for example a
defect found while writing a guide. Kenshou has no opinion on where a consumer keeps findings;
this plan defines a small JSON document a consumer can produce from whatever it uses.

How commands are assembled: `Kenshou.Core.Cli` (`kenshou-core/src/Kenshou/Core/Cli.hs`) defines
`CliCommand` (a name, description, group, and an `optparse-applicative` parser yielding
`CliEnv -> IO ExitCode`) and `Program`, the record an executable passes to
`Kenshou.Cli.mainWith`. `CliEnv` gives a command the validated `Registry`.
`kenshou-cli/src/Kenshou/Cli/Registry.hs` defines `standardCommands`, the list of generic
commands, and `selfTestAssembly`. `kenshou-evidence/src/Kenshou/Evidence/HistoryCli.hs` is a
short, complete example of a command defined in `kenshou-evidence`. By convention standard
output carries only the command's document; diagnostics go to standard error. Exit codes are
part of the protocol: 0 success, 1 failed, 2 usage error, 3 inconclusive, 4 errored or
infrastructure failure.

The relevant architecture decisions are these.
[ADR-1](../adr/0001-toolkit-packages-never-depend-on-a-layer-bundle.md) says the generic
packages never depend on a consumer's layer; `scripts/coupling-guard.sh` fails when a generic
package or schema contains the words `keiro`, `kiroku`, `pgmq`, `shibuya`, or `kafka`, so
fixtures here use made-up owners.
[ADR-3](../adr/0003-kenshou-owns-the-verification-protocol.md) says every JSON document carries
an explicit schema identifier, uses hand-written codecs rather than derived ones, and that
commands are contributed as values.
[ADR-11](../adr/0011-distinguish-documented-limitations-from-known-defects.md) says known-defect
references are canonical `mori://` URIs to bug reports filed in the owning repository.
[ADR-16](../adr/0016-register-a-suite-as-layer-bundles-assembled-into-a-program.md) describes
the `Program` assembly. [ADR-20](../adr/0020-verify-the-harness-against-its-own-cohort-and-confine-consumer-data.md)
confines real consumer data to two fixture directories; this plan adds none.

The request originates from
`mori://shinzui/keiro-runtime-kenshou/masterplans/2-close-the-verification-and-repair-loop-for-the-keiro-runtime-in-rounds`,
and the consumer's integration is
`mori://shinzui/keiro-runtime-kenshou/plans/20-report-owner-record-status-for-every-kenshou-finding`.
Neither is needed to implement this plan and nothing here may name that consumer in code.

IR-3, IR-4, and IR-5 build on this plan's snapshot and canonical identities. Their plans are
[plan 9](9-reconcile-known-defect-scopes-with-owner-version-claims.md),
[plan 10](10-derive-fix-verification-dispositions-from-immutable-evidence.md), and
[plan 11](11-run-verification-rounds-against-frozen-baseline-evidence.md).

One constraint from IR-1
([docs/improvement-requests/run-every-package-test-suite-from-its-source-distribution.md](../improvement-requests/run-every-package-test-suite-from-its-source-distribution.md)):
tests must not read files outside their own package. Put every new fixture inside the package
whose test reads it, and list it under `extra-source-files` in that package's cabal file.


## Plan of Work

### Milestone 1: the owner-record library

This milestone produces a library with no command. At the end, a test can hand it citations and
a resolver and get back a complete status document.

Create `kenshou-evidence/src/Kenshou/Evidence/Owner.hs` (the model and the resolution
algorithm), `Kenshou/Evidence/Owner/Record.hs` (parsing a record's bytes),
`Kenshou/Evidence/Owner/Resolver.hs` (the resolvers), and `Kenshou/Evidence/Owner/Snapshot.hs`
(writing and reading a snapshot directory). Add them to `exposed-modules` in
`kenshou-evidence/kenshou-evidence.cabal`. The types are specified in Interfaces and
Dependencies; the behavior is as follows.

A citation is a reference together with who cites it: a scenario identifier or a finding
identifier, plus an optional location string. A source is a named action returning citations.
`catalogOwnerSource` builds one from a `Registry`: for every scenario, every individual known
defect yields one citation carrying the scenario identifier and that defect's expected failure
labels. `findingsFileSource` reads a `kenshou.owner-findings/v1` document:

```json
{
  "schema": "kenshou.owner-findings/v1",
  "findings": [
    {
      "id": "F-1",
      "title": "Reader loses the last item after restart",
      "references": ["mori://fixture/owner-a/okf/bug-reports/concepts/BUG-1"],
      "location": "docs/findings.md#f-1"
    }
  ]
}
```

A resolver takes a reference and returns either the record's bytes with provenance, or a
structured failure. Provenance records the resolver's name, a relative `location` for the file
it read, and the SHA-256 of the bytes; it never records an absolute path. The resolvers
themselves do not look at git. `withGitProvenance` wraps a resolver and, when the file it read
is inside a git checkout, adds that checkout's `HEAD` revision and whether the file differs from
it; outside a checkout, or when `git` is not installed, both stay absent. Provide three
resolvers. `mappedResolver` takes pairs of a bundle URI
prefix and a local bundle directory; for a reference under a mapped prefix it parses every
`.md` file in that directory (excluding `index.md` and `log.md`) and selects the one whose
frontmatter handle equals the reference's handle. It must never match on a file name. Its
`location` is the file's path relative to the mapped directory. It
reports `not-found` when no record carries the handle and `ambiguous-handle` when more than one
does. `moriResolver` runs `mori path <reference>` and reads the path printed on the second
line; a non-zero exit is `not-found`, and a missing `mori` executable is `resolver-failed`. Its
`location` is the file's path relative to the root of the checkout that contains it, or the bare
file name when there is no checkout.
`snapshotResolver` answers only from a snapshot directory. `chainResolvers` tries resolvers in
order and returns the first that does not answer `no-mapping`.

Parsing a record reads the frontmatter and nothing else. A record kind is a pair of an OKF
`type` name and the frontmatter key that holds the handle; the defaults are `Bug Report` with
`bugId` and `Improvement Request` with `requestId`, and a consumer may supply more. The parser
keeps `status`, `affects`, `affectedVersion`, `fixedVersion`, `lastWorkingVersion`,
`duplicateOf`, and `title` exactly as written, and additionally classifies each version field
into one of five states: absent, `unreleased`, `unknown`, a released version (parsed with
`Data.Version.parseVersion`, the same parser `cohortScopeApplies` uses), or unparseable text.
A field of the wrong YAML type (for example a list where text is expected) becomes a
`malformed-field` reason naming the field; it never becomes a guess. If the handle inside the
record differs from the handle in the reference, the record is reported with reason
`handle-mismatch` and is not treated as resolved.

Resolution proceeds per distinct reference. A reference that is not of the canonical concept
form is `not-a-record`. Otherwise the resolver is asked; failure gives `unresolved` with the
resolver's reason. A resolved concept of an unconfigured type is `not-a-record`. A resolved
record whose status is `duplicate` (or that has a `duplicateOf` value) is followed: a local
handle is resolved against the same bundle prefix as the record that names it, a `mori://`
value is used as given. The walk keeps the set of references visited; reaching one twice ends
the walk with reason `duplicate-cycle`, and every member of the cycle is reported with that
reason and no canonical target. A chain that ends at an unresolved reference is reported as
`duplicate-target-unresolved`. Otherwise the last record is the canonical record, and each
earlier one is an alias of it. Citations made through an alias are attributed to the canonical
record and keep the alias they came through. Canonical identity is always the full Mori URI, so
`BUG-1` of one owner and `BUG-1` of another never merge.

The result is an `OwnerStatus` value with one entry per distinct reference that is cited or was
reached while following a duplicate chain, sorted by reference, and a hand-written encoder for
`kenshou.owner-status/v1`. A record that nothing cites directly and that no alias leads
citations to has an empty `citedBy`; it is listed so that a snapshot is complete. An entry looks like this:

```json
{
  "reference": "mori://fixture/owner-a/okf/bug-reports/concepts/BUG-2",
  "resolution": "resolved",
  "reasons": [],
  "kind": "Bug Report",
  "handle": "BUG-2",
  "title": "Lease is not released after a cancelled write",
  "status": "fixed",
  "affects": "mori://fixture/owner-a",
  "versions": {
    "affected": {"raw": "1.2.0", "state": "released"},
    "fixed": {"raw": "1.3.0", "state": "released"},
    "lastWorking": {"raw": null, "state": "absent"}
  },
  "canonical": "mori://fixture/owner-a/okf/bug-reports/concepts/BUG-2",
  "aliases": ["mori://fixture/owner-a/okf/bug-reports/concepts/BUG-4"],
  "citedBy": [
    {"scenario": "consumer/table/correctness/lease-release", "labels": ["lease-held"], "via": "mori://fixture/owner-a/okf/bug-reports/concepts/BUG-4"},
    {"finding": "F-2", "location": "docs/findings.md#f-2"}
  ],
  "source": {"resolver": "mapped", "location": "lease-not-released.md", "sha256": "…", "revision": null, "dirty": null},
  "links": []
}
```

The document's top level has `schema`, `observedAt` (when the bytes were captured, not when the
report was rendered), `snapshot` (the snapshot's digest, or null for a live read), and
`records`. `resolution` is one of `resolved`, `unresolved`, and `not-a-record`. `links` holds
whatever a consumer's enrichment returns, described in Milestone 3.

A snapshot directory contains `snapshot.json` (schema `kenshou.owner-snapshot/v1`: `observedAt`,
the citations, and for each reference in the status document its resolution outcome, provenance,
and enrichment links) and `records/`, holding each resolved record's bytes in a file named by its
SHA-256. Every reference reached during resolution is included, so a duplicate target that
nothing cites directly has its bytes in the snapshot too. Reading a snapshot verifies every file
against its recorded digest and fails if one differs; it then rebuilds the status document from
the stored bytes and the stored links, and consults nothing else. The snapshot's own digest is
the SHA-256 of `snapshot.json`. Because provenance holds only relative locations, two machines
that snapshot the same bytes without git provenance produce the same `snapshot.json` apart from
`observedAt`.

Create the fixtures under `kenshou-evidence/test/fixtures/owners/`: two bundles,
`owner-a/bug-reports/` and `owner-b/bug-reports/`, and `findings.json`. Name the Markdown files
by subject, not by handle, so that a file-name match would fail the tests. Between them they
must contain: a `BUG-1` in each owner; a fixed report with a released `fixedVersion`; a fixed
report with `fixedVersion: unreleased`; one with `unknown`; one whose `fixedVersion` is prose; a
duplicate of a duplicate of a canonical report; two reports that are duplicates of each other;
a duplicate whose target does not exist; a report whose `fixedVersion` is a YAML list; and one
concept of an unrelated type (use `type: Guide`). The findings file cites an overlapping subset,
one handle that exists in no bundle, and one `https://` URL. Add the fixture globs to
`extra-source-files`.

Add a `describe "owner records"` block to `kenshou-evidence/test/Main.hs` that resolves the
fixtures with `mappedResolver` and asserts each case's resolution, reasons, canonical reference,
aliases, and version states, and that the encoded document for the whole fixture set, with a
fixed `observedAt` supplied by the test, equals the checked-in golden file
`kenshou-evidence/test/fixtures/owners/status.golden.json` byte for byte. No path substitution is
needed: `mappedResolver` records relative locations and no git state, so the document is the same
in a checkout, in a source distribution, and on any machine. Add one test that wraps the resolver
in `withGitProvenance` over a temporary directory that is not a checkout and asserts that
`revision` and `dirty` stay absent.

### Milestone 2: the `owners` command

Create `kenshou-evidence/src/Kenshou/Evidence/Owner/Cli.hs` exporting `ownersCommand` and
`ownersCommandWith`. The command has two subcommands.

`owners status` accepts `--findings FILE` (repeatable), `--map PREFIX=DIR` (repeatable),
`--snapshot DIR`, `--no-git-provenance`, and `--json`. Without `--snapshot` it gathers citations
from the registry and the findings files, resolves them with the mapped resolver (when any
`--map` is given) chained before the Mori resolver, both wrapped in `withGitProvenance` unless
`--no-git-provenance` is given, and prints the report. With `--snapshot` it reads citations,
bytes, and links only from the snapshot: it runs no source (including any a consumer configured),
no resolver, and no enrichment. Combining `--snapshot` with `--findings`, `--map`, or
`--no-git-provenance` is a usage error. The text report prints one block per record: the reference, the
resolution with its reasons, the owner's status and version fields exactly as written, the
canonical reference when it differs, and the citing scenarios and findings. One diagnostic line
per unresolved, cyclic, or malformed record goes to standard error. The exit code is 0 when the
report was produced, whatever it contains; 2 for a usage error; 4 when a source reports an
error, or a findings file or a snapshot cannot be read or fails its digest check.

`owners snapshot --out DIR` takes the same source options, resolves once, runs the configured
enrichments once, and writes the snapshot directory. It refuses an existing `DIR`. A snapshot
meant to be checked in as a fixture is taken with `--no-git-provenance`, so that it does not
change when the surrounding repository gains a commit.

Add `ownersCommand` to the list in `standardCommands` in
`kenshou-cli/src/Kenshou/Cli/Registry.hs`, and add `withCommand :: CliCommand -> [CliCommand] ->
[CliCommand]` there, which replaces the command of the same name or appends it. Write the JSON
Schema files `schemas/kenshou.owner-status.v1.schema.json`,
`schemas/kenshou.owner-snapshot.v1.schema.json`, and
`schemas/kenshou.owner-findings.v1.schema.json`, and add `check-jsonschema` lines for the golden
status document, a golden snapshot index, and the fixture findings file to the `schemas-check`
recipe in `justfile`. Add a help topic `kenshou-cli/help/owners.md` and register it the way the
existing topics in `kenshou-cli/src/Kenshou/Cli/Help.hs` are registered; the help golden files
under `kenshou-cli/test/golden/` may need regenerating.

In `kenshou-cli/test/Main.hs` add tests that run the command through `runWithArgsWith` (the
same entry point the existing CLI tests use) against a copy of the fixtures in a temporary
directory: take a snapshot, record the SHA-256 of every owner file, edit one owner file's
`status`, run `owners status --snapshot` twice, and assert that both outputs decode to equal
JSON values, that they still show the original status, that a live `owners status` shows the
edited status, and that no command changed any owner file. The CLI tests may not read
`kenshou-evidence`'s fixture directory (IR-1), so generate the small bundles they need in the
test itself.

### Milestone 3: the consumer extension points, proven by a synthetic consumer

`ownersCommandWith` takes an `OwnerConfig`: extra sources added to the registry source, an
optional resolver placed before the built-in chain, extra record kinds, and enrichments. An
enrichment is a named function from a resolved record to a list of labelled links; it exists so
a consumer can attach its own plan or tracker references (the motivating consumer attaches
intention identifiers from a personal tracker) without Kenshou depending on any tracker.
Enrichment results appear under `links` and never affect resolution. Enrichments run during a
live `owners status` and during `owners snapshot`; a snapshot stores their results, and a replay
prints the stored links without running them.

In `kenshou-cli/test/Main.hs`, assemble a synthetic consumer the way a real one would: a
`LayerBundle` for a made-up layer with two scenarios whose known defects cite fixture owner
records (one a group of two defects), a `Program` built from `selfTestAssembly` with that bundle
added and `withCommand (ownersCommandWith config)` applied to its commands, where `config`
supplies an in-memory source, an in-memory resolver, and an enrichment. Assert that the report
contains the extra source's citations, the resolver's records, and the enrichment's links, and
that nothing was read through `mori`. This is the acceptance evidence that a consumer needs no
change to a generic package and no tracker.

Finish the documentation. Add terminology concepts for "owner record" and "owner snapshot" to
`docs/terminology/` following the existing files there, add a section to
`docs/guides/adopting-kenshou-in-a-project.md` showing a consumer supplying `OwnerConfig`, and
record the placement and snapshot decisions in a new ADR. Allocate the ADR handle with
`okf id next docs/adr --profile docs/adr/profile.dhall ADR`, add a log entry with `okf log add`,
and regenerate the indexes with `okf index docs/<bundle> --write`. Add a CHANGELOG entry to
`kenshou-evidence/CHANGELOG.md` and `kenshou-cli/CHANGELOG.md`, set both packages' `version` to
0.1.1.0, and raise the bounds on them in the cabal files of the packages that depend on them
(`kenshou-cli` on `kenshou-evidence`, `kenshou-synthetic` on `kenshou-cli`) to `^>=0.1.1.0`. The
`kenshou-cli` entry states that `standardCommands` now includes a command named `owners` and
that a program contributing its own command of that name must use `withCommand`. Do not tag or
publish. Update IR-2's frontmatter only
in ways its profile allows (read `docs/improvement-requests/profile.dhall` and the profile it
imports before changing `status`), and add a line to `docs/improvement-requests/log.md` with
`okf log add`.


## Concrete Steps

All commands run from the repository root inside `nix develop`.

Build and run the focused tests while developing:

```bash
cabal build kenshou-evidence kenshou-cli
cabal test kenshou-evidence:test:kenshou-evidence-test
cabal test kenshou-cli:test:kenshou-cli-test
```

Exercise the command against the fixtures:

```bash
K=$(cabal list-bin kenshou)
F=kenshou-evidence/test/fixtures/owners
"$K" owners status --findings "$F/findings.json" \
  --map mori://fixture/owner-a/okf/bug-reports="$F/owner-a/bug-reports" \
  --map mori://fixture/owner-b/okf/bug-reports="$F/owner-b/bug-reports"
```

The report should contain blocks of this shape (wording may differ; the facts may not):

```text
mori://fixture/owner-a/okf/bug-reports/concepts/BUG-1
  resolved  Bug Report  status=fixed  affected=1.2.0  fixed=1.3.0
  cited by finding F-1

mori://fixture/owner-b/okf/bug-reports/concepts/BUG-1
  resolved  Bug Report  status=confirmed  affected=0.4.1  fixed=(absent)
  cited by finding F-3

mori://fixture/owner-a/okf/bug-reports/concepts/BUG-5
  resolved  duplicate-cycle
  cited by finding F-4

mori://shinzui/kenshou/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites
  not-a-record  reference does not name an OKF concept
  cited by scenario selftest/kernel/correctness/known-defect
```

Check the snapshot round trip by hand:

```bash
tmp=$(mktemp -d)
cp -R "$F" "$tmp/owners"
"$K" owners snapshot --out "$tmp/snap" --findings "$tmp/owners/findings.json" \
  --map mori://fixture/owner-a/okf/bug-reports="$tmp/owners/owner-a/bug-reports" \
  --map mori://fixture/owner-b/okf/bug-reports="$tmp/owners/owner-b/bug-reports"
"$K" owners status --snapshot "$tmp/snap" --json > "$tmp/first.json"
sed -i.bak 's/^status: fixed$/status: confirmed/' "$tmp"/owners/owner-a/bug-reports/*.md
"$K" owners status --snapshot "$tmp/snap" --json > "$tmp/second.json"
diff <(jq -S . "$tmp/first.json") <(jq -S . "$tmp/second.json") && echo "replay identical"
"$K" owners snapshot --out "$tmp/snap"; echo "exit=$?"
```

The expected tail of the transcript is:

```text
replay identical
kenshou owners snapshot: refusing to overwrite an existing snapshot
exit=2
```

Finish with the full gate:

```bash
just verify
```

Commit at each milestone. Every commit message follows Conventional Commits and ends with both
trailers:

```text
feat(evidence): resolve owner records from consumer-supplied sources

ExecPlan: docs/plans/8-resolve-owner-records-through-consumer-supplied-sources.md
Intention: intention_01m7nec7ckece87s8pqhkme1py
```


## Validation and Acceptance

The plan is accepted when all four of IR-2's criteria hold as observable behavior.

For AC-1, the fixture command prints, and `--json` encodes, every cited record with its
canonical reference, the owner's raw status and version text, its resolution state, and its
citing scenarios and findings; the golden-file test compares the JSON with values taken from the
fixture records.

For AC-2, the `owner records` test block passes for a duplicate chain, a duplicate cycle, a
missing record, a missing duplicate target, a non-record concept, a plan reference, an
`https://` reference, `unreleased`, `unknown`, unparseable, and malformed version fields, and
for two owners that both have a `BUG-1`. Each case asserts a structured reason and a stable
canonical reference, and no case produces a version or identity that is not in the source.

For AC-3, the synthetic-consumer test in `kenshou-cli/test/Main.hs` passes, `just
coupling-check` prints `coupling-guard: clean`, and `just plan-check` passes. The test runs with
no `mori` lookups, which shows that neither the registry nor a tracker is required.

For AC-4, the snapshot test passes: two reports from one snapshot are equal as JSON values after
the owner files changed, and every owner file's digest is unchanged by every command.

`just verify` exits 0. Before this plan, `kenshou owners status` fails with a usage error
because the command does not exist; after it, the command exits 0.


## Idempotence and Recovery

Every command in this plan is read-only with respect to owner repositories. `owners status` can
be run any number of times. `owners snapshot` creates its directory once and refuses to
overwrite it; to retake a snapshot, choose a new directory, and delete an abandoned one by hand.
The implementation writes a snapshot into a temporary sibling directory and renames it into
place, so an interrupted run leaves no partial snapshot under the requested name. Tests work in
temporary directories. If regenerating a golden file, inspect the diff before committing it;
the golden file is the acceptance evidence, not an output to accept blindly.


## Interfaces and Dependencies

No new library dependency is needed. `kenshou-evidence` already depends on `okf-core`, `aeson`,
`process`, `directory`, `filepath`, `containers`, `text`, `bytestring`, and `time`. Use
`Kenshou.Core.Canonical.sha256Hex` for digests, as `Kenshou.Evidence.Source` does.

At the end of the plan these names exist. Field details beyond those stated may be adjusted
during implementation, but the later plans depend on the names and meanings below.

In `kenshou-evidence/src/Kenshou/Evidence/Owner.hs`:

```haskell
data Citer = CitedByScenario ScenarioId [Text] | CitedByFinding Text

data OwnerCitation = OwnerCitation
  { reference :: Text,
    citer :: Citer,
    location :: Maybe Text
  }

data OwnerSource = OwnerSource
  { name :: Text,
    citations :: IO (Either Text [OwnerCitation])
  }

catalogOwnerSource :: Registry -> OwnerSource
findingsFileSource :: FilePath -> OwnerSource

data Resolution = Resolved | Unresolved | NotARecord

data OwnerEntry = OwnerEntry
  { reference :: Text,
    resolution :: Resolution,
    reasons :: [OwnerReason],
    record :: Maybe OwnerRecord,
    canonical :: Maybe Text,
    aliases :: [Text],
    citedBy :: [(OwnerCitation, Maybe Text)],
    source :: Maybe Provenance,
    links :: [OwnerLink]
  }

data OwnerStatus = OwnerStatus
  { observedAt :: UTCTime,
    snapshotDigest :: Maybe Text,
    records :: [OwnerEntry]
  }

resolveOwners :: [RecordKind] -> OwnerResolver -> [OwnerCitation] -> IO [OwnerEntry]
canonicalOwners :: OwnerStatus -> Map Text OwnerEntry
```

`canonicalOwners` maps every cited reference, including aliases, to the entry of its canonical
record; plans 9 and 10 use it to join scenarios to owners.

In `kenshou-evidence/src/Kenshou/Evidence/Owner/Record.hs`:

```haskell
data RecordKind = RecordKind {typeName :: Text, handleField :: Text}
defaultRecordKinds :: [RecordKind]

data VersionClaim
  = ClaimAbsent
  | ClaimUnreleased
  | ClaimUnknown
  | ClaimReleased Version Text
  | ClaimUnparseable Text

data OwnerRecord = OwnerRecord
  { kind :: Text,
    handle :: Text,
    title :: Maybe Text,
    status :: Maybe Text,
    affects :: Maybe Text,
    affectedVersion :: VersionClaim,
    fixedVersion :: VersionClaim,
    lastWorkingVersion :: VersionClaim,
    duplicateOf :: Maybe Text
  }

parseOwnerRecord :: [RecordKind] -> ByteString -> Either OwnerReason OwnerRecord
```

In `kenshou-evidence/src/Kenshou/Evidence/Owner/Resolver.hs`:

```haskell
data Provenance = Provenance
  { resolver :: Text,
    location :: Maybe Text,
    sha256 :: Text,
    revision :: Maybe Text,
    dirty :: Maybe Bool
  }

data ResolveResult
  = ResolvedBytes ByteString Provenance
  | NoMapping
  | NotFound Text
  | ResolverFailed Text

data OwnerResolver = OwnerResolver {name :: Text, resolve :: Text -> IO ResolveResult}

mappedResolver :: [RecordKind] -> [(Text, FilePath)] -> OwnerResolver
moriResolver :: OwnerResolver
chainResolvers :: [OwnerResolver] -> OwnerResolver
withGitProvenance :: OwnerResolver -> OwnerResolver
```

`location` is always relative, as described in the Plan of Work. Only `withGitProvenance` fills
`revision` and `dirty`.

In `kenshou-evidence/src/Kenshou/Evidence/Owner/Snapshot.hs`:

```haskell
writeSnapshot :: FilePath -> OwnerStatus -> [(Text, ByteString)] -> IO (Either Text ())
readSnapshot :: [RecordKind] -> FilePath -> IO (Either Text OwnerStatus)
snapshotResolver :: FilePath -> IO (Either Text OwnerResolver)
```

In `kenshou-evidence/src/Kenshou/Evidence/Owner/Cli.hs`:

```haskell
data OwnerEnrichment = OwnerEnrichment {name :: Text, enrich :: OwnerEntry -> IO [OwnerLink]}

data OwnerConfig = OwnerConfig
  { sources :: [OwnerSource],
    resolver :: Maybe OwnerResolver,
    recordKinds :: [RecordKind],
    enrichments :: [OwnerEnrichment]
  }

defaultOwnerConfig :: OwnerConfig
ownersCommand :: CliCommand
ownersCommandWith :: OwnerConfig -> CliCommand
```

In `kenshou-cli/src/Kenshou/Cli/Registry.hs`, `standardCommands` gains `ownersCommand`, and
`withCommand :: CliCommand -> [CliCommand] -> [CliCommand]` is exported and re-exported from
`Kenshou.Cli`.

The documents this plan introduces are `kenshou.owner-findings/v1`, `kenshou.owner-status/v1`,
and `kenshou.owner-snapshot/v1`, each with a schema file under `schemas/`.


## Revision Notes

2026-11-18: Revised after review, before implementation began. Provenance now records a
relative location instead of an absolute path, and git state is added only by the
`withGitProvenance` decorator, because the earlier design made the golden file and every
checked-in snapshot depend on the machine and the current commit. Snapshots now store enrichment
links and every reference reached through a duplicate chain, so a replay runs nothing live. The
plan also states its version step and the `owners` command-name collision, which it did not
before.
