-- | @synthetic/table/concurrency/competing-writers-hold-disjoint-leases@: contender
-- processes repeatedly take a lease on a key under a transaction-scoped advisory
-- lock, append one item while they hold it, and release it. Their facts, ordered by
-- the database clock, must show that no owner acted on a key another owner held.
module Kenshou.Suite.Synthetic.Concurrency
  ( contenderRole,
    competingWriters,
    leaseLabel,
  )
where

import Control.Concurrent (threadDelay)
import Control.Concurrent.STM (atomically)
import Control.Monad (forM, forM_, when)
import Data.Aeson (FromJSON (..), object, withObject, (.:), (.=))
import Data.Aeson.Types (parseMaybe)
import Data.Functor.Contravariant ((>$<))
import Data.Int (Int64)
import Data.List (sortOn)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Hasql.Decoders qualified as Decoders
import Hasql.Encoders qualified as Encoders
import Hasql.Statement qualified as Statement
import Kenshou.Check.Fact (FactKind (..), ProcId (..))
import Kenshou.Check.Invariant
import Kenshou.Check.Ledger (LedgerConfig, LedgerWriter, defaultLedgerConfig, record, sealLedger, withLedger)
import Kenshou.Check.Ledger.Read (discoverLedgers)
import Kenshou.Check.Process
import Kenshou.Check.Scenario
import Kenshou.Check.Verdict (InvariantClass (..))
import Kenshou.Core.Context (RunContext (..))
import Kenshou.Core.Contribution (AdvisoryKeySpec (..), AdvisoryLabel (..))
import Kenshou.Core.Dimension
import Kenshou.Core.Env (PostgresRequirement (..), noEnvironment)
import Kenshou.Core.Env qualified as Env
import Kenshou.Core.Id (parseScenarioId, renderRunId)
import Kenshou.Core.Knob
import Kenshou.Core.Phase (zeroPhases)
import Kenshou.Core.Role
import Kenshou.Core.Scenario
import Kenshou.Suite.Synthetic.Knobs (intKnob, knob)
import Kenshou.Suite.Synthetic.Roles (awaitStart, awaitStop, intArg, roleName)
import Kenshou.Suite.Synthetic.Schema (syntheticSchema)
import Kenshou.Suite.Synthetic.Table (run, withConnection)

-- | A lease step a contender reports, at a database clock time in microseconds.
data Step = Step {kind :: !Text, key :: !Text, at :: !Int64}

instance FromJSON Step where
  parseJSON = withObject "lease step" \value -> Step <$> value .: "kind" <*> value .: "key" <*> value .: "at"

-- | The label a stall capture gives the advisory lock a contender takes on a key.
leaseLabel :: Text -> AdvisoryLabel
leaseLabel key = AdvisoryLabel ("synthetic lease " <> key) (HashText ("synthetic/lease/" <> key))

-- | Takes the lease on each of @keys@ keys in turn, @iterations@ times, appending one
-- item under each lease; every step reports the database clock time.
contenderRole :: WorkerRole
contenderRole = WorkerRole (roleName "synthetic/contender") "Takes leases on keys and appends an item while holding each." \context -> do
  connection <- maybe (fail "the contender requires PostgreSQL") (pure . (.connectionString)) context.init.postgres
  let iterations = intArg context "iterations"
      keys = intArg context "keys"
      owner = context.init.instanceName
      step kind key at = object ["kind" .= (kind :: Text), "key" .= key, "at" .= at]
  withConnection connection ("synthetic-contender-" <> owner) \database -> do
    context.send WrkReady
    started <- awaitStart context
    when started do
      forM_ [1 .. iterations] \iteration -> do
        let key = "lease-" <> Text.pack (show (iteration `mod` keys))
        run database () (unit "begin")
        run database key takeLock
        acquiredAt <- run database (key, owner) acquireLease
        actedAt <- run database key appendUnderLease
        releasedAt <- run database (key, owner) releaseLease
        run database () (unit "commit")
        context.send (WrkFacts [step "acquired" key acquiredAt, step "acted" key actedAt, step "released" key releasedAt])
        now <- getCurrentTime
        context.send (WrkProgress iteration now)
      awaitStop context

competingWriters :: Scenario
competingWriters =
  Scenario
    { id = either (error . show) id (parseScenarioId "synthetic/table/concurrency/competing-writers-hold-disjoint-leases"),
      revision = 1,
      summary = "Runs contending writers that take per-key leases and checks no owner acts on another's lease.",
      tier = TierSmoke,
      placement = PlaceEither,
      knobs =
        [ intKnob "contention.contenders" "Contending writer processes" 4 2 32,
          intKnob "contender.iterations" "Leases each contender takes" 100 1 100000,
          intKnob "lease.keys" "Keys the contenders share" 3 1 100
        ],
      dimensions = postgresDimensions (PgFsyncOff :| [PgDurable]) (Pg18 :| [Pg17]) noDimensions,
      phases = zeroPhases,
      requires = noEnvironment {Env.postgres = Just (PostgresRequirement [syntheticSchema] [] False)},
      knownDefect = Nothing,
      run = runContention
    }

