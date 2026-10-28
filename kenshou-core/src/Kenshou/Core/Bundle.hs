module Kenshou.Core.Bundle
  ( LayerBundle (..),
    mkBundle,
    lookupBundle,
    lookupResource,
    registrySubjects,
    ScenarioRule (..),
    requirePgVersionsFor,
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
import Data.Foldable (toList)
import Data.List (group, sort, sortOn)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Kenshou.Core.Contribution (AdvisoryLabel, OracleSpec (..), PoolMethodology)
import Kenshou.Core.Dimension (DimensionSupport (..), PgDurability (..), PgVersion (..), Support (..), Supported (..))
import Kenshou.Core.Env (EnvRequirements (..), MigrationSet (..), MigrationSetName, PostgresRequirement (..), mkMigrationSetName, renderMigrationSetName)
import Kenshou.Core.Id (Kind (..), LayerId, ScenarioId (..), renderKind, renderLayer, renderScenarioId, unSegment)
import Kenshou.Core.Knob (KnobSpec (..), renderKnobName)
import Kenshou.Core.Resource (ResourceName, ResourceProvider (..), renderResourceName)
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
    migrations :: [MigrationSet],
    -- | Checks this bundle contributes. 'mkRegistry' applies every bundle's rules
    -- to every scenario in the registry.
    rules :: [ScenarioRule],
    -- | Providers for named resources. Any scenario in the registry may require a
    -- resource a bundle provides.
    resources :: [ResourceProvider],
    -- | SQL oracles the suite's scenarios reconcile, by name.
    oracles :: [OracleSpec],
    -- | Advisory-lock labels a stall capture of the suite's scenarios names.
    advisoryLabels :: [AdvisoryLabel],
    -- | The connection-pool size the suite recommends, when it has one.
    methodology :: Maybe PoolMethodology,
    -- | The canonical Mori URI that evidence records of this layer name as their
    -- subject.
    evidenceSubject :: Maybe Text
  }

mkBundle :: LayerId -> [Scenario] -> [WorkerRole] -> LayerBundle
mkBundle layer scenarios roles = LayerBundle {layer, scenarios, roles, migrations = [], rules = [], resources = [], oracles = [], advisoryLabels = [], methodology = Nothing, evidenceSubject = Nothing}

-- | A named registry check. Each message 'check' returns becomes a 'RegistryError'
-- prefixed with the scenario identifier.
data ScenarioRule = ScenarioRule
  { name :: Text,
    check :: Scenario -> [Text]
  }

-- | Require that a scenario using the migration set supports only the given
-- PostgreSQL versions, for a set whose migrations need a particular server.
requirePgVersionsFor :: MigrationSetName -> NonEmpty PgVersion -> ScenarioRule
requirePgVersionsFor set versions =
  ScenarioRule
    { name = renderMigrationSetName set <> "-postgres-versions",
      check = \scenario ->
        [ renderMigrationSetName set <> " scenarios require PostgreSQL " <> Text.intercalate " or " (fmap versionText (toList versions))
        | Just requirement <- [scenario.requires.postgres],
          set `elem` requirement.schemas,
          not (supportsOnly scenario.dimensions.pgVersion)
        ]
    }
  where
    supportsOnly (Supported support) = all (`elem` versions) support.values
    supportsOnly NotApplicable = False
    versionText Pg17 = "17"
    versionText Pg18 = "18"

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
        <> resourceErrors bundles
        <> [RegistryError ("evidence subject must be a canonical Mori URI: " <> subject) | bundle <- bundles, Just subject <- [bundle.evidenceSubject], not ("mori://" `Text.isPrefixOf` subject)]
        <> concat [duplicateErrors ("oracle in " <> renderLayer bundle.layer) (fmap (.name) bundle.oracles) | bundle <- bundles]
        <> [RegistryError (renderScenarioId scenario.id <> ": " <> message) | rule <- concatMap (.rules) bundles, scenario <- scenarios, message <- rule.check scenario]

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

-- No two bundles provide the same resource, and every resource a scenario requires
-- has a provider.
resourceErrors :: [LayerBundle] -> [RegistryError]
resourceErrors bundles =
  duplicateErrors "resource provider" (fmap (renderResourceName . (.name)) providers)
    <> [ RegistryError ("scenario requires unprovided resource " <> renderResourceName required <> ": " <> renderScenarioId scenario.id)
       | scenario <- concatMap (.scenarios) bundles,
         required <- scenario.requires.resources,
         required `notElem` fmap (.name) providers
       ]
  where
    providers = concatMap (.resources) bundles

-- | The first registered bundle of a layer. Several bundles may share a layer;
-- suite contributions are read from the first.
lookupBundle :: Registry -> LayerId -> Maybe LayerBundle
lookupBundle (Registry bundles) wanted = case filter ((== wanted) . (.layer)) bundles of
  bundle : _ -> Just bundle
  [] -> Nothing

-- | The evidence subject each layer's first bundle that declares one names.
registrySubjects :: Registry -> Map.Map LayerId Text
registrySubjects (Registry bundles) = Map.fromListWith (\_ first -> first) [(bundle.layer, subject) | bundle <- bundles, Just subject <- [bundle.evidenceSubject]]

lookupResource :: Registry -> ResourceName -> Maybe ResourceProvider
lookupResource (Registry bundles) wanted = case [provider | bundle <- bundles, provider <- bundle.resources, provider.name == wanted] of
  provider : _ -> Just provider
  [] -> Nothing

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
