module Kenshou.Cli.Command.Round
  ( RoundConfig (..),
    defaultRoundConfig,
    roundCommand,
    roundCommandWith,
  )
where

import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), except, runExceptT)
import Data.Aeson qualified as Aeson
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.ByteString.Lazy.Char8 qualified as LBS.Char8
import Data.List (group, sort)
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Text.IO qualified as Text.IO
import Data.Time (Day, utctDay)
import Kenshou.Cli.PlanOptions
import Kenshou.Core.Bundle (allScenarios)
import Kenshou.Core.Cli (CliCommand (..), CliEnv (..), CliGroup (Analysis))
import Kenshou.Core.Cli.Config (ConfigInputs (..))
import Kenshou.Evidence.Config (EvidenceDefaults (..), resolveEvidenceDefaults)
import Kenshou.Evidence.Observation qualified as Run
import Kenshou.Evidence.Owner.Cli (OwnerConfig (..), defaultOwnerConfig)
import Kenshou.Evidence.Round qualified as Round
import Kenshou.Evidence.Round.Plan qualified as Plan
import Kenshou.Evidence.Round.Report qualified as Report
import Kenshou.Plan.Catalog (CatalogDocument (..), fromScenario)
import Kenshou.Plan.RunPlan (PlanContext (..), PlanSkeleton (..), RunPlan (..))
import Options.Applicative
import Settei qualified
import Settei.Env (envSnapshot)
import Settei.Optparse (DiagnosticMode (NoDiagnostic))
import System.Directory (makeAbsolute)
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
        <> command "plan" (info (handlePlan <$> planParser <**> helper) (progDesc "Plan reruns for one frozen cohort"))
        <> command "evaluate" (info (handleEvaluate config <$> evaluateParser <**> helper) (progDesc "Freeze candidate evidence and execution attempts"))
        <> command "report" (info (handleReport config <$> reportParser <**> helper) (progDesc "Derive a report from a frozen evaluation"))

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
  result <- Round.openRound (Round.OpenOptions identifier target mode capture references)
  case result of
    Left err -> roundError "open" err
    Right definition -> do
      Text.IO.hPutStrLn stderr ("opened round " <> definition.roundId <> " with " <> Text.pack (show (length definition.baseline)) <> " baseline observations")
      pure ExitSuccess
  where
    capture = case input of
      Adopt path -> Round.FromInputs path
      Capture options ->
        Round.Fresh $
          Round.FreshInputs
            options.owners
            (maybe (pure catalog) BS.readFile options.catalog)
            options.packageMap
            (maybe (pure environment.componentGraph) BS.readFile options.graph)
            options.baseline
            options.candidate
            (loadPublished config.owners options.published options.baselineRuns)
            options.coverage
            options.scopeOverrides
    catalog = LBS.toStrict (Aeson.encode (CatalogDocument (map fromScenario (allScenarios environment.registry))))

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

data PlanArguments = PlanArguments FilePath Round.Arm Text SelectionOptions PolicyOptions

planParser :: Parser PlanArguments
planParser =
  PlanArguments
    <$> fileOption "round" "DIR" "Opened round directory"
    <*> option (jsonWord "expected baseline or candidate") (long "arm" <> metavar "baseline|candidate" <> help "Cohort arm to plan")
    <*> textOption "out" "NAME" "Create a named run plan and coverage document"
    <*> selectionOptionsParser
    <*> policyOptionsParser

handlePlan :: PlanArguments -> CliEnv -> IO ExitCode
handlePlan (PlanArguments path arm name selectors options) _ = do
  frozen <- Round.readRound path
  seed <- makeSeed options.seedValue
  case frozen of
    Left err -> roundError "plan" err
    Right (definition, inputs) -> case (parseSelections selectors, seed >>= makePolicy options Nothing) of
      (Left problem, _) -> roundError "plan" (Round.RoundUsage problem)
      (_, Left problem) -> roundError "plan" (Round.RoundUsage problem)
      (Right (includes, excludes), Right policy) -> do
        let (selected, skeleton, coverage) = Plan.planRoundWithSelectors definition inputs arm policy includes excludes
        case validateKnobPins options selected of
          Left problem -> roundError "plan" (Round.RoundUsage problem)
          Right () -> do
            written <- Plan.writeRoundPlan path name skeleton coverage
            case written of
              Left err -> roundError "plan" err
              Right plan -> do
                Text.IO.hPutStrLn stderr $
                  "planned "
                    <> Text.pack (show (length plan.runs))
                    <> " runs for "
                    <> skeleton.context.cohortName
                    <> " ("
                    <> skeleton.context.cohortPlanHash
                    <> "); activate this cohort before executing"
                pure ExitSuccess

