module Kenshou.Measure.Selftest (bundle) where

import Kenshou.Core.Bundle (LayerBundle (..), mkBundle)
import Kenshou.Core.Id (selftestLayer)
import Kenshou.Measure.Selftest.PgInsert (pgInsertScenario)
import Kenshou.Measure.Selftest.RegressionInjected (regressionInjectedScenario)
import Kenshou.Measure.Selftest.SleepService (sleepServiceScenario)

bundle :: LayerBundle
bundle = mkBundle selftestLayer [sleepServiceScenario, pgInsertScenario, regressionInjectedScenario] []
