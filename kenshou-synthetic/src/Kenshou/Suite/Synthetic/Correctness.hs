-- | @synthetic/table/correctness/append-survives-kill-restart@: a writer process
-- appends items while it is killed and restarted, a reader process observes them,
-- and the run's ledger must show no loss, per-key order, duplicates only within the
-- crash windows, quiescence, and agreement with the table.
module Kenshou.Suite.Synthetic.Correctness (appendSurvivesKillRestart) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.STM (atomically)
import Control.Monad (forM_)
import Data.Aeson (object, (.=))
import Data.Int (Int64)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Kenshou.Check.Fact (FactKind (..), ProcId (..))
import Kenshou.Check.Invariant
import Kenshou.Check.Ledger (defaultLedgerConfig, record, recordDurable, sealLedger, withLedger)
import Kenshou.Check.Ledger.Read (discoverLedgers)
import Kenshou.Check.Oracle (OracleResult (..), reconcile, runOracle)
import Kenshou.Check.Process
import Kenshou.Check.Scenario
import Kenshou.Check.Verdict (InvariantClass (..))
import Kenshou.Core.Context (ArtifactDir (..), RunContext (..), artifactPath, requirePostgres)
import Kenshou.Core.Dimension
import Kenshou.Core.Env (PostgresRequirement (..), noEnvironment)
import Kenshou.Core.Env qualified as Env
import Kenshou.Core.Id (parseScenarioId, renderRunId)
import Kenshou.Core.Knob
import Kenshou.Core.Phase (zeroPhases)
import Kenshou.Core.Role (ControlMessage (..))
import Kenshou.Core.Scenario
import Kenshou.Suite.Synthetic.Knobs (intKnob, knob)
import Kenshou.Suite.Synthetic.Oracle (itemsQuery)
import Kenshou.Suite.Synthetic.Roles (Fact (..), decodeFacts)
import Kenshou.Suite.Synthetic.Schema (syntheticSchema)

appendSurvivesKillRestart :: Scenario
appendSurvivesKillRestart =
  Scenario
    { id = either (error . show) id (parseScenarioId "synthetic/table/correctness/append-survives-kill-restart"),
      revision = 1,
      summary = "Appends items through a writer that is killed and restarted, and checks a reader sees each exactly once.",
      tier = TierSmoke,
      placement = PlaceEither,
      knobs =
        [ intKnob "writer.count" "Items per key" 500 1 100000,
          intKnob "writer.keys" "Keys written in turn" 8 1 1000,
          intKnob "kill.count" "Times the writer is killed and restarted" 2 0 20
        ],
      dimensions = postgresDimensions (PgFsyncOff :| [PgDurable]) (Pg18 :| [Pg17]) noDimensions,
      phases = zeroPhases,
      requires = noEnvironment {Env.postgres = Just (PostgresRequirement [syntheticSchema] [] False)},
      knownDefect = Nothing,
      run = runAppend
    }

runAppend :: RunContext -> IO ScenarioReport
runAppend context = withCheck context \environment -> withSupervisor environment \supervisor -> do
  let count = knobInt context.knobs (knob "writer.count")
      keys = knobInt context.knobs (knob "writer.keys")
      kills = fromIntegral (knobInt context.knobs (knob "kill.count")) :: Int
      total = count * keys
  readerSpec <- roleProcess environment "synthetic/reader" 0 (object ["total" .= total])
  writerSpec <- roleProcess environment "synthetic/writer" 0 (object ["count" .= count, "keys" .= keys])
  reader <- start supervisor readerSpec
  firstWriter <- start supervisor writerSpec
  -- Kill the writer after it has written a share of its items, then restart it.
  writers <- killAndRestart supervisor (max 1 (total `div` fromIntegral (kills + 1))) kills firstWriter
  finished <- waitFor 120000 (atomically ((>= total) . (.count) <$> progress reader))
  _ <- traverse (\writer -> stopGracefully supervisor writer 2000) (lastOf writers)
  _ <- stopGracefully supervisor reader 2000
  writerFacts <- decodeFacts . concat <$> traverse readChildMessages writers
  readerFacts <- decodeFacts <$> readChildMessages reader
  forM_ writerFacts \fact -> case fact.kind of
    "intent" -> record environment.ledger Intent fact.key fact.seq fact.item mempty
    "produced" -> recordDurable environment.ledger Produced fact.key fact.seq fact.item mempty
    _ -> pure ()
  -- The reader's observations go in their own ledger scope, as a consumer process
  -- would write them, so per-key order is judged over the consumer's arrivals.
  withLedger (defaultLedgerConfig environment.ledgerDirectory (ProcId "synthetic-reader" 0 0) (renderRunId context.runId)) \readerLedger -> do
    forM_ readerFacts \fact -> do
      recordDurable readerLedger Observed fact.key fact.seq fact.item mempty
      record readerLedger Terminal fact.key fact.seq fact.item mempty
    sealLedger readerLedger
  sealLedger environment.ledger
  ledgerSet <- discoverLedgers environment.ledgerDirectory
  windows <- crashWindows supervisor
  verdictDirectory <- artifactPath context VerdictsDir ""
  durable <- runOracle verdictDirectory (requirePostgres context) itemsQuery >>= either (fail . show) pure
  verdicts <-
    runCheckers
      environment
      ledgerSet
      [ noLoss "no-loss" Contract readerScope,
        perKeyOrder "per-key-order" Contract readerScope,
        duplicatesWithin "duplicates-within-windows" Contract readerScope (DuplicateBudget (Just 0) Nothing) windows,
        eventualQuiescence "eventual-quiescence" Contract (Deadline 120000000),
        reconcile "ledger-versus-oracle" Contract durable.rows
      ]
  if finished && fromIntegral (length readerFacts) == total
    then finishWithVerdicts environment verdicts
    else pure (failedWith ["reader-incomplete"] "the reader did not observe every item before the deadline")
  where
    lastOf values = case reverse values of
      final : _ -> [final]
      [] -> []

readerScope :: Text
readerScope = "synthetic-reader/0"

start :: Supervisor -> ProcessSpec -> IO Child
start supervisor spec = do
  child <- spawn supervisor spec
  awaitReady child 10000
  sendCommand child CtlStart
  pure child

-- | Kill the writer each time it has written another @step@ items, restarting it,
-- and return every incarnation in order.
killAndRestart :: Supervisor -> Int64 -> Int -> Child -> IO [Child]
killAndRestart supervisor step remaining child
  | remaining <= 0 = pure [child]
  | otherwise = do
      _ <- waitFor 60000 (atomically ((>= step) . (.count) <$> progress child))
      killChild supervisor child
      replacement <- restartChild supervisor child
      awaitReady replacement 10000
      sendCommand replacement CtlStart
      (child :) <$> killAndRestart supervisor step (remaining - 1) replacement

-- | Poll a condition every 20 ms for at most the given milliseconds.
waitFor :: Int -> IO Bool -> IO Bool
waitFor millis condition = loop millis
  where
    loop left = do
      satisfied <- condition
      if satisfied || left <= 0 then pure satisfied else threadDelay 20000 >> loop (left - 20)
