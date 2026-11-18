-- | Parsing an owner record's bytes: the frontmatter of an OKF concept that a
-- known defect or a finding cites. Only the frontmatter is read, and every value
-- is kept exactly as the owner wrote it; version fields are additionally
-- classified, never normalised.
module Kenshou.Evidence.Owner.Record
  ( RecordKind (..),
    defaultRecordKinds,
    VersionClaim (..),
    classifyVersion,
    versionClaimRaw,
    versionClaimState,
    OwnerRecord (..),
    OwnerReason (..),
    reasonCode,
    reasonMessage,
    reasonField,
    parseOwnerRecord,
    conceptHandle,
  )
where

import Data.Aeson (Value (..))
import Data.ByteString (ByteString)
import Data.Char (isDigit)
import Data.List (find)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Version (Version, parseVersion, showVersion)
import Okf.Document (OKFDocument (..), frontmatterLookup, parseDocument)
import Text.ParserCombinators.ReadP (readP_to_S)

-- | A kind of owner record: the OKF @type@ a concept must have, and the
-- frontmatter key that holds its handle.
data RecordKind = RecordKind {typeName :: Text, handleField :: Text}
  deriving stock (Eq, Show)

-- | @Bug Report@ with @bugId@ and @Improvement Request@ with @requestId@.
defaultRecordKinds :: [RecordKind]
defaultRecordKinds = [RecordKind "Bug Report" "bugId", RecordKind "Improvement Request" "requestId"]

-- | What an owner claims in a version field. 'ClaimMalformed' is a field of the
-- wrong YAML type; it carries no value because none was written as text.
data VersionClaim
  = ClaimAbsent
  | ClaimUnreleased
  | ClaimUnknown
  | ClaimReleased Version Text
  | ClaimUnparseable Text
  | ClaimMalformed
  deriving stock (Eq, Show)

-- | Classify a version field's text: the two reserved words, a bare released
-- version (digits separated by dots, as 'Data.Version.parseVersion' reads them,
-- with no tags), or anything else as unparseable.
classifyVersion :: Text -> VersionClaim
classifyVersion "unreleased" = ClaimUnreleased
classifyVersion "unknown" = ClaimUnknown
classifyVersion raw = case [version | (version, "") <- readP_to_S parseVersion (Text.unpack raw)] of
  [] -> ClaimUnparseable raw
  versions ->
    let version = last versions
     in if Text.all (\character -> isDigit character || character == '.') raw && showVersion version == Text.unpack raw then ClaimReleased version raw else ClaimUnparseable raw

-- | The text the owner wrote, when there is any.
versionClaimRaw :: VersionClaim -> Maybe Text
versionClaimRaw = \case
  ClaimAbsent -> Nothing
  ClaimUnreleased -> Just "unreleased"
  ClaimUnknown -> Just "unknown"
  ClaimReleased _ raw -> Just raw
  ClaimUnparseable raw -> Just raw
  ClaimMalformed -> Nothing

versionClaimState :: VersionClaim -> Text
versionClaimState = \case
  ClaimAbsent -> "absent"
  ClaimUnreleased -> "unreleased"
  ClaimUnknown -> "unknown"
  ClaimReleased _ _ -> "released"
  ClaimUnparseable _ -> "unparseable"
  ClaimMalformed -> "malformed"

-- | An owner record's claims, exactly as written. 'malformedFields' names every
-- field whose YAML type was wrong; such a field is 'Nothing' or 'ClaimMalformed'.
data OwnerRecord = OwnerRecord
  { kind :: Text,
    handle :: Text,
    title :: Maybe Text,
    status :: Maybe Text,
    affects :: Maybe Text,
    affectedVersion :: VersionClaim,
    fixedVersion :: VersionClaim,
    lastWorkingVersion :: VersionClaim,
    duplicateOf :: Maybe Text,
    malformedFields :: [Text]
  }
  deriving stock (Eq, Show)

-- | Why a reference did not resolve cleanly. Each has a stable code.
data OwnerReason
  = -- | The reference is not of the form @mori://…/okf/<bundle>/concepts/<HANDLE>@.
    NotAConcept
  | -- | The concept's @type@ is not a configured record kind.
    UnconfiguredType Text
  | -- | The bytes are not UTF-8 or their frontmatter cannot be parsed.
    UnreadableRecord Text
  | -- | A required field (@type@ or the handle field) is absent.
    MissingField Text
  | -- | A field has the wrong YAML type; the text says what was expected.
    MalformedField Text Text
  | -- | The record's own handle differs from the reference's handle.
    HandleMismatch Text Text
  | NotFoundReason Text
  | AmbiguousHandle [Text]
  | ResolverFailure Text
  | -- | No resolver claims the reference's bundle.
    NoResolver
  | -- | The duplicate chain returns to a reference it already visited.
    DuplicateCycle [Text]
  | -- | The duplicate chain ends at a reference that does not resolve to a record.
    DuplicateTargetUnresolved Text
  | -- | The record says it is a duplicate but names no target.
    DuplicateTargetAbsent
  deriving stock (Eq, Show)

