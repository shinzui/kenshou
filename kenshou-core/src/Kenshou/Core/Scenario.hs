module Kenshou.Core.Scenario
  ( Tier (..),
    Placement (..),
    KnownDefect (..),
    individualKnownDefects,
    CohortScope (..),
    PackageCondition (..),
    cohortScopeApplies,
    conditionPackage,
    ScopeSource (..),
    ScopePackage (..),
    cohortScopePackages,
    ConditionResult (..),
    ScopeEvaluation (..),
    evaluateScope,
    scopeApplies,
    parseScopeVersion,
    ScenarioReport (..),
    Scenario (..),
    renderTier,
    renderPlacement,
    passed,
    failedWith,
    inconclusiveBecause,
    infrastructureFailureBecause,
  )
where

import Data.List.NonEmpty (NonEmpty)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Version (Version, parseVersion)
import Kenshou.Core.Cohort (CohortIdentity (..), PackageSource (..), ResolvedComponent (..), ResolvedPackage (..))
import Kenshou.Core.Context (RunContext)
import Kenshou.Core.Dimension (DimensionSupport)
import Kenshou.Core.Env (EnvRequirements)
import Kenshou.Core.Id (ScenarioId)
import Kenshou.Core.Knob (KnobSpec)
import Kenshou.Core.Outcome (Outcome (..))
import Kenshou.Core.Phase (PhasePlan)
import Text.ParserCombinators.ReadP (readP_to_S)

data Tier = TierSmoke | TierStandard | TierExtended | TierSoak deriving stock (Eq, Ord, Show)

data Placement = PlaceLocal | PlaceCell | PlaceEither deriving stock (Eq, Ord, Show)

data KnownDefect
  = KnownDefect
      { reference :: Text,
        summary :: Text,
        expectedFailures :: [Text],
        appliesTo :: CohortScope
      }
  | KnownDefectGroup (NonEmpty KnownDefect)
  deriving stock (Eq, Show)

individualKnownDefects :: KnownDefect -> [KnownDefect]
individualKnownDefects (KnownDefectGroup defects) = concatMap individualKnownDefects defects
individualKnownDefects defect = [defect]

data CohortScope = AllCohorts | OnlyWhen (NonEmpty PackageCondition) deriving stock (Eq, Show)

data PackageCondition
  = ResolvedFromHackage Text
  | ResolvedFromGit Text
  | VersionBelow Text Text
  | RevisionIs Text Text
  deriving stock (Eq, Show)

-- | Whether a scope applies to a resolved cohort: 'AllCohorts' always does, and
-- 'OnlyWhen' does when every condition holds for at least one resolved package.
-- Defined through 'evaluateScope', the only scope evaluator.
cohortScopeApplies :: CohortIdentity -> CohortScope -> Bool
cohortScopeApplies cohort scope = scopeApplies (evaluateScope (cohortScopePackages cohort) scope)

-- | Where a package the scope evaluator sees was resolved from. A Git source
-- carries its exact revision; any other source (boot, local path) is 'ScopeOther'.
data ScopeSource = ScopeHackage | ScopeGit Text | ScopeOther
  deriving stock (Eq, Show)

-- | A resolved package as the scope evaluator sees it. Both a run's resolved
-- cohort ('cohortScopePackages') and an evidence record's component list convert
-- to this.
data ScopePackage = ScopePackage
  { name :: Text,
    version :: Text,
    source :: ScopeSource
  }
  deriving stock (Eq, Show)

-- | Every package of every component of a resolved cohort, in order.
cohortScopePackages :: CohortIdentity -> [ScopePackage]
cohortScopePackages cohort =
  [ ScopePackage {name = package.resolvedPackageName, version = package.resolvedPackageVersion, source = scopeSource package.resolvedPackageSource}
  | component <- cohort.identityComponents,
    package <- component.resolvedComponentPackages
  ]
  where
    scopeSource = \case
      FromHackage _ -> ScopeHackage
      FromGit _ revision _ -> ScopeGit revision
      _ -> ScopeOther

