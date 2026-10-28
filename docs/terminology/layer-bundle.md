---
type: Term
title: layer bundle
description: The unit a suite registers with the harness for one layer, carrying its scenarios, worker roles, and contributions such as migration sets, resource providers, oracles, and an evidence subject.
generated: {by: 'process:claude-code', at: '2026-10-28T17:45:00Z'}
termId: TERM-32
status: current
tags: [registration]
discouraged: [layer suite]
related: [TERM-1, TERM-9, TERM-31, TERM-33]
anchors:
  - {kind: file, resource: kenshou-core/src/Kenshou/Core/Bundle.hs}
  - {kind: file, resource: kenshou-synthetic/src/Kenshou/Suite/Synthetic.hs}
  - {kind: doc, resource: docs/adr/0016-register-a-suite-as-layer-bundles-assembled-into-a-program.md}
---

# layer bundle

A layer bundle is a `Kenshou.Core.Bundle.LayerBundle`, built with `mkBundle` from a
[layer identifier](layer-identifier.md), the layer's [scenarios](scenario.md), and
its worker roles, and extended with contributions: migration sets, rules,
[named resources](named-resource.md), oracles, advisory-lock labels, a pool
methodology, routing rules, and an evidence subject. `mkRegistry` validates every
registered bundle together.

Say "layer bundle", not "layer suite": a [suite](suite.md) is a named run selection
such as `suites/smoke.json`, not the registration unit.
