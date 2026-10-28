module Kenshou.Diagnose.SelfTest (bundle) where

import Kenshou.Core.Bundle (LayerBundle (..), mkBundle)
import Kenshou.Core.Id (selftestLayer)
import Kenshou.Diagnose.SelfTest.Leak (leakingWorkerScenario, stableWorkerScenario)
import Kenshou.Diagnose.SelfTest.Stall

bundle :: LayerBundle
bundle =
  mkBundle
    selftestLayer
    [ leakingWorkerScenario,
      stableWorkerScenario,
      deadlockedWorkersScenario,
      poolStarvedScenario,
      lockWaiterScenario,
      idleSpinnerScenario,
      healthyProgressScenario
    ]
    []
