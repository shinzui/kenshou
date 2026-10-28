-- | Statements against the synthetic suite's tables, shared by its workers and
-- scenarios.
module Kenshou.Suite.Synthetic.Table
  ( Row (..),
    withConnection,
    appendItem,
    highestSeq,
    allRows,
    countItems,
    run,
  )
where

import Control.Exception (bracket)
import Data.Functor.Contravariant ((>$<))
import Data.Int (Int64)
import Data.Text (Text)
import Hasql.Connection qualified as Connection
import Hasql.Connection.Settings qualified as Settings
import Hasql.Decoders qualified as Decoders
import Hasql.Encoders qualified as Encoders
import Hasql.Session qualified as Session
import Hasql.Statement qualified as Statement

-- | One row of @synthetic.items@.
data Row = Row {key :: !Text, seq :: !Int64, item :: !Text}
  deriving stock (Eq, Ord, Show)

-- | Open one connection with an application name, so a stall capture or a backend
-- fault can select it.
withConnection :: Text -> Text -> (Connection.Connection -> IO a) -> IO a
withConnection connectionString application action =
  bracket (Connection.acquire settings >>= either (fail . show) pure) Connection.release action
  where
    settings = Settings.connectionString connectionString <> Settings.applicationName application

-- | Run one statement, failing loudly on a database error.
run :: Connection.Connection -> params -> Statement.Statement params result -> IO result
run connection params statement = Connection.use connection (Session.statement params statement) >>= either (fail . show) pure

-- | Insert an item; 'False' when the row already exists.
appendItem :: Statement.Statement (Text, Int64, Text, Text) Bool
appendItem =
  Statement.unpreparable
    "insert into synthetic.items (key, seq, item, writer) values ($1, $2, $3, $4) on conflict do nothing"
    ( ((\(key, _, _, _) -> key) >$< Encoders.param (Encoders.nonNullable Encoders.text))
        <> ((\(_, sequence, _, _) -> sequence) >$< Encoders.param (Encoders.nonNullable Encoders.int8))
        <> ((\(_, _, item, _) -> item) >$< Encoders.param (Encoders.nonNullable Encoders.text))
        <> ((\(_, _, _, writer) -> writer) >$< Encoders.param (Encoders.nonNullable Encoders.text))
    )
    ((> 0) <$> Decoders.rowsAffected)

-- | The highest sequence number already written for a key, or 0.
highestSeq :: Statement.Statement Text Int64
highestSeq =
  Statement.unpreparable
    "select coalesce(max(seq), 0)::bigint from synthetic.items where key = $1"
    (Encoders.param (Encoders.nonNullable Encoders.text))
    (Decoders.singleRow (Decoders.column (Decoders.nonNullable Decoders.int8)))

-- | Every row, in key and sequence order.
allRows :: Statement.Statement () [Row]
allRows =
  Statement.unpreparable
    "select key, seq, item from synthetic.items order by key, seq"
    Encoders.noParams
    (Decoders.rowList (Row <$> Decoders.column (Decoders.nonNullable Decoders.text) <*> Decoders.column (Decoders.nonNullable Decoders.int8) <*> Decoders.column (Decoders.nonNullable Decoders.text)))

countItems :: Statement.Statement () Int64
countItems = Statement.unpreparable "select count(*)::bigint from synthetic.items" Encoders.noParams (Decoders.singleRow (Decoders.column (Decoders.nonNullable Decoders.int8)))
