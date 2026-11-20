module Kenshou.Cli.Command.Round
  ( RoundConfig (..),
    defaultRoundConfig,
    roundCommand,
    roundCommandWith,
  )
where

import Control.Exception (IOException, displayException, try)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), except, runExceptT)
import Data.Aeson qualified as Aeson
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text.IO
import Data.Time (Day)
import Kenshou.Core.Bundle (allScenarios)
import Kenshou.Core.Cli (CliCommand (..), CliEnv (..), CliGroup (Analysis))
import Kenshou.Core.Cli.Config (ConfigInputs (..))
import Kenshou.Evidence.Config (EvidenceDefaults (..), resolveEvidenceDefaults)
import Kenshou.Evidence.Observation qualified as Run
import Kenshou.Evidence.Owner.Cli (OwnerConfig (..), defaultOwnerConfig)
import Kenshou.Evidence.Round qualified as Round
import Kenshou.Plan.Catalog (CatalogDocument (..), fromScenario)
import Options.Applicative
import Settei qualified
import Settei.Env (envSnapshot)
import Settei.Optparse (DiagnosticMode (NoDiagnostic))
import System.Directory (doesPathExist, makeAbsolute)
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (stderr)

data RoundConfig = RoundConfig
  { owners :: OwnerConfig,
    reportPath :: Maybe (Text -> Day -> FilePath)
  }

defaultRoundConfig :: RoundConfig
defaultRoundConfig = RoundConfig defaultOwnerConfig Nothing

roundCommand :: CliCommand
roundCommand = roundCommandWith defaultRoundConfig

roundCommandWith :: RoundConfig -> CliCommand
roundCommandWith config =
  CliCommand "round" "Plan and report verification rounds against frozen evidence" Analysis False $
    hsubparser $
      command "open" (info (handleOpen config <$> openParser <**> helper) (progDesc "Freeze the inputs for a verification round"))

data OpenCapture = Adopt FilePath | Capture CaptureOptions

data OpenArguments = OpenArguments Text FilePath Round.RoundMode OpenCapture [(Text, FilePath)]

data CaptureOptions = CaptureOptions
  { owners :: FilePath,
    packageMap :: FilePath,
    catalog :: Maybe FilePath,
    graph :: Maybe FilePath,
    baseline :: FilePath,
    candidate :: FilePath,
    baselineRuns :: FilePath,
    coverage :: Maybe FilePath,
    scopeOverrides :: Maybe FilePath,
    published :: PublishedOptions
  }

data PublishedOptions = PublishedOptions (Maybe FilePath) (Maybe Text) (Maybe FilePath)

openParser :: Parser OpenArguments
openParser =
  OpenArguments
    <$> textOption "id" "ID" "Identifier for the round"
    <*> fileOption "out" "DIR" "Create the round in this directory"
    <*> option (jsonWord "expected release or change") (long "mode" <> metavar "release|change" <> help "Select planning mode")
    <*> (Adopt <$> fileOption "from-inputs" "DIR" "Use an already captured input directory" <|> Capture <$> captureParser)
    <*> many (option (eitherReader parseReference) (long "reference" <> metavar "KIND=PATH" <> help "Record a supporting artifact and its digest"))
  where
    captureParser =
      CaptureOptions
        <$> fileOption "owners" "DIR" "Existing owner snapshot"
        <*> fileOption "package-map" "FILE" "Owner package map"
        <*> optional (fileOption "catalog" "FILE" "Use a captured scenario catalog")
        <*> optional (fileOption "graph" "FILE" "Use a captured component graph")
        <*> fileOption "baseline-identity" "FILE" "Resolved baseline cohort identity"
        <*> fileOption "candidate-identity" "FILE" "Resolved candidate cohort identity"
        <*> fileOption "baseline-runs" "FILE" "JSON array of explicit baseline run IDs or concept references"
        <*> optional (fileOption "coverage" "FILE" "Required scenarios by owner")
        <*> optional (fileOption "scope-overrides" "FILE" "Explicit round-only scope overrides")
        <*> publishedParser
    parseReference raw = case break (== '=') raw of
      (kind, '=' : path) | not (null kind || null path) -> Right (Text.pack kind, path)
      _ -> Left "expected KIND=PATH"

