-- | Evidence for one run, with labels read only from the verified result bytes.
module Kenshou.Evidence.Observation
  ( Trust (..),
    renderTrust,
    ObservationSource (..),
    Labels (..),
    Observation (..),
    RunDataLocator,
    directoryRunData,
    objectStoreRunData,
    loadPublishedObservations,
    loadSealedObservation,
    mergeObservations,
  )
where

import Control.Exception (IOException, try)
import Data.Aeson (Value, eitherDecodeStrict', withObject, (.!=), (.:), (.:?))
import Data.Aeson.Types (Parser, parseEither)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Format.ISO8601 (iso8601Show)
import Kenshou.Core.Cohort (CohortIdentity (..), CohortName (..), PlanHash (..))
import Kenshou.Core.Defect (ScopePackage (..), ScopeSource (..), cohortScopePackages)
import Kenshou.Core.Id (ScenarioId, parseRunId, renderRunId)
import Kenshou.Core.Outcome (Outcome)
import Kenshou.Evidence.Frontmatter ()
import Kenshou.Evidence.History (HistoryEntry (..), HistoryError (..), historyEntries)
import Kenshou.Evidence.Source (RunResultView (..), RunSource (..), SourceError (..), loadRunSource)
import Kenshou.Evidence.Store (ObjectStore (..))
import Kenshou.Evidence.Types (ComponentRef (..), ComponentSource (..), DataKind (..), DataLink (..), Revision (..), Sha256 (..), sha256Bytes)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

data Trust = HumanReviewed | MachineConfirmed | Unverified | LocalSealed
  deriving stock (Eq, Show, Enum, Bounded)

renderTrust :: Trust -> Text
renderTrust = \case
  HumanReviewed -> "human-reviewed"
  MachineConfirmed -> "machine-confirmed"
  Unverified -> "unverified"
  LocalSealed -> "local-sealed"

data ObservationSource = PublishedRecord Text | SealedRun FilePath
  deriving stock (Eq, Show)

data Labels = LabelsVerified [Text] | LabelsUnavailable Text
  deriving stock (Eq, Show)

data Observation = Observation
  { runId :: Text,
    source :: ObservationSource,
    scenario :: ScenarioId,
    scenarioRevision :: Maybe Int,
    startedAt :: Text,
    outcome :: Outcome,
    labels :: Labels,
    packages :: [ScopePackage],
    cohortName :: Text,
    planHash :: Text,
    trust :: Trust,
    replay :: Maybe Value
  }
  deriving stock (Eq, Show)

type RunDataLocator = Text -> DataLink -> IO (Maybe ByteString)

directoryRunData :: FilePath -> RunDataLocator
directoryRunData root identifier _ = case parseRunId identifier of
  Left _ -> pure Nothing
  Right run -> optionalRead (root </> Text.unpack (renderRunId run) </> "run-result.json")

objectStoreRunData :: ObjectStore -> RunDataLocator
objectStoreRunData store _ link =
  withSystemTempDirectory "kenshou-observation" \scratch -> do
    let target = scratch </> "run-result.json"
    fetched <- store.fetchObject link.uri target
    case fetched of
      Left _ -> pure Nothing
      Right () -> optionalRead target

optionalRead :: FilePath -> IO (Maybe ByteString)
optionalRead path = either (const Nothing) Just <$> (try (ByteString.readFile path) :: IO (Either IOException ByteString))

-- | The source of a published observation is its bundle-relative concept path.
loadPublishedObservations :: RunDataLocator -> FilePath -> IO (Either Text [Observation])
loadPublishedObservations locate root = do
  entries <- historyEntries root
  case entries of
    Left (HistoryError problem) -> pure (Left problem)
    Right history -> fmap sequence . traverse loadPublished $ filter ((== "run") . (.recordKind)) history
  where
    loadPublished entry = case first (\message -> entry.concept <> ": " <> Text.pack message) (parseEither (parseRecord entry) entry.record) of
      Left problem -> pure (Left problem)
      Right (observation, links) -> Right <$> loadLabels locate observation links

    parseRecord :: HistoryEntry -> Value -> Parser (Observation, [DataLink])
    parseRecord entry = withObject "verification run" \record -> do
      runId <- renderRunId <$> record .: "runId"
      scenario <- record .: "scenario"
      outcome <- record .: "outcome"
      cohortName <- record .: "cohort"
      Sha256 hash <- record .: "solverPlanHash"
      components <- record .: "components"
      links <- record .:? "data" .!= []
      let source = PublishedRecord entry.concept
          trust = case entry.trust of
            "human-reviewed" -> HumanReviewed
            "machine-confirmed" -> MachineConfirmed
            _ -> Unverified
          observation = Observation runId source scenario Nothing entry.startedAt outcome (LabelsUnavailable "run-data-missing") (map componentPackage components) cohortName ("sha256:" <> hash) trust Nothing
      pure (observation, links)

    componentPackage :: ComponentRef -> ScopePackage
    componentPackage component =
      ScopePackage component.package component.version $ case component.source of
        FromHackage -> ScopeHackage
        FromGit -> ScopeGit (maybe "" (\(Revision revision) -> revision) component.revision)

loadLabels :: RunDataLocator -> Observation -> [DataLink] -> IO Observation
loadLabels locate observation links = case filter ((== RunResultData) . (.kind)) links of
  [] -> pure observation
  [link] -> do
    contents <- locate observation.runId link
    pure case contents of
      Nothing -> observation
      Just bytes
        | sha256Bytes bytes /= link.digest -> unavailable "run-data-digest-mismatch"
        | otherwise -> case eitherDecodeStrict' bytes of
            Left _ -> unavailable "run-data-invalid"
            Right result
              | renderRunId result.resultRunId == observation.runId,
                result.resultScenario == observation.scenario,
                unPlanHash result.resultCohort.identityPlanHash == observation.planHash ->
                  observation
                    { scenarioRevision = result.resultScenarioRevision,
                      labels = resultLabels result
                    }
              | otherwise -> unavailable "run-data-identity-mismatch"
  _ -> pure (unavailable "run-data-ambiguous")
  where
    unavailable reason = observation {labels = LabelsUnavailable reason}

resultLabels :: RunResultView -> Labels
resultLabels result = maybe (LabelsUnavailable "labels-absent") LabelsVerified result.resultFailures

loadSealedObservation :: FilePath -> IO (Either Text Observation)
loadSealedObservation root = fmap (first (\(SourceError message) -> Text.pack root <> ": " <> message) . fmap fromRun) (loadRunSource root)
  where
    fromRun run =
      let result = run.result
          cohort = result.resultCohort
       in Observation
            { runId = renderRunId result.resultRunId,
              source = SealedRun root,
              scenario = result.resultScenario,
              scenarioRevision = result.resultScenarioRevision,
              startedAt = Text.pack (iso8601Show result.resultStartedAt),
              outcome = result.resultOutcome,
              labels = resultLabels result,
              packages = cohortScopePackages cohort,
              cohortName = unCohortName cohort.identityCohort,
              planHash = unPlanHash cohort.identityPlanHash,
              trust = LocalSealed,
              replay = Nothing
            }

-- | Prefer the published record when a run is also available locally.
mergeObservations :: [Observation] -> [Observation] -> [Observation]
mergeObservations published sealed = Map.elems (Map.fromListWith (flip const) [(run.runId, run) | run <- published <> sealed])
