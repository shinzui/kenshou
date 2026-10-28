module Kenshou.Cli
  ( mainWith,
    runWithArgsWith,
    CliAssembly,
    Program (..),
    selfTestBundles,
    standardCommands,
    standardTopics,
    selfTestAssembly,
  )
where

import Kenshou.Cli.Main (mainWith, runWithArgsWith)
import Kenshou.Cli.Registry (CliAssembly, Program (..), selfTestAssembly, selfTestBundles, standardCommands, standardTopics)
