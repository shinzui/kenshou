-- | Capture and replay a verification round without consulting mutable sources
-- after it is opened.
module Kenshou.Evidence.Round
  ( RoundMode (..),
    Arm (..),
    BaselineEntry (..),
    ArtifactReference (..),
    RoundDefinition (..),
    RoundInputs (..),
    ScopeOverride (..),
    OpenOptions (..),
    InputCapture (..),
    FreshInputs (..),
    RoundError (..),
    applyScopeOverrides,
    declaredScopes,
    openRound,
    readRound,
    readRoundWithDigest,
    readArtifactReference,
    decodeObservations,
    parseObservations,
    writeFileOnce,
  )
where

import Control.Monad (forM_, unless, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), except)
import Data.Aeson hiding (decode)
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (Parser, parseEither)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (traverse_)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Kenshou.Core.Canonical (sha256Hex)
import Kenshou.Core.Cohort (CohortIdentity (..), CohortName (..), PlanHash (..))
import Kenshou.Core.Defect (parseScope, scopeValue)
import Kenshou.Core.Id (ScenarioId, renderRunId)
import Kenshou.Core.Scenario (CohortScope, KnownDefect (..), individualKnownDefects)
import Kenshou.Evidence.Disposition (decodeCoverage, observationSourceValue, observationValue, parseObservation, parseObservationSource, parseTrust)
import Kenshou.Evidence.Observation (Observation (..), ObservationSource, Trust, renderTrust)
import Kenshou.Evidence.Owner (OwnerStatus)
import Kenshou.Evidence.Owner.Reconcile (PackageMap, decodePackageMap)
import Kenshou.Evidence.Owner.Snapshot (readSnapshot)
import Kenshou.Evidence.Round.Storage
import Kenshou.Evidence.Types (mkSha256)
import Kenshou.Plan.Catalog (ScenarioInfo (..), decodeCatalog)
import Kenshou.Plan.Components (ComponentGraph, GraphError (..), decodeGraph)
import System.Directory (createDirectoryIfMissing, makeAbsolute)
import System.FilePath (isRelative, splitDirectories, takeDirectory, (</>))

data RoundMode = ReleaseRefresh | ChangeOnly deriving stock (Eq, Show)

data Arm = Baseline | Candidate deriving stock (Eq, Show)

data BaselineEntry = BaselineEntry
  { runId :: Text,
    source :: ObservationSource,
    scenario :: ScenarioId,
    trust :: Trust
  }
  deriving stock (Eq, Show)

data ArtifactReference = ArtifactReference
  { kind :: Text,
    path :: FilePath,
    sha256 :: Text
  }
  deriving stock (Eq, Show)

data RoundDefinition = RoundDefinition
  { roundId :: Text,
    openedAt :: UTCTime,
    mode :: RoundMode,
    inputs :: Map FilePath Text,
    baselineCohort :: (Text, Text),
    candidateCohort :: (Text, Text),
    baseline :: [BaselineEntry],
    references :: [ArtifactReference],
    scopeOverrides :: [ScopeOverride]
  }
  deriving stock (Eq, Show)

data ScopeOverride = ScopeOverride
  { scenario :: ScenarioId,
    reference :: Text,
    appliesTo :: CohortScope,
    reason :: Text
  }
  deriving stock (Eq, Show)

data RoundInputs = RoundInputs
  { owners :: OwnerStatus,
    catalog :: [ScenarioInfo],
    packageMap :: PackageMap,
    graph :: ComponentGraph,
    baselineIdentity :: CohortIdentity,
    candidateIdentity :: CohortIdentity,
    baselineObservations :: [Observation],
    coverage :: Map Text [ScenarioId]
  }

data OpenOptions = OpenOptions
  { roundId :: Text,
    out :: FilePath,
    mode :: RoundMode,
    capture :: InputCapture,
    references :: [(Text, FilePath)]
  }

data InputCapture = FromInputs FilePath | Fresh FreshInputs

data FreshInputs = FreshInputs
  { owners :: FilePath,
    catalog :: ByteString,
    packageMap :: FilePath,
    graph :: ByteString,
    baselineIdentity :: FilePath,
    candidateIdentity :: FilePath,
    loadBaseline :: IO (Either Text [Observation]),
    coverage :: Maybe FilePath,
    scopeOverrides :: Maybe FilePath
  }

