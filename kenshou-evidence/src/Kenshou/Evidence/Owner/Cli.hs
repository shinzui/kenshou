-- | The @owners@ command: report what owners claim about the records that
-- registered scenarios and a consumer's findings cite, live or from a snapshot,
-- and reconcile known-defect scopes with those claims.
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

import Control.Exception (IOException, SomeException, displayException, try)
import Control.Monad (filterM, forM, forM_)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), except, runExceptT)
import Data.Aeson (Value, encode, toJSON)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy.Char8 qualified as LazyByteString
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Time (getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import Kenshou.Core.Bundle (allScenarios)
import Kenshou.Core.Canonical (canonicalEncode, sha256Hex)
import Kenshou.Core.Cli (CliCommand (..), CliEnv (..), CliGroup (Analysis))
import Kenshou.Core.Cli.Config (ConfigInputs (..))
import Kenshou.Core.Id (renderScenarioId)
import Kenshou.Evidence.Config (EvidenceDefaults (..), resolveEvidenceDefaults)
import Kenshou.Evidence.Disposition qualified as Disposition
import Kenshou.Evidence.Observation qualified as Run
import Kenshou.Evidence.Owner
import Kenshou.Evidence.Owner.Reconcile (ScopeFinding (..), Severity (..), decodePackageMap, reconcileScopes, reconciliationValue, renderReconciliationText)
import Kenshou.Evidence.Owner.Record (reasonCode, reasonMessage, versionClaimRaw, versionClaimState)
import Kenshou.Evidence.Owner.Resolver (chainResolvers, mappedResolver, moriResolver, withGitProvenance)
import Kenshou.Evidence.Owner.Snapshot (SnapshotError (..), readSnapshot, writeSnapshot)
import Kenshou.Plan.Catalog (CatalogDocument (..), decodeCatalog, fromScenario)
import Options.Applicative
import Settei qualified
import Settei.Env (envSnapshot)
import Settei.Optparse (DiagnosticMode (NoDiagnostic))
import System.Directory (doesDirectoryExist, doesPathExist, listDirectory, makeAbsolute)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO (hFlush, stderr)
import System.IO.Error (isAlreadyExistsError)
import System.IO.Temp (withTempFile)
import System.Posix.Files (createLink)

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
    enrichments :: [OwnerEnrichment],
    evidenceBundle :: Maybe FilePath,
    evidenceBundleUri :: Maybe Text,
    runDataLocator :: Maybe Run.RunDataLocator,
    sealedRunRoots :: [FilePath],
    -- | Results of a consumer's domain replay are included in the frozen input.
    -- The run's digest-verified labels, outcome and attestation trust still govern verification.
    replayObservation :: Run.Observation -> IO (Either Text (Maybe Value))
  }

defaultOwnerConfig :: OwnerConfig
defaultOwnerConfig =
  OwnerConfig
    { sources = [],
      resolver = Nothing,
      recordKinds = [],
      enrichments = [],
      evidenceBundle = Nothing,
      evidenceBundleUri = Nothing,
      runDataLocator = Nothing,
      sealedRunRoots = [],
      replayObservation = const (pure (Right Nothing))
    }

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
              <> command "dispositions" (info (dispositionsHandler config <$> dispositionsParser <**> helper) (progDesc "Derive fix verification from a frozen input or capture current evidence"))
              <> command "reconcile" (info (reconcileHandler <$> reconcileParser <**> helper) (progDesc "Compare known-defect scopes with a snapshot's owner version claims and propose corrections"))
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

data ReconcileOptions = ReconcileOptions
  { snapshot :: FilePath,
    packageMap :: FilePath,
    catalog :: Maybe FilePath,
    json :: Bool
  }

reconcileParser :: Parser ReconcileOptions
reconcileParser =
  ReconcileOptions
    <$> strOption (long "snapshot" <> metavar "DIR" <> help "The owner snapshot whose claims scopes are compared with")
    <*> strOption (long "package-map" <> metavar "FILE" <> help "A kenshou.owner-package-map/v1 file naming each owner's packages")
    <*> optional (strOption (long "catalog" <> metavar "FILE" <> help "A kenshou.scenario-list/v1 catalog; defaults to the registered scenarios"))
    <*> switch (long "json" <> help "Emit kenshou.scope-reconciliation/v1 JSON")

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

