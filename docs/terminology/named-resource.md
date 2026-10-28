---
type: Term
title: named resource
description: A piece of infrastructure besides PostgreSQL that a scenario requires by name and that a registered provider acquires around each run.
generated: {by: 'process:claude-code', at: '2026-10-28T17:45:00Z'}
termId: TERM-33
status: current
tags: [environment]
aliases: [extra resource]
related: [TERM-1, TERM-3, TERM-32]
anchors:
  - {kind: file, resource: kenshou-core/src/Kenshou/Core/Resource.hs}
  - {kind: file, resource: kenshou-synthetic/src/Kenshou/Suite/Synthetic/Echo.hs}
  - {kind: doc, resource: docs/adr/0019-provision-named-resources-and-keep-legacy-documents-readable.md}
---

# named resource

A named resource is anything a scenario needs besides its PostgreSQL databases: a
message broker, an object store, a stub service. The scenario lists its
`ResourceName` in its environment requirements; a [layer bundle](layer-bundle.md)
registers a `ResourceProvider` that normalizes the [run specification](run-specification.md)'s
value, acquires the resource around a local run, and may bind it on a verification
cell. Workers receive the provisioned value in the `resources` block of their
initialization document, and the run result records the provider's fingerprint.
