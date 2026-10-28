module Kenshou.Measure.Methodology
  ( PoolMethodology (..),
    poolMethodologyFor,
    minimumTrials,
    defaultTrials,
  )
where

import Kenshou.Core.Bundle (LayerBundle (..), Registry, lookupBundle)
import Kenshou.Core.Contribution (PoolMethodology (..))
import Kenshou.Core.Id (LayerId)

-- | The connection-pool methodology a layer's registered bundle contributes.
poolMethodologyFor :: Registry -> LayerId -> Maybe PoolMethodology
poolMethodologyFor registry layer = lookupBundle registry layer >>= (.methodology)

minimumTrials, defaultTrials :: Int
minimumTrials = 3
defaultTrials = 5