-- | Read the snapshot, package map, and catalog, print the findings, and exit 1
-- when any finding is a contradiction. Every input is only read.
reconcileHandler :: ReconcileOptions -> CliEnv -> IO ExitCode
reconcileHandler options environment = do
  loaded <- load
  case loaded of
    Left message -> failure ("kenshou owners reconcile: " <> message)
    Right (status, packageMap, scenarios) -> do
      let findings = reconcileScopes status packageMap scenarios
      if options.json
        then LazyByteString.putStrLn (encode (reconciliationValue status findings))
        else Text.IO.putStr (renderReconciliationText status findings)
      forM_ [finding | finding <- findings, finding.severity == Warning] \finding ->
        Text.IO.hPutStrLn stderr ("kenshou owners reconcile: warning: " <> renderScenarioId finding.scenario <> ": " <> finding.code <> ": " <> finding.rationale)
      pure (if any ((== Contradiction) . (.severity)) findings then ExitFailure 1 else ExitSuccess)
  where
    load = do
      snapshotRead <- try (readSnapshot options.snapshot) :: IO (Either SomeException (Either Text OwnerStatus))
      case either (Left . Text.pack . displayException) id snapshotRead of
        Left message -> pure (Left message)
        Right status ->
          readInput options.packageMap >>= \case
            Left message -> pure (Left message)
            Right bytes -> case decodePackageMap bytes of
              Left message -> pure (Left (Text.pack options.packageMap <> ": " <> message))
              Right packageMap -> case options.catalog of
                Nothing -> pure (Right (status, packageMap, fmap fromScenario (allScenarios environment.registry)))
                Just path ->
                  readInput path >>= \case
                    Left message -> pure (Left message)
                    Right catalogBytes -> pure case decodeCatalog catalogBytes of
                      Left message -> Left (Text.pack path <> ": " <> message)
                      Right scenarios -> Right (status, packageMap, scenarios)
    readInput path = do
      result <- try (ByteString.readFile path) :: IO (Either IOException ByteString)
      pure (either (\problem -> Left ("cannot read " <> Text.pack path <> ": " <> Text.pack (displayException problem))) Right result)

data DispositionMode = Replay FilePath | Capture CaptureOptions

data CaptureOptions = CaptureOptions
  { snapshot :: FilePath,
    packageMap :: FilePath,
    catalog :: Maybe FilePath,
    bundle :: Maybe FilePath,
    runData :: Maybe FilePath,
    runs :: [FilePath],
    coverage :: Maybe FilePath,
    writeInput :: Maybe FilePath
  }

dispositionsParser :: Parser (DispositionMode, Bool)
dispositionsParser =
  (,)
    <$> (Replay <$> filePath "input" "FILE" "Replay only this frozen disposition input" <|> Capture <$> capture)
    <*> switch (long "json" <> help "Emit kenshou.dispositions/v1 JSON")
  where
    filePath optionName placeholder description =
      strOption (long optionName <> metavar placeholder <> help description)
    capture =
      CaptureOptions
        <$> filePath "snapshot" "DIR" "Read this verified owner snapshot"
        <*> filePath "package-map" "FILE" "Map owners to resolved packages"
        <*> optional (filePath "catalog" "FILE" "Read scenario declarations from this catalog")
        <*> optional (filePath "bundle" "DIR" "Read published runs and attestations from this bundle")
        <*> optional (filePath "run-data" "DIR" "Read linked results from DIR/RUN_ID/run-result.json")
        <*> many (filePath "runs" "DIR" "Read sealed local runs from the subdirectories of DIR, repeatable")
        <*> optional (filePath "coverage" "FILE" "Override required scenarios by owner reference")
        <*> optional (filePath "write-input" "FILE" "Save the frozen input to a new file")

