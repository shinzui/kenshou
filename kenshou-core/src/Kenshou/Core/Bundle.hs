module Kenshou.Core.Bundle
  ( LayerBundle (..),
    mkBundle,
    Registry,
    registryMigrationSets,
    RegistryError (..),
    ListFilter (..),
    emptyListFilter,
    mkRegistry,
    allScenarios,
    allRoles,
    lookupScenario,
    lookupRole,
    selectScenarios,
    scenarioListDocument,
    scenarioListDocumentFor,
  )
where

import Data.Aeson (Value, object, toJSON, (.=))
import Data.List (group, sort, sortOn)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Kenshou.Core.Dimension (DimensionSupport (..), PgDurability (..), Support (..), Supported (..))
import Kenshou.Core.Env (EnvRequirements (..), MigrationSet (..), MigrationSetName, PostgresRequirement (..), mkMigrationSetName, renderMigrationSetName)
import Kenshou.Core.Id (Kind (..), LayerId, ScenarioId (..), renderKind, renderLayer, renderScenarioId, unSegment)
import Kenshou.Core.Knob (KnobSpec (..), renderKnobName)
import Kenshou.Core.Role (RoleName, WorkerRole (..), renderRoleName)
import Kenshou.Core.Scenario (KnownDefect (..), Placement, Scenario (..), Tier, individualKnownDefects, renderPlacement, renderTier)
import Kenshou.Core.Selector (ScenarioSelector, matchesSelector)
import Kenshou.Core.Version (suiteVersion)

-- | What a suite registers with the kernel. Build one with 'mkBundle' and set the
-- optional contributions with record update, so new fields never break a suite.
data LayerBundle = LayerBundle
  { layer :: LayerId,
    scenarios :: [Scenario],
    roles :: [WorkerRole],
    -- | Migration sets this bundle defines. Any scenario in the registry may
    -- require them by name.
    migrations :: [MigrationSet]
  }

mkBundle :: LayerId -> [Scenario] -> [WorkerRole] -> LayerBundle
mkBundle layer scenarios roles = LayerBundle {layer, scenarios, roles, migrations = []}

newtype Registry = Registry [LayerBundle]

newtype RegistryError = RegistryError Text
  deriving stock (Eq, Show)

data ListFilter = ListFilter
  { selectors :: [ScenarioSelector],
    layers :: [LayerId],
    kinds :: [Kind],
    maxTier :: Maybe Tier,
    placements :: [Placement]
  }

emptyListFilter :: ListFilter
emptyListFilter = ListFilter [] [] [] Nothing []

mkRegistry :: [LayerBundle] -> Either (NonEmpty RegistryError) Registry
mkRegistry bundles = case errors of
  [] -> Right (Registry bundles)
  first : rest -> Left (first :| rest)
  where
    scenarios = concatMap (.scenarios) bundles
    roles = concatMap (.roles) bundles
    errors =
      [RegistryError ("scenario layer differs from bundle: " <> renderScenarioId scenario.id) | bundle <- bundles, scenario <- bundle.scenarios, scenario.id.layer /= bundle.layer]
        <> duplicateErrors "scenario" (fmap (renderScenarioId . (.id)) scenarios)
        <> duplicateErrors "role" (fmap (renderRoleName . (.name)) roles)
        <> [RegistryError ("role layer differs from bundle: " <> renderRoleName role.name) | bundle <- bundles, role <- bundle.roles, not ((renderLayer bundle.layer <> "/") `Text.isPrefixOf` renderRoleName role.name)]
        <> concatMap validateScenario scenarios
        <> migrationErrors bundles

-- Every set and required name is a valid pg-migrate component name, no two bundles
-- define the same set, and every set a scenario or another set requires is defined.
migrationErrors :: [LayerBundle] -> [RegistryError]
migrationErrors bundles =
  [RegistryError problem | name <- definedNames <> requiredNames, Left problem <- [mkMigrationSetName (renderMigrationSetName name)]]
    <> duplicateErrors "migration set" (fmap renderMigrationSetName definedNames)
    <> [ RegistryError (renderScenarioId scenario.id <> ": no registered bundle defines migration set " <> renderMigrationSetName name)
       | scenario <- concatMap (.scenarios) bundles,
         name <- scenarioSets scenario,
         name `notElem` definedNames
       ]
    <> [ RegistryError ("migration set " <> renderMigrationSetName set.name <> " requires undefined set " <> renderMigrationSetName name)
       | set <- sets,
         name <- set.requires,
         name `notElem` definedNames
       ]
  where
    sets = concatMap (.migrations) bundles
    definedNames = fmap (.name) sets
    requiredNames = concatMap scenarioSets (concatMap (.scenarios) bundles) <> concatMap (.requires) sets
    scenarioSets scenario = concatMap (.schemas) (maybe [] pure scenario.requires.postgres <> fmap snd scenario.requires.extraPostgres)