reasonCode :: OwnerReason -> Text
reasonCode = \case
  NotAConcept -> "not-a-concept"
  UnconfiguredType _ -> "unconfigured-type"
  UnreadableRecord _ -> "unreadable-record"
  MissingField _ -> "missing-field"
  MalformedField _ _ -> "malformed-field"
  HandleMismatch _ _ -> "handle-mismatch"
  NotFoundReason _ -> "not-found"
  AmbiguousHandle _ -> "ambiguous-handle"
  ResolverFailure _ -> "resolver-failed"
  NoResolver -> "no-mapping"
  DuplicateCycle _ -> "duplicate-cycle"
  DuplicateTargetUnresolved _ -> "duplicate-target-unresolved"
  DuplicateTargetAbsent -> "duplicate-target-absent"

reasonMessage :: OwnerReason -> Text
reasonMessage = \case
  NotAConcept -> "reference does not name an OKF concept"
  UnconfiguredType name -> "concept type " <> quoted name <> " is not an owner record kind"
  UnreadableRecord detail -> "record cannot be read: " <> detail
  MissingField name -> "field " <> name <> " is absent"
  MalformedField name expected -> "field " <> name <> " must be " <> expected
  HandleMismatch expected found -> "record handle " <> quoted found <> " differs from the reference handle " <> quoted expected
  NotFoundReason detail -> detail
  AmbiguousHandle locations -> "more than one record carries the handle: " <> Text.intercalate ", " locations
  ResolverFailure detail -> detail
  NoResolver -> "no resolver maps this reference"
  DuplicateCycle members -> "duplicate chain is a cycle: " <> Text.intercalate " -> " members
  DuplicateTargetUnresolved target -> "duplicate target does not resolve to a record: " <> target
  DuplicateTargetAbsent -> "record is a duplicate but names no duplicateOf target"
  where
    quoted value = "\"" <> value <> "\""

-- | The field a reason is about, when it is about one.
reasonField :: OwnerReason -> Maybe Text
reasonField = \case
  MissingField name -> Just name
  MalformedField name _ -> Just name
  _ -> Nothing

-- | The handle a concept carries: the value of the handle field of its own type
-- when that type is configured, otherwise of the first configured handle field it
-- has. 'Nothing' when the bytes are unreadable or carry no such field. Used to
-- find a record in a bundle directory; never derived from a file name.
conceptHandle :: [RecordKind] -> ByteString -> Maybe Text
conceptHandle kinds bytes = do
  document <- either (const Nothing) Just (Text.Encoding.decodeUtf8' bytes) >>= either (const Nothing) Just . parseDocument
  let front = document.frontmatter
      textField name = case frontmatterLookup name front of Just (String value) -> Just value; _ -> Nothing
  case textField "type" >>= \typeValue -> find ((== typeValue) . (.typeName)) kinds of
    Just recordKind -> textField recordKind.handleField
    Nothing -> case mapMaybe (textField . (.handleField)) kinds of
      value : _ -> Just value
      [] -> Nothing

-- | Parse a record from its bytes. A concept of an unconfigured type is
-- @Left ('UnconfiguredType' t)@; a record with a wrong-typed optional field still
-- parses and names the field in 'malformedFields'.
parseOwnerRecord :: [RecordKind] -> ByteString -> Either OwnerReason OwnerRecord
parseOwnerRecord kinds bytes = do
  decoded <- either (const (Left (UnreadableRecord "bytes are not UTF-8"))) Right (Text.Encoding.decodeUtf8' bytes)
  document <- either (Left . UnreadableRecord . Text.pack . show) Right (parseDocument decoded)
  let front = document.frontmatter
      lookupField name = frontmatterLookup name front
      requiredText name = case lookupField name of
        Nothing -> Left (MissingField name)
        Just Null -> Left (MissingField name)
        Just (String value) -> Right value
        Just _ -> Left (MalformedField name "text")
      optionalText name = case lookupField name of
        Nothing -> (Nothing, [])
        Just Null -> (Nothing, [])
        Just (String value) -> (Just value, [])
        Just _ -> (Nothing, [name])
      versionField name = case lookupField name of
        Nothing -> (ClaimAbsent, [])
        Just Null -> (ClaimAbsent, [])
        Just (String value) -> (classifyVersion value, [])
        Just _ -> (ClaimMalformed, [name])
  typeValue <- requiredText "type"
  recordKind <- maybe (Left (UnconfiguredType typeValue)) Right (find ((== typeValue) . (.typeName)) kinds)
  handle <- requiredText recordKind.handleField
  let (title, titleBad) = optionalText "title"
      (status, statusBad) = optionalText "status"
      (affects, affectsBad) = optionalText "affects"
      (affectedVersion, affectedBad) = versionField "affectedVersion"
      (fixedVersion, fixedBad) = versionField "fixedVersion"
      (lastWorkingVersion, lastWorkingBad) = versionField "lastWorkingVersion"
      (duplicateOf, duplicateBad) = optionalText "duplicateOf"
  pure
    OwnerRecord
      { kind = typeValue,
        handle,
        title,
        status,
        affects,
        affectedVersion,
        fixedVersion,
        lastWorkingVersion,
        duplicateOf,
        malformedFields = concat [titleBad, statusBad, affectsBad, affectedBad, fixedBad, lastWorkingBad, duplicateBad]
      }