dispositionsHandler :: OwnerConfig -> (DispositionMode, Bool) -> CliEnv -> IO ExitCode
dispositionsHandler config (mode, json) environment = do
  loaded <- try @IOException (runExceptT load)
  case either (Left . Text.pack . displayException) id loaded of
    Left message -> failure (prefix <> message)
    Right (input, output) -> do
      written <- try @IOException (forM_ output (uncurry writeFrozenInput))
      case written of
        Left problem
          | isAlreadyExistsError problem -> usage (prefix <> "refusing to overwrite an existing input file")
          | otherwise -> failure (prefix <> Text.pack (displayException problem))
        Right () -> do
          let conclusions = Disposition.deriveDispositions input
          if json
            then LazyByteString.putStrLn (encode (Disposition.dispositionsValue input conclusions))
            else Text.IO.putStr (Disposition.renderDispositionsText conclusions)
          pure ExitSuccess
  where
    prefix = "kenshou owners dispositions: "
    load = case mode of
      Replay path -> do
        input <- readDispositionFile Disposition.decodeDispositionInput path
        pure (input, Nothing)
      Capture options -> do
        captured <- captureDispositions config environment options
        let frozen = prettyJson (Disposition.dispositionInputValue captured)
        input <- except (Disposition.decodeDispositionInput frozen)
        pure (input, fmap (,frozen) options.writeInput)

captureDispositions :: OwnerConfig -> CliEnv -> CaptureOptions -> ExceptT Text IO Disposition.DispositionInput
captureDispositions config environment options = do
  owners <- ExceptT (readSnapshot options.snapshot)
  (packageMap, packageMapDigest) <- readWithDigest decodePackageMap options.packageMap
  (catalog, catalogDigest) <- case options.catalog of
    Nothing -> do
      let document = CatalogDocument (map fromScenario (allScenarios environment.registry))
      pure (document.scenarios, sha256Hex (canonicalEncode (toJSON document)))
    Just path -> readWithDigest decodeCatalog path
  coverage <- maybe (pure Map.empty) (readDispositionFile Disposition.decodeCoverage) options.coverage
  processEnvironment <- lift getEnvironment
  settings <- ExceptT (resolveEvidenceDefaults (envSnapshot [(Text.pack name, Text.pack setting) | (name, setting) <- processEnvironment]) (ConfigInputs [] [] NoDiagnostic))
  defaults <- except (first Settei.renderErrorsText settings.answer)
  bundle <- lift (makeAbsolute (fromMaybe (Text.unpack defaults.bundleRoot) (options.bundle <|> config.evidenceBundle)))
  let bundleUri = config.evidenceBundleUri <|> defaults.bundleUri
      locator = fromMaybe (\_ _ -> pure Nothing) (fmap Run.directoryRunData options.runData <|> config.runDataLocator)
      localRoots = if null options.runs then config.sealedRunRoots else options.runs
  published <- ExceptT (Run.loadPublishedObservations locator bundle)
  directories <- lift (concat <$> traverse runDirectories localRoots)
  local <- traverse (ExceptT . Run.loadSealedObservation) directories
  observations <- traverse (withReplay bundle bundleUri) (Run.mergeObservations published local)
  capturedAt <- lift (Text.pack . iso8601Show <$> getCurrentTime)
  pure Disposition.DispositionInput {capturedAt, owners, catalog, catalogDigest, packageMap, packageMapDigest, coverage, observations}
  where
    readWithDigest decoder path = readDispositionFile (\bytes -> (,sha256Hex bytes) <$> decoder bytes) path
    runDirectories root = do
      absolute <- makeAbsolute root
      entries <- sort <$> listDirectory absolute
      filterM doesDirectoryExist [absolute </> entry | entry <- entries]
    withReplay bundle bundleUri (observation :: Run.Observation) = do
      let qualified = case observation.source of
            Run.PublishedRecord concept ->
              let reference = maybe (Text.pack (bundle </> Text.unpack concept <> ".md")) (\uri -> uri <> "/concepts/" <> concept) bundleUri
               in observation {Run.source = Run.PublishedRecord reference}
            Run.SealedRun _ -> observation
      replay <- ExceptT (config.replayObservation qualified)
      pure qualified {Run.replay = replay}

readDispositionFile :: (ByteString -> Either Text a) -> FilePath -> ExceptT Text IO a
readDispositionFile decode path =
  ExceptT (first (\message -> Text.pack path <> ": " <> message) . decode <$> ByteString.readFile path)

-- Install a fully written file without replacing an existing path, even when
-- two captures race to write the same output.
writeFrozenInput :: FilePath -> ByteString -> IO ()
writeFrozenInput path contents =
  withTempFile (takeDirectory path) ".kenshou-disposition-input-" \temporary handle -> do
    ByteString.hPut handle contents
    hFlush handle
    createLink temporary path

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
