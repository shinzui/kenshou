-- | The one place that maps the cell protocol's dedicated broker fields onto the
-- named resource that documents once carried as a top-level field. The cell agent
-- in mori://shinzui/load-testing-infra still describes a broker with
-- @CellEnvironment.broker@ and resets it with @reset.broker@; this module binds and
-- requests it through the generic resource path. Delete it when load-testing-infra
-- publishes @resources@ in the cell environment and accepts @reset.resources@ in
-- the submission.
module Kenshou.Remote.Cell.Legacy
  ( brokerAsResource,
    legacyBrokerReset,
    legacyBrokerAvailable,
  )
where

import Data.Aeson (Value, object, (.=))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Kenshou.Core.Resource.Types (legacyKafkaName)
import Kenshou.Remote.Cell.Docs (BrokerReset (..), CellBroker (..), CellDescriptor (..), CellImages (..), ResetBlock (..))

-- | The resource value a cell broker binds to, exactly as the cell client has
-- always passed it to scenarios.
brokerAsResource :: CellBroker -> Either Text Value
brokerAsResource broker
  | null addresses = Left "cell broker has no bootstrap servers"
  | otherwise = Right (object ["backend" .= ("external" :: Text), "brokers" .= addresses, "lanes" .= (0 :: Int)])
  where
    addresses = filter (not . Text.null) (fmap Text.strip (Text.splitOn "," broker.bootstrapServers))

-- | Move a reset of that resource into the dedicated broker wipe. The entry leaves
-- @reset.resources@, because the cell agent decodes submissions strictly and would
-- reject the extension; the submission keeps the exact shape it always had.
legacyBrokerReset :: ResetBlock -> ResetBlock
legacyBrokerReset reset
  | Map.member legacyKafkaName reset.resources = reset {broker = Just (BrokerReset True), resources = Map.delete legacyKafkaName reset.resources}
  | otherwise = reset

-- | Whether the cell's descriptor names a broker image.
legacyBrokerAvailable :: CellDescriptor -> Bool
legacyBrokerAvailable descriptor = not (Text.null descriptor.images.broker)
