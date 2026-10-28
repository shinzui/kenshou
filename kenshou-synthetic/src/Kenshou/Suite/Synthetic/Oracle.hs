-- | The synthetic suite's SQL oracle, registered on its bundle so the correctness
-- scenario and attestation recompute the same durable rows.
module Kenshou.Suite.Synthetic.Oracle
  ( itemsOracle,
    itemsQuery,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Kenshou.Check.Oracle (ItemRef (..), OracleQuery, OracleSpec (..), fromSpec)
import Text.Read (readMaybe)

itemsOracle :: OracleSpec
itemsOracle = OracleSpec "synthetic-items" "select key || '|' || seq || '|' || item from synthetic.items order by key, seq"

-- | The registered oracle with its row decoder: one @key|seq|item@ line per row.
itemsQuery :: OracleQuery [ItemRef]
itemsQuery = fromSpec itemsOracle (traverse row . filter (not . Text.null) . Text.lines)
  where
    row :: Text -> Either Text ItemRef
    row line = case Text.splitOn "|" line of
      [key, sequence, item] | Just number <- readMaybe (Text.unpack sequence) -> Right (ItemRef key number item)
      _ -> Left ("unreadable oracle row: " <> line)
