-- | Names and values of the resources a scenario may require besides PostgreSQL:
-- anything a suite provisions for a run, such as a message broker or an object
-- store. 'Kenshou.Core.Resource' adds the provider contract; these types live apart
-- so the environment and context modules can name them without an import cycle.
module Kenshou.Core.Resource.Types
  ( ResourceName,
    mkResourceName,
    renderResourceName,
    legacyKafkaName,
    ProvisionedResource (..),
    CellBinding (..),
  )
where

import Data.Aeson (FromJSON (..), FromJSONKey (..), FromJSONKeyFunction (..), ToJSON (..), ToJSONKey (..), Value, withText)
import Data.Aeson.Types (toJSONKeyText)
import Data.Char (isAsciiLower, isDigit)
import Data.Text (Text)
import Data.Text qualified as Text

-- | Lowercase ASCII letters, digits, and hyphens, starting with a letter, at most
-- 63 characters, so a name is usable as a JSON object key without escaping.
newtype ResourceName = ResourceName Text
  deriving stock (Eq, Ord, Show)

mkResourceName :: Text -> Either Text ResourceName
mkResourceName value
  | valid = Right (ResourceName value)
  | otherwise = Left ("invalid resource name \"" <> value <> "\"")
  where
    valid =
      Text.length value >= 1
        && Text.length value <= 63
        && isAsciiLower (Text.head value)
        && Text.all (\character -> isAsciiLower character || isDigit character || character == '-') value

renderResourceName :: ResourceName -> Text
renderResourceName (ResourceName value) = value

-- | The resource name that documents written before named resources carried as a
-- top-level field. It exists only for the legacy readers and the compat-key/v1 shim;
-- the coupling allow-list names it.
legacyKafkaName :: ResourceName
legacyKafkaName = ResourceName "kafka"

-- | What a provider hands a run for one resource.
data ProvisionedResource = ProvisionedResource
  { -- | Sent to every worker in @WorkerInit.resources@.
    workerValue :: Value,
    -- | Recorded in the run result fingerprint under @resources.<name>@.
    fingerprint :: Value
  }
  deriving stock (Eq, Show)

-- | How a resource is bound on a leased verification cell.
data CellBinding = CellBinding
  { -- | The capability key a cell must report.
    capability :: Text,
    -- | The value for @cell.submission@ @reset.resources.<name>@, if the cell must
    -- reset the resource before the run.
    reset :: Maybe Value
  }
  deriving stock (Eq, Show)

instance ToJSON ResourceName where toJSON = toJSON . renderResourceName

instance FromJSON ResourceName where parseJSON = withText "ResourceName" (either (fail . Text.unpack) pure . mkResourceName)

instance ToJSONKey ResourceName where toJSONKey = toJSONKeyText renderResourceName

instance FromJSONKey ResourceName where fromJSONKey = FromJSONKeyTextParser (either (fail . Text.unpack) pure . mkResourceName)