openRound :: OpenOptions -> IO (Either RoundError RoundDefinition)
openRound options = runRoundIO do
  requireName options.roundId
  createDirectoryOnce options.out \stage -> do
    files <- case options.capture of
      FromInputs path -> readTree path
      Fresh fresh -> captureInputs fresh
    let inputDir = stage </> "inputs"
    lift $ forM_ files \(path, bytes) -> do
      createDirectoryIfMissing True (takeDirectory (inputDir </> path))
      BS.writeFile (inputDir </> path) bytes
    (inputs, scopeOverrides, capturedReferences) <- decodeInputs inputDir (Map.fromList files)
    references <- traverse (uncurry readArtifactReference) options.references
    openedAt <- lift getCurrentTime
    let definition =
          RoundDefinition
            { roundId = options.roundId,
              openedAt,
              mode = options.mode,
              inputs = Map.fromList [(path, sha256Hex bytes) | (path, bytes) <- files],
              baselineCohort = cohortKey inputs.baselineIdentity,
              candidateCohort = cohortKey inputs.candidateIdentity,
              baseline = map baselineEntry inputs.baselineObservations,
              references = capturedReferences <> references,
              scopeOverrides
            }
    lift (LBS.writeFile (stage </> "round.json") (encode definition))
    pure definition

captureInputs :: FreshInputs -> RoundIO [(FilePath, ByteString)]
captureInputs fresh = do
  owners <- readTree fresh.owners
  observations <- ExceptT (first RoundInput <$> fresh.loadBaseline)
  required <-
    lift $
      traverse
        (\(name, path) -> (name,) <$> BS.readFile path)
        [ ("package-map.json", fresh.packageMap),
          ("baseline-identity.json", fresh.baselineIdentity),
          ("candidate-identity.json", fresh.candidateIdentity)
        ]
  optional <-
    lift $
      traverse
        (\(name, path) -> (name,) <$> BS.readFile path)
        [ (name, path)
        | (name, Just path) <- [("coverage.json", fresh.coverage), ("scope-overrides.json", fresh.scopeOverrides)]
        ]
  pure $
    [("owners" </> name, bytes) | (name, bytes) <- owners]
      <> required
      <> optional
      <> [ ("catalog.json", fresh.catalog),
           ("graph.json", fresh.graph),
           ("baseline-observations.json", LBS.toStrict (encode (map observationValue observations)))
         ]

readRound :: FilePath -> IO (Either RoundError (RoundDefinition, RoundInputs))
readRound path = fmap (fmap (\(definition, inputs, _) -> (definition, inputs))) (readRoundWithDigest path)

-- | Hash the same definition bytes that were decoded.
readRoundWithDigest :: FilePath -> IO (Either RoundError (RoundDefinition, RoundInputs, Text))
readRoundWithDigest path = runRoundIO do
  bytes <- lift (BS.readFile (path </> "round.json"))
  definition <- except (first RoundInput (decodeJson bytes))
  let inputDir = path </> "inputs"
  files <- Map.fromList <$> readTree inputDir
  unless (Map.keysSet files == Map.keysSet definition.inputs) (failRound "round input files do not match round.json")
  forM_ (Map.toList files) \(name, contents) ->
    unless
      (Map.lookup name definition.inputs == Just (sha256Hex contents))
      (failRound ("round input digest mismatch: " <> Text.pack name))
  (inputs, overrides, capturedReferences) <- decodeInputs inputDir files
  unless
    ( definition.baselineCohort == cohortKey inputs.baselineIdentity
        && definition.candidateCohort == cohortKey inputs.candidateIdentity
        && definition.baseline == map baselineEntry inputs.baselineObservations
        && definition.scopeOverrides == overrides
        && take (length capturedReferences) definition.references == capturedReferences
    )
    (failRound "round definition disagrees with its frozen inputs")
  pure (definition, inputs, sha256Hex bytes)

