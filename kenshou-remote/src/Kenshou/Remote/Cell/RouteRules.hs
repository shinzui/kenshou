module Kenshou.Remote.Cell.RouteRules
  ( CellCapabilities (..),
    RuleCondition (..),
    RoutingRule (..),
    defaultRoutingRules,
    matchingRules,
    capabilityKnown,
    descriptorDigest,
    loadCellCapabilities,
  )
where

import Data.Aeson (FromJSON (..), ToJSON (..), Value (..), eitherDecodeFileStrict', encode, object, withObject, (.:), (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Kenshou.Core.Canonical (sha256Hex)
import Kenshou.Core.Contribution (RoutingRule (..), RuleCondition (..))
import Kenshou.Core.Id (RunId)
import Kenshou.Core.Knob (RawKnob (..), mkKnobName)
import Kenshou.Core.RunSpec (RunSpec (..))
import Kenshou.Plan.Selector (Selector, matches, parseSelector)
import Kenshou.Remote.Cell.Docs (CellDescriptor (..))
import System.Directory (doesFileExist)
import System.FilePath ((</>))

data CellCapabilities = CellCapabilities
  { cell :: !Text,
    descriptorSha256 :: !Text,
    probedBy :: !RunId,
    probedAt :: !UTCTime,
    capabilities :: !(Map Text Value)
  }
  deriving stock (Eq, Show)

-- | Superseded by 'Kenshou.Core.Bundle.registryRoutingRules': suites contribute
-- their routing rules on their bundles. Kept, empty, so existing imports compile.
defaultRoutingRules :: [RoutingRule]
defaultRoutingRules = []

instance FromJSON CellCapabilities where
  parseJSON = withObject "cell capabilities" \fields -> do
    schema <- fields .: "schema"
    if schema == ("kenshou.cell-capabilities/v1" :: Text) then pure () else fail "unsupported cell capabilities schema"
    document <- CellCapabilities <$> fields .: "cell" <*> fields .: "descriptorSha256" <*> fields .: "probedBy" <*> fields .: "probedAt" <*> fields .: "capabilities"
    if Text.null document.cell || Text.length document.descriptorSha256 /= 64 || not (Text.all (`elem` (['0' .. '9'] <> ['a' .. 'f'])) document.descriptorSha256)
      then fail "invalid cell capabilities identity"
      else pure document

instance ToJSON CellCapabilities where
  toJSON cache =
    object
      [ "schema" .= ("kenshou.cell-capabilities/v1" :: Text),
        "cell" .= cache.cell,
        "descriptorSha256" .= cache.descriptorSha256,
        "probedBy" .= cache.probedBy,
        "probedAt" .= cache.probedAt,
        "capabilities" .= cache.capabilities
      ]

matchingRules :: [RoutingRule] -> RunSpec -> [RoutingRule]
matchingRules rules spec = filter (matchesRule spec) rules
  where
    matchesRule run rule = case rule.condition of
      ScenarioMatches selector -> matches selector run.scenario
      KnobEquals name expected -> case mkKnobName name of
        Left _ -> False
        Right key -> case lookup key run.knobs of
          Just (RawText actual) -> actual == expected
          Just (RawJson (String actual)) -> actual == expected
          _ -> False

capabilityKnown :: CellCapabilities -> Text -> Maybe Bool
capabilityKnown cache name = case Map.lookup name cache.capabilities of
  Just (Bool available) -> Just available
  _ -> Nothing

-- The cache uses the canonical codec form, so object member order in the
-- downloaded descriptor cannot invalidate an otherwise identical cell shape.
descriptorDigest :: CellDescriptor -> Text
descriptorDigest = Text.drop 7 . sha256Hex . LazyByteString.toStrict . encode

-- A cache belongs to one descriptor revision. Missing and stale files leave
-- routing in its explicit unprobed state; malformed files must be repaired.
loadCellCapabilities :: FilePath -> CellDescriptor -> IO (Either Text (Maybe CellCapabilities))
loadCellCapabilities directory descriptor = do
  let path = directory </> Text.unpack descriptor.name <> ".capabilities.json"
  present <- doesFileExist path
  if not present
    then pure (Right Nothing)
    else do
      decoded <- eitherDecodeFileStrict' path
      pure case decoded of
        Left problem -> Left ("invalid capability cache " <> Text.pack path <> ": " <> Text.pack problem)
        Right cache
          | cache.cell == descriptor.name && cache.descriptorSha256 == descriptorDigest descriptor -> Right (Just cache)
          | otherwise -> Right Nothing
