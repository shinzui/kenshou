-- | The @owners@ command: report what owners claim about the records that
-- registered scenarios and a consumer's findings cite, live or from a snapshot.
--
-- A consumer that needs its own sources, resolver, record kinds, or enrichments
-- replaces the standard command with 'ownersCommandWith'.
module Kenshou.Evidence.Owner.Cli
  ( OwnerEnrichment (..),
    OwnerConfig (..),
    defaultOwnerConfig,
    ownersCommand,
    ownersCommandWith,
    renderOwnerStatusText,
  )
where

import Control.Exception (SomeException, displayException, try)
import Control.Monad (forM, forM_)
import Data.Aeson (encode)
import Data.ByteString.Lazy.Char8 qualified as LazyByteString
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Time (getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import Kenshou.Core.Cli (CliCommand (..), CliEnv (..), CliGroup (Analysis))
import Kenshou.Core.Id (renderScenarioId)
import Kenshou.Evidence.Owner
import Kenshou.Evidence.Owner.Record (reasonCode, reasonMessage, versionClaimRaw, versionClaimState)
import Kenshou.Evidence.Owner.Resolver (chainResolvers, mappedResolver, moriResolver, withGitProvenance)
import Kenshou.Evidence.Owner.Snapshot (SnapshotError (..), readSnapshot, writeSnapshot)
import Options.Applicative
import System.Directory (doesPathExist)
import System.Exit (ExitCode (..))
import System.IO (stderr)

-- | A consumer action that attaches labelled links (plan or tracker references,
-- say) to a resolved record. Its results appear under @links@ and never affect
-- resolution; a snapshot stores them and a replay does not run it.
data OwnerEnrichment = OwnerEnrichment {name :: Text, enrich :: OwnerEntry -> IO [OwnerLink]}

-- | What a consumer adds to the standard command: sources besides the registry,
-- a resolver tried before the built-in mapped and Mori resolvers, record kinds
-- besides 'defaultRecordKinds', and enrichments.
data OwnerConfig = OwnerConfig
  { sources :: [OwnerSource],
    resolver :: Maybe OwnerResolver,
    recordKinds :: [RecordKind],
    enrichments :: [OwnerEnrichment]
  }

defaultOwnerConfig :: OwnerConfig
defaultOwnerConfig = OwnerConfig {sources = [], resolver = Nothing, recordKinds = [], enrichments = []}

ownersCommand :: CliCommand
ownersCommand = ownersCommandWith defaultOwnerConfig

ownersCommandWith :: OwnerConfig -> CliCommand
ownersCommandWith config =
  CliCommand
    { name = "owners",
      description = "Report what owners claim about cited records",
      group = Analysis,
      hidden = False,
      parser =
        subparser
          ( command "status" (info (statusHandler config <$> statusParser <**> helper) (progDesc "Report every cited owner record, live or from a snapshot"))
              <> command "snapshot" (info (snapshotHandler config <$> snapshotParser <**> helper) (progDesc "Freeze the owner records' bytes into a new directory"))
          )
    }

data LiveOptions = LiveOptions
  { findings :: [FilePath],
    maps :: [(Text, FilePath)],
    noGitProvenance :: Bool
  }

data StatusOptions = StatusOptions
  { live :: LiveOptions,
    snapshot :: Maybe FilePath,
    json :: Bool
  }

data SnapshotOptions = SnapshotOptions {live :: LiveOptions, out :: FilePath}

liveParser :: Parser LiveOptions
liveParser =
  LiveOptions
    <$> many (strOption (long "findings" <> metavar "FILE" <> help "A kenshou.owner-findings/v1 file; may repeat"))
    <*> many (option (eitherReader parseMapping) (long "map" <> metavar "PREFIX=DIR" <> help "Resolve references under a bundle URI from a local bundle directory; may repeat"))
    <*> switch (long "no-git-provenance" <> help "Do not record the checkout revision and dirty state of the files read")

statusParser :: Parser StatusOptions
statusParser =
  StatusOptions
    <$> liveParser
    <*> optional (strOption (long "snapshot" <> metavar "DIR" <> help "Report from a snapshot instead of reading the owners' files"))
    <*> switch (long "json" <> help "Emit kenshou.owner-status/v1 JSON")

snapshotParser :: Parser SnapshotOptions
snapshotParser = SnapshotOptions <$> liveParser <*> strOption (long "out" <> metavar "DIR" <> help "Directory to create; must not exist")

parseMapping :: String -> Either String (Text, FilePath)
parseMapping raw = case break (== '=') raw of
  (prefix, '=' : directory)
    | not (null prefix), not (null directory) -> Right (Text.pack prefix, directory)
  _ -> Left "a mapping must be PREFIX=DIR"

statusHandler :: OwnerConfig -> StatusOptions -> CliEnv -> IO ExitCode
statusHandler config options environment = case options.snapshot of
  Just directory
    | not (null options.live.findings) || not (null options.live.maps) || options.live.noGitProvenance ->
        usage "kenshou owners status: --snapshot cannot be combined with --findings, --map, or --no-git-provenance"
    | otherwise ->
        readSnapshot directory >>= \case
          Left message -> failure ("kenshou owners status: " <> message)
          Right status -> report status
  Nothing ->
    observe config environment options.live >>= \case
      Left message -> failure ("kenshou owners status: " <> message)
      Right observation -> report observation.status
  where
    report status = do
      if options.json
        then LazyByteString.putStrLn (encode (ownerStatusValue status))
        else Text.IO.putStr (renderOwnerStatusText status)
      forM_ status.records \entry -> forM_ (diagnostic entry) (Text.IO.hPutStrLn stderr)
      pure ExitSuccess

snapshotHandler :: OwnerConfig -> SnapshotOptions -> CliEnv -> IO ExitCode
snapshotHandler config options environment = do
  exists <- doesPathExist options.out
  if exists
    then refuse
    else
      observe config environment options.live >>= \case
        Left message -> failure ("kenshou owners snapshot: " <> message)
        Right observation ->
          writeSnapshot options.out observation.kinds observation.citations observation.answers observation.status >>= \case
            Left SnapshotExists -> refuse
            Left (SnapshotFailed message) -> failure ("kenshou owners snapshot: " <> message)
            Right digest -> do
              Text.IO.putStrLn digest
              Text.IO.hPutStrLn stderr ("kenshou owners snapshot: wrote " <> Text.pack options.out)
              pure ExitSuccess
  where
    refuse = usage "kenshou owners snapshot: refusing to overwrite an existing snapshot"

data Observation = Observation
  { kinds :: [RecordKind],
    citations :: [OwnerCitation],
    answers :: [(Text, ResolveResult)],
    status :: OwnerStatus
  }

-- | Gather, resolve, and enrich once, from the registry, the configured sources,
-- and the findings files.
observe :: OwnerConfig -> CliEnv -> LiveOptions -> IO (Either Text Observation)
observe config environment options = do
  observedAt <- getCurrentTime
  gathered <- gatherCitations ([catalogOwnerSource environment.registry] <> config.sources <> fmap findingsFileSource options.findings)
  case gathered of
    Left message -> pure (Left message)
    Right citations -> do
      let kinds = defaultRecordKinds <> config.recordKinds
          builtIn = [mappedResolver kinds options.maps | not (null options.maps)] <> [moriResolver]
          chained = chainResolvers (maybe [] pure config.resolver <> builtIn)
          resolver = if options.noGitProvenance then chained else withGitProvenance chained
      (entries, answers) <- resolveOwnersObserved kinds resolver citations
      enriched <- enrichEntries config.enrichments entries
      pure case enriched of
        Left message -> Left message
        Right records -> Right Observation {kinds, citations, answers, status = OwnerStatus {observedAt, snapshotDigest = Nothing, records}}

enrichEntries :: [OwnerEnrichment] -> [OwnerEntry] -> IO (Either Text [OwnerEntry])
enrichEntries [] entries = pure (Right entries)
enrichEntries enrichments entries = fmap sequence $ forM entries \entry ->
  if entry.resolution /= Resolved
    then pure (Right entry)
    else do
      results <- forM enrichments \enrichment -> do
        outcome <- try (enrichment.enrich entry >>= \links -> length links `seq` pure links) :: IO (Either SomeException [OwnerLink])
        pure case outcome of
          Left problem -> Left ("enrichment " <> enrichment.name <> " failed for " <> entry.reference <> ": " <> Text.pack (displayException problem))
          Right links -> Right links
      pure case sequence results of
        Left message -> Left message
        Right links ->
          Right
            OwnerEntry
              { reference = entry.reference,
                resolution = entry.resolution,
                reasons = entry.reasons,
                record = entry.record,
                canonical = entry.canonical,
                aliases = entry.aliases,
                citedBy = entry.citedBy,
                source = entry.source,
                links = entry.links <> concat links
              }

-- | One line for a record that did not resolve, sits in a duplicate cycle, or has
-- a malformed field.
diagnostic :: OwnerEntry -> Maybe Text
diagnostic entry
  | entry.resolution == Unresolved || any notable entry.reasons =
      Just ("kenshou owners: " <> entry.reference <> ": " <> Text.intercalate "; " [reasonCode reason <> ": " <> reasonMessage reason | reason <- entry.reasons])
  | otherwise = Nothing
  where
    notable = \case
      DuplicateCycle _ -> True
      MalformedField _ _ -> True
      _ -> False

-- | The text report: one block per record with the owner's claims exactly as
-- written, the reasons, the canonical record when it differs, and the citers.
renderOwnerStatusText :: OwnerStatus -> Text
renderOwnerStatusText status = Text.unlines (heading <> concatMap block status.records)
  where
    heading =
      ["observed at " <> Text.pack (iso8601Show status.observedAt)]
        <> maybe [] (\digest -> ["snapshot " <> digest]) status.snapshotDigest
    block entry =
      [""]
        <> [entry.reference]
        <> ["  " <> Text.intercalate "  " (renderResolution entry.resolution : maybe [] claims entry.record)]
        <> ["  " <> reasonCode reason <> "  " <> reasonMessage reason | reason <- entry.reasons]
        <> ["  canonical " <> canonical | Just canonical <- [entry.canonical], canonical /= entry.reference]
        <> ["  alias " <> alias | alias <- entry.aliases]
        <> [citedLine citation via | (citation, via) <- entry.citedBy]
        <> ["  link " <> link.label <> "  " <> link.target | link <- entry.links]
    claims record =
      [ record.kind,
        "status=" <> maybe "(absent)" quoted record.status,
        "affected=" <> claim record.affectedVersion,
        "fixed=" <> claim record.fixedVersion
      ]
        <> ["lastWorking=" <> claim record.lastWorkingVersion | record.lastWorkingVersion /= ClaimAbsent]
        <> ["duplicateOf=" <> target | Just target <- [record.duplicateOf]]
    claim version = maybe ("(" <> versionClaimState version <> ")") quoted (versionClaimRaw version)
    quoted raw = if Text.any (== ' ') raw then "\"" <> raw <> "\"" else raw
    citedLine citation via =
      "  cited by "
        <> ( case citation.citer of
               CitedByScenario scenario labels -> "scenario " <> renderScenarioId scenario <> (if null labels then "" else " [" <> Text.intercalate ", " labels <> "]")
               CitedByFinding finding -> "finding " <> finding
           )
        <> maybe "" (" at " <>) citation.location
        <> maybe "" (" via " <>) via

usage :: Text -> IO ExitCode
usage message = Text.IO.hPutStrLn stderr message >> pure (ExitFailure 2)

failure :: Text -> IO ExitCode
failure message = Text.IO.hPutStrLn stderr message >> pure (ExitFailure 4)
