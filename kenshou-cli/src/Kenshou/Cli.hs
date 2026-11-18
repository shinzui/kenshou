module Kenshou.Cli
  ( mainWith,
    runWithArgsWith,
    CliAssembly,
    Program (..),
    selfTestBundles,
    standardCommands,
    withCommand,
    standardTopics,
    selfTestAssembly,
  )
where

import Kenshou.Cli.Main (mainWith, runWithArgsWith)
import Kenshou.Cli.Registry (CliAssembly, Program (..), selfTestAssembly, selfTestBundles, standardCommands, standardTopics, withCommand)
