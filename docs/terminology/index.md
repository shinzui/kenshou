---
okf_version: "0.2"
---

# Files

- [profile.dhall](profile.dhall)

# Term

- [attestation](attestation.md) - A separate verification record reporting whether an evidence claim is confirmed, refuted, or incomplete.
- [baseline](baseline.md) - A reference run or set of trials against which candidate behavior is assessed.
- [benchmark-grade run](benchmark-grade-run.md) - A run with complete and healthy measurement evidence suitable for an authoritative performance comparison.
- [cohort](cohort.md) - The resolved set of runtime component packages and sources tested by a Kenshou executable.
- [comparison key](comparison-key.md) - A digest of the workload and environment inputs that must match for a direct run comparison.
- [comparison policy](comparison-policy.md) - The versioned thresholds and evidence requirements used to judge paired performance trials.
- [component graph](component-graph.md) - The checked-in map of build and runtime dependencies used to select verification after a change.
- [diagnosis](diagnosis.md) - A recomputable explanation of a suspected leak or stall from saved samples and captures.
- [dimension](dimension.md) - A named verification axis whose supported values select a run's instrumentation or PostgreSQL mode.
- [disposition](disposition.md) - The evidence-based conclusion about one owner's defect for a resolved cohort.
- [evidence record](evidence-record.md) - An OKF account of a run or comparison whose claim is fixed and whose raw artifacts are digest-pinned.
- [fact ledger](fact-ledger.md) - An append-only record of scenario actions and observations consumed by independent correctness checks.
- [fault window](fault-window.md) - A recorded interval in which Kenshou deliberately disturbs a runtime or its environment.
- [invariant](invariant.md) - A stated property that Kenshou checks against observations from a scenario.
- [knob](knob.md) - A typed, scenario-specific input that changes a workload or diagnostic setting.
- [known defect](known-defect.md) - An owner-repository contract failure whose reference and expected failure labels are scoped to affected cohorts.
- [layer bundle](layer-bundle.md) - The unit a suite registers with the harness for one layer, carrying its scenarios, worker roles, and contributions such as migration sets, resource providers, oracles, and an evidence subject.
- [layer identifier](layer-identifier.md) - The open, validated name of a layer of the system a suite verifies, which is the first segment of every scenario identifier in that layer.
- [named resource](named-resource.md) - A piece of infrastructure besides PostgreSQL that a scenario requires by name and that a registered provider acquires around each run.
- [observation](observation.md) - A captured reading of a published evidence record or a sealed local run for fix verification.
- [oracle](oracle.md) - An independent source of expected state used to judge a scenario's observed behavior.
- [outcome](outcome.md) - The reported execution state of a run, distinct from whether its failure blocks a gate.
- [owner record](owner-record.md) - A bug report or improvement request, kept in the repository that owns a behavior, that a known defect or a consumer finding cites by its canonical concept URI.
- [owner snapshot](owner-snapshot.md) - A create-once directory holding the exact owner-record bytes, their digests, the citations, and the enrichment links from which an owner status can be reported again.
- [paired comparison](paired-comparison.md) - A controlled performance comparison of interleaved baseline and candidate run trials.
- [phase](phase.md) - A timed part of a run's workload lifecycle, named warm-up, steady, or drain.
- [round evaluation](round-evaluation.md) - A named capture of the candidate evidence used to report on a verification round.
- [round](round.md) - A frozen baseline, pair of cohort identities, and set of inputs for verification reruns.
- [run plan](run-plan.md) - A versioned schedule of selected runs with fixed specifications, reasons, and identities.
- [run specification](run-specification.md) - A versioned input document that selects a scenario and supplies the values and environment for one execution.
- [run](run.md) - One identified execution of a scenario whose inputs, outcome, and artifacts are saved together.
- [scenario](scenario.md) - A registered verification case with a stable identity, declared inputs and environment needs, and executable behavior.
- [scope reconciliation](scope-reconciliation.md) - Comparing each known defect's cohort scope with the version claims of the owner record it cites, and proposing reviewable corrections without editing source or owner records.
- [sealed run](sealed-run.md) - A completed run directory whose manifest fixes the files that belong to its evidence.
- [series key](series-key.md) - A digest of run compatibility inputs including the resolved cohort plan hash.
- [suite](suite.md) - A named planning policy that selects a useful set of scenario kinds, tiers, and matrix settings.
- [telemetry arm](telemetry-arm.md) - A selected tracing or metrics mode whose effect and measurement overhead Kenshou can compare.
- [tier](tier.md) - A scenario's declared execution cost class used to filter planned work.
- [verdict](verdict.md) - A saved judgment that a named check held, was violated, or could not be evaluated.
- [verification cell](verification-cell.md) - A leased and resettable machine environment for controlled remote verification runs.