data EvaluateArguments = EvaluateArguments FilePath Text (Maybe FilePath) PublishedOptions [FilePath] (Maybe Text) [FilePath] Bool

evaluateParser :: Parser EvaluateArguments
evaluateParser =
  EvaluateArguments
    <$> fileOption "round" "DIR" "Opened round directory"
    <*> textOption "id" "ID" "Create an evaluation with this identifier"
    <*> optional (fileOption "candidate-runs" "FILE" "JSON array of explicit candidate run IDs or concept references")
    <*> publishedParser
    <*> many (fileOption "runs" "DIR" "Read sealed local runs, optionally with a plan summary")
    <*> optional (textOption "plan" "NAME" "Freeze this round plan and its coverage")
    <*> many (fileOption "comparison" "PATH" "Link a separate comparison artifact by path and digest")
    <*> switch (long "allow-empty" <> help "Allow a deliberately empty evaluation")

handleEvaluate :: RoundConfig -> EvaluateArguments -> CliEnv -> IO ExitCode
handleEvaluate config (EvaluateArguments path identifier selected publishedOptions runs plan comparisons allowEmpty) _ = do
  let published = loadPublished config.owners publishedOptions <$> selected
  result <- Report.createEvaluation (Report.EvaluationOptions path identifier published runs plan comparisons allowEmpty)
  case result of
    Left err -> roundError "evaluate" err
    Right evaluation -> do
      let trusts = map (Run.renderTrust . (.trust)) evaluation.candidate
          counts = [trust <> "=" <> Text.pack (show (length same)) | same@(trust : _) <- group (sort trusts)]
      Text.IO.hPutStrLn stderr $
        Text.unwords (["froze", Text.pack (show (length trusts)), "candidate observations"] <> counts)
      pure ExitSuccess

data ReportArguments = ReportArguments FilePath Text Bool (Maybe FilePath)

reportParser :: Parser ReportArguments
reportParser =
  ReportArguments
    <$> fileOption "round" "DIR" "Opened round directory"
    <*> textOption "evaluation" "ID" "Replay this existing frozen evaluation"
    <*> switch (long "json" <> help "Emit kenshou.round-report/v1 JSON")
    <*> optional (fileOption "write-report" "PATH" "Create a dated Markdown rendering")

handleReport :: RoundConfig -> ReportArguments -> CliEnv -> IO ExitCode
handleReport config (ReportArguments path identifier asJson output) _ = do
  result <- runExceptT do
    (definition, inputs, digest) <- ExceptT (Round.readRoundWithDigest path)
    evaluation <- ExceptT (Report.readEvaluation path identifier definition digest)
    report <- except (Report.roundReport definition inputs evaluation)
    let reportPath = output <|> fmap (\destination -> destination definition.roundId (utctDay evaluation.createdAt)) config.reportPath
    mapM_ (\target -> ExceptT (Round.writeFileOnce target (Text.Encoding.encodeUtf8 (Report.renderRoundReportMarkdown report)))) reportPath
    pure report
  case result of
    Left err -> roundError "report" err
    Right report -> do
      if asJson
        then LBS.Char8.putStrLn (Aeson.encode (Report.roundReportValue report))
        else Text.IO.putStr (Report.renderRoundReportText report)
      pure (Report.reportExitCode report)

roundError :: Text -> Round.RoundError -> IO ExitCode
roundError subcommand err = do
  let (code, message) = case err of
        Round.RoundUsage problem -> (2, problem)
        Round.RoundInput problem -> (4, problem)
  Text.IO.hPutStrLn stderr ("kenshou round " <> subcommand <> ": " <> message)
  pure (ExitFailure code)
