set shell := ["zsh", "-cu"]

pg_host := env_var_or_default("PGHOST", "db")
pg_data := env_var_or_default("PGDATA", "db/db")
pg_log := env_var_or_default("PGLOG", "db/postgres.log")
pg_user := env_var_or_default("PGUSER", `whoami`)
pg_database := env_var_or_default("PGDATABASE", "kenshou")

[group('meta')]
default:
    just --list

[group('meta')]
verify: fmt-check haskell-build plan-check cohort-check graph-check haskell-test schemas-check selftest

# Fails when Cabal's resolved plan contains a consumer layer package. The
# generic packages must build without any of them.
[group('verification')]
plan-check:
    cabal build all --dry-run >/dev/null
    jq -r '.["install-plan"][]["pkg-name"]' dist-newstyle/cache/plan.json | sort -u | grep -E '^kenshou-'
    ! jq -r '.["install-plan"][]["pkg-name"]' dist-newstyle/cache/plan.json | grep -qE '^kenshou-(pgmq|kiroku|shibuya|kafka|keiro|runtime)$'

[group('verification')]
graph-check:
    cabal run -v0 kenshou -- plan --graph-check

[group('verification')]
schemas-check:
    check-jsonschema --schemafile schemas/kenshou.perf-calibration-definition.v1.schema.json kenshou-core/test/golden/perf-calibration-definition.synthetic.json
    check-jsonschema --schemafile schemas/kenshou.perf-calibration-acceptance.v1.schema.json kenshou-core/test/golden/perf-calibration-acceptance.synthetic.json
    check-jsonschema --schemafile schemas/kenshou.perf-calibration-reference.v1.schema.json kenshou-core/test/golden/perf-calibration-reference.synthetic.json
    check-jsonschema --schemafile schemas/kenshou.perf-publication.v1.schema.json kenshou-cli/test/fixtures/perf-publication.synthetic.json
    check-jsonschema --schemafile schemas/kenshou.perf-session.v1.schema.json kenshou-remote/test/golden/perf-session.fixture.json
    check-jsonschema --schemafile schemas/kenshou.perf-result.v1.schema.json kenshou-core/test/golden/perf-result.*.fixture.json
    check-jsonschema --schemafile schemas/kenshou.perf-prepared.v1.schema.json kenshou-core/test/golden/perf-prepared.fixture.json
    check-jsonschema --schemafile schemas/kenshou.perf-plan.v1.schema.json kenshou-core/test/golden/perf-plan.json
    check-jsonschema --schemafile schemas/kenshou.perf-request.v1.schema.json kenshou-core/test/golden/perf-request.json
    for fixture in kenshou-remote/test/golden/cell/cell.*.v1.json; do schema="${fixture%.json}.schema.json"; check-jsonschema --base-uri "file://$PWD/$schema" --schemafile "$schema" "$fixture" || exit; done
    check-jsonschema --schemafile schemas/kenshou.cohort-identity.v1.schema.json kenshou-core/test/fixtures/cohort-identity.golden.json
    check-jsonschema --schemafile schemas/kenshou.payload.v1.schema.json kenshou-remote/test/golden/payload.json
    check-jsonschema --schemafile schemas/kenshou.payload-identity.v1.schema.json kenshou-remote/test/golden/payload-identity.json
    check-jsonschema --schemafile schemas/kenshou.cell-run.v1.schema.json kenshou-remote/test/golden/cell-run.json
    check-jsonschema --schemafile schemas/kenshou.cell-session.v1.schema.json kenshou-remote/test/golden/cell-session.json
    check-jsonschema --schemafile schemas/kenshou.cell-capabilities.v1.schema.json kenshou-remote/test/golden/cell-capabilities.json
    check-jsonschema --schemafile schemas/kenshou.cell-route.v1.schema.json kenshou-remote/test/golden/cell-route.json
    check-jsonschema --schemafile schemas/kenshou.parity-report.v1.schema.json kenshou-remote/test/golden/parity-report.json
    check-jsonschema --schemafile schemas/component-graph.v1.schema.json kenshou-core/data/components.json
    check-jsonschema --schemafile schemas/run-plan.v1.schema.json kenshou-core/test/golden/run-plan.minimal.json
    check-jsonschema --schemafile schemas/plan-summary.v1.schema.json kenshou-core/test/golden/plan-summary.minimal.json
    check-jsonschema --schemafile schemas/suite.v1.schema.json suites/*.json
    check-jsonschema --schemafile schemas/run-spec-v1.schema.json kenshou-core/test/golden/run-spec.minimal.json kenshou-core/test/golden/run-spec.effective.json kenshou-core/test/golden/run-spec.external.json
    check-jsonschema --schemafile schemas/run-result-v1.schema.json kenshou-core/test/golden/run-result.passed.json kenshou-core/test/golden/run-result.known-defect.json
    check-jsonschema --schemafile schemas/artifact-manifest-v1.schema.json kenshou-core/test/golden/manifest.json
    check-jsonschema --schemafile schemas/comparison-policy-v1.schema.json policies/default.json policies/selftest.json
    check-jsonschema --schemafile schemas/overhead-policy-v1.schema.json policies/telemetry-overhead.json
    check-jsonschema --schemafile schemas/overhead-report-v1.schema.json kenshou-telemetry/test/golden/overhead-report.minimal.json
    check-jsonschema --schemafile schemas/health-notice-v1.schema.json kenshou-measure/test/fixtures/health-notice.json
    check-jsonschema --schemafile schemas/diagnosis.v1.schema.json kenshou-diagnose/test/golden/leak-diagnosis.json
    check-jsonschema --schemafile schemas/leak-policy.v1.schema.json policies/leak-default.json
    check-jsonschema --schemafile schemas/scenario-list-v1.schema.json kenshou-core/test/golden/scenario-list.json
    tmpdir=$(mktemp -d); trap 'rm -rf -- "$tmpdir"' EXIT; K=$(cabal list-bin kenshou); mkdir "$tmpdir/bundle"; KENSHOU_EVIDENCE_BUNDLE="$tmpdir/bundle" "$K" evidence check --json > "$tmpdir/evidence-check.json"; check-jsonschema --schemafile schemas/evidence-check-v1.schema.json "$tmpdir/evidence-check.json"
    tmpdir=$(mktemp -d); trap 'rm -rf -- "$tmpdir"' EXIT; K=$(cabal list-bin kenshou); mkdir "$tmpdir/bundle"; KENSHOU_EVIDENCE_BUNDLE="$tmpdir/bundle" "$K" history --scenario selftest/kernel/correctness/always-pass --json > "$tmpdir/evidence-history.json"; check-jsonschema --schemafile schemas/evidence-history-v1.schema.json "$tmpdir/evidence-history.json"
    tmpdir=$(mktemp -d); trap 'rm -rf -- "$tmpdir"' EXIT; K=$(cabal list-bin kenshou); "$K" attest invalid --project fixture --json > "$tmpdir/attest-result.json" || test "$?" = 2; check-jsonschema --schemafile schemas/attest-result-v1.schema.json "$tmpdir/attest-result.json"
    jq -c . kenshou-core/test/golden/worker-messages.jsonl | while IFS= read -r line; do printf '%s\n' "$line" | check-jsonschema --schemafile schemas/worker-message-v1.schema.json -; done
    tmpdir=$(mktemp -d); trap 'rm -rf -- "$tmpdir"' EXIT; K=$(cabal list-bin kenshou); "$K" list --json > "$tmpdir/scenario-list.json"; "$K" run selftest/kernel/correctness/always-pass --out "$tmpdir/runs" >/dev/null; rundir=$(find "$tmpdir/runs" -mindepth 1 -maxdepth 1 -type d | head -1); check-jsonschema --schemafile schemas/scenario-list-v1.schema.json "$tmpdir/scenario-list.json"; check-jsonschema --schemafile schemas/run-spec-v1.schema.json "$rundir/run-spec.json"; check-jsonschema --schemafile schemas/run-result-v1.schema.json "$rundir/run-result.json"; check-jsonschema --schemafile schemas/artifact-manifest-v1.schema.json "$rundir/manifest.json"
    tmpdir=$(mktemp -d); trap 'rm -rf -- "$tmpdir"' EXIT; K=$(cabal list-bin kenshou); "$K" run selftest/check/correctness/ledger-detects-loss-dup-reorder --set ledger.facts=1000 --out "$tmpdir" >/dev/null; rundir=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -1); check-jsonschema --schemafile schemas/kenshou.verdict.v1.schema.json "$rundir"/verdicts/*.json; jq '{"$schema": .["$schema"], "type": "array", "items": .}' schemas/kenshou.ledger-fact.v1.schema.json > "$tmpdir/ledger-array.schema.json"; jq -s 'map(select(.schema == "kenshou.ledger-fact/v1"))' "$rundir"/verdicts/ledger/*.jsonl > "$tmpdir/ledger-facts.json"; check-jsonschema --schemafile "$tmpdir/ledger-array.schema.json" "$tmpdir/ledger-facts.json"

[group('verification')]
selftest:
    tmpdir=$(mktemp -d); trap 'rm -rf -- "$tmpdir"' EXIT; K=$(cabal list-bin kenshou); "$K" run selftest/kernel/correctness/always-pass --out "$tmpdir"; "$K" run selftest/kernel/correctness/outcome --out "$tmpdir"; "$K" run selftest/kernel/correctness/known-defect --out "$tmpdir"; "$K" run selftest/kernel/correctness/postgres-roundtrip --dim pg.durability=fsync-off --out "$tmpdir"; "$K" run selftest/kernel/correctness/postgres-roundtrip --dim pg.durability=durable --out "$tmpdir"; "$K" run selftest/kernel/concurrency/worker-echo --out "$tmpdir"; set +e; "$K" run selftest/kernel/correctness/always-fail --out "$tmpdir"; fail=$?; "$K" run selftest/kernel/correctness/errors --out "$tmpdir"; errored=$?; set -e; test "$fail" = 1; test "$errored" = 4
    tmpdir=$(mktemp -d); trap 'rm -rf -- "$tmpdir"' EXIT; K=$(cabal list-bin kenshou); "$K" run selftest/check/correctness/ledger-detects-loss-dup-reorder --set ledger.facts=1000 --out "$tmpdir"; "$K" run selftest/check/concurrency/kill-and-restart-worker --set kill.count=2 --out "$tmpdir"; "$K" run selftest/check/concurrency/postgres-backend-kill --dim pg.durability=fsync-off --out "$tmpdir"; "$K" run selftest/check/concurrency/postgres-backend-kill --dim pg.durability=durable --out "$tmpdir"; "$K" run selftest/check/concurrency/proxy-partition --out "$tmpdir"; "$K" run selftest/check/correctness/model-replays-counterexample --set model.tests=20 --out "$tmpdir"

[group('haskell')]
haskell-build:
    cabal build all

[group('haskell')]
haskell-test:
    cabal test kenshou-core:tests
    cabal test kenshou-check:test:kenshou-check-test
    cabal test kenshou-measure:test:kenshou-measure-test
    cabal test kenshou-diagnose:test:kenshou-diagnose-test
    cabal test kenshou-telemetry:test:kenshou-telemetry-test
    cabal test kenshou-evidence:test:kenshou-evidence-test
    cabal test kenshou-remote:test:kenshou-remote-test
    cabal test kenshou-cli:test:kenshou-cli-test

[group('format')]
fmt:
    nix fmt

[group('format')]
fmt-check:
    nix fmt -- --fail-on-change

[group('cohort')]
cohort-show:
    cabal run -v0 kenshou -- cohort show

[group('cohort')]
cohort-check:
    check-jsonschema --schemafile schemas/kenshou.cohort.v1.schema.json cohort/*.json
    cabal run -v0 kenshou -- cohort check

[group('database')]
postgres-init:
    mkdir -p "{{pg_host}}" .dev
    if [ ! -d "{{pg_data}}" ]; then PGDATA="{{pg_data}}" initdb --auth=trust --no-locale --encoding=UTF8; fi

[group('database')]
postgres-start: postgres-init
    pg_ctl status -D "{{pg_data}}" >/dev/null || pg_ctl start -w -D "{{pg_data}}" -l "{{pg_log}}" -o "--unix_socket_directories='{{pg_host}}'" -o "-c listen_addresses=''"

[group('database')]
postgres-stop:
    pg_ctl stop -D "{{pg_data}}"

[group('database')]
create-database db=pg_database:
    PGHOST="{{pg_host}}" createdb "{{db}}" 2>/dev/null || PGHOST="{{pg_host}}" psql -d "{{db}}" -Atqc 'SELECT 1' >/dev/null
