-- | Owner records: the bug reports and improvement requests in the repositories
-- that own a broken behavior, as cited by registered scenarios' known defects and
-- by a consumer's findings. This module gathers citations, resolves every cited
-- reference through a resolver, follows duplicate chains, and builds the
-- @kenshou.owner-status/v1@ document. It reports what an owner claimed when the
-- bytes were read; it never writes to an owner's files and never verifies a claim.
module Kenshou.Evidence.Owner
  ( -- * Citations and sources
    Citer (..),
    OwnerCitation (..),
    OwnerSource (..),
    catalogOwnerSource,
    findingsFileSource,
    decodeFindings,
    gatherCitations,

    -- * Resolution
    Resolution (..),
    OwnerLink (..),
    OwnerEntry (..),
    OwnerStatus (..),
    resolveOwners,
    resolveOwnersObserved,
    canonicalOwners,
    renderResolution,

    -- * Encoding
    ownerStatusValue,
    citationValue,
    parseCitation,
    provenanceValue,
    parseProvenance,
    linkValue,
    parseLink,
    prettyJson,

    -- * Re-exports
    RecordKind (..),
    defaultRecordKinds,
    OwnerRecord (..),
    OwnerReason (..),
    VersionClaim (..),
    Provenance (..),
    ResolveResult (..),
    OwnerResolver (..),
  )
where

