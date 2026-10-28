# Consumer baseline fixtures

Verbatim copies of files from `mori://shinzui/keiro-runtime-kenshou` at commit
`a1648293443ad88ff1695ed800ff44c99993574e`, laid out at the consumer's paths. Some imported
generic tests read these files from the consumer's checkout layout; they read them from
here instead. Nothing outside the test suites reads this directory.

```text
cohort/released.{json,project}           kenshou-core perf tests, kenshou-remote payload tests,
cohort/shibuya-current.{json,project}    and the kenshou-cli perf planning tests
policies/performance/catalog.v1.json     kenshou-core and kenshou-measure perf tests
policies/cell-routing.json               kenshou-remote route-rule test
docs/verification/                       kenshou-evidence attestation tests and the
                                         kenshou-cli history test (skeleton, self-test
                                         runs, and their attestations only; the run and
                                         attestation indexes are pruned to those entries)
```

This directory is a bridge, not a fixture set to extend. The plans that replace it are
`docs/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites.md`
(perf and cohort fixtures), `docs/plans/4-move-residual-layer-knowledge-out-of-the-toolkits-and-make-evidence-targets-configuration.md`
(the cell routing rule and the evidence bundle), and
`docs/plans/5-prove-the-harness-boundary-with-a-synthetic-layer-and-a-coupling-guard.md`,
which deletes the directory once nothing reads it.