publishedParser :: Parser PublishedOptions
publishedParser =
  PublishedOptions
    <$> optional (fileOption "bundle" "DIR" "Published verification evidence bundle")
    <*> optional (textOption "bundle-uri" "URI" "Canonical URI of the published verification bundle")
    <*> optional (fileOption "run-data" "DIR" "Linked results at DIR/RUN_ID/run-result.json")

fileOption :: String -> String -> String -> Parser FilePath
fileOption name placeholder description = strOption (long name <> metavar placeholder <> help description)

textOption :: String -> String -> String -> Parser Text
textOption name placeholder description = Text.pack <$> fileOption name placeholder description

jsonWord :: (Aeson.FromJSON a) => String -> ReadM a
jsonWord message = eitherReader \word -> case Aeson.fromJSON (Aeson.String (Text.pack word)) of
  Aeson.Error _ -> Left message
  Aeson.Success parsed -> Right parsed

handleOpen :: RoundConfig -> OpenArguments -> CliEnv -> IO ExitCode
handleOpen config (OpenArguments identifier target mode input references) environment = do
  loaded <- try @IOException prepare
  case loaded of
    Left err -> roundError "open" (Round.RoundInput (Text.pack (displayException err)))
    Right (Left err) -> roundError "open" err
    Right (Right capture) -> do
      result <- Round.openRound (Round.OpenOptions identifier target mode capture references)
      case result of
        Left err -> roundError "open" err
        Right definition -> do
          Text.IO.hPutStrLn stderr ("opened round " <> definition.roundId <> " with " <> Text.pack (show (length definition.baseline)) <> " baseline observations")
          pure ExitSuccess
  where
    prepare = do
      exists <- doesPathExist target
      if exists
        then pure (Left (Round.RoundUsage ("refusing to overwrite " <> Text.pack target)))
        else
          Right <$> case input of
            Adopt path -> pure (Round.FromInputs path)
            Capture options -> do
              let catalog = LBS.toStrict (Aeson.encode (CatalogDocument (map fromScenario (allScenarios environment.registry))))
              catalogBytes <- maybe (pure catalog) BS.readFile options.catalog
              graphBytes <- maybe (pure environment.componentGraph) BS.readFile options.graph
              pure $
                Round.Fresh $
                  Round.FreshInputs
                    options.owners
                    catalogBytes
                    options.packageMap
                    graphBytes
                    options.baseline
                    options.candidate
                    (loadPublished config.owners options.published options.baselineRuns)
                    options.coverage
                    options.scopeOverrides

loadPublished :: OwnerConfig -> PublishedOptions -> FilePath -> IO (Either Text [Run.Observation])
loadPublished config (PublishedOptions bundleOption uriOption dataRoot) file = runExceptT do
  requests <- lift (BS.readFile file) >>= except . first (\message -> Text.pack file <> ": " <> Text.pack message) . Aeson.eitherDecodeStrict'
  if null requests
    then pure []
    else do
      env <- lift getEnvironment
      settings <- ExceptT (resolveEvidenceDefaults (envSnapshot [(Text.pack name, Text.pack setting) | (name, setting) <- env]) (ConfigInputs [] [] NoDiagnostic))
      defaults <- except (first Settei.renderErrorsText settings.answer)
      root <- lift (makeAbsolute (fromMaybe (Text.unpack defaults.bundleRoot) (bundleOption <|> config.evidenceBundle)))
      let uri = uriOption <|> config.evidenceBundleUri <|> defaults.bundleUri
          locator = fromMaybe (\_ _ -> pure Nothing) (fmap Run.directoryRunData dataRoot <|> config.runDataLocator)
      observations <- ExceptT (Run.loadSelectedPublishedObservations locator root uri requests)
      traverse (qualify root uri) observations
  where
    qualify root uri observation = do
      let source = case observation.source of
            Run.PublishedRecord concept ->
              Run.PublishedRecord $
                maybe (Text.pack (root </> Text.unpack concept <> ".md")) (\bundleUri -> bundleUri <> "/concepts/" <> concept) uri
            sealed -> sealed
          qualified = observation {Run.source = source}
      replay <- ExceptT (config.replayObservation qualified)
      pure qualified {Run.replay = replay}

roundError :: Text -> Round.RoundError -> IO ExitCode
roundError subcommand err = do
  let (code, message) = case err of
        Round.RoundUsage problem -> (2, problem)
        Round.RoundInput problem -> (4, problem)
  Text.IO.hPutStrLn stderr ("kenshou round " <> subcommand <> ": " <> message)
  pure (ExitFailure code)