decodeInputs :: FilePath -> Map FilePath ByteString -> RoundIO (RoundInputs, [ScopeOverride], [ArtifactReference])
decodeInputs path files = do
  -- Validate the path before the snapshot reader opens any of its record files.
  _ <- required "owners/snapshot.json" Right
  owners <- ExceptT (first RoundInput <$> readSnapshot (path </> "owners"))
  catalog <- required "catalog.json" decodeCatalog
  unless (Set.size (Set.fromList (map (.id) catalog)) == length catalog) (failRound "catalog has duplicate scenario identifiers")
  packageMap <- required "package-map.json" decodePackageMap
  graph <- required "graph.json" (first (.errorText) . decodeGraph)
  baselineIdentity <- required "baseline-identity.json" decodeJson
  candidateIdentity <- required "candidate-identity.json" decodeJson
  forM_ [baselineIdentity, candidateIdentity] (except . first (RoundInput . Text.pack) . parseEither parseDigest . snd . cohortKey)
  baselineObservations <- required "baseline-observations.json" decodeObservations
  coverage <- optional "coverage.json" decodeCoverage Map.empty
  overrides <- optional "scope-overrides.json" (fmap (\(OverrideDocument entries) -> entries) . decodeJson) []
  _ <- except (applyScopeOverrides overrides catalog)
  references <- optional "references.json" decodeJson []
  forM_ references \ref -> do
    unless
      (isRelative ref.path && all (`notElem` [".", ".."]) (splitDirectories ref.path))
      (failRound ("invalid captured artifact path: " <> Text.pack ref.path))
    _ <- required ref.path \contents ->
      if sha256Hex contents == ref.sha256 then Right () else Left "captured artifact digest mismatch"
    pure ()
  pure (RoundInputs {owners, catalog, packageMap, graph, baselineIdentity, candidateIdentity, baselineObservations, coverage}, overrides, references)
  where
    required :: FilePath -> (ByteString -> Either Text a) -> RoundIO a
    required name decode =
      maybe (failRound ("missing round input: " <> Text.pack name)) (decodeNamed name decode) (Map.lookup name files)
    optional :: FilePath -> (ByteString -> Either Text a) -> a -> RoundIO a
    optional name decode fallback = maybe (pure fallback) (decodeNamed name decode) (Map.lookup name files)
    decodeNamed :: FilePath -> (ByteString -> Either Text a) -> ByteString -> RoundIO a
    decodeNamed name decode = except . first (RoundInput . ((Text.pack name <> ": ") <>)) . decode

readArtifactReference :: Text -> FilePath -> RoundIO ArtifactReference
readArtifactReference kind requested = do
  when (Text.null (Text.strip kind)) (usageError "expected a non-empty reference kind")
  path <- lift (makeAbsolute requested)
  sha256 <- lift (sha256Hex <$> BS.readFile path)
  pure ArtifactReference {kind, path, sha256}

cohortKey :: CohortIdentity -> (Text, Text)
cohortKey identity = (unCohortName identity.identityCohort, unPlanHash identity.identityPlanHash)

baselineEntry :: Observation -> BaselineEntry
baselineEntry observation = BaselineEntry observation.runId observation.source observation.scenario observation.trust

decodeObservations :: ByteString -> Either Text [Observation]
decodeObservations = fmap (\(Observations runs) -> runs) . decodeJson

newtype Observations = Observations [Observation]

instance FromJSON Observations where
  parseJSON = fmap Observations . parseObservations

parseObservations :: Value -> Parser [Observation]
parseObservations value = do
  observations <- parseJSON value >>= traverse parseObservation
  unless (Set.size (Set.fromList (map (.runId) observations)) == length observations) (fail "duplicate observation run identifiers")
  pure observations

decodeJson :: (FromJSON a) => ByteString -> Either Text a
decodeJson = first Text.pack . eitherDecodeStrict'

declaredScopes :: [ScenarioInfo] -> Map (ScenarioId, Text) [CohortScope]
declaredScopes catalog =
  Map.fromListWith
    (<>)
    [ ((scenario.id, defect.reference), [defect.appliesTo])
    | scenario <- catalog,
      declaration <- maybe [] pure scenario.knownDefect,
      defect <- individualKnownDefects declaration
    ]

applyScopeOverrides :: [ScopeOverride] -> [ScenarioInfo] -> Either RoundError [ScenarioInfo]
applyScopeOverrides overrides catalog = do
  unless (Map.size replacements == length overrides) (Left (RoundInput "duplicate round scope override"))
  traverse_ validate overrides
  pure [entry {knownDefect = update entry.id <$> entry.knownDefect} | entry <- catalog]
  where
    replacements = Map.fromList [((entry.scenario, entry.reference), entry.appliesTo) | entry <- overrides]
    scopes = declaredScopes catalog
    validate entry = case Map.lookup (entry.scenario, entry.reference) scopes of
      Just [_] | not (Text.null (Text.strip entry.reason)) -> Right ()
      _ -> Left (RoundInput ("invalid round scope override for " <> entry.reference))
    update scenario = \case
      KnownDefectGroup defects -> KnownDefectGroup (fmap (update scenario) defects)
      KnownDefect {reference, summary, expectedFailures, appliesTo} ->
        KnownDefect reference summary expectedFailures (Map.findWithDefault appliesTo (scenario, reference) replacements)

