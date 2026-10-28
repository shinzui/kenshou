# Consumer baseline fixtures

Verbatim copies of files from `mori://shinzui/keiro-runtime-kenshou` at commit
`a1648293443ad88ff1695ed800ff44c99993574e`, laid out at the consumer's paths. Some generic
tests exercise protocol documents that only a real consumer run produced, or read files
from the consumer's checkout layout; they read them from here. Nothing outside the test
suites reads this directory, and it is the only place outside
`kenshou-evidence/test/fixtures/consumer-records/` where consumer names may appear.

```text
kenshou-core/test/golden/perf-*.json     captured output of a real `kenshou perf prepare` and
                                         `perf run`: the prepared document, plan, request, and
                                         aggregate results read by the kenshou-core,
                                         kenshou-remote, and kenshou-cli perf tests
kenshou-core/data/components.json        the consumer's component graph, read by the
                                         kenshou-cli perf planning tests with the request above
perf-contracts.json                      the consumer's reviewed benchmark revisions and
                                         steady-count knob, as data, for validating the
                                         captured preparation (not a consumer file; derived
                                         from the contracts its kernel once hard-coded)
cohort/released.{json,project}           kenshou-remote payload tests and the kenshou-cli
cohort/shibuya-current.{json,project}    perf planning tests
policies/performance/catalog.v1.json     kenshou-measure metric admission and the kenshou-cli
                                         perf planning tests
policies/cell-routing.json               kenshou-remote route-rule test
docs/verification/                       kenshou-evidence attestation tests and the
                                         kenshou-cli history test (skeleton, self-test
                                         runs, and their attestations only; the run and
                                         attestation indexes are pruned to those entries)
```

The captured perf documents cannot be regenerated in this repository, because producing
them needs Nix payload builds, exact-revision Git sources, and an object store; they stay
here as protocol fixtures until a synthetic perf pipeline exists. The other entries are a
bridge that later plans replace: the cell routing rule and the evidence bundle by
`docs/plans/4-move-residual-layer-knowledge-out-of-the-toolkits-and-make-evidence-targets-configuration.md`.
The kenshou-core planning and perf specs use synthetic fixtures under
`kenshou-core/test/fixtures/{plan,perf}/` instead.
