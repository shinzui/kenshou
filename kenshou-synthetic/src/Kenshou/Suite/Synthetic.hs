{-# LANGUAGE TemplateHaskell #-}

-- | The synthetic reference suite: a layer named @synthetic@ that exercises every
-- extension point a consuming suite uses, built only on the generic packages. It is
-- both the proof that the harness boundary holds and the worked example of a suite.
module Kenshou.Suite.Synthetic
  ( syntheticLayer,
    syntheticBundle,
    syntheticProgram,
    syntheticGraphBytes,
  )
where

import Data.ByteString (ByteString)
import Data.FileEmbed (embedFile)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text qualified as Text
import Kenshou.Cli (Program (..), selfTestAssembly)
import Kenshou.Core.Bundle (LayerBundle (..), mkBundle, requirePgVersionsFor)
import Kenshou.Core.Contribution (PoolMethodology (..), RoutingRule (..), RuleCondition (..))
import Kenshou.Core.Dimension (PgVersion (..))
import Kenshou.Core.Id (LayerId, mkLayerId)
import Kenshou.Suite.Synthetic.Bench (appendThroughput, steadyAppend)
import Kenshou.Suite.Synthetic.Concurrency (competingWriters, contenderRole, leaseLabel)
import Kenshou.Suite.Synthetic.Correctness (appendSurvivesKillRestart)
import Kenshou.Suite.Synthetic.Echo (echoClientRole, echoProvider, resourceRoundtrip)
import Kenshou.Suite.Synthetic.Oracle (itemsOracle)
import Kenshou.Suite.Synthetic.Roles (readerRole, writerRole)
import Kenshou.Suite.Synthetic.Schema (syntheticMigrationSet, syntheticSchema)

syntheticLayer :: LayerId
syntheticLayer = either (error . show) id (mkLayerId "synthetic")

syntheticBundle :: LayerBundle
syntheticBundle =
  (mkBundle syntheticLayer [appendSurvivesKillRestart, competingWriters, appendThroughput, steadyAppend, resourceRoundtrip] [writerRole, readerRole, contenderRole, echoClientRole])
    { migrations = [syntheticMigrationSet],
      rules = [requirePgVersionsFor syntheticSchema (Pg18 :| [Pg17])],
      resources = [echoProvider],
      oracles = [itemsOracle],
      advisoryLabels = [leaseLabel ("lease-" <> Text.pack (show key)) | key <- [0 .. 9 :: Int]],
      methodology = Just (PoolMethodology 8 (4, 16)),
      evidenceSubject = Just "mori://shinzui/kenshou",
      -- An example rule: a run that asks for unlogged item tables needs a cell whose
      -- PostgreSQL allows them.
      routingRules = [RoutingRule (KnobEquals "writer.storage" "unlogged") "postgres.unlogged-tables" "Unlogged item tables need a cell PostgreSQL that allows them."]
    }

-- | The @kenshou@ executable's program: the self-test assembly plus the synthetic
-- bundle, with a component graph that also covers the synthetic layer.
syntheticProgram :: Program
syntheticProgram = selfTestAssembly {bundles = selfTestAssembly.bundles <> [syntheticBundle], componentGraph = syntheticGraphBytes}

-- | The self-test component graph plus the synthetic suite's components.
syntheticGraphBytes :: ByteString
syntheticGraphBytes = $(embedFile "data/components.json")