-- | Why a condition does or does not hold. 'ConditionFails' means a package of
-- the named package is present but none satisfies the condition;
-- 'ConditionPackageMissing' that no package of that name is present;
-- 'ConditionMalformed' that a version text did not parse (the bound, or the
-- resolved version of a package of that name), naming the text.
data ConditionResult
  = ConditionHolds
  | ConditionFails
  | ConditionPackageMissing
  | ConditionMalformed Text
  deriving stock (Eq, Show)

-- | A scope's evaluation, condition by condition.
data ScopeEvaluation
  = AppliesToAll
  | Evaluated (NonEmpty (PackageCondition, ConditionResult))
  deriving stock (Eq, Show)

-- | Evaluate a scope against resolved packages, explaining each condition.
evaluateScope :: [ScopePackage] -> CohortScope -> ScopeEvaluation
evaluateScope _ AllCohorts = AppliesToAll
evaluateScope packages (OnlyWhen conditions) = Evaluated (fmap (\condition -> (condition, evaluateCondition packages condition)) conditions)

evaluateCondition :: [ScopePackage] -> PackageCondition -> ConditionResult
evaluateCondition packages condition
  | null named = ConditionPackageMissing
  | any satisfies named = ConditionHolds
  | VersionBelow _ bound <- condition, Nothing <- parseScopeVersion bound = ConditionMalformed bound
  | VersionBelow _ _ <- condition, unparsed : _ <- [package.version | package <- named, Nothing <- [parseScopeVersion package.version]] = ConditionMalformed unparsed
  | otherwise = ConditionFails
  where
    named = [package | package <- packages, package.name == conditionPackage condition]
    satisfies package = case condition of
      ResolvedFromHackage _ -> package.source == ScopeHackage
      ResolvedFromGit _ -> case package.source of ScopeGit _ -> True; _ -> False
      VersionBelow _ bound -> maybe False (uncurry (<)) ((,) <$> parseScopeVersion package.version <*> parseScopeVersion bound)
      RevisionIs _ revision -> package.source == ScopeGit revision

-- | The package a condition names.
conditionPackage :: PackageCondition -> Text
conditionPackage = \case
  ResolvedFromHackage package -> package
  ResolvedFromGit package -> package
  VersionBelow package _ -> package
  RevisionIs package _ -> package

-- | Reduce an evaluation to whether the scope applies: every condition holds. A
-- missing package or a malformed version does not hold.
scopeApplies :: ScopeEvaluation -> Bool
scopeApplies AppliesToAll = True
scopeApplies (Evaluated results) = all ((== ConditionHolds) . snd) results

-- | The version parser for scope bounds and resolved versions: the longest
-- complete parse of 'Data.Version.parseVersion'. Owner version claims are parsed
-- with it too, so an owner's version and a scope's bound are always read alike.
parseScopeVersion :: Text -> Maybe Version
parseScopeVersion value = case [version | (version, "") <- readP_to_S parseVersion (Text.unpack value)] of
  [] -> Nothing
  versions -> Just (last versions)

data ScenarioReport = ScenarioReport
  { outcome :: Outcome,
    reason :: Maybe Text,
    failures :: [Text]
  }
  deriving stock (Eq, Show)

data Scenario = Scenario
  { id :: ScenarioId,
    revision :: Int,
    summary :: Text,
    tier :: Tier,
    placement :: Placement,
    knobs :: [KnobSpec],
    dimensions :: DimensionSupport,
    phases :: PhasePlan,
    requires :: EnvRequirements,
    knownDefect :: Maybe KnownDefect,
    run :: RunContext -> IO ScenarioReport
  }

renderTier :: Tier -> Text
renderTier TierSmoke = "smoke"
renderTier TierStandard = "standard"
renderTier TierExtended = "extended"
renderTier TierSoak = "soak"

renderPlacement :: Placement -> Text
renderPlacement PlaceLocal = "local"
renderPlacement PlaceCell = "cell"
renderPlacement PlaceEither = "either"

passed :: ScenarioReport
passed = ScenarioReport Passed Nothing []

failedWith :: [Text] -> Text -> ScenarioReport
failedWith labels message = ScenarioReport Failed (Just message) labels

inconclusiveBecause :: Text -> ScenarioReport
inconclusiveBecause message = ScenarioReport Inconclusive (Just message) []

infrastructureFailureBecause :: Text -> ScenarioReport
infrastructureFailureBecause message = ScenarioReport InfrastructureFailure (Just message) []
