module Kenshou.Cli.Registry
  ( CliAssembly,
    Program (..),
    selfTestBundles,
    standardCommands,
    standardTopics,
    selfTestAssembly,
  )
where

import Kenshou.Check.Selftest qualified as CheckSelftest
import Kenshou.Cli.Attest (measurementRecomputer, pairedComparisonRecomputer, runOutcomeRecomputer)
import Kenshou.Cli.Command.Cell (cellCommand)
import Kenshou.Cli.Command.Cohort (cohortCommand)
import Kenshou.Cli.Command.Execute (executeCommand)
import Kenshou.Cli.Command.List (listCommand)
import Kenshou.Cli.Command.Overhead (overheadCommand)
import Kenshou.Cli.Command.Perf (perfCommand)
import Kenshou.Cli.Command.Plan (planCommand)
import Kenshou.Cli.Command.Run (runCommand)
import Kenshou.Cli.Command.Worker (workerCommand)
import Kenshou.Cli.Completions (completionsCommand)
import Kenshou.Cli.Diagnose qualified as Diagnose
import Kenshou.Cli.Help qualified as Help
import Kenshou.Core.Bundle (LayerBundle)
import Kenshou.Core.Cli (CliCommand, HelpTopic, Program (..), defaultProgram)
import Kenshou.Core.Selftest qualified as Selftest
import Kenshou.Diagnose.SelfTest qualified as DiagnoseSelftest
import Kenshou.Evidence.Attest (Recomputer)
import Kenshou.Evidence.Cli (attestCommandWith, evidenceCommand, recordCommand)
import Kenshou.Evidence.HistoryCli (historyCommand)
import Kenshou.Measure.Cli qualified as Measure
import Kenshou.Measure.Selftest qualified as MeasureSelftest
import Kenshou.Remote.Selftest qualified as RemoteSelftest
import Kenshou.Telemetry.SelfTest qualified as TelemetrySelftest

-- | Everything an executable registers: its name and header, the layer bundles
-- whose scenarios and roles it runs, the operator commands it exposes, the help
-- topics, its component graph, and its performance contracts.
-- Extension contract: a suite adds its bundles to 'bundles', and its own
-- recomputers through 'standardCommands', without changing this library.
type CliAssembly = Program

-- | The self-test bundles the kernel and toolkits define for themselves.
selfTestBundles :: [LayerBundle]
selfTestBundles = [Selftest.bundle, MeasureSelftest.bundle, CheckSelftest.bundle, DiagnoseSelftest.bundle, TelemetrySelftest.selfTestBundle, RemoteSelftest.bundle]

-- | The generic operator commands, with @attest@ using the given recomputers.
standardCommands :: [Recomputer] -> [CliCommand]
standardCommands recomputers = [listCommand, planCommand, Help.helpCommand, runCommand, executeCommand, cellCommand, perfCommand, overheadCommand, Measure.summarizeCommand, Measure.compareCommand, Diagnose.diagnoseCommand, historyCommand, recordCommand, attestCommandWith recomputers, evidenceCommand, workerCommand, cohortCommand, completionsCommand]

standardTopics :: [HelpTopic]
standardTopics = Help.topics

-- | The self-test bundles with the standard commands and the generic recomputers.
selfTestAssembly :: CliAssembly
selfTestAssembly =
  defaultProgram
    { bundles = selfTestBundles,
      commands = standardCommands [runOutcomeRecomputer, measurementRecomputer, pairedComparisonRecomputer],
      topics = standardTopics
    }
