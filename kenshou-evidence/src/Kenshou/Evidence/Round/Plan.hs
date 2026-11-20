-- | Build ordinary executable plans and account for the selected and omitted work.
module Kenshou.Evidence.Round.Plan
  ( Omission (..),
    OwnerCoverage (..),
    RoundCoverage (..),
    planRound,
    planRoundWithSelectors,
    writeRoundPlan,
    roundPlanPaths,
  )
where

import Control.Applicative ((<|>))
import Control.Exception (IOException, try)
import Control.Monad (unless)
import Control.Monad.Trans.Class (lift)
import Data.Aeson hiding (decode)
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Kenshou.Core.Id (RunId, ScenarioId, renderScenarioId)
import Kenshou.Core.RunSpec (RunSpec (..))
import Kenshou.Core.Scenario (KnownDefect (..), individualKnownDefects)
import Kenshou.Evidence.Owner qualified as Owner
import Kenshou.Evidence.Round
import Kenshou.Evidence.Round.Storage
import Kenshou.Plan.Catalog (ScenarioInfo (..))
import Kenshou.Plan.Change
import Kenshou.Plan.Change.Cohort (diffResolvedCohorts)
import Kenshou.Plan.Components qualified as Components
import Kenshou.Plan.Policy (PlanPolicy)
import Kenshou.Plan.RunPlan hiding (planId)
import Kenshou.Plan.RunPlan qualified as RunPlan
import Kenshou.Plan.Selector (Selector, parseSelector, renderSelector)
import System.Directory (createDirectoryIfMissing, getSymbolicLinkTarget)
import System.FilePath ((</>))
import System.IO.Error (isAlreadyExistsError)
import System.Posix.Files (createSymbolicLink)

data Omission = Omission
  { scenario :: Maybe ScenarioId,
    reason :: Text,
    detail :: Text
  }
  deriving stock (Eq, Ord, Show)

data OwnerCoverage = OwnerCoverage
  { planned :: [ScenarioId],
    omitted :: [Omission]
  }
  deriving stock (Eq, Show)

data RoundCoverage = RoundCoverage
  { roundId :: Text,
    mode :: RoundMode,
    arm :: Arm,
    owners :: Map Text OwnerCoverage,
    selected :: [Value],
    omissions :: [Omission],
    estimateMinutes :: Int,
    planId :: Maybe RunId
  }
  deriving stock (Eq, Show)

planRound :: RoundDefinition -> RoundInputs -> Arm -> PlanPolicy -> (PlanSkeleton, RoundCoverage)
planRound definition inputs arm policy =
  let (_, skeleton, coverage) = planRoundWithSelectors definition inputs arm policy [] []
   in (skeleton, coverage)

planRoundWithSelectors ::
  RoundDefinition ->
  RoundInputs ->
  Arm ->
  PlanPolicy ->
  [Selector] ->
  [Selector] ->
  ([Selected], PlanSkeleton, RoundCoverage)
planRoundWithSelectors definition inputs arm policy includes excludes = (kept, skeleton, coverage)
  where
    (cohortName, cohortPlanHash) = case arm of
      Baseline -> definition.baselineCohort
      Candidate -> definition.candidateCohort
    (changes, warnings) = diffResolvedCohorts inputs.graph inputs.baselineIdentity inputs.candidateIdentity
    refresh = case definition.mode of
      ReleaseRefresh -> selectAll inputs.catalog
      ChangeOnly -> selectScenarios inputs.graph inputs.catalog changes
    scenarioIds = Set.fromList (map (.id) inputs.catalog)
    ownerRefs = Map.fromList [(entry.reference, fromMaybe entry.reference entry.canonical) | entry <- inputs.owners.records]
    ownerScenarios =
      Map.fromListWith Set.union $
        [ (canonical, Set.singleton info.id)
        | info <- inputs.catalog,
          declaration <- maybe [] pure info.knownDefect,
          defect <- individualKnownDefects declaration,
          Just canonical <- [Map.lookup defect.reference ownerRefs]
        ]
          <> [ (owner, Set.singleton scenario)
             | entry <- inputs.owners.records,
               let owner = fromMaybe entry.reference entry.canonical,
               (citation, _) <- entry.citedBy,
               Owner.CitedByScenario scenario _ <- [citation.citer],
               Set.notMember scenario scenarioIds
             ]
    reproductions =
      concat
        [ selectBySelectors OwnerReproduction owner (mapMaybeSelector scenarios) inputs.catalog
        | (owner, scenarios) <- Map.toAscList ownerScenarios
        ]
    mapMaybeSelector scenarios = [selector | scenario <- Set.toAscList scenarios, Right selector <- [parseSelector (renderScenarioId scenario)]]
    combined =
      Map.fromListWith merge [(entry.scenario.id, entry) | entry <- reproductions <> refresh]
    -- The refresh selection carries graph policy requirements. Combining reasons
    -- keeps those requirements and every owner reference.
    merge refreshOrOwner earlier =
      Selected
        earlier.scenario
        (earlier.reasons <> refreshOrOwner.reasons)
        (refreshOrOwner.minPolicy <|> earlier.minPolicy)
        (refreshOrOwner.minKnobPolicy <|> earlier.minKnobPolicy)
    kept = applySelectors includes excludes (Map.elems combined)
    keptIds = Set.fromList [entry.scenario.id | entry <- kept]
    selectInputs =
      object
        [ "roundId" .= definition.roundId,
          "roundMode" .= definition.mode,
          "arm" .= arm,
          "select" .= map renderSelector includes,
          "exclude" .= map renderSelector excludes
        ]
    context =
      PlanContext
        Nothing
        (Components.graphDigest inputs.graph)
        cohortName
        cohortPlanHash
        (PlanInputs selectInputs)
        changes
        (map (.message) warnings)
    built = buildPlan context policy kept
    excluded =
      [ Skipped scenario SkipExcluded "removed by round plan selectors"
      | scenario <- Set.toAscList (Map.keysSet combined Set.\\ keptIds)
      ]
    skeleton = PlanSkeleton built.context built.policy built.runs (built.skipped <> excluded) built.estimateMinutes
    planned = Set.fromList [run.spec.scenario | run <- skeleton.runs]
    omissions =
      [Omission (Just item.scenario) (renderSkipReason item.reason) item.detail | item <- skeleton.skipped]
        <> [Omission (Just scenario) "not-selected" "outside change selection" | scenario <- Set.toAscList (scenarioIds Set.\\ Map.keysSet combined)]
        <> [Omission (Just scenario) "not-in-catalog" "owner snapshot cites a scenario absent from the frozen catalog" | scenario <- Set.toAscList (Set.unions (Map.elems ownerScenarios) Set.\\ scenarioIds)]
        <> [Omission Nothing "unmapped-change" warning.message | warning <- warnings, warning.code == "unmapped-package"]
    forOwner scenarios =
      OwnerCoverage
        (Set.toAscList (Set.intersection scenarios planned))
        [item | item <- omissions, Just scenario <- [item.scenario], Set.member scenario scenarios]
    coverage =
      RoundCoverage
        definition.roundId
        definition.mode
        arm
        (Map.map forOwner ownerScenarios)
        [object ["scenario" .= entry.scenario.id, "reasons" .= entry.reasons] | entry <- Map.elems combined]
        omissions
        skeleton.estimateMinutes
        Nothing

