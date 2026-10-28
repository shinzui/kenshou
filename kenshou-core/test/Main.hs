{-# LANGUAGE FieldSelectors #-}

module Main (main) where

import Control.Exception (bracket_)
import Data.Aeson (FromJSON, Value (..), eitherDecode, eitherDecodeFileStrict', encode, encodeFile, object, toJSON, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as ByteString
import Data.Either (isLeft, isRight)
import Data.Foldable (toList)
import Data.IORef (modifyIORef', newIORef, readIORef)
import Data.Int (Int64)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Database.PostgreSQL.Migrate (migrationComponent, sqlMigration)
import Kenshou.Core.Bundle (LayerBundle (..), ListFilter (..), RegistryError (..), ScenarioRule (..), allScenarios, emptyListFilter, mkBundle, mkRegistry, registryMigrationSets, requirePgVersionsFor, selectScenarios)
import Kenshou.Core.Bundle qualified as Bundle
import Kenshou.Core.Canonical (canonicalEncode)
import Kenshou.Core.Cohort
import Kenshou.Core.Compat (comparisonKey, compatInputs, seriesKey)
import Kenshou.Core.Context (Environment (..), RunContext (..))
import Kenshou.Core.Dimension
import Kenshou.Core.Env (EnvRequirements (..), MigrationSet (..), MigrationSetName (..), PostgresRequirement (..), noEnvironment, requiresResource)
import Kenshou.Core.Env.Migration (composePlan, orderMigrationSets)
import Kenshou.Core.Env.Postgres (EnvError (..), PgSettingsSnapshot (..), PostgresEnv (..), ServerControl (..), StopMode (..), withPostgresEnv, withPostgresEnvNamed)
import Kenshou.Core.Id
import Kenshou.Core.Knob
import Kenshou.Core.Log (nullLogger)
import Kenshou.Core.Manifest (verifyManifest, writeManifest)
import Kenshou.Core.Outcome (Outcome (Passed))
import Kenshou.Core.Phase (zeroPhases)
import Kenshou.Core.Resource (ProvisionedResource (..), ResourceProvider (..), mkResourceName)
import Kenshou.Core.Run (RunOutput (..), RunnerConfig (..), defectDisposition, executeRun)
import Kenshou.Core.RunResult (KnownDefectStatus (..))
import Kenshou.Core.RunSpec
import Kenshou.Core.RunSpec.Resolve (resolveRunSpec)
import Kenshou.Core.Scenario (CohortScope (..), KnownDefect (..), PackageCondition (..), Placement (..), Scenario (..), ScenarioReport (..), Tier (..), failedWith)
import Kenshou.Core.Selector (matchesSelector, parseSelector)
import Kenshou.Core.Selftest qualified as Selftest
import Kenshou.Core.Selftest.Schema (selftestMigrationSet, selftestSchema)
import Kenshou.PerfCalibrationSpec qualified
import Kenshou.PerfPreparedSpec qualified
import Kenshou.PerfResultSpec qualified
import Kenshou.PerfSpec qualified
import Kenshou.PlanSpec qualified
import Kenshou.ResourceSpec qualified
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import System.Process (readProcessWithExitCode)
import Test.Hspec
  ( Spec,
    describe,
    expectationFailure,
    hspec,
    it,
    pendingWith,
    shouldBe,
    shouldContain,
    shouldNotBe,
    shouldReturn,
  )

main :: IO ()
main = hspec do
  Kenshou.PerfCalibrationSpec.spec
  Kenshou.PerfResultSpec.spec
  descriptorSpec
  hashSpec
  mismatchSpec
  activeCohortSpec
  identifierSpec
  layerIdentifierSpec
  selectorSpec
  registrySpec
  openRegistrySpec
  resourceProvisioningSpec
  knownDefectGroupSpec
  knobSpec
  dimensionSpec
  runSpecSpec
  compatibilitySpec
  manifestSpec
  goldenSpec
  postgresEnvironmentSpec
  migrationPlanSpec
  Kenshou.PlanSpec.spec
  Kenshou.ResourceSpec.spec
  Kenshou.PerfPreparedSpec.spec
  Kenshou.PerfSpec.spec

-- The consumer's own layer strings are checked against its sealed records in the
-- kenshou-evidence consumer compatibility tests; these cases use synthetic names.
layerIdentifierSpec :: Spec
layerIdentifierSpec = describe "layer identifiers" do
  it "renders the self-test layer" do
    renderLayer selftestLayer `shouldBe` "selftest"
  it "accepts any valid segment and renders scenario identifiers in any layer" do
    renderLayer <$> parseLayer "acme" `shouldBe` Right "acme"
    renderScenarioId <$> parseScenarioId "acme/widget/correctness/roundtrip" `shouldBe` Right "acme/widget/correctness/roundtrip"
  it "rejects invalid segments" do
    isLeft (parseLayer "Acme") `shouldBe` True
    isLeft (parseLayer "") `shouldBe` True

descriptorSpec :: Spec
descriptorSpec = describe "cohort identity" do
  it "matches the stable JSON golden" do
    descriptor <- decodeFixture "descriptor-released.json"
    plan <- decodeFixture "plan-released.json"
    golden <- decodeFixture "cohort-identity.golden.json"
    case identityFromPlan descriptor "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd" plan of
      Left err -> expectationFailure (show err)
      Right identity -> toJSON identity `shouldBe` (golden :: Value)
  it "round-trips a Nix resolver while old Cabal records omit it" do
    let cabalIdentity = identityWith []
        nixIdentity = cabalIdentity {identityResolver = Just "nix"}
    eitherDecode (encode cabalIdentity) `shouldBe` Right cabalIdentity
    eitherDecode (encode nixIdentity) `shouldBe` Right nixIdentity

hashSpec :: Spec
hashSpec = describe "planHash" do
  it "ignores install-plan order and local checkout paths" do
    baseline <- hashFixture "plan-released.json"
    reordered <- hashFixture "plan-reordered.json"
    moved <- hashFixture "plan-local-change.json"
    reordered `shouldBe` baseline
    moved `shouldBe` baseline

  it "changes with a package version or git revision" do
    baseline <- hashFixture "plan-released.json"
    versionChanged <- hashFixture "plan-version-change.json"
    commitChanged <- hashFixture "plan-commit-change.json"
    versionChanged `shouldNotBe` baseline
    commitChanged `shouldNotBe` baseline

mismatchSpec :: Spec
mismatchSpec = describe "checkCohort" do
  it "reports every mismatch constructor" do
    let descriptor = onePackageDescriptor
        missing = identityWith []
        wrongVersion = identityWith [ResolvedPackage "foo" "2.0.0" (FromHackage Nothing)]
        wrongSource = identityWith [ResolvedPackage "foo" "1.0.0" (FromGit "https://example.com/foo.git" "abc" Nothing)]
        localSource = identityWith [ResolvedPackage "foo" "1.0.0" (FromLocalPath "/tmp/foo")]
        wrongCohort = (identityWith [ResolvedPackage "foo" "1.0.0" (FromHackage Nothing)]) {identityCohort = CohortName "head"}
        wrongCompiler = (identityWith [ResolvedPackage "foo" "1.0.0" (FromHackage Nothing)]) {identityCompiler = "ghc-9.10.3"}
    checkCohort descriptor missing `shouldContain` [MissingPackage "foo"]
    checkCohort descriptor wrongVersion `shouldContain` [VersionMismatch "foo" "1.0.0" "2.0.0"]
    checkCohort descriptor wrongSource `shouldContain` [SourceMismatch "foo" HackageSource (FromGit "https://example.com/foo.git" "abc" Nothing)]
    checkCohort descriptor localSource `shouldContain` [LocalPathSource "foo" "/tmp/foo"]
    checkCohort descriptor wrongCohort `shouldContain` [CohortNameMismatch (CohortName "released") (CohortName "head")]
    checkCohort descriptor wrongCompiler `shouldContain` [CompilerMismatch "ghc-9.12.4" "ghc-9.10.3"]

activeCohortSpec :: Spec
activeCohortSpec = describe "activeCohortName" do
  it "accepts exactly one cohort import" do
    result <- activeCohortName (fixtures <> "/valid-project")
    result `shouldBe` Right (CohortName "released")

  it "rejects extra lines" do
    result <- activeCohortName (fixtures <> "/invalid-project")
    case result of
      Left (CohortInvalidActive _) -> pure ()
      other -> expectationFailure ("expected CohortInvalidActive, got " <> show other)

identifierSpec :: Spec
identifierSpec = describe "scenario identifiers" do
  it "round-trips canonical identifiers" do
    let rendered = "acme/append/concurrency/expected-version-race"
    fmap renderScenarioId (parseScenarioId rendered) `shouldBe` Right rendered

  it "rejects malformed identifiers" do
    parseScenarioId "acme/append/correctness" `shouldBe` Left "scenario identifier must have four segments: \"acme/append/correctness\""
    parseScenarioId "ACME/append/correctness/example" `shouldBe` Left "invalid layer \"ACME\": invalid segment \"ACME\""

  it "generates canonical UUIDv7 run ids" do
    generated <- newRunId
    parseRunId (renderRunId generated) `shouldBe` Right generated

selectorSpec :: Spec
selectorSpec = describe "scenario selectors" do
  it "supports one-segment and recursive wildcards" do
    scenario <- expectRight (parseScenarioId "selftest/kernel/correctness/always-pass")
    one <- expectRight (parseSelector "*/*/correctness/*")
    recursive <- expectRight (parseSelector "selftest/**")
    matchesSelector one scenario `shouldBe` True
    matchesSelector recursive scenario `shouldBe` True

-- A suite that is not the kernel's: its own layer, migration set, and rule.
openRegistrySpec :: Spec
openRegistrySpec = describe "open registry" do
  let layer = either (error . Text.unpack) id (mkLayerId "acme")
      acmeSet = syntheticSet "acme" []
      roundtrip pgVersions =
        Scenario
          { id = either (error . show) id (parseScenarioId "acme/widget/correctness/roundtrip"),
            revision = 1,
            summary = "Round-trips a widget.",
            tier = TierSmoke,
            placement = PlaceEither,
            knobs = [],
            dimensions = postgresDimensions (PgDurable :| []) pgVersions noDimensions,
            phases = zeroPhases,
            requires = noEnvironment {postgres = Just (PostgresRequirement [MigrationSetName "acme"] [] False)},
            knownDefect = Nothing,
            run = const (pure (ScenarioReport Passed Nothing []))
          }
      bundleWith scenario = (mkBundle layer [scenario] []) {migrations = [acmeSet], rules = [requirePgVersionsFor (MigrationSetName "acme") (Pg18 :| [])]}
      registryErrors bundles = either (fmap (\(RegistryError message) -> message) . toList) (const []) (mkRegistry bundles)
  it "accepts a bundle for a new layer with its own migration set and rule" do
    registry <- expectRight (mkRegistry [Selftest.bundle, bundleWith (roundtrip (Pg18 :| []))])
    Map.keys (registryMigrationSets registry) `shouldBe` [MigrationSetName "acme", MigrationSetName "kenshou-selftest"]
    fmap (renderScenarioId . (.id)) (selectScenarios registry emptyListFilter {layers = [layer]}) `shouldBe` ["acme/widget/correctness/roundtrip"]
  it "rejects a scenario that violates a contributed rule with the rule's message" do
    registryErrors [bundleWith (roundtrip (Pg17 :| [Pg18]))] `shouldBe` ["acme/widget/correctness/roundtrip: acme scenarios require PostgreSQL 18"]
  it "applies a rule to scenarios of every bundle" do
    let rule = ScenarioRule "no-selftest" (\scenario -> ["rejected" | renderLayer scenario.id.layer == "selftest"])
    length (registryErrors [Selftest.bundle, (bundleWith (roundtrip (Pg18 :| []))) {rules = [rule]}]) `shouldBe` length Selftest.bundle.scenarios
  it "rejects duplicate and undefined migration sets" do
    registryErrors [bundleWith (roundtrip (Pg18 :| [])), (mkBundle layer [] []) {migrations = [acmeSet]}] `shouldBe` ["duplicate migration set: acme"]
    registryErrors [(bundleWith (roundtrip (Pg18 :| []))) {migrations = []}] `shouldBe` ["acme/widget/correctness/roundtrip: no registered bundle defines migration set acme"]

-- A suite resource with a stub provider that records when it is acquired and released.
resourceProvisioningSpec :: Spec
resourceProvisioningSpec = describe "resource provisioning" do
  let layer = either (error . Text.unpack) id (mkLayerId "acme")
      stub = either (error . Text.unpack) id (mkResourceName "stub")
      provider :: (Text -> IO ()) -> ResourceProvider
      provider record =
        ResourceProvider
          { name = stub,
            summary = "Stub resource",
            normalize = Right . fromMaybe (object ["mode" .= ("default" :: Text)]),
            withLocal = \_ value action ->
              bracket_ (record "acquire") (record "release") (action (ProvisionedResource (object ["spec" .= value]) (object ["kind" .= ("stub" :: Text)]))),
            cell = Nothing
          }
      roundtrip :: (Text -> IO ()) -> Scenario
      roundtrip record =
        Scenario
          { id = either (error . show) id (parseScenarioId "acme/widget/correctness/uses-stub"),
            revision = 1,
            summary = "Uses the stub resource.",
            tier = TierSmoke,
            placement = PlaceEither,
            knobs = [],
            dimensions = noDimensions,
            phases = zeroPhases,
            requires = requiresResource stub,
            knownDefect = Nothing,
            run = \context -> do
              record "run"
              pure (if fmap (.workerValue) (Map.lookup stub context.env.resources) == Just (object ["spec" .= object ["mode" .= ("default" :: Text)]]) then ScenarioReport Passed Nothing [] else failedWith ["no-stub"] "the stub resource was not provisioned")
          }
      bundleWith record = (mkBundle layer [roundtrip record] []) {Bundle.resources = [provider record]}
      registryErrors bundles = either (fmap (\(RegistryError message) -> message) . toList) (const []) (mkRegistry bundles)
      ignore = const (pure ())
  it "rejects a duplicate provider and an unprovided resource" do
    registryErrors [bundleWith ignore, (mkBundle layer [] []) {Bundle.resources = [provider ignore]}] `shouldBe` ["duplicate resource provider: stub"]
    registryErrors [(bundleWith ignore) {Bundle.resources = []}] `shouldBe` ["scenario requires unprovided resource stub: acme/widget/correctness/uses-stub"]
  it "normalizes the value, provisions around the run, and records the fingerprint" $ withSystemTempDirectory "kenshou-resource" \root -> do
    events <- newIORef ([] :: [Text])
    let record event = modifyIORef' events (<> [event])
    registry <- expectRight (mkRegistry [bundleWith record])
    scenarioId <- expectRight (parseScenarioId "acme/widget/correctness/uses-stub")
    output <- executeRun (RunnerConfig registry root (identityWith []) Nothing False False []) (minimalRunSpec scenarioId) >>= expectRight
    readIORef events `shouldReturn` ["acquire", "run", "release"]
    runSpec <- decodeFile (output.directory </> "run-spec.json")
    runResult <- decodeFile (output.directory </> "run-result.json")
    path ["environment", "resources", "stub"] runSpec `shouldBe` Just (object ["mode" .= ("default" :: Text)])
    path ["fingerprint", "resources", "stub"] runResult `shouldBe` Just (object ["kind" .= ("stub" :: Text)])
    path ["outcome"] runResult `shouldBe` Just (String "passed")
  where
    decodeFile file = eitherDecodeFileStrict' file >>= either fail pure :: IO Value
    path [] value = Just value
    path (key : rest) (Object fields) = KeyMap.lookup (Key.fromText key) fields >>= path rest
    path _ _ = Nothing

registrySpec :: Spec
registrySpec = describe "scenario registry" do
  it "sorts the kernel self-tests by identifier" do
    case mkRegistry [Selftest.bundle] of
      Left errors -> expectationFailure (show errors)
      Right registry ->
        fmap (renderScenarioId . (.id)) (allScenarios registry)
          `shouldBe` [ "selftest/kernel/concurrency/worker-echo",
                       "selftest/kernel/correctness/always-fail",
                       "selftest/kernel/correctness/always-pass",
                       "selftest/kernel/correctness/errors",
                       "selftest/kernel/correctness/known-defect",
                       "selftest/kernel/correctness/outcome",
                       "selftest/kernel/correctness/postgres-roundtrip"
                     ]

knownDefectGroupSpec :: Spec
knownDefectGroupSpec = describe "grouped known defects" do
  let base = case filter (\item -> renderScenarioId item.id == "selftest/kernel/correctness/known-defect") Selftest.bundle.scenarios of
        [item] -> item
        _ -> error "missing known-defect self-test"
      first = KnownDefect "mori://example/bugs/1" "first" ["first-failure"] AllCohorts
      second = KnownDefect "mori://example/bugs/2" "second" ["second-failure"] AllCohorts
      scenario = base {knownDefect = Just (KnownDefectGroup (first :| [second]))}
      cohort = identityWith []
      disposition strict labels = defectDisposition strict cohort scenario (failedWith labels "grouped defect probe")
  it "accepts either or both independently reproduced defects" do
    let check labels = case disposition False labels of
          (Just (KnownDefectGroup _, DefectReproduced), False, 0) -> pure ()
          other -> expectationFailure (show other)
    check ["first-failure"]
    check ["second-failure"]
    check ["first-failure", "second-failure"]
  it "blocks unrelated failures and strict known-defect runs" do
    case disposition False ["second-failure", "new-failure"] of
      (Just (_, DefectDifferentFailure), True, 1) -> pure ()
      other -> expectationFailure (show other)
    case disposition True ["second-failure"] of
      (Just (_, DefectReproduced), False, 1) -> pure ()
      other -> expectationFailure (show other)
  it "does not excuse a failed result without a failure label" do
    case disposition False [] of
      (Just (_, DefectDifferentFailure), True, 1) -> pure ()
      other -> expectationFailure (show other)
  it "ignores labels owned only by a defect outside the resolved cohort" do
    let scoped = KnownDefect "mori://example/bugs/2" "second" ["second-failure"] (OnlyWhen (ResolvedFromGit "foo" :| []))
        scopedScenario = base {knownDefect = Just (KnownDefectGroup (first :| [scoped]))}
        result = defectDisposition False (identityWith [ResolvedPackage "foo" "1.0.0" (FromHackage Nothing)]) scopedScenario (failedWith ["second-failure"] "scoped defect probe")
    case result of
      (Just (_, DefectDifferentFailure), True, 1) -> pure ()
      other -> expectationFailure (show other)

knobSpec :: Spec
knobSpec = describe "knob resolution" do
  let workers = knobName "selftest.workers"
      enabled = knobName "selftest.enabled"
      declarations =
        [ KnobSpec workers "Worker count" KnobInt (VInt 2) (IntRange 1 8) [VInt 1, VInt 8],
          KnobSpec enabled "Enable work" KnobBool (VBool False) AnyValue []
        ]
  it "fills defaults and parses typed command-line values" do
    resolved <- expectRight (resolveKnobs declarations [(workers, RawText "4"), (enabled, RawText "true")])
    knobInt resolved workers `shouldBe` (4 :: Int64)
    knobBool resolved enabled `shouldBe` True
  it "reports duplicates, unknown names and range violations together" do
    let unknown = knobName "selftest.unknown"
        result = resolveKnobs declarations [(workers, RawText "9"), (workers, RawText "1"), (unknown, RawText "x")]
    case result of
      Left problems -> length problems `shouldBe` 3
      Right _ -> expectationFailure "expected knob errors"

dimensionSpec :: Spec
dimensionSpec = describe "dimension resolution" do
  let support = postgresDimensions (PgFsyncOff :| [PgDurable]) (Pg18 :| []) noDimensions
  it "fills every applicable default" do
    resolveDimensions support [] `shouldBe` Right (Dimensions Nothing Nothing (Just PgFsyncOff) (Just Pg18))
  it "rejects unsupported and inapplicable values" do
    case resolveDimensions support [("pg.version", "17"), ("telemetry.tracing", "off")] of
      Left problems -> length problems `shouldBe` 2
      Right _ -> expectationFailure "expected dimension errors"

runSpecSpec :: Spec
runSpecSpec = describe "run specification" do
  it "decodes a minimal document and emits a round-trippable effective document" do
    input <- case eitherDecode "{\"schema\":\"kenshou.run-spec/v1\",\"scenario\":\"selftest/kernel/correctness/always-pass\",\"seed\":7}" of
      Left err -> expectationFailure err >> fail "unreachable"
      Right value -> pure value
    registry <- expectRight (mkRegistry [Selftest.bundle])
    resolution <- resolveRunSpec registry input
    (_, effective) <- expectRight resolution
    eitherDecode (encode effective) `shouldBe` Right (toJSON effective :: Value)
  it "rejects a non-v7 run id while decoding" do
    let document = "{\"schema\":\"kenshou.run-spec/v1\",\"scenario\":\"selftest/kernel/correctness/always-pass\",\"runId\":\"550e8400-e29b-41d4-a716-446655440000\"}"
    case (eitherDecode document :: Either String RunSpec) of
      Left err -> err `shouldContain` "UUIDv7"
      Right _ -> expectationFailure "expected UUIDv7 rejection"

compatibilitySpec :: Spec
compatibilitySpec = describe "compatibility keys" do
  it "exclude run identity and cohort from comparison keys, but include the cohort in series keys" do
    registry <- expectRight (mkRegistry [Selftest.bundle])
    scenarioId <- expectRight (parseScenarioId "selftest/kernel/correctness/always-pass")
    firstResolution <- resolveRunSpec registry (minimalRunSpec scenarioId)
    secondResolution <- resolveRunSpec registry (minimalRunSpec scenarioId)
    (_, firstSpec) <- expectRight firstResolution
    (_, secondSpec) <- expectRight secondResolution
    let firstCohort = identityWith []
        secondCohort = firstCohort {identityPlanHash = PlanHash "sha256:other"}
        firstInputs = compatInputs firstSpec Nothing [] firstCohort
        repeatedInputs = compatInputs secondSpec Nothing [] firstCohort
        otherCohortInputs = compatInputs firstSpec Nothing [] secondCohort
    comparisonKey firstInputs `shouldBe` comparisonKey repeatedInputs
    comparisonKey firstInputs `shouldBe` comparisonKey otherCohortInputs
    seriesKey firstInputs `shouldNotBe` seriesKey otherCohortInputs

knobName :: Text -> KnobName
knobName = either (error . show) id . mkKnobName

manifestSpec :: Spec
manifestSpec = describe "artifact manifests" do
  it "detects a changed file" $ withSystemTempDirectory "kenshou-manifest" \directory -> do
    runId <- expectRight (parseRunId "01997f3a-5b7c-7e21-8a44-0d6c2f9b1e55")
    ByteString.writeFile (directory <> "/run-spec.json") "{}\n"
    manifest <- writeManifest directory runId Map.empty
    encodeFile (directory <> "/manifest.json") manifest
    verifyManifest directory `shouldReturn` Right ()
    ByteString.appendFile (directory <> "/run-spec.json") "x"
    verification <- verifyManifest directory
    case verification of
      Left _ -> pure ()
      Right () -> expectationFailure "expected a digest mismatch"

goldenSpec :: Spec
goldenSpec = describe "JSON goldens" do
  mapM_ roundTrips ["run-spec.minimal.json", "run-spec.effective.json", "run-spec.external.json", "run-result.passed.json", "run-result.known-defect.json", "manifest.json", "scenario-list.json"]
  where
    roundTrips name = it ("round-trips " <> name <> " canonically") do
      original <- decodeGolden name
      redecoded <- case eitherDecode (encode original) of
        Left err -> expectationFailure err >> fail "unreachable"
        Right value -> pure value
      canonicalEncode original `shouldBe` canonicalEncode (redecoded :: Value)
    decodeGolden name = do
      result <- eitherDecodeFileStrict' ("test/golden/" <> name)
      case result of
        Left err -> expectationFailure err >> fail "unreachable"
        Right value -> pure (value :: Value)

postgresEnvironmentSpec :: Spec
postgresEnvironmentSpec = describe "PostgreSQL environments" do
  it "migrates, clones, restarts, and crash-restarts PostgreSQL 18" $ withSystemTempDirectory "kenshou-pg18" \directory -> do
    runId <- expectRight (parseRunId "01997f3a-5b7c-7e21-8a44-0d6c2f9b1e55")
    let requirement = PostgresRequirement [selftestSchema] [] True
        expectedSchemas = "kenshou_selftest,pgmigrate"
        dimensions = Dimensions Nothing Nothing (Just PgFsyncOff) (Just Pg18)
    result <- withPostgresEnv selftestSets nullLogger directory runId requirement (PostgresEphemeral []) dimensions \environment -> do
      schemas <- psqlTest environment.connectionString "select string_agg(schema_name, ',' order by schema_name) from information_schema.schemata where schema_name in ('kenshou_selftest','pgmigrate')"
      clone <- environment.newDatabase "clone"
      clonedSchemas <- psqlTest clone "select string_agg(schema_name, ',' order by schema_name) from information_schema.schemata where schema_name in ('kenshou_selftest','pgmigrate')"
      case environment.control of
        Nothing -> expectationFailure "expected server control"
        Just control -> do
          control.restartServer
          psqlTest environment.connectionString "select 1" `shouldReturn` Right "1"
          control.stopServer StopImmediate
          control.startServer
          psqlTest environment.connectionString "select 1" `shouldReturn` Right "1"
      pure (schemas, clonedSchemas, Map.lookup "fsync" environment.snapshot.settings)
    result `shouldBe` Right (Right expectedSchemas, Right expectedSchemas, Just "off")

  it "creates and drops fresh databases in external mode" $ withSystemTempDirectory "kenshou-pg-external" \directory -> do
    runId <- expectRight (parseRunId "01997f3a-5b7c-7e21-8a44-0d6c2f9b1e55")
    let dimensions = Dimensions Nothing Nothing (Just PgFsyncOff) (Just Pg18)
        outerRequirement = PostgresRequirement [] [] False
        externalRequirement = PostgresRequirement [selftestSchema] [("shared_preload_libraries", "'pg_stat_statements'")] False
    outer <- withPostgresEnv selftestSets nullLogger directory runId outerRequirement (PostgresEphemeral [("shared_preload_libraries", "'pg_stat_statements'")]) dimensions \server -> do
      inner <- withPostgresEnv selftestSets nullLogger directory runId externalRequirement (PostgresExternal (ConnLiteral server.adminConnectionString)) dimensions (\environment -> psqlTest environment.connectionString "select to_regnamespace('kenshou_selftest') is not null")
      missing <- withPostgresEnv selftestSets nullLogger directory runId (PostgresRequirement [] [("shared_preload_libraries", "'missing_extension'")] False) (PostgresExternal (ConnLiteral server.adminConnectionString)) dimensions (const (pure ()))
      missing `shouldBe` Left (EnvError "external PostgreSQL is missing required preloaded libraries: missing_extension")
      remaining <- psqlTest server.adminConnectionString "select count(*) from pg_database where datname like 'kenshou_01997f3a5b7c7%'"
      pure (inner, remaining)
    outer `shouldBe` Right (Right (Right "t"), Right "0")

  it "keeps two named contexts of one run apart on a shared external server" $ withSystemTempDirectory "kenshou-pg-shared" \directory -> do
    runId <- expectRight (parseRunId "01997f3a-5b7c-7e21-8a44-0d6c2f9b1e56")
    let dimensions = Dimensions Nothing Nothing (Just PgFsyncOff) (Just Pg18)
        requirement = PostgresRequirement [] [] False
    outer <- withPostgresEnv selftestSets nullLogger directory runId requirement (PostgresEphemeral []) dimensions \server -> do
      let external = PostgresExternal (ConnLiteral server.adminConnectionString)
      nested <- withPostgresEnvNamed selftestSets False (Just "shop") nullLogger directory runId requirement external dimensions \shop ->
        withPostgresEnvNamed selftestSets False (Just "warehouse") nullLogger directory runId requirement external dimensions \warehouse ->
          pure (shop.databaseName /= warehouse.databaseName)
      remaining <- psqlTest server.adminConnectionString "select count(*) from pg_database where datname like 'kenshou_01997f3a5b7c7%'"
      pure (nested, remaining)
    outer `shouldBe` Right (Right (Right True), Right "0")

  it "selects PostgreSQL 17 and applies a composed plan" do
    available <- lookupEnv "KENSHOU_PG17_BIN"
    case available of
      Nothing -> pendingWith "KENSHOU_PG17_BIN is not set"
      Just _ -> withSystemTempDirectory "kenshou-pg17" \directory -> do
        runId <- expectRight (parseRunId "01997f3a-5b7c-7e21-8a44-0d6c2f9b1e55")
        let requirement = PostgresRequirement [selftestSchema] [] False
            dimensions = Dimensions Nothing Nothing (Just PgFsyncOff) (Just Pg17)
        result <- withPostgresEnv selftestSets nullLogger directory runId requirement (PostgresEphemeral []) dimensions (pure . (.snapshot.serverVersionNum))
        case result of
          Left err -> expectationFailure (show err)
          Right version -> (version >= 170000 && version < 180000) `shouldBe` True

psqlTest :: Text -> Text -> IO (Either Text Text)
psqlTest connection query = do
  (code, output, err) <- readProcessWithExitCode "psql" ["-d", Text.unpack connection, "-Atqc", Text.unpack query] ""
  pure case code of ExitSuccess -> Right (Text.strip (Text.pack output)); _ -> Left (Text.strip (Text.pack err))

onePackageDescriptor :: CohortDescriptor
onePackageDescriptor =
  CohortDescriptor
    "kenshou.cohort/v1"
    (CohortName "released")
    "fixture"
    "2026-09-20"
    "ghc-9.12.4"
    "2026-09-20T13:44:47Z"
    "cohort/released.project"
    [ComponentSpec (ComponentId "foo") "mori://example/foo" HackageSource [PackagePin "foo" "1.0.0" Nothing]]
    []
    []

identityWith :: [ResolvedPackage] -> CohortIdentity
identityWith packages =
  CohortIdentity
    (CohortName "released")
    "ghc-9.12.4"
    "3.16.1.0"
    "linux"
    "x86_64"
    (Just "2026-09-20T13:44:47Z")
    (PlanHash "sha256:fixture")
    "fixture"
    [ResolvedComponent (ComponentId "foo") "mori://example/foo" packages]
    Nothing

hashFixture :: FilePath -> IO PlanHash
hashFixture name = do
  value <- decodeFixture name
  case planHash value of
    Left err -> expectationFailure (show err) >> fail "unreachable"
    Right result -> pure result

decodeFixture :: (FromJSON value) => FilePath -> IO value
decodeFixture name = do
  result <- eitherDecodeFileStrict' (fixtures <> "/" <> name)
  case result of
    Left err -> expectationFailure err >> fail "unreachable"
    Right value -> pure value

fixtures :: FilePath
fixtures = "test/fixtures"

expectRight :: (Show problem) => Either problem value -> IO value
expectRight (Right value) = pure value
expectRight (Left problem) = expectationFailure (show problem) >> fail "unreachable"

migrationPlanSpec :: Spec
migrationPlanSpec = describe "migration plan composition" do
  let alpha = syntheticSet "alpha" []
      beta = syntheticSet "beta" [MigrationSetName "alpha"]
      gamma = syntheticSet "gamma" [MigrationSetName "beta"]
      unavailable = MigrationSet (MigrationSetName "delta") [] (Left "not built")
      cyclic = syntheticSet "epsilon" [MigrationSetName "epsilon"]
      sets = Map.fromList [(set.name, set) | set <- [alpha, beta, gamma, unavailable, cyclic]]
      order names = fmap (fmap (.name)) (orderMigrationSets sets (fmap MigrationSetName names))
  it "composes the self-test migration set" do
    isRight (composePlan selftestSets [selftestSchema]) `shouldBe` True
  it "keeps the declared order and inserts required sets first, transitively" do
    order ["gamma"] `shouldBe` Right (fmap MigrationSetName ["alpha", "beta", "gamma"])
    order ["beta", "alpha"] `shouldBe` Right (fmap MigrationSetName ["alpha", "beta"])
    order ["alpha", "gamma", "beta"] `shouldBe` Right (fmap MigrationSetName ["alpha", "beta", "gamma"])
    isRight (composePlan sets [MigrationSetName "gamma"]) `shouldBe` True
  it "rejects an empty selection, an undefined set, an unavailable set, and a cycle" do
    isLeft (composePlan sets []) `shouldBe` True
    isLeft (composePlan sets [MigrationSetName "missing"]) `shouldBe` True
    isLeft (composePlan sets [MigrationSetName "delta"]) `shouldBe` True
    isLeft (order ["epsilon"]) `shouldBe` True

-- A set whose one migration creates a schema of the same name.
syntheticSet :: Text -> [MigrationSetName] -> MigrationSet
syntheticSet name requires =
  MigrationSet
    { name = MigrationSetName name,
      requires,
      component = either (Left . Text.pack . show) Right do
        migration <- sqlMigration "create-schema" (Text.Encoding.encodeUtf8 ("create schema " <> name <> ";\n"))
        migrationComponent name (Set.fromList [dependency | MigrationSetName dependency <- requires]) (migration :| [])
    }

selftestSets :: Map.Map MigrationSetName MigrationSet
selftestSets = Map.singleton selftestSchema selftestMigrationSet