registryMigrationSets :: Registry -> Map.Map MigrationSetName MigrationSet
registryMigrationSets (Registry bundles) = Map.fromList [(set.name, set) | bundle <- bundles, set <- bundle.migrations]

duplicateErrors :: Text -> [Text] -> [RegistryError]
duplicateErrors label values = [RegistryError ("duplicate " <> label <> ": " <> item) | items@(item : _) <- group (sort values), length items > 1]

validateScenario :: Scenario -> [RegistryError]
validateScenario scenario =
  [RegistryError (renderScenarioId scenario.id <> ": revision must be positive") | scenario.revision < 1]
    <> [RegistryError (renderScenarioId scenario.id <> ": duplicate knob " <> name) | name <- duplicateNames]
    <> postgresErrors
    <> benchmarkErrors
    <> knownDefectErrors
  where
    duplicateNames = [item | items@(item : _) <- group (sort (fmap (renderKnobName . (.name)) scenario.knobs)), length items > 1]
    hasPostgres = isJust scenario.requires.postgres
    pgApplicable = case (scenario.dimensions.pgDurability, scenario.dimensions.pgVersion) of
      (NotApplicable, NotApplicable) -> False
      _ -> True
    postgresErrors =
      [RegistryError (renderScenarioId scenario.id <> ": PostgreSQL dimensions disagree with environment requirement") | hasPostgres /= pgApplicable]
    benchmarkErrors = case (scenario.id.kind, scenario.requires.postgres, scenario.dimensions.pgDurability) of
      (Benchmark, Just _, Supported support) | PgFsyncOff `elem` support.values -> [RegistryError (renderScenarioId scenario.id <> ": benchmark supports fsync-off")]
      _ -> []
    knownDefectErrors =
      [ RegistryError (renderScenarioId scenario.id <> ": invalid known-defect reference")
      | defect <- maybe [] individualKnownDefects scenario.knownDefect,
        not ("mori://" `Text.isPrefixOf` defect.reference || "https://" `Text.isPrefixOf` defect.reference)
      ]

allScenarios :: Registry -> [Scenario]
allScenarios (Registry bundles) = sortOn (renderScenarioId . (.id)) (concatMap (.scenarios) bundles)

allRoles :: Registry -> [WorkerRole]
allRoles (Registry bundles) = sortOn (renderRoleName . (.name)) (concatMap (.roles) bundles)

lookupScenario :: Registry -> ScenarioId -> Maybe Scenario
lookupScenario registry wanted = Map.lookup wanted (Map.fromList [(scenario.id, scenario) | scenario <- allScenarios registry])

lookupRole :: Registry -> RoleName -> Maybe WorkerRole
lookupRole registry wanted = Map.lookup wanted (Map.fromList [(role.name, role) | role <- allRoles registry])

selectScenarios :: Registry -> ListFilter -> [Scenario]
selectScenarios registry filterValue = filter selected (allScenarios registry)
  where
    selected scenario =
      (null filterValue.selectors || any (`matchesSelector` scenario.id) filterValue.selectors)
        && (null filterValue.layers || scenario.id.layer `elem` filterValue.layers)
        && (null filterValue.kinds || scenario.id.kind `elem` filterValue.kinds)
        && maybe True (scenario.tier <=) filterValue.maxTier
        && (null filterValue.placements || scenario.placement `elem` filterValue.placements)

scenarioListDocument :: Registry -> Value
scenarioListDocument registry = scenarioListDocumentFor (allScenarios registry) (allRoles registry)

scenarioListDocumentFor :: [Scenario] -> [WorkerRole] -> Value
scenarioListDocumentFor scenarios roles =
  object
    [ "schema" .= ("kenshou.scenario-list/v1" :: Text),
      "suiteVersion" .= suiteVersion,
      "scenarios" .= fmap scenarioValue scenarios,
      "roles" .= fmap roleValue roles
    ]
  where
    scenarioValue scenario =
      object
        [ "id" .= renderScenarioId scenario.id,
          "layer" .= renderLayer scenario.id.layer,
          "component" .= unSegment scenario.id.component,
          "kind" .= renderKind scenario.id.kind,
          "name" .= unSegment scenario.id.name,
          "revision" .= scenario.revision,
          "summary" .= scenario.summary,
          "tier" .= renderTier scenario.tier,
          "placement" .= renderPlacement scenario.placement,
          "knownDefect" .= fmap defectReferences scenario.knownDefect
        ]
    roleValue role = object ["name" .= renderRoleName role.name, "summary" .= role.summary]
    defectReferences defect = case individualKnownDefects defect of
      [single] -> toJSON single.reference
      many -> toJSON (fmap (.reference) many)
