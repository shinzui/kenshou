-- | Freeze candidate evidence, along with the exact plans and execution
-- summaries used to identify attempts.
module Kenshou.Evidence.Round.Evaluation
  ( Evaluation (..),
    EvaluationOptions (..),
    EvaluationPlan (..),
    ExecutionSummary (..),
    FrozenDocument (artifact, decoded),
    createEvaluation,
    readEvaluation,
  )
where

import Control.Monad (unless, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), except)
import Data.Aeson
import Data.Aeson.Types (Parser)
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.List (sort)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time (UTCTime, getCurrentTime)
import Kenshou.Core.Canonical (sha256Hex)
import Kenshou.Core.Id (parseRunId)
import Kenshou.Core.RunSpec (CohortExpectation (..), RunSpec (..))
import Kenshou.Evidence.Disposition (observationValue)
import Kenshou.Evidence.Observation qualified as Run
import Kenshou.Evidence.Round
import Kenshou.Evidence.Round.Plan
import Kenshou.Evidence.Round.Storage
import Kenshou.Plan.Execute (ExecutablePlan (..), ExecutableRun (..))
import Kenshou.Plan.Summary (PlanSummary)
import System.Directory (doesFileExist, listDirectory, makeAbsolute)
import System.FilePath ((</>))

data EvaluationOptions = EvaluationOptions
  { roundDirectory :: FilePath,
    evaluationId :: Text,
    published :: Maybe (IO (Either Text [Run.Observation])),
    sealedRoots :: [FilePath],
    planName :: Maybe Text,
    comparisons :: [FilePath],
    allowEmpty :: Bool
  }

data Evaluation = Evaluation
  { evaluationId :: Text,
    createdAt :: UTCTime,
    roundDigest :: Text,
    candidate :: [Run.Observation],
    plan :: Maybe EvaluationPlan,
    summaries :: [ExecutionSummary],
    comparisons :: [ArtifactReference]
  }
  deriving stock (Eq, Show)

data EvaluationPlan = EvaluationPlan
  { name :: Text,
    runPlanDocument :: FrozenDocument ExecutablePlan,
    coverageDocument :: FrozenDocument RoundCoverage
  }
  deriving stock (Eq, Show)

newtype ExecutionSummary = ExecutionSummary {document :: FrozenDocument PlanSummary}
  deriving stock (Eq, Show)

-- Keep the original JSON text so a replay can verify the digest and decode the
-- exact captured document, even if the external artifact has moved.
data FrozenDocument a = FrozenDocument
  { artifact :: ArtifactReference,
    contents :: Text,
    decoded :: a
  }
  deriving stock (Eq, Show)

createEvaluation :: EvaluationOptions -> IO (Either RoundError Evaluation)
createEvaluation options = runRoundIO do
  requireName options.evaluationId
  let target = options.roundDirectory </> "evaluations" </> Text.unpack options.evaluationId
  requireUnused target
  (definition, _, roundDigest) <- ExceptT (readRoundWithDigest options.roundDirectory)
  unless
    (options.allowEmpty || maybe False (const True) options.published || not (null options.sealedRoots))
    (usageError "supply --candidate-runs or --runs, or pass --allow-empty")
  createDirectoryOnce target \stage -> do
    published <- maybe (pure []) (ExceptT . fmap (first RoundInput)) options.published
    requireDistinct published
    local <- concat <$> traverse readSealedRuns options.sealedRoots
    let candidate = Run.mergeObservations published local
    when (null candidate && not options.allowEmpty) (usageError "no candidate observations found; use --allow-empty to record an empty evaluation")
    plan <- traverse (capturePlan options.roundDirectory) options.planName
    summaries <- concat <$> traverse readSummary options.sealedRoots
    comparisons <- traverse (readArtifactReference "comparison") options.comparisons
    createdAt <- lift getCurrentTime
    let evaluation = Evaluation options.evaluationId createdAt roundDigest candidate plan summaries comparisons
    validateEvaluation definition evaluation
    lift (encodeFile (stage </> "evaluation.json") evaluation)
    pure evaluation
  where
    requireDistinct observed =
      unless
        (Set.size (Set.fromList (map (.runId) observed)) == length observed)
        (failRound "duplicate published candidate run identifiers")

