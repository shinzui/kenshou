-- | Owner snapshots: the exact bytes an owner status was built from, frozen in a
-- directory so later rounds report from the same bytes instead of rereading the
-- owners' repositories.
--
-- A snapshot directory holds @snapshot.json@ (@kenshou.owner-snapshot/v1@: the
-- capture time, the record kinds, the citations, and for every reference in the
-- status document the resolver's answer, its provenance, and the enrichment links)
-- and @records/@, each resolved record's bytes in a file named by their SHA-256. A
-- snapshot is created once and never overwritten. Reading one verifies every file
-- against its digest and runs no source, resolver, or enrichment.
module Kenshou.Evidence.Owner.Snapshot
  ( SnapshotError (..),
    SnapshotContents (..),
    writeSnapshot,
    readSnapshot,
    loadSnapshot,
    snapshotResolver,
  )
where

import Control.Exception (SomeException, try)
import Control.Monad (forM, forM_, when)
import Data.Aeson (Value (..), object, (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types (Parser, parseEither, withObject)
import Data.ByteString qualified as ByteString
import Data.List (sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Kenshou.Core.Canonical (sha256Hex)
import Kenshou.Evidence.Owner
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, doesPathExist, listDirectory, makeAbsolute, removeDirectoryRecursive, renameDirectory)
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO.Temp (createTempDirectory)

data SnapshotError
  = -- | The requested directory already exists.
    SnapshotExists
  | SnapshotFailed Text
  deriving stock (Eq, Show)

-- | A verified snapshot's contents. Answers carry no local paths.
data SnapshotContents = SnapshotContents
  { observedAt :: UTCTime,
    recordKinds :: [RecordKind],
    citations :: [OwnerCitation],
    answers :: Map Text ResolveResult,
    links :: Map Text [OwnerLink],
    digest :: Text
  }

-- | Write a snapshot of a status document: the record kinds and citations it was
-- resolved from and the resolver's answers. The directory is built beside the
-- target and renamed into place, so an interrupted write leaves nothing under the
-- requested name. Returns the snapshot's digest (the SHA-256 of @snapshot.json@).
writeSnapshot :: FilePath -> [RecordKind] -> [OwnerCitation] -> [(Text, ResolveResult)] -> OwnerStatus -> IO (Either SnapshotError Text)
writeSnapshot requested kinds citations answers status = do
  target <- makeAbsolute requested
  exists <- doesPathExist target
  if exists
    then pure (Left SnapshotExists)
    else do
      let parent = takeDirectory target
      createDirectoryIfMissing True parent
      staging <- createTempDirectory parent ("." <> takeFileName target <> ".partial")
      outcome <- try (populate staging) :: IO (Either SomeException Text)
      case outcome of
        Left problem -> do
          _ <- try (removeDirectoryRecursive staging) :: IO (Either SomeException ())
          pure (Left (SnapshotFailed (Text.pack (show problem))))
        Right digest -> do
          raced <- doesPathExist target
          if raced
            then removeDirectoryRecursive staging >> pure (Left SnapshotExists)
            else renameDirectory staging target >> pure (Right digest)
  where
    answerTable = Map.fromList answers
    populate staging = do
      createDirectoryIfMissing False (staging </> "records")
      forM_ answers \case
        (_, ResolvedBytes bytes provenance _) -> ByteString.writeFile (staging </> "records" </> recordFileName provenance.sha256) bytes
        _ -> pure ()
      let index = prettyJson (snapshotValue kinds citations answerTable status)
      ByteString.writeFile (staging </> "snapshot.json") index
      pure (sha256Hex index)

recordFileName :: Text -> FilePath
recordFileName digest = Text.unpack (fromMaybe digest (Text.stripPrefix "sha256:" digest))

snapshotValue :: [RecordKind] -> [OwnerCitation] -> Map Text ResolveResult -> OwnerStatus -> Value
snapshotValue kinds citations answers status =
  object
    [ "schema" .= ("kenshou.owner-snapshot/v1" :: Text),
      "observedAt" .= status.observedAt,
      "recordKinds" .= [object ["type" .= kind.typeName, "handleField" .= kind.handleField] | kind <- kinds],
      "citations" .= fmap citationValue citations,
      "references" .= fmap referenceValue status.records
    ]
  where
    referenceValue entry =
      object $
        ["reference" .= entry.reference, "links" .= fmap linkValue entry.links]
          <> answerPairs (Map.lookup entry.reference answers)
    answerPairs = \case
      Nothing -> ["answer" .= ("not-asked" :: Text)]
      Just (ResolvedBytes _ provenance _) -> ["answer" .= ("bytes" :: Text), "source" .= provenanceValue provenance]
      Just NoMapping -> ["answer" .= ("no-mapping" :: Text)]
      Just (NotFound message) -> ["answer" .= ("not-found" :: Text), "message" .= message]
      Just (Ambiguous locations) -> ["answer" .= ("ambiguous-handle" :: Text), "locations" .= locations]
      Just (ResolverFailed message) -> ["answer" .= ("resolver-failed" :: Text), "message" .= message]

-- | Read and verify a snapshot directory. Fails when @snapshot.json@ is not a valid
-- index, when a record file is missing, unlisted, or differs from its digest.
loadSnapshot :: FilePath -> IO (Either Text SnapshotContents)
loadSnapshot directory = do
  let indexPath = directory </> "snapshot.json"
      recordsPath = directory </> "records"
  present <- doesFileExist indexPath
  if not present
    then pure (Left ("not a snapshot: " <> Text.pack indexPath <> " does not exist"))
    else do
      index <- ByteString.readFile indexPath
      case Aeson.eitherDecodeStrict' index >>= parseEither parseIndex of
        Left message -> pure (Left ("invalid snapshot index: " <> Text.pack message))
        Right (observedAt, recordKinds, citations, stored) -> do
          recordsPresent <- doesDirectoryExist recordsPath
          listed <- if recordsPresent then sort <$> listDirectory recordsPath else pure []
          let expected = sort [recordFileName provenance.sha256 | (_, Just (StoredBytes provenance), _) <- stored]
              distinct = Map.keys (Map.fromList [(name, ()) | name <- expected])
          if listed /= distinct
            then pure (Left "snapshot records do not match the index")
            else do
              resolved <- forM stored \(reference, answer, links) -> case answer of
                Just (StoredBytes provenance) -> do
                  bytes <- ByteString.readFile (recordsPath </> recordFileName provenance.sha256)
                  pure
                    if sha256Hex bytes /= provenance.sha256
                      then Left ("snapshot record for " <> reference <> " differs from its digest")
                      else Right (reference, Just (ResolvedBytes bytes provenance Nothing), links)
                Just (StoredAnswer result) -> pure (Right (reference, Just result, links))
                Nothing -> pure (Right (reference, Nothing, links))
              pure case sequence resolved of
                Left message -> Left message
                Right entries ->
                  Right
                    SnapshotContents
                      { observedAt,
                        recordKinds,
                        citations,
                        answers = Map.fromList [(reference, result) | (reference, Just result, _) <- entries],
                        links = Map.fromList [(reference, links) | (reference, _, links) <- entries],
                        digest = sha256Hex index
                      }

data StoredAnswer = StoredBytes Provenance | StoredAnswer ResolveResult

parseIndex :: Value -> Parser (UTCTime, [RecordKind], [OwnerCitation], [(Text, Maybe StoredAnswer, [OwnerLink])])
parseIndex = withObject "owner snapshot" \document -> do
  schema <- document .: "schema"
  when (schema /= ("kenshou.owner-snapshot/v1" :: Text)) (fail "schema must be kenshou.owner-snapshot/v1")
  observedAt <- document .: "observedAt"
  kinds <- document .: "recordKinds" >>= traverse (withObject "record kind" \kind -> RecordKind <$> kind .: "type" <*> kind .: "handleField")
  citations <- document .: "citations" >>= traverse parseCitation
  references <-
    document .: "references" >>= traverse \value -> flip (withObject "reference") value \item -> do
      reference <- item .: "reference"
      links <- item .: "links" >>= traverse parseLink
      answer <- item .: "answer"
      stored <- case answer :: Text of
        "not-asked" -> pure Nothing
        "bytes" -> Just . StoredBytes <$> (item .: "source" >>= parseProvenance)
        "no-mapping" -> pure (Just (StoredAnswer NoMapping))
        "not-found" -> Just . StoredAnswer . NotFound <$> item .: "message"
        "ambiguous-handle" -> Just . StoredAnswer . Ambiguous <$> item .: "locations"
        "resolver-failed" -> Just . StoredAnswer . ResolverFailed <$> item .: "message"
        other -> fail ("unknown answer " <> Text.unpack other)
      _ <- item .:? "message" :: Parser (Maybe Text)
      pure (reference, stored, links)
  pure (observedAt, kinds, citations, references)

-- | A resolver that answers only from a snapshot's stored answers.
snapshotResolver :: FilePath -> IO (Either Text OwnerResolver)
snapshotResolver directory = fmap contentsResolver <$> loadSnapshot directory

contentsResolver :: SnapshotContents -> OwnerResolver
contentsResolver contents = OwnerResolver "snapshot" \reference ->
  pure (Map.findWithDefault (ResolverFailed ("reference is not in the snapshot: " <> reference)) reference contents.answers)

-- | Rebuild the status document from a snapshot: the stored citations resolved
-- against the stored bytes with the stored record kinds, and the stored links. The
-- document carries the snapshot's capture time and digest.
readSnapshot :: FilePath -> IO (Either Text OwnerStatus)
readSnapshot directory =
  loadSnapshot directory >>= \case
    Left message -> pure (Left message)
    Right contents -> do
      entries <- resolveOwners contents.recordKinds (contentsResolver contents) contents.citations
      let rebuilt = fmap (.reference) entries
      unless' (sort rebuilt == sort (Map.keys contents.links)) do
        pure
          ( Right
              OwnerStatus
                { observedAt = contents.observedAt,
                  snapshotDigest = Just contents.digest,
                  records = [withLinks (Map.findWithDefault [] entry.reference contents.links) entry | entry <- entries]
                }
          )
  where
    unless' consistent action = if consistent then action else pure (Left "snapshot references do not match its citations")
    withLinks links entry = OwnerEntry {reference = entry.reference, resolution = entry.resolution, reasons = entry.reasons, record = entry.record, canonical = entry.canonical, aliases = entry.aliases, citedBy = entry.citedBy, source = entry.source, links}