import Control.Exception (IOException, try)
import Data.Aeson (Value (..), object, (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Pair, Parser, parseEither, withObject)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Builder (Builder, byteString, char8, lazyByteString, toLazyByteString)
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List (sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.Vector qualified as Vector
import Kenshou.Core.Bundle (Registry, allScenarios)
import Kenshou.Core.Id (ScenarioId, parseScenarioId, renderScenarioId)
import Kenshou.Core.Scenario (KnownDefect (..), Scenario (..), individualKnownDefects)
import Kenshou.Evidence.Owner.Record
import Kenshou.Evidence.Owner.Resolver (ConceptReference (..), OwnerResolver (..), Provenance (..), ResolveResult (..), parseConceptReference)

-- | Who cites a reference: a scenario, with the expected-failure labels its known
-- defect excuses, or a consumer finding.
data Citer = CitedByScenario ScenarioId [Text] | CitedByFinding Text
  deriving stock (Eq, Show)

data OwnerCitation = OwnerCitation
  { reference :: Text,
    citer :: Citer,
    location :: Maybe Text
  }
  deriving stock (Eq, Show)

-- | A named producer of citations. A 'Left' is an error in the source itself, not
-- an unresolved reference.
data OwnerSource = OwnerSource
  { name :: Text,
    citations :: IO (Either Text [OwnerCitation])
  }

-- | One citation per individual known defect of every registered scenario.
catalogOwnerSource :: Registry -> OwnerSource
catalogOwnerSource registry =
  OwnerSource "catalog" . pure . Right $
    [ OwnerCitation {reference, citer = CitedByScenario scenario.id expectedFailures, location = Nothing}
    | scenario <- allScenarios registry,
      KnownDefect {reference, expectedFailures} <- maybe [] individualKnownDefects scenario.knownDefect
    ]

-- | The citations in a @kenshou.owner-findings/v1@ file.
findingsFileSource :: FilePath -> OwnerSource
findingsFileSource path = OwnerSource ("findings:" <> Text.pack path) do
  read' <- try (ByteString.readFile path) :: IO (Either IOException ByteString)
  pure case read' of
    Left problem -> Left ("cannot read findings file " <> Text.pack path <> ": " <> Text.pack (show problem))
    Right bytes -> either (\message -> Left (Text.pack path <> ": " <> message)) Right (decodeFindings bytes)

-- | Decode a @kenshou.owner-findings/v1@ document into citations, in file order.
decodeFindings :: ByteString -> Either Text [OwnerCitation]
decodeFindings bytes = do
  value <- either (Left . Text.pack) Right (Aeson.eitherDecodeStrict' bytes)
  either (Left . Text.pack) Right (parseEither parser value)
  where
    parser = withObject "owner findings" \document -> do
      schema <- document .: "schema"
      if schema /= ("kenshou.owner-findings/v1" :: Text) then fail "schema must be kenshou.owner-findings/v1" else pure ()
      findings <- document .: "findings" :: Parser [Value]
      concat <$> traverse finding findings
    finding = withObject "finding" \item -> do
      identifier <- item .: "id"
      if Text.null identifier then fail "a finding id cannot be empty" else pure ()
      references <- item .: "references"
      location <- item .:? "location"
      _ <- item .:? "title" :: Parser (Maybe Text)
      pure [OwnerCitation {reference, citer = CitedByFinding identifier, location} | reference <- references]

-- | Run every source in order and concatenate their citations; the first source
-- error stops the gathering.
gatherCitations :: [OwnerSource] -> IO (Either Text [OwnerCitation])
gatherCitations = go []
  where
    go gathered [] = pure (Right (concat (reverse gathered)))
    go gathered (source : rest) =
      source.citations >>= \case
        Left message -> pure (Left ("source " <> source.name <> ": " <> message))
        Right found -> go (found : gathered) rest

data Resolution = Resolved | Unresolved | NotARecord
  deriving stock (Eq, Show)

renderResolution :: Resolution -> Text
renderResolution = \case
  Resolved -> "resolved"
  Unresolved -> "unresolved"
  NotARecord -> "not-a-record"

-- | A labelled link a consumer's enrichment attached to a record.
data OwnerLink = OwnerLink {label :: Text, target :: Text}
  deriving stock (Eq, Show)

-- | One distinct reference. 'citedBy' holds the citations of this reference and,
-- for a canonical record, those of its aliases, each paired with the alias it came
-- through. 'canonical' is absent when the reference is not a resolved record or its
-- duplicate chain does not end at one.
data OwnerEntry = OwnerEntry
  { reference :: Text,
    resolution :: Resolution,
    reasons :: [OwnerReason],
    record :: Maybe OwnerRecord,
    canonical :: Maybe Text,
    aliases :: [Text],
    citedBy :: [(OwnerCitation, Maybe Text)],
    source :: Maybe Provenance,
    links :: [OwnerLink]
  }
  deriving stock (Eq, Show)

-- | The status document. 'observedAt' is when the bytes were captured;
-- 'snapshotDigest' names the snapshot a replay read, and is absent for a live read.
data OwnerStatus = OwnerStatus
  { observedAt :: UTCTime,
    snapshotDigest :: Maybe Text,
    records :: [OwnerEntry]
  }
  deriving stock (Eq, Show)

data Lookup
  = LookNotConcept
  | LookFailed OwnerReason
  | LookNotRecord OwnerReason Provenance
  | LookUnreadable OwnerReason Provenance
  | LookMismatch OwnerRecord OwnerReason Provenance
  | LookRecord OwnerRecord Provenance

data Chain = ChainNone | ChainCanonical Text | ChainBroken OwnerReason

-- | Resolve every distinct cited reference and every reference reached through a
-- duplicate chain. Entries are sorted by reference.
resolveOwners :: [RecordKind] -> OwnerResolver -> [OwnerCitation] -> IO [OwnerEntry]
resolveOwners kinds resolver citations = fst <$> resolveOwnersObserved kinds resolver citations

-- | 'resolveOwners', also returning each answer the resolver gave, by reference.
-- A snapshot stores these answers so that a replay can rebuild the same entries.
resolveOwnersObserved :: [RecordKind] -> OwnerResolver -> [OwnerCitation] -> IO ([OwnerEntry], [(Text, ResolveResult)])
resolveOwnersObserved kinds resolver citations = do
  (lookups, answers) <- explore (Set.toList (Set.fromList (fmap (.reference) citations))) Map.empty Map.empty
  pure (buildEntries citations lookups, Map.toList answers)
  where
    explore [] lookups answers = pure (lookups, answers)
    explore (reference : rest) lookups answers
      | Map.member reference lookups = explore rest lookups answers
      | otherwise = case parseConceptReference reference of
          Nothing -> explore rest (Map.insert reference LookNotConcept lookups) answers
          Just concept -> do
            answer <- resolver.resolve reference
            let found = interpret kinds concept answer
                next = case found of
                  LookRecord record _ | Just (Right target) <- duplicateTarget concept record -> [target]
                  _ -> []
            explore (next <> rest) (Map.insert reference found lookups) (Map.insert reference answer answers)

interpret :: [RecordKind] -> ConceptReference -> ResolveResult -> Lookup
interpret kinds concept = \case
  NoMapping -> LookFailed NoResolver
  NotFound message -> LookFailed (NotFoundReason message)
  Ambiguous locations -> LookFailed (AmbiguousHandle locations)
  ResolverFailed message -> LookFailed (ResolverFailure message)
  ResolvedBytes bytes provenance _ -> case parseOwnerRecord kinds bytes of
    Left reason@(UnconfiguredType _) -> LookNotRecord reason provenance
    Left reason -> LookUnreadable reason provenance
    Right record
      | record.handle /= concept.handle -> LookMismatch record (HandleMismatch concept.handle record.handle) provenance
      | otherwise -> LookRecord record provenance

-- | Where a record's duplicate chain continues: a local handle is resolved in the
-- record's own bundle, a @mori://@ value is used as given, and any other value is
-- used as given (and then fails to be a concept).
duplicateTarget :: ConceptReference -> OwnerRecord -> Maybe (Either OwnerReason Text)
duplicateTarget concept record = case record.duplicateOf of
  Just value
    | "mori://" `Text.isPrefixOf` value -> Just (Right value)
    | isLocalHandle value -> Just (Right (concept.bundle <> "/concepts/" <> value))
    | otherwise -> Just (Right value)
  Nothing
    | record.status == Just "duplicate" -> Just (Left DuplicateTargetAbsent)
    | otherwise -> Nothing
  where
    isLocalHandle value = not (Text.null value) && Text.all (\character -> character `notElem` ("/: \t#?" :: String)) value

buildEntries :: [OwnerCitation] -> Map Text Lookup -> [OwnerEntry]
buildEntries citations lookups = fmap entry (Map.toList lookups)
  where
    chains = Map.mapWithKey (\reference _ -> chainOf reference) lookups
    aliasesOf = Map.fromListWith (flip (<>)) [(canonical, [reference]) | (reference, ChainCanonical canonical) <- Map.toList chains, canonical /= reference]
    direct reference = [(citation, Nothing) | citation <- citations, citation.reference == reference]

    chainOf start = walk [start] start
      where
        walk path current = case Map.lookup current lookups of
          Just (LookRecord record _) | Just concept <- parseConceptReference current -> case duplicateTarget concept record of
            Nothing -> ChainCanonical current
            Just (Left reason)
              | current == start -> ChainBroken reason
              | otherwise -> ChainBroken (DuplicateTargetUnresolved current)
            Just (Right target)
              | target `elem` path -> ChainBroken (DuplicateCycle (dropWhile (/= target) path))
              | otherwise -> case Map.lookup target lookups of
                  Just (LookRecord _ _) -> walk (path <> [target]) target
                  _ -> ChainBroken (DuplicateTargetUnresolved target)
          _ -> ChainNone

    malformed record = [MalformedField field "text" | field <- record.malformedFields]

    entry (reference, found) =
      let aliases = Map.findWithDefault [] reference aliasesOf
          citedBy = direct reference <> [(citation, Just alias) | alias <- aliases, (citation, _) <- direct alias]
          base resolution reasons record source canonical =
            OwnerEntry {reference, resolution, reasons, record, canonical, aliases, citedBy, source, links = []}
       in case found of
            LookNotConcept -> base NotARecord [NotAConcept] Nothing Nothing Nothing
            LookFailed reason -> base Unresolved [reason] Nothing Nothing Nothing
            LookNotRecord reason provenance -> base NotARecord [reason] Nothing (Just provenance) Nothing
            LookUnreadable reason provenance -> base Unresolved [reason] Nothing (Just provenance) Nothing
            LookMismatch record reason provenance -> base Unresolved (reason : malformed record) (Just record) (Just provenance) Nothing
            LookRecord record provenance -> case Map.findWithDefault ChainNone reference chains of
              ChainCanonical canonical -> base Resolved (malformed record) (Just record) (Just provenance) (Just canonical)
              ChainBroken reason -> base Resolved (malformed record <> [reason]) (Just record) (Just provenance) Nothing
              ChainNone -> base Resolved (malformed record) (Just record) (Just provenance) Nothing

-- | Every reference in the document mapped to the entry of its canonical record;
-- a reference without a canonical record maps to its own entry, so its reasons
-- stay visible.
canonicalOwners :: OwnerStatus -> Map Text OwnerEntry
canonicalOwners status = Map.fromList [(entry.reference, target entry) | entry <- status.records]
  where
    byReference = Map.fromList [(entry.reference, entry) | entry <- status.records]
    target entry = fromMaybe entry (entry.canonical >>= (`Map.lookup` byReference))

-- Encoding ---------------------------------------------------------------

ownerStatusValue :: OwnerStatus -> Value
ownerStatusValue status =
  object
    [ "schema" .= ("kenshou.owner-status/v1" :: Text),
      "observedAt" .= status.observedAt,
      "snapshot" .= status.snapshotDigest,
      "records" .= fmap entryValue status.records
    ]

entryValue :: OwnerEntry -> Value
entryValue entry =
  object
    [ "reference" .= entry.reference,
      "resolution" .= renderResolution entry.resolution,
      "reasons" .= fmap reasonValue entry.reasons,
      "kind" .= fmap (.kind) entry.record,
      "handle" .= fmap (.handle) entry.record,
      "title" .= (entry.record >>= (.title)),
      "status" .= (entry.record >>= (.status)),
      "affects" .= (entry.record >>= (.affects)),
      "duplicateOf" .= (entry.record >>= (.duplicateOf)),
      "versions" .= fmap versionsValue entry.record,
      "canonical" .= entry.canonical,
      "aliases" .= entry.aliases,
      "citedBy" .= [Object (KeyMap.fromList (citerPairs citation <> maybe [] (\alias -> ["via" .= alias]) via)) | (citation, via) <- entry.citedBy],
      "source" .= fmap provenanceValue entry.source,
      "links" .= fmap linkValue entry.links
    ]
  where
    versionsValue record =
      object
        [ "affected" .= claimValue record.affectedVersion,
          "fixed" .= claimValue record.fixedVersion,
          "lastWorking" .= claimValue record.lastWorkingVersion
        ]
    claimValue claim = object ["raw" .= versionClaimRaw claim, "state" .= versionClaimState claim]

reasonValue :: OwnerReason -> Value
reasonValue reason = object (["code" .= reasonCode reason, "message" .= reasonMessage reason] <> maybe [] (\field -> ["field" .= field]) (reasonField reason))

citerPairs :: OwnerCitation -> [Pair]
citerPairs citation =
  ( case citation.citer of
      CitedByScenario scenario labels -> ["scenario" .= renderScenarioId scenario, "labels" .= labels]
      CitedByFinding finding -> ["finding" .= finding]
  )
    <> maybe [] (\location -> ["location" .= location]) citation.location

-- | A citation with its reference, as a snapshot stores it.
citationValue :: OwnerCitation -> Value
citationValue citation = object (("reference" .= citation.reference) : citerPairs citation)

parseCitation :: Value -> Parser OwnerCitation
parseCitation = withObject "citation" \item -> do
  reference <- item .: "reference"
  location <- item .:? "location"
  scenario <- item .:? "scenario"
  finding <- item .:? "finding"
  citer <- case (scenario, finding) of
    (Just raw, Nothing) -> do
      identifier <- either (fail . Text.unpack) pure (parseScenarioId raw)
      CitedByScenario identifier <$> item .: "labels"
    (Nothing, Just identifier) -> pure (CitedByFinding identifier)
    _ -> fail "a citation names exactly one scenario or finding"
  pure OwnerCitation {reference, citer, location}

provenanceValue :: Provenance -> Value
provenanceValue provenance =
  object
    [ "resolver" .= provenance.resolver,
      "location" .= provenance.location,
      "sha256" .= provenance.sha256,
      "revision" .= provenance.revision,
      "dirty" .= provenance.dirty
    ]

parseProvenance :: Value -> Parser Provenance
parseProvenance = withObject "provenance" \item ->
  Provenance <$> item .: "resolver" <*> item .:? "location" <*> item .: "sha256" <*> item .:? "revision" <*> item .:? "dirty"

linkValue :: OwnerLink -> Value
linkValue link = object ["label" .= link.label, "target" .= link.target]

parseLink :: Value -> Parser OwnerLink
parseLink = withObject "link" \item -> OwnerLink <$> item .: "label" <*> item .: "target"

-- | Deterministic, indented JSON: object keys in byte order, two-space indent, and
-- a trailing newline. Used for golden files and snapshot indexes, which people read
-- in diffs.
prettyJson :: Value -> ByteString
prettyJson value = LazyByteString.toStrict (toLazyByteString (render 0 value <> char8 '\n'))
  where
    render :: Int -> Value -> Builder
    render indent = \case
      Object fields
        | KeyMap.null fields -> "{}"
        | otherwise ->
            block indent '{' '}' [lazyByteString (Aeson.encode (Key.toText key)) <> ": " <> render (indent + 2) item | (key, item) <- sortOn (Key.toText . fst) (KeyMap.toList fields)]
      Array items
        | Vector.null items -> "[]"
        | otherwise -> block indent '[' ']' (fmap (render (indent + 2)) (Vector.toList items))
      scalar -> lazyByteString (Aeson.encode scalar)
    block indent open close items =
      char8 open
        <> char8 '\n'
        <> mconcat (zipWith (\position item -> spaces (indent + 2) <> item <> (if position == length items then "" else ",") <> char8 '\n') [1 :: Int ..] items)
        <> spaces indent
        <> char8 close
    spaces count = byteString (ByteString.replicate count 32)
