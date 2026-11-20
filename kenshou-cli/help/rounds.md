# Verification rounds

A round freezes a baseline observation index, its trust, both cohort
identities, an owner snapshot, the catalog, and the planning inputs. Choose
round and evaluation identifiers that describe the work.

## Open and plan

Capture the owner snapshot with `kenshou owners snapshot`, and capture each
identity with `kenshou cohort show --json` while its cohort is active.
Supply a JSON array of explicit published run IDs or concept references for
`--baseline-runs`. Use `--bundle`, `--bundle-uri`, and `--run-data` to locate
published evidence when needed.

```bash
kenshou round open --id refresh --out refresh --mode release \
  --owners owners --package-map owner-package-map.json \
  --baseline-identity baseline.json --candidate-identity candidate.json \
  --baseline-runs baseline-runs.json
kenshou round plan --round refresh --arm candidate --out smoke \
  --max-tier smoke --placement local --seed 42
```

Use `--from-inputs DIR` in place of the fresh capture inputs to adopt a manual
capture and verify it offline. The directory has the same layout as
`refresh/inputs`. If it includes a `references.json` array, each entry names
an artifact relative to that directory with `kind`, `path`, and `sha256`.
Use repeatable `--reference KIND=PATH` to record supporting files by digest.
A `--scope-overrides FILE` document changes a named declaration's scope only
for the round and appears in the report with its reason.

Release mode considers the whole catalog. Change mode considers owner
reproductions and scenarios affected by package changes. `--select` and
`--exclude` filter that selection. The coverage document records omissions,
including placement and budget limits.

## Execute, evaluate, and report

Activate the plan's cohort before running the ordinary executor.

```bash
kenshou execute --plan refresh/plans/smoke.run-plan.json --out execution
kenshou round evaluate --round refresh --id first --plan smoke --runs execution
kenshou round report --round refresh --evaluation first --json
kenshou round report --round refresh --evaluation first --write-report refresh-first.md
```

A sealed local run has `local-sealed` trust. A pass can support
`not-reproduced`. To verify a fix, publish and attest the results, then create
a separate evaluation with `--candidate-runs FILE`. The file is a JSON array
of run IDs or concept references. You can combine it with `--runs execution`
to keep the execution's list of attempts. To freeze an empty candidate
evaluation deliberately, use `--allow-empty`.

Repeatable `--comparison PATH` links controlled performance evidence.
Reports replay the frozen evaluation. Use a new evaluation identifier when
more evidence becomes available. Exit 1 signals a regression, a defect on
a claimed fixed release, or a new failure. Exit 3 signals incomplete
verification, including absent controls or missing coverage. Exit 0 signals a
completed comparison. Exit 2 signals usage errors and exit 4 signals missing or
invalid inputs.
