-- | Measured appends to @synthetic.items@: a benchmark whose paired comparisons
-- exercise the measurement toolkit, and a soak whose runtime series feed the leak
-- diagnosis.
module Kenshou.Suite.Synthetic.Bench
  ( appendThroughput,
    steadyAppend,
  )
where

import Control.Exception (bracket)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word64)
import Hasql.Connection qualified as Connection
import Hasql.Connection.Settings qualified as Settings
import Hasql.Session qualified as Session
import Kenshou.Core.Context (RunContext (..), requirePostgres)
import Kenshou.Core.Dimension
import Kenshou.Core.Env (PostgresRequirement (..), noEnvironment)
import Kenshou.Core.Env qualified as Env
import Kenshou.Core.Env.Postgres (PostgresEnv (..))
import Kenshou.Core.Id (Kind (..), parseScenarioId)
import Kenshou.Core.Phase qualified as Core
import Kenshou.Core.Scenario
import Kenshou.Measure.Knobs
import Kenshou.Measure.Load
import Kenshou.Measure.Recorder
import Kenshou.Measure.Session
import Kenshou.Suite.Synthetic.Schema (syntheticSchema)
import Kenshou.Suite.Synthetic.Table (appendItem, countItems)

appendThroughput :: Scenario
appendThroughput =
  (appendScenario "synthetic/table/benchmark/append-throughput" "Measures single-row appends to the synthetic items table." Benchmark (Core.PhasePlan 2 10 1))
    { tier = TierStandard
    }

steadyAppend :: Scenario
steadyAppend =
  (appendScenario "synthetic/table/soak/steady-append" "Appends at a steady rate long enough for a leak diagnosis." Soak (Core.PhasePlan 5 30 0))
    { tier = TierSoak
    }

appendScenario :: Text -> Text -> Kind -> Core.PhasePlan -> Scenario
appendScenario identifier summary kind phases =
  Scenario
    { id = either (error . show) id (parseScenarioId identifier),
      revision = 1,
      summary,
      tier = TierSmoke,
      placement = PlaceEither,
      -- An open loop at a modest rate measures append latency without saturating
      -- the load driver, which the measurement health checks would flag.
      knobs = loadKnobs (defaultLoadDefaults {model = "open-constant", ratePerSecond = 200, executors = 8}) <> measureKnobs kind,
      dimensions = postgresDimensions (PgDurable :| []) (Pg18 :| [Pg17]) telemetryOff,
      phases,
      requires = noEnvironment {Env.postgres = Just (PostgresRequirement [syntheticSchema] [("shared_preload_libraries", "'pg_stat_statements'")] False)},
      knownDefect = Nothing,
      run = runAppendLoad
    }

runAppendLoad :: RunContext -> IO ScenarioReport
runAppendLoad context = case (loadModelFromKnobs context.knobs, measureConfigFromKnobs context (phasePlanFromCore context.phases)) of
  (Left message, _) -> pure (failedWith ["invalid-load-config"] message)
  (_, Left message) -> pure (failedWith ["invalid-measure-config"] message)
  (Right loadModel, Right config) -> do
    let environment = requirePostgres context
        workers = case loadModel of ClosedLoop closed -> closed.workers; OpenLoop open -> open.executors
        settings = Settings.connectionString environment.connectionString <> Settings.applicationName "synthetic-append"
    bracket (traverse (const (Connection.acquire settings)) [1 .. max 1 workers]) (mapM_ Connection.release . concatMap (either (const []) pure)) \acquired ->
      case sequence acquired of
        Left problem -> pure (infrastructureFailureBecause (Text.pack (show problem)))
        Right [] -> pure (infrastructureFailureBecause "no PostgreSQL connection")
        Right connections@(first : _) -> do
          let operation = Operation (OpName "append") (appendOne connections)
          (_, report) <- withMeasurement context config (\measurement -> runLoad measurement loadModel operation)
          counted <- Connection.use first (Session.statement () countItems)
          let successful = case report.recorder.operations of
                recorded : _ -> sum [successes | (successes, _, _) <- Map.elems recorded.phaseCounts]
                [] -> 0
              scenarioReport = case counted of
                Right rows | fromIntegral rows == successful -> passed
                _ -> failedWith ["row-count"] ("rows " <> Text.pack (show counted) <> ", recorded successes " <> Text.pack (show successful))
          pure scenarioReport {outcome = measuredOutcome report scenarioReport.outcome}

appendOne :: [Connection.Connection] -> Int -> Word64 -> IO OpResult
appendOne connections worker sequenceNumber = do
  let connection = connections !! (worker `mod` length connections)
      key = "load-" <> Text.pack (show worker)
      number = fromIntegral sequenceNumber
  result <- Connection.use connection (Session.statement (key, number, key <> "/" <> Text.pack (show number), "load") appendItem)
  pure case result of
    Right True -> OpOk 1
    _ -> OpFailed (ErrorCause "postgres")

telemetryOff :: DimensionSupport
telemetryOff =
  DimensionSupport
    (Supported (Support (TracingOff :| []) TracingOff))
    (Supported (Support (MetricsOff :| []) MetricsOff))
    NotApplicable
    NotApplicable