-- | The two flat filenames resolve together when their shared directory is
-- published. An interrupted writer's dangling aliases can be reused on retry.
writeRoundPlan :: FilePath -> Text -> PlanSkeleton -> RoundCoverage -> IO (Either RoundError RunPlan)
writeRoundPlan roundDir name skeleton coverage = runRoundIO do
  requireName name
  requireUnused target
  lift (createDirectoryIfMissing True root)
  createDirectoryOnce target \stage -> do
    plan <- lift (stampPlan skeleton)
    lift $ LBS.writeFile (stage </> "run-plan.json") (encode plan)
    lift $ LBS.writeFile (stage </> "coverage.json") (encode coverage {planId = Just (RunPlan.planId plan)})
    alias planFile (Text.unpack name </> "run-plan.json")
    alias coverageFile (Text.unpack name </> "coverage.json")
    pure plan
  where
    root = roundDir </> "plans"
    target = root </> Text.unpack name
    (planFile, coverageFile) = roundPlanPaths roundDir name
    alias path destination = do
      linked <- lift (try @IOException (createSymbolicLink destination path))
      case linked of
        Right () -> pure ()
        Left err
          | isAlreadyExistsError err -> do
              existing <- lift (try @IOException (getSymbolicLinkTarget path))
              unless
                (either (const False) (== destination) existing)
                (usageError ("refusing to overwrite " <> Text.pack path))
          | otherwise -> lift (ioError err)

roundPlanPaths :: FilePath -> Text -> (FilePath, FilePath)
roundPlanPaths roundDir name =
  (base <> ".run-plan.json", base <> ".coverage.json")
  where
    base = roundDir </> "plans" </> Text.unpack name

instance ToJSON Omission where
  toJSON item = object ["scenario" .= item.scenario, "reason" .= item.reason, "detail" .= item.detail]

instance FromJSON Omission where
  parseJSON = withObject "coverage omission" \item ->
    Omission <$> item .: "scenario" <*> item .: "reason" <*> item .: "detail"

instance ToJSON OwnerCoverage where
  toJSON item = object ["planned" .= item.planned, "omitted" .= item.omitted]

instance FromJSON OwnerCoverage where
  parseJSON = withObject "owner coverage" \item ->
    OwnerCoverage <$> item .: "planned" <*> item .: "omitted"

instance ToJSON RoundCoverage where
  toJSON coverage =
    object
      [ "schema" .= ("kenshou.round-coverage/v1" :: Text),
        "roundId" .= coverage.roundId,
        "mode" .= coverage.mode,
        "arm" .= coverage.arm,
        "owners" .= coverage.owners,
        "selected" .= coverage.selected,
        "omissions" .= coverage.omissions,
        "estimateMinutes" .= coverage.estimateMinutes,
        "planId" .= coverage.planId
      ]

instance FromJSON RoundCoverage where
  parseJSON = withObject "round coverage" \document -> do
    schema <- document .: "schema"
    unless (schema == ("kenshou.round-coverage/v1" :: Text)) (fail "unsupported round coverage schema")
    RoundCoverage
      <$> document .: "roundId"
      <*> document .: "mode"
      <*> document .: "arm"
      <*> document .: "owners"
      <*> document .: "selected"
      <*> document .: "omissions"
      <*> document .: "estimateMinutes"
      <*> document .:? "planId"