instance ToJSON RoundMode where
  toJSON ReleaseRefresh = String "release"
  toJSON ChangeOnly = String "change"

instance FromJSON RoundMode where
  parseJSON = withText "round mode" \case
    "release" -> pure ReleaseRefresh
    "change" -> pure ChangeOnly
    _ -> fail "expected round mode release or change"

instance ToJSON Arm where
  toJSON Baseline = String "baseline"
  toJSON Candidate = String "candidate"

instance FromJSON Arm where
  parseJSON = withText "round arm" \case
    "baseline" -> pure Baseline
    "candidate" -> pure Candidate
    _ -> fail "expected round arm baseline or candidate"

instance ToJSON ScopeOverride where
  toJSON entry =
    object ["scenario" .= entry.scenario, "reference" .= entry.reference, "appliesTo" .= scopeValue entry.appliesTo, "reason" .= entry.reason]

instance FromJSON ScopeOverride where
  parseJSON = withObject "round scope override" \item -> do
    unless (all (`elem` ["scenario", "reference", "appliesTo", "reason"]) (KeyMap.keys item)) (fail "unknown scope override field")
    ScopeOverride <$> item .: "scenario" <*> item .: "reference" <*> (item .: "appliesTo" >>= parseScope) <*> item .: "reason"

newtype OverrideDocument = OverrideDocument [ScopeOverride]

instance FromJSON OverrideDocument where
  parseJSON = withObject "round scope overrides" \document -> do
    schema <- document .: "schema"
    unless (schema == ("kenshou.round-scope-overrides/v1" :: Text)) (fail "unsupported round scope overrides schema")
    OverrideDocument <$> document .: "overrides"

instance ToJSON BaselineEntry where
  toJSON entry = object ["runId" .= entry.runId, "source" .= observationSourceValue entry.source, "scenario" .= entry.scenario, "trust" .= renderTrust entry.trust]

instance FromJSON BaselineEntry where
  parseJSON = withObject "round baseline entry" \entry ->
    BaselineEntry
      <$> (renderRunId <$> entry .: "runId")
      <*> (entry .: "source" >>= parseObservationSource)
      <*> entry .: "scenario"
      <*> (entry .: "trust" >>= parseTrust)

instance ToJSON ArtifactReference where
  toJSON entry = object ["kind" .= entry.kind, "path" .= entry.path, "sha256" .= entry.sha256]

instance FromJSON ArtifactReference where
  parseJSON = withObject "round artifact reference" \entry ->
    ArtifactReference <$> entry .: "kind" <*> entry .: "path" <*> (entry .: "sha256" >>= parseDigest)

instance ToJSON RoundDefinition where
  toJSON definition =
    object
      [ "schema" .= ("kenshou.round/v1" :: Text),
        "roundId" .= definition.roundId,
        "openedAt" .= definition.openedAt,
        "mode" .= definition.mode,
        "inputs" .= definition.inputs,
        "baselineCohort" .= cohortValue definition.baselineCohort,
        "candidateCohort" .= cohortValue definition.candidateCohort,
        "baseline" .= definition.baseline,
        "references" .= definition.references,
        "scopeOverrides" .= definition.scopeOverrides
      ]
    where
      cohortValue (name, hash) = object ["name" .= name, "planHash" .= hash]

instance FromJSON RoundDefinition where
  parseJSON = withObject "round definition" \document -> do
    schema <- document .: "schema"
    unless (schema == ("kenshou.round/v1" :: Text)) (fail "unsupported round schema")
    RoundDefinition
      <$> document .: "roundId"
      <*> document .: "openedAt"
      <*> document .: "mode"
      <*> (document .: "inputs" >>= traverse parseDigest)
      <*> (document .: "baselineCohort" >>= parseCohort)
      <*> (document .: "candidateCohort" >>= parseCohort)
      <*> document .: "baseline"
      <*> document .: "references"
      <*> document .: "scopeOverrides"
    where
      parseCohort = withObject "round cohort" \cohort -> (,) <$> cohort .: "name" <*> (cohort .: "planHash" >>= parseDigest)

parseDigest :: Text -> Parser Text
parseDigest raw = case Text.stripPrefix "sha256:" raw of
  Just digest | Right _ <- mkSha256 digest -> pure raw
  _ -> fail "expected a sha256-prefixed lowercase hexadecimal digest"
