---
type: Term
title: oracle
description: An independent source of expected state used to judge a scenario's observed behavior.
generated: {by: 'process:claude-code', at: '2026-10-28T17:30:00Z'}
termId: TERM-16
status: current
tags: [correctness]
related: [TERM-14, TERM-15, TERM-17]
anchors:
  - {kind: file, resource: kenshou-check/src/Kenshou/Check/Oracle.hs}
  - {kind: doc, resource: kenshou-check/README.md}
---

# oracle

An oracle checks what should have happened using evidence outside the feature
being tested. Kenshou's SQL oracles, registered on a suite's layer bundle, reconcile a
[fact ledger](fact-ledger.md) with the system's durable tables without linking
the system's libraries into the checker. That separation helps detect a runtime and its
own report disagreeing about the same work.