runContention :: RunContext -> IO ScenarioReport
runContention context = withCheck context \environment -> withSupervisor environment \supervisor -> do
  let contenders = fromIntegral (knobInt context.knobs (knob "contention.contenders")) :: Int
      iterations = knobInt context.knobs (knob "contender.iterations")
      keys = knobInt context.knobs (knob "lease.keys")
  children <- forM [0 .. contenders - 1] \index -> do
    spec <- roleProcess environment "synthetic/contender" index (object ["iterations" .= iterations, "keys" .= keys])
    child <- spawn supervisor spec
    awaitReady child 10000
    pure child
  forM_ children \child -> sendCommand child CtlStart
  finished <- and <$> traverse (\child -> waitFor 60000 (atomically ((>= iterations) . (.count) <$> progress child))) children
  forM_ children \child -> stopGracefully supervisor child 2000
  steps <- forM (zip [0 ..] children) \(index, child) -> do
    messages <- readChildMessages child
    pure [(index, step) | WrkFacts values <- messages, Just step <- fmap (parseMaybe parseJSON) values :: [Maybe Step]]
  -- Each contender records its own steps in its own ledger scope, in the order the
  -- database clock put them, so wall-clock order across owners is the real order.
  withLedgers [defaultLedgerConfig environment.ledgerDirectory (ProcId "synthetic-contender" index 0) (renderRunId context.runId) | index <- [0 .. contenders - 1]] \writers -> do
    forM_ (sortOn ((.at) . snd) (concat steps)) \(index, step) ->
      record (writers !! index) (stepKind step.kind) step.key step.at step.key mempty
    mapM_ sealLedger writers
  sealLedger environment.ledger
  ledgerSet <- discoverLedgers environment.ledgerDirectory
  verdicts <- runCheckers environment ledgerSet [disjointOwnership "disjoint-ownership" Contract]
  if finished && length (concat steps) == contenders * fromIntegral iterations * 3
    then finishWithVerdicts environment verdicts
    else pure (failedWith ["contenders-incomplete"] "not every contender finished its leases")
  where
    stepKind :: Text -> FactKind
    stepKind = \case
      "acquired" -> Acquired
      "acted" -> Acted
      _ -> Released

withLedgers :: [LedgerConfig] -> ([LedgerWriter] -> IO a) -> IO a
withLedgers configs action = go configs []
  where
    go [] opened = action (reverse opened)
    go (config : rest) opened = withLedger config \writer -> go rest (writer : opened)

waitFor :: Int -> IO Bool -> IO Bool
waitFor millis condition = loop millis
  where
    loop left = do
      satisfied <- condition
      if satisfied || left <= 0 then pure satisfied else threadDelay 20000 >> loop (left - 20)

unit :: Text -> Statement.Statement () ()
unit sql = Statement.unpreparable sql Encoders.noParams Decoders.noResult

clockMicros :: Decoders.Result Int64
clockMicros = Decoders.singleRow (Decoders.column (Decoders.nonNullable Decoders.int8))

takeLock :: Statement.Statement Text ()
takeLock = Statement.unpreparable "select pg_advisory_xact_lock(hashtext('synthetic/lease/' || $1))" (Encoders.param (Encoders.nonNullable Encoders.text)) Decoders.noResult

acquireLease :: Statement.Statement (Text, Text) Int64
acquireLease =
  Statement.unpreparable
    "insert into synthetic.leases (key, owner, acquired_at, expires_at) values ($1, $2, clock_timestamp(), clock_timestamp() + interval '5 seconds') on conflict (key) do update set owner = excluded.owner, acquired_at = excluded.acquired_at, expires_at = excluded.expires_at returning (extract(epoch from clock_timestamp()) * 1000000)::bigint"
    pairParams
    clockMicros

appendUnderLease :: Statement.Statement Text Int64
appendUnderLease =
  Statement.unpreparable
    "insert into synthetic.items (key, seq, item, writer) select $1, coalesce(max(seq), 0) + 1, $1 || '/' || (coalesce(max(seq), 0) + 1), 'contender' from synthetic.items where key = $1 returning (extract(epoch from clock_timestamp()) * 1000000)::bigint"
    (Encoders.param (Encoders.nonNullable Encoders.text))
    clockMicros

releaseLease :: Statement.Statement (Text, Text) Int64
releaseLease =
  Statement.unpreparable
    "with released as (delete from synthetic.leases where key = $1 and owner = $2) select (extract(epoch from clock_timestamp()) * 1000000)::bigint"
    pairParams
    clockMicros

pairParams :: Encoders.Params (Text, Text)
pairParams = (fst >$< Encoders.param (Encoders.nonNullable Encoders.text)) <> (snd >$< Encoders.param (Encoders.nonNullable Encoders.text))