readEvaluation :: FilePath -> Text -> RoundDefinition -> Text -> IO (Either RoundError Evaluation)
readEvaluation path name definition roundDigest = runRoundIO do
  requireName name
  let file = path </> "evaluations" </> Text.unpack name </> "evaluation.json"
  present <- lift (doesFileExist file)
  unless present (failRound ("evaluation " <> name <> " does not exist; create it with round evaluate"))
  evaluation <- readDocument (first Text.pack . eitherDecodeStrict') file
  unless (evaluation.evaluationId == name) (failRound "evaluation identifier does not match its directory")
  unless (evaluation.roundDigest == roundDigest) (failRound "evaluation does not match the round definition digest")
  validateEvaluation definition evaluation
  pure evaluation

capturePlan :: FilePath -> Text -> RoundIO EvaluationPlan
capturePlan roundDir name = do
  requireName name
  let (planPath, coveragePath) = roundPlanPaths roundDir name
  EvaluationPlan name
    <$> freezeDocument "run-plan" planPath
    <*> freezeDocument "round-coverage" coveragePath

validateEvaluation :: RoundDefinition -> Evaluation -> RoundIO ()
validateEvaluation definition evaluation = do
  let (cohortName, planHash) = definition.candidateCohort
  mapM_ (validateObservation cohortName planHash) evaluation.candidate
  mapM_ (validatePlan cohortName planHash) evaluation.plan
  where
    validateObservation cohortName planHash (observation :: Run.Observation) =
      unless
        (observation.cohortName == cohortName && observation.planHash == planHash)
        (failRound ("candidate run " <> observation.runId <> " does not match the frozen candidate cohort"))
    validatePlan cohortName planHash captured = do
      let coverage = captured.coverageDocument.decoded
          plan = captured.runPlanDocument.decoded
          matchesArm run = run.spec.cohortExpectation == Just (CohortExpectation (Just cohortName) planHash)
      unless
        ( coverage.roundId == definition.roundId
            && coverage.mode == definition.mode
            && coverage.arm == Candidate
            && coverage.planId == Just plan.planId
            && all matchesArm plan.runs
        )
        (failRound ("plan " <> captured.name <> " does not match the round's candidate arm or coverage document"))

readSealedRuns :: FilePath -> RoundIO [Run.Observation]
readSealedRuns root = do
  path <- lift (makeAbsolute root)
  single <- lift (doesFileExist (path </> "run-result.json"))
  directories <-
    if single
      then pure [path]
      else do
        entries <- lift (sort <$> listDirectory path)
        pure [path </> entry | entry <- entries, Right _ <- [parseRunId (Text.pack entry)]]
  traverse (ExceptT . fmap (first RoundInput) . Run.loadSealedObservation) directories

readSummary :: FilePath -> RoundIO [ExecutionSummary]
readSummary root = do
  let path = root </> "plan-summary.json"
  present <- lift (doesFileExist path)
  if present
    then pure <$> (ExecutionSummary <$> freezeDocument "plan-summary" path)
    else pure []

freezeDocument :: (FromJSON a) => Text -> FilePath -> RoundIO (FrozenDocument a)
freezeDocument kind requested = do
  path <- lift (makeAbsolute requested)
  bytes <- lift (BS.readFile path)
  let namedError message = RoundInput (Text.pack path <> ": " <> message)
  contents <- except (first (namedError . Text.pack . show) (Text.Encoding.decodeUtf8' bytes))
  decoded <- except (first (namedError . Text.pack) (eitherDecodeStrict' bytes))
  pure (FrozenDocument (ArtifactReference kind path (sha256Hex bytes)) contents decoded)

instance ToJSON (FrozenDocument a) where
  toJSON document = object ["artifact" .= document.artifact, "contents" .= document.contents]

instance (FromJSON a) => FromJSON (FrozenDocument a) where
  parseJSON = withObject "captured JSON document" \document -> do
    artifact <- document .: "artifact"
    contents <- document .: "contents"
    let bytes = Text.Encoding.encodeUtf8 contents
    unless (sha256Hex bytes == artifact.sha256) (fail ("captured document digest mismatch: " <> artifact.path))
    decoded <- either fail pure (eitherDecodeStrict' bytes)
    pure FrozenDocument {artifact, contents, decoded}

instance ToJSON EvaluationPlan where
  toJSON plan =
    object ["name" .= plan.name, "runPlan" .= plan.runPlanDocument, "coverage" .= plan.coverageDocument]

instance FromJSON EvaluationPlan where
  parseJSON = withObject "captured round plan" \plan ->
    EvaluationPlan <$> plan .: "name" <*> plan .: "runPlan" <*> plan .: "coverage"

instance ToJSON ExecutionSummary where
  toJSON = toJSON . (.document)

instance FromJSON ExecutionSummary where
  parseJSON = fmap ExecutionSummary . parseJSON

instance ToJSON Evaluation where
  toJSON evaluation =
    object
      [ "schema" .= ("kenshou.round-evaluation/v1" :: Text),
        "evaluationId" .= evaluation.evaluationId,
        "createdAt" .= evaluation.createdAt,
        "roundDigest" .= evaluation.roundDigest,
        "candidate" .= map observationValue evaluation.candidate,
        "plan" .= evaluation.plan,
        "summaries" .= evaluation.summaries,
        "comparisons" .= evaluation.comparisons
      ]

instance FromJSON Evaluation where
  parseJSON = withObject "round evaluation" parseEvaluation

parseEvaluation :: Object -> Parser Evaluation
parseEvaluation document = do
  schema <- document .: "schema"
  unless (schema == ("kenshou.round-evaluation/v1" :: Text)) (fail "unsupported round evaluation schema")
  Evaluation
    <$> document .: "evaluationId"
    <*> document .: "createdAt"
    <*> document .: "roundDigest"
    <*> (document .: "candidate" >>= parseObservations)
    <*> document .: "plan"
    <*> document .: "summaries"
    <*> document .: "comparisons"
