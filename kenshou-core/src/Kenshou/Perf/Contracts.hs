-- | What a suite supplies to performance planning and preparation. The kernel's
-- validators are generic; which scenario revisions honour count-bound steady work,
-- which knob carries that count, and how an isolated cohort lane is built are
-- facts about the suite's scenarios and packages, so the executable passes them in
-- through 'Kenshou.Core.Cli.Program'.
module Kenshou.Perf.Contracts
  ( PerfContracts (..),
    noPerfContracts,
  )
where

import Data.Text (Text)
import Kenshou.Core.Cohort (CohortDescriptor)
import Kenshou.Core.Knob (KnobName)

data PerfContracts = PerfContracts
  { -- | Benchmark scenario identifiers and revisions whose phase contract has been
    -- reviewed: they implement count-bound steady work rather than timed phases.
    -- A profile naming any other scenario revision is rejected.
    reviewedPhaseContracts :: [(Text, Int)],
    -- | The knob whose effective value must equal a profile's steady count, when
    -- the suite has one.
    steadyCountKnob :: Maybe KnobName,
    -- | Extra Cabal project stanzas for a cohort lane, such as package flags that
    -- leave out parts of the suite the lane cannot build.
    laneStanzas :: CohortDescriptor -> [Text],
    -- | The harness packages, by directory name, that a cohort lane builds.
    lanePackages :: CohortDescriptor -> [String] -> [String]
  }

-- | No reviewed contracts: every performance profile is rejected, and cohort
-- lanes build every harness package without extra stanzas.
noPerfContracts :: PerfContracts
noPerfContracts =
  PerfContracts
    { reviewedPhaseContracts = [],
      steadyCountKnob = Nothing,
      laneStanzas = const [],
      lanePackages = const id
    }
