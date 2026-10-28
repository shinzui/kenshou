-- | The synthetic reference suite: a layer named @synthetic@ that exercises every
-- extension point a consuming suite uses, built only on the generic packages. It is
-- both the proof that the harness boundary holds and the worked example of a suite.
module Kenshou.Suite.Synthetic
  ( syntheticLayer,
    syntheticBundle,
    syntheticProgram,
  )
where

import Kenshou.Cli (Program (..), selfTestAssembly)
import Kenshou.Core.Bundle (LayerBundle (..), mkBundle)
import Kenshou.Core.Id (LayerId, mkLayerId)
import Kenshou.Suite.Synthetic.Correctness (appendSurvivesKillRestart)
import Kenshou.Suite.Synthetic.Oracle (itemsOracle)
import Kenshou.Suite.Synthetic.Roles (readerRole, writerRole)
import Kenshou.Suite.Synthetic.Schema (syntheticMigrationSet)

syntheticLayer :: LayerId
syntheticLayer = either (error . show) id (mkLayerId "synthetic")

syntheticBundle :: LayerBundle
syntheticBundle =
  (mkBundle syntheticLayer [appendSurvivesKillRestart] [writerRole, readerRole])
    { migrations = [syntheticMigrationSet],
      oracles = [itemsOracle],
      evidenceSubject = Just "mori://shinzui/kenshou"
    }

-- | The @kenshou@ executable's program: the self-test assembly plus the synthetic
-- bundle.
syntheticProgram :: Program
syntheticProgram = selfTestAssembly {bundles = selfTestAssembly.bundles <> [syntheticBundle]}
