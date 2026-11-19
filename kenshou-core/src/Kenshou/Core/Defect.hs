-- | The catalog encoding of a complete known-defect declaration: every reference,
-- summary, excused failure label, group, and cohort condition, exactly as the
-- scenario declares it. Groups are preserved, not flattened, so a declaration
-- read back from a catalog equals the one the scenario holds.
--
-- The encoding appears under @knownDefectDeclaration@ in each scenario of a
-- @kenshou.scenario-list/v1@ document, beside the older @knownDefect@ field that
-- carries only references.
module Kenshou.Core.Defect
  ( -- * Encoding
    defectValue,
    parseDefect,
    scopeValue,
    parseScope,
    conditionValue,
    parseCondition,
    defectReferencesValue,

    -- * Scope evaluation (re-exported from "Kenshou.Core.Scenario")
    ScopeSource (..),
    ScopePackage (..),
    cohortScopePackages,
    ConditionResult (..),
    ScopeEvaluation (..),
    evaluateScope,
    scopeApplies,
    parseScopeVersion,
    conditionPackage,
  )
where

import Data.Aeson (Value, object, toJSON, (.:), (.=))
import Data.Aeson.Types (Parser, withObject)
import Data.Foldable (toList)
import Data.List.NonEmpty (NonEmpty)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Kenshou.Core.Scenario

-- | A declaration as @{"kind": "single", ...}@ or @{"kind": "group", "defects": [...]}@.
defectValue :: KnownDefect -> Value
defectValue = \case
  KnownDefect {reference, summary, expectedFailures, appliesTo} ->
    object
      [ "kind" .= ("single" :: Text),
        "reference" .= reference,
        "summary" .= summary,
        "expectedFailures" .= expectedFailures,
        "appliesTo" .= scopeValue appliesTo
      ]
  KnownDefectGroup defects -> object ["kind" .= ("group" :: Text), "defects" .= fmap defectValue (toList defects)]

-- | The inverse of 'defectValue'. Rejects an unknown kind and an empty group.
parseDefect :: Value -> Parser KnownDefect
parseDefect = withObject "known defect" \item ->
  item .: "kind" >>= \case
    ("single" :: Text) -> do
      reference <- item .: "reference"
      summary <- item .: "summary"
      expectedFailures <- item .: "expectedFailures"
      appliesTo <- item .: "appliesTo" >>= parseScope
      pure KnownDefect {reference, summary, expectedFailures, appliesTo}
    "group" -> KnownDefectGroup <$> (item .: "defects" >>= nonEmpty "defects" >>= traverse parseDefect)
    other -> fail ("unknown known-defect kind " <> Text.unpack other)

-- | A scope as @{"kind": "all-cohorts"}@ or @{"kind": "only-when", "conditions": [...]}@.
scopeValue :: CohortScope -> Value
scopeValue = \case
  AllCohorts -> object ["kind" .= ("all-cohorts" :: Text)]
  OnlyWhen conditions -> object ["kind" .= ("only-when" :: Text), "conditions" .= fmap conditionValue (toList conditions)]

parseScope :: Value -> Parser CohortScope
parseScope = withObject "cohort scope" \item ->
  item .: "kind" >>= \case
    ("all-cohorts" :: Text) -> pure AllCohorts
    "only-when" -> OnlyWhen <$> (item .: "conditions" >>= nonEmpty "conditions" >>= traverse parseCondition)
    other -> fail ("unknown cohort scope kind " <> Text.unpack other)

conditionValue :: PackageCondition -> Value
conditionValue = \case
  ResolvedFromHackage package -> object ["kind" .= ("resolved-from-hackage" :: Text), "package" .= package]
  ResolvedFromGit package -> object ["kind" .= ("resolved-from-git" :: Text), "package" .= package]
  VersionBelow package version -> object ["kind" .= ("version-below" :: Text), "package" .= package, "version" .= version]
  RevisionIs package revision -> object ["kind" .= ("revision-is" :: Text), "package" .= package, "revision" .= revision]

parseCondition :: Value -> Parser PackageCondition
parseCondition = withObject "package condition" \item -> do
  package <- item .: "package"
  item .: "kind" >>= \case
    ("resolved-from-hackage" :: Text) -> pure (ResolvedFromHackage package)
    "resolved-from-git" -> pure (ResolvedFromGit package)
    "version-below" -> VersionBelow package <$> item .: "version"
    "revision-is" -> RevisionIs package <$> item .: "revision"
    other -> fail ("unknown package condition kind " <> Text.unpack other)

-- | The older @knownDefect@ catalog field: the reference of a single defect, or
-- the references of a group's individual defects in order.
defectReferencesValue :: KnownDefect -> Value
defectReferencesValue defect = case individualKnownDefects defect of
  [single] -> toJSON single.reference
  many -> toJSON (fmap (.reference) many)

nonEmpty :: String -> [Value] -> Parser (NonEmpty Value)
nonEmpty name = maybe (fail (name <> " must not be empty")) pure . NonEmpty.nonEmpty
