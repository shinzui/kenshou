-- | Worker roles of the synthetic suite. Each runs in its own process, receives a
-- @kenshou.worker-init/v1@ document, and reports facts as JSON objects with a
-- @kind@, @key@, @seq@, and @item@ that the scenario turns into ledger facts.
module Kenshou.Suite.Synthetic.Roles
  ( writerRole,
    readerRole,
    Fact (..),
    decodeFacts,
    roleName,
    awaitStart,
    awaitStop,
    intArg,
  )
where

import Control.Concurrent (threadDelay)
import Control.Monad (forM_, unless, when)
import Data.Aeson (FromJSON (..), Value (..), object, withObject, (.:), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (parseMaybe)
import Data.Int (Int64)
import Data.Maybe (mapMaybe)
import Data.Scientific (toBoundedInteger)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (getCurrentTime)
import Kenshou.Core.Role
import Kenshou.Suite.Synthetic.Table

-- | A fact a worker reports.
data Fact = Fact {kind :: !Text, key :: !Text, seq :: !Int64, item :: !Text}
  deriving stock (Eq, Show)

instance FromJSON Fact where
  parseJSON = withObject "synthetic fact" \value -> Fact <$> value .: "kind" <*> value .: "key" <*> value .: "seq" <*> value .: "item"

factValue :: Text -> Row -> Value
factValue kind row = object ["kind" .= kind, "key" .= row.key, "seq" .= row.seq, "item" .= row.item]

-- | The facts in a worker's messages.
decodeFacts :: [WorkerMessage] -> [Fact]
decodeFacts messages = mapMaybe (parseMaybe parseJSON) [value | WrkFacts values <- messages, value <- values]

-- | Appends @count@ items to each of @keys@ keys, one transaction per item, in
-- sequence-major order. It reports an @intent@ fact before each insert and a
-- @produced@ fact after the insert commits, and after a restart resumes from the
-- highest sequence already committed for each key.
writerRole :: WorkerRole
writerRole = WorkerRole (roleName "synthetic/writer") "Appends items to synthetic.items, resuming after a restart." \context -> do
  connection <- requireConnection context
  let count = intArg context "count"
      keys = [keyName number | number <- [0 .. intArg context "keys" - 1]]
      writer = context.init.instanceName
  withConnection connection ("synthetic-writer-" <> writer) \database -> do
    context.send WrkReady
    started <- awaitStart context
    when started do
      resumed <- traverse (\key -> (key,) <$> run database key highestSeq) keys
      let pending = [Row key sequence (key <> "/" <> Text.pack (show sequence)) | sequence <- [1 .. count], (key, written) <- resumed, sequence > written]
      forM_ (zip [1 :: Int64 ..] pending) \(number, row) -> do
        context.send (WrkFacts [factValue "intent" row])
        inserted <- run database (row.key, row.seq, row.item, writer) appendItem
        when inserted (context.send (WrkFacts [factValue "produced" row]))
        now <- getCurrentTime
        context.send (WrkProgress number now)
      context.send (WrkCustom "written" (object ["items" .= length pending]))
      awaitStop context

-- | Polls @synthetic.items@ and reports an @observed@ fact for every row it has not
-- reported before, until it has seen @total@ rows.
readerRole :: WorkerRole
readerRole = WorkerRole (roleName "synthetic/reader") "Observes every row of synthetic.items exactly once." \context -> do
  connection <- requireConnection context
  let total = intArg context "total"
  withConnection connection "synthetic-reader" \database -> do
    context.send WrkReady
    started <- awaitStart context
    when started do
      let loop seen = do
            rows <- run database () allRows
            let fresh = filter (`Set.notMember` seen) rows
                seen' = foldr Set.insert seen fresh
            unless (null fresh) (context.send (WrkFacts (fmap (factValue "observed") fresh)))
            now <- getCurrentTime
            context.send (WrkProgress (fromIntegral (Set.size seen')) now)
            if fromIntegral (Set.size seen') >= total then pure () else threadDelay 20000 >> loop seen'
      loop Set.empty
      awaitStop context

requireConnection :: RoleContext -> IO Text
requireConnection context = maybe (fail "the synthetic roles require PostgreSQL") (pure . (.connectionString)) context.init.postgres

awaitStart :: RoleContext -> IO Bool
awaitStart context =
  context.receive >>= \case
    Just CtlStart -> pure True
    Just (CtlStop _) -> pure False
    Nothing -> pure False
    Just _ -> awaitStart context

awaitStop :: RoleContext -> IO ()
awaitStop context =
  context.receive >>= \case
    Just (CtlStop _) -> pure ()
    Nothing -> pure ()
    Just _ -> awaitStop context

intArg :: RoleContext -> Text -> Int64
intArg context name = case context.init.args of
  Object fields | Just (Number value) <- KeyMap.lookup (Key.fromText name) fields, Just number <- toBoundedInteger value -> number
  _ -> error ("synthetic worker argument " <> Text.unpack name <> " is missing")

keyName :: Int64 -> Text
keyName number = "key-" <> Text.pack (show number)

roleName :: Text -> RoleName
roleName = either (error . Text.unpack) id . mkRoleName
