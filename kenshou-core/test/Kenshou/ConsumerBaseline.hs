-- | The first consumer's component graph and performance contracts, which the
-- planning and performance specs still exercise through the fixtures in
-- ../fixtures/consumer-baseline/. The kernel no longer carries either; the plan
-- docs/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites.md
-- (M4) replaces this module with synthetic fixtures.
module Kenshou.ConsumerBaseline
  ( consumerGraph,
    consumerContracts,
  )
where

import Data.Text (Text)
import Kenshou.Core.Cohort (CohortDescriptor (..), ComponentId (..), ComponentSpec (..))
import Kenshou.Core.Knob (mkKnobName)
import Kenshou.Perf.Contracts (PerfContracts (..))
import Kenshou.Plan.Components (ComponentGraph, GraphError, loadGraphFile)

consumerGraph :: IO (Either GraphError ComponentGraph)
consumerGraph = loadGraphFile "../fixtures/consumer-baseline/kenshou-core/data/components.json"

consumerContracts :: PerfContracts
consumerContracts =
  PerfContracts
    { reviewedPhaseContracts = [("shibuya/core-ordering/benchmark/concurrency-sweep", 2), ("shibuya/pgmq-adapter/benchmark/end-to-end-throughput-latency", 1)],
      steadyCountKnob = either (const Nothing) Just (mkKnobName "shibuya.messages"),
      laneStanzas = \descriptor -> if isolated descriptor then ["package kenshou-cli", "  flags: -runtime-suites", "package kenshou-core", "  flags: -keiro-schema"] else [],
      lanePackages = \descriptor packages -> if isolated descriptor then filter (`notElem` ["kenshou-kafka", "kenshou-keiro", "kenshou-kiroku", "kenshou-pgmq", "kenshou-runtime"]) packages else packages
    }
  where
    isolated descriptor =
      let names = map (componentText . (.componentId)) descriptor.descriptorComponents
       in "shibuya" `elem` names && all (`elem` ["shibuya", "shibuya-pgmq-adapter", "pgmq-hs", "kiroku"]) names
    componentText :: ComponentId -> Text
    componentText (ComponentId name) = name
