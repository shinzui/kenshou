module Kenshou.Cli
  ( mainWith,
    runWithArgsWith,
    CliAssembly,
    Program (..),
    selfTestBundles,
    standardCommands,
    withCommand,
    RoundConfig (..),
    defaultRoundConfig,
    roundCommand,
    roundCommandWith,
    standardTopics,
    selfTestAssembly,
  )
where

import Kenshou.Cli.Command.Round (RoundConfig (..), defaultRoundConfig, roundCommand, roundCommandWith)
import Kenshou.Cli.Main (mainWith, runWithArgsWith)
import Kenshou.Cli.Registry (CliAssembly, Program (..), selfTestAssembly, selfTestBundles, standardCommands, standardTopics, withCommand)
