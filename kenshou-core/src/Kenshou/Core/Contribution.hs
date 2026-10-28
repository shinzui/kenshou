-- | Data a suite contributes through its layer bundle for the toolkits to consume:
-- SQL oracles the correctness toolkit runs, advisory-lock labels stall diagnoses
-- name, and a connection-pool methodology. The types live in the kernel because
-- 'Kenshou.Core.Bundle.LayerBundle' carries them; the toolkits re-export them from
-- the modules that use them.
module Kenshou.Core.Contribution
  ( OracleSpec (..),
    AdvisoryKeySpec (..),
    AdvisoryLabel (..),
    PoolMethodology (..),
  )
where

import Control.Applicative ((<|>))
import Data.Aeson (FromJSON (..), ToJSON (..), object, withObject, (.:), (.=))
import Data.Int (Int64)
import Data.Text (Text)

-- | A named SQL query whose rows a correctness scenario reconciles.
data OracleSpec = OracleSpec {name :: !Text, sql :: !Text}
  deriving stock (Eq, Show)

-- | How PostgreSQL derives an advisory-lock key from a label's text.
data AdvisoryKeySpec = HashTextExtended !Text | HashText !Text | LiteralKey !Int64
  deriving stock (Eq, Show)

-- | A human label for an advisory lock, so a stall capture names who holds it.
data AdvisoryLabel = AdvisoryLabel {label :: !Text, key :: !AdvisoryKeySpec}
  deriving stock (Eq, Show)

-- | The pool size a suite recommends for its scenarios and the range its
-- measurements justify.
data PoolMethodology = PoolMethodology {recommendedPoolSize :: !Int, poolRange :: !(Int, Int)}
  deriving stock (Eq, Show)

instance ToJSON OracleSpec where
  toJSON spec = object ["name" .= spec.name, "sql" .= spec.sql]

instance FromJSON OracleSpec where
  parseJSON = withObject "OracleSpec" \value -> OracleSpec <$> value .: "name" <*> value .: "sql"

instance ToJSON AdvisoryKeySpec where
  toJSON (HashTextExtended text) = object ["hashTextExtended" .= text]
  toJSON (HashText text) = object ["hashText" .= text]
  toJSON (LiteralKey key) = object ["literal" .= key]

instance FromJSON AdvisoryKeySpec where
  parseJSON = withObject "AdvisoryKeySpec" \value ->
    (HashTextExtended <$> value .: "hashTextExtended") <|> (HashText <$> value .: "hashText") <|> (LiteralKey <$> value .: "literal")

instance ToJSON AdvisoryLabel where
  toJSON advisory = object ["label" .= advisory.label, "key" .= advisory.key]

instance FromJSON AdvisoryLabel where
  parseJSON = withObject "AdvisoryLabel" \value -> AdvisoryLabel <$> value .: "label" <*> value .: "key"

instance ToJSON PoolMethodology where
  toJSON methodology = object ["recommendedPoolSize" .= methodology.recommendedPoolSize, "poolRange" .= methodology.poolRange]

instance FromJSON PoolMethodology where
  parseJSON = withObject "PoolMethodology" \value -> PoolMethodology <$> value .: "recommendedPoolSize" <*> value .: "poolRange"
