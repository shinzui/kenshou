module Kenshou.Cli
  ( mainWith,
    runWithArgsWith,
    CliAssembly (..),
    selfTestBundles,
    standardCommands,
    standardTopics,
    selfTestAssembly,
  )
where

import Kenshou.Cli.Main (mainWith, runWithArgsWith)
import Kenshou.Cli.Registry (CliAssembly (..), selfTestAssembly, selfTestBundles, standardCommands, standardTopics)
