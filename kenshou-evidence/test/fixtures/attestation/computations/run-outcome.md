---
type: Attested Computation
title: Run outcome
description: Algorithm metadata for run outcome attestation.
status: stable
runtime: kenshou
parameters:
  - name: runDirectory
    type: path
    required: true
executor:
  resource: /references/executors/kenshou-run.sh
  receipt: [run-spec.json, run-result.json, manifest.json]
attester:
  resource: /references/attesters/kenshou-attest.sh
generated:
  by: process:kenshou-test
  at: 2026-09-26T19:50:17Z
algorithm: run-outcome
algorithmVersion: 1
appliesTo: [correctness, concurrency, soak, benchmark]
computationId: VC-1
implementation: Kenshou.Core.Run
inputs: [run-spec, run-result, verdicts, diagnosis, logs]
produces: outcome
---

# Computation

```text
Read the sealed run outcome and failure labels.
```
