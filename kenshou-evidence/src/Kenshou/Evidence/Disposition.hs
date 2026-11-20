-- | Derive fix verification from captured evidence and owner claims.
module Kenshou.Evidence.Disposition
  ( Disposition (..),
    DispositionInput (..),
    CohortSide (..),
    ObservationResult (..),
    ClassifiedObservation (..),
    DispositionReason (..),
    Conclusion (..),
    deriveDispositions,
    decodeDispositionInput,
    dispositionInputValue,
    dispositionsValue,
    renderDispositionsText,
    decodeCoverage,
    observationValue,
    parseObservation,
    observationSourceValue,
    parseObservationSource,
    parseTrust,
    renderDisposition,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (unless)
import Data.Aeson (Value, eitherDecodeStrict', object, withObject, (.!=), (.:), (.:!), (.:?), (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.Types (Parser, parseEither)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.Foldable (toList)
import Data.List (find, groupBy, nub, sortOn)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.Time.Format.ISO8601 (iso8601ParseM)
import Kenshou.Core.Defect
import Kenshou.Core.Id (ScenarioId, renderRunId, renderScenarioId)
import Kenshou.Core.Outcome (Outcome (..))
import Kenshou.Core.Scenario (KnownDefect (..), individualKnownDefects)
import Kenshou.Evidence.Observation
import Kenshou.Evidence.Owner qualified as Owner
import Kenshou.Evidence.Owner.Reconcile (OwnerPackages (..), PackageMap (..), choosePackage, ownerPackages, packageMapValue, parsePackageMap)
import Kenshou.Evidence.Owner.Record (reasonCode, reasonMessage, versionClaimRaw)
import Kenshou.Evidence.Types (mkSha256)
import Kenshou.Plan.Catalog (CatalogDocument (..), ScenarioInfo (..))

data Disposition
  = VerifiedFixed
  | StillReproduces
  | ReproducesAsExpected
  | NotReproduced
  | Regressed
  | DifferentFailure
  | NotYetReleased
  | NotRun
  | Unverifiable
  deriving stock (Eq, Show, Enum, Bounded)

data DispositionInput = DispositionInput
  { capturedAt :: Text,
    owners :: Owner.OwnerStatus,
    catalog :: [ScenarioInfo],
    catalogDigest :: Text,
    packageMap :: PackageMap,
    packageMapDigest :: Text,
    coverage :: Map Text [ScenarioId],
    observations :: [Observation]
  }
  deriving stock (Eq, Show)

data CohortSide = FixedSide | AffectedSide | Open | UnreleasedFix | Unknown Text
  deriving stock (Eq, Show)

data ObservationResult
  = ResultPassed
  | ResultReproduced
  | ResultDifferentFailure
  | ResultSiblingDefect
  | ResultLabelsUnavailable
  | ResultNoSignal
  deriving stock (Eq, Show)

data ClassifiedObservation = ClassifiedObservation
  { observation :: Observation,
    result :: ObservationResult,
    otherFailures :: [Text],
    -- | Each cited reference and its scope evaluation, including duplicate aliases.
    scope :: [(Text, ScopeEvaluation)],
    reproductionInScope :: Bool
  }
  deriving stock (Eq, Show)

data DispositionReason = DispositionReason
  { code :: Text,
    runs :: [Text],
    scenarios :: [ScenarioId],
    detail :: Maybe Text
  }
  deriving stock (Eq, Show)

data Conclusion = Conclusion
  { owner :: Text,
    claim :: Maybe Owner.OwnerRecord,
    cohort :: Maybe (Text, Text),
    side :: Maybe CohortSide,
    disposition :: Disposition,
    reasons :: [DispositionReason],
    required :: Map ScenarioId (Maybe Text),
    considered :: [ClassifiedObservation],
    incompatible :: [Observation]
  }
  deriving stock (Eq, Show)

data CohortEvidence = CohortEvidence
  { identity :: (Text, Text),
    side :: Maybe CohortSide,
    compatible :: [ClassifiedObservation],
    incompatible :: [Observation]
  }

-- | Derive one conclusion for each canonical owner and observed cohort.
-- Alias declarations are pooled per scenario, with their evaluations retained.
deriveDispositions :: DispositionInput -> [Conclusion]
deriveDispositions input = concatMap (uncurry concludeOwner) (Map.toAscList owners)
  where
    canonical = Owner.canonicalOwners input.owners
    ownerOf reference = maybe reference (\(entry :: Owner.OwnerEntry) -> entry.reference) (Map.lookup reference canonical)
    declarations =
      Map.fromListWith
        (Map.unionWith (<>))
        [ (ownerOf defect.reference, Map.singleton info.id [(info, defect)])
        | info <- input.catalog,
          defect@KnownDefect {} <- maybe [] individualKnownDefects info.knownDefect
        ]
    owners =
      Map.union
        (Map.fromList [(entry.reference, Just entry) | entry <- Map.elems canonical])
        (Map.map (const Nothing) declarations)
    byScenario = Map.fromListWith (<>) [(run.scenario, [run]) | run <- input.observations]

    concludeOwner reference entry =
      let claim = entry >>= (.record)
          attributed = Map.findWithDefault Map.empty reference declarations
          requiredIds = fromMaybe (Map.keys attributed) (Map.lookup reference input.coverage <|> aliasCoverage reference)
          required = Map.fromList [(scenario, Nothing) | scenario <- requiredIds]
          base = Conclusion reference claim Nothing Nothing NotRun [] required [] []
          runs =
            [ (run, classifyFor run scenarioDefects)
            | (scenario, scenarioDefects) <- Map.toAscList attributed,
              run <- Map.findWithDefault [] scenario byScenario
            ]
          classifyFor run scenarioDefects@((info, _) : _)
            | Just info.revision == run.scenarioRevision =
                let allDefects = maybe [] individualKnownDefects info.knownDefect
                    siblings = [defect | defect@KnownDefect {} <- allDefects, ownerOf defect.reference /= reference]
                 in Just (classify run (map snd scenarioDefects) siblings)
          classifyFor _ _ = Nothing
          incompatible = sortOn runOrder [run | (run, Nothing) <- runs]
          chooseSide packages = case entry of
            Just ownerEntry -> claimSide input.packageMap ownerEntry (map snd (concat (Map.elems attributed))) packages
            Nothing -> Unknown "unmapped-owner"
          cohorts =
            map (collectCohort chooseSide) . Map.toAscList $
              Map.fromListWith (<>) [(run.planHash, [(run, classification)]) | (run, classification) <- runs]
       in case entry of
            Just ownerEntry
              | ownerEntry.resolution == Owner.Resolved,
                ownerEntry.canonical == Just reference,
                Just record <- claim ->
                  if any (not . null . (.compatible)) cohorts
                    then map (concludeCohort base (regressionPasses cohorts)) cohorts
                    else
                      [ base
                          { disposition = if record.status == Just "fixed" && record.fixedVersion == Owner.ClaimUnreleased then NotYetReleased else NotRun,
                            reasons = [reason "incompatible-revision" incompatible [] | not (null incompatible)],
                            incompatible = incompatible
                          }
                      ]
            _ ->
              [ base
                  { disposition = Unverifiable,
                    reasons = case maybe [] (.reasons) entry of
                      [] -> [reason "no-owner-claim" [] []]
                      reasons -> [DispositionReason (reasonCode item) [] [] (Just (reasonMessage item)) | item <- reasons],
                    considered = sortOn (runOrder . (.observation)) (mapMaybe snd runs),
                    incompatible = incompatible
                  }
              ]

    aliasCoverage reference = case nub [required | (alias, required) <- Map.toAscList input.coverage, alias /= reference, ownerOf alias == reference] of
      [required] -> Just required
      _ -> Nothing

runOrder :: Observation -> (Maybe UTCTime, Text)
runOrder run = (iso8601ParseM (Text.unpack run.startedAt), run.runId)

classify :: Observation -> [KnownDefect] -> [KnownDefect] -> ClassifiedObservation
classify run own siblings =
  ClassifiedObservation run result other scope (Set.isSubsetOf matching applicable)
  where
    scope =
      [(defect.reference, evaluateScope run.packages defect.appliesTo) | defect@KnownDefect {} <- own]
    applicable = labelsFrom [defect | (defect, (_, evaluated)) <- zip own scope, scopeApplies evaluated]
    applicableSiblings = labelsFrom [defect | defect@KnownDefect {} <- siblings, scopeApplies (evaluateScope run.packages defect.appliesTo)]
    labelsFrom defects = Set.fromList [label | KnownDefect {expectedFailures} <- defects, label <- toList expectedFailures]
    failures = case run.labels of
      LabelsVerified labels -> Set.fromList labels
      LabelsUnavailable _ -> Set.empty
    ownLabels = labelsFrom own
    matching = failures `Set.intersection` ownLabels
    uncovered = failures `Set.difference` (ownLabels `Set.union` applicableSiblings)
    result = case run.outcome of
      Passed -> ResultPassed
      Failed -> case run.labels of
        LabelsUnavailable _ -> ResultLabelsUnavailable
        LabelsVerified _
          | not (Set.null matching) -> ResultReproduced
          | not (Set.null failures) && Set.null uncovered -> ResultSiblingDefect
          | otherwise -> ResultDifferentFailure
      _ -> ResultNoSignal
    other = [label | run.outcome == Failed, label <- Set.toAscList uncovered]

claimSide :: PackageMap -> Owner.OwnerEntry -> [KnownDefect] -> [ScopePackage] -> CohortSide
claimSide mapping owner declarations packages = case select of
  Left problem -> Unknown problem
  Right (package, comparable) -> case owner.record of
    Just claim
      | claim.status /= Just "fixed" -> Open
      | otherwise -> case claim.fixedVersion of
          Owner.ClaimUnreleased -> UnreleasedFix
          Owner.ClaimReleased fixedVersion _
            | not comparable -> Unknown "owner-version-not-package-version"
            | otherwise -> compareVersion package fixedVersion
          _ -> Unknown "unsupported-claim"
    Nothing -> Unknown "no-owner-claim"
  where
    select = do
      choices <- traverse mapped declarations
      case nub (map fst choices) of
        [package] -> Right (package, all snd choices)
        _ -> Left "ambiguous-package-mapping"
    mapped KnownDefect {reference, appliesTo} = do
      ownerMapping <- maybe (Left "unmapped-owner") Right (Map.lookup reference mapping.byReference <|> ownerPackages mapping owner)
      package <- choosePackage ownerMapping appliesTo
      pure (package, package `elem` ownerMapping.versionsApplyTo)
    mapped (KnownDefectGroup _) = Left "ambiguous-package-mapping"
    compareVersion name fixedVersion = case nub [package | package <- packages, package.name == name] of
      [] -> Unknown "package-missing"
      [package] -> case package.source of
        ScopeGit _ -> Unknown "git-cohort"
        _ -> case parseScopeVersion package.version of
          Nothing -> Unknown "unparseable-version"
          Just version -> if version >= fixedVersion then FixedSide else AffectedSide
      _ -> Unknown "ambiguous-cohort-package"

collectCohort :: ([ScopePackage] -> CohortSide) -> (Text, [(Observation, Maybe ClassifiedObservation)]) -> CohortEvidence
collectCohort chooseSide (hash, runs) =
  CohortEvidence
    { identity = (minimum [run.cohortName | (run, _) <- runs], hash),
      side = case nub [chooseSide run.observation.packages | run <- compatible] of
        [] -> Nothing
        [side] -> Just side
        _ -> Just (Unknown "inconsistent-cohort-packages"),
      compatible,
      incompatible = [run | (run, Nothing) <- ordered]
    }
  where
    ordered = sortOn (runOrder . fst) runs
    compatible = mapMaybe snd ordered

confirmed :: Observation -> Bool
confirmed run = run.trust `elem` [MachineConfirmed, HumanReviewed]

regressionPasses :: [CohortEvidence] -> Map ScenarioId [Observation]
regressionPasses cohorts =
  Map.map (reverse . sortOn runOrder) $
    Map.fromListWith
      (<>)
      [ (run.observation.scenario, [run.observation])
      | cohort <- cohorts,
        cohort.side == Just FixedSide,
        run <- cohort.compatible,
        run.result == ResultPassed,
        confirmed run.observation
      ]

-- The precedence here follows the public decision table. Only the three signal
-- results can become a scenario's latest observation.
concludeCohort :: Conclusion -> Map ScenarioId [Observation] -> CohortEvidence -> Conclusion
concludeCohort base earlierPasses evidence =
  base
    { cohort = Just evidence.identity,
      side = evidence.side,
      disposition,
      reasons = primary <> supplementary,
      required = Map.mapWithKey (\scenario _ -> fmap (.observation.runId) (Map.lookup scenario latest)) base.required,
      considered = evidence.compatible,
      incompatible = evidence.incompatible
    }
  where
    newestFirst = reverse evidence.compatible
    latest =
      Map.fromListWith
        (flip const)
        [(run.observation.scenario, run) | run <- newestFirst, run.result `elem` [ResultPassed, ResultReproduced, ResultDifferentFailure]]
    requiredLatest = Map.intersection latest base.required
    missing = Map.keys (Map.difference base.required requiredLatest)
    reproductions = filter ((== ResultReproduced) . (.result)) (Map.elems latest)
    regressions =
      [ (run, earlier)
      | run <- reproductions,
        Just earlier <- [find ((< runOrder run.observation) . runOrder) (Map.findWithDefault [] run.observation.scenario earlierPasses)]
      ]
    different = filter ((== ResultDifferentFailure) . (.result)) (Map.elems latest)
    newerThanSignal classified = maybe True ((< runOrder classified.observation) . runOrder . (.observation)) (Map.lookup classified.observation.scenario latest)
    unreadable =
      [ run
      | run <- newestFirst,
        run.result == ResultLabelsUnavailable,
        Map.member run.observation.scenario base.required,
        newerThanSignal run
      ]
    weak = filter (not . confirmed . (.observation)) (Map.elems requiredLatest)
    outside = filter (not . (.reproductionInScope)) reproductions
    (disposition, primary)
      | evidence.side == Just FixedSide,
        not (null regressions) =
          (Regressed, [reason "earlier-confirmed-pass" [earlier, run.observation] [run.observation.scenario] | (run, earlier) <- regressions])
      | evidence.side == Just FixedSide, not (null reproductions) = (StillReproduces, [])
      | not (null reproductions) = case (evidence.side, outside) of
          (_, []) -> (ReproducesAsExpected, [])
          (Just (Unknown problem), _) -> (Unverifiable, [reason problem [] [], forRuns "outside-declared-scope" outside])
          _ -> (StillReproduces, [forRuns "outside-declared-scope" outside])
      | not (null different) = (DifferentFailure, [])
      | not (null unreadable) = (Unverifiable, [forRuns "labels-unavailable" unreadable])
      | not (Map.null requiredLatest),
        null missing = case evidence.side of
          Just FixedSide
            | null weak -> (VerifiedFixed, [])
            | otherwise -> (NotReproduced, [forRuns "insufficient-trust" weak])
          Just UnreleasedFix -> (NotYetReleased, [])
          Just (Unknown problem) -> (Unverifiable, [reason problem [] []])
          _ -> (NotReproduced, [])
      | not (Map.null requiredLatest) =
          (if evidence.side == Just UnreleasedFix then NotYetReleased else NotReproduced, [reason "incomplete-coverage" [] missing])
      | otherwise = (Unverifiable, unusable)
    unusable = case unusableEvidence of
      [] -> [reason "incomplete-coverage" [] missing]
      reasons' -> reasons'
    unusableEvidence =
      [ forRuns code runs
      | (result, code) <- [(ResultNoSignal, "no-signal"), (ResultSiblingDefect, "sibling-defect")],
        let runs = filter ((== result) . (.result)) newestFirst,
        not (null runs)
      ]
        <> [reason "incompatible-revision" evidence.incompatible [] | not (null evidence.incompatible)]
        <> [reason "incomplete-coverage" [] missing | not (Map.null latest)]
    supplementary =
      [ forRuns "later-run-without-signal" later
      | let later = [run | run <- newestFirst, run.result `elem` [ResultNoSignal, ResultSiblingDefect], Map.member run.observation.scenario latest, newerThanSignal run],
        not (null later)
      ]
        <> [forRuns "other-failures-present" mixed | let mixed = filter (not . null . (.otherFailures)) reproductions, not (null mixed)]

reason :: Text -> [Observation] -> [ScenarioId] -> DispositionReason
reason code runs scenarios = DispositionReason code (map (.runId) runs) scenarios Nothing

forRuns :: Text -> [ClassifiedObservation] -> DispositionReason
forRuns code items = reason code (map (.observation) items) (nub (map (.observation.scenario) items))

-- Frozen input ---------------------------------------------------------------

inputSchema :: Text
inputSchema = "kenshou.disposition-input/v1"

dispositionInputValue :: DispositionInput -> Value
dispositionInputValue input =
  object
    [ "schema" .= inputSchema,
      "capturedAt" .= input.capturedAt,
      "owners" .= Owner.ownerStatusValue input.owners,
      "catalog" .= CatalogDocument input.catalog,
      "catalogDigest" .= input.catalogDigest,
      "packageMap" .= packageMapValue input.packageMap,
      "packageMapDigest" .= input.packageMapDigest,
      "coverage" .= input.coverage,
      "observations" .= map observationValue input.observations
    ]

decodeDispositionInput :: ByteString -> Either Text DispositionInput
decodeDispositionInput bytes = first Text.pack (eitherDecodeStrict' bytes >>= parseEither parseInput)
  where
    parseInput = withObject "disposition input" \document -> do
      schema <- document .: "schema"
      unless (schema == inputSchema) (fail "unsupported disposition-input schema")
      capturedAt <- document .: "capturedAt" >>= timestamp
      owners <- document .: "owners" >>= Owner.parseOwnerStatus
      _ <- traverse digest owners.snapshotDigest
      CatalogDocument catalog <- document .: "catalog"
      unless (Set.size (Set.fromList [info.id | info <- catalog]) == length catalog) (fail "catalog has duplicate scenario identifiers")
      catalogDigest <- document .: "catalogDigest" >>= digest
      packageMap <- document .: "packageMap" >>= parsePackageMap
      packageMapDigest <- document .: "packageMapDigest" >>= digest
      coverage <- document .:? "coverage" .!= Map.empty
      observations <- document .: "observations" >>= traverse parseObservation
      pure DispositionInput {capturedAt, owners, catalog, catalogDigest, packageMap, packageMapDigest, coverage, observations}

-- | Coverage is a JSON object keyed by owner reference with scenario ID arrays.
decodeCoverage :: ByteString -> Either Text (Map Text [ScenarioId])
decodeCoverage = first Text.pack . eitherDecodeStrict'

digest :: Text -> Parser Text
digest raw = case Text.stripPrefix "sha256:" raw >>= either (const Nothing) Just . mkSha256 of
  Nothing -> fail "expected a sha256-prefixed lowercase hexadecimal digest"
  Just _ -> pure raw

timestamp :: Text -> Parser Text
timestamp raw = case iso8601ParseM (Text.unpack raw) :: Maybe UTCTime of
  Just _ -> pure raw
  Nothing -> fail "expected an ISO 8601 UTC timestamp"

observationValue :: Observation -> Value
observationValue run =
  object $
    [ "runId" .= run.runId,
      "source" .= observationSourceValue run.source,
      "scenario" .= run.scenario,
      "scenarioRevision" .= run.scenarioRevision,
      "startedAt" .= run.startedAt,
      "outcome" .= run.outcome,
      "labels" .= labelsValue run.labels,
      "packages" .= map packageValue run.packages,
      "cohortName" .= run.cohortName,
      "planHash" .= run.planHash,
      "trust" .= renderTrust run.trust
    ]
      <> ["replay" .= result | Just result <- [run.replay]]
  where
    labelsValue = \case
      LabelsVerified labels -> object ["kind" .= ("verified" :: Text), "values" .= labels]
      LabelsUnavailable why -> object ["kind" .= ("unavailable" :: Text), "reason" .= why]
    packageValue :: ScopePackage -> Value
    packageValue package = object (["name" .= package.name, "version" .= package.version] <> sourcePairs package.source)
    sourcePairs = \case
      ScopeHackage -> ["source" .= ("hackage" :: Text)]
      ScopeGit revision -> ["source" .= ("git" :: Text), "revision" .= revision]
      ScopeOther -> ["source" .= ("other" :: Text)]

parseObservation :: Value -> Parser Observation
parseObservation = withObject "observation" \item ->
  Observation
    <$> (renderRunId <$> item .: "runId")
    <*> (item .: "source" >>= parseObservationSource)
    <*> item .: "scenario"
    <*> item .: "scenarioRevision"
    <*> (item .: "startedAt" >>= timestamp)
    <*> item .: "outcome"
    <*> (item .: "labels" >>= parseLabels)
    <*> (item .: "packages" >>= traverse parsePackage)
    <*> item .: "cohortName"
    <*> (item .: "planHash" >>= digest)
    <*> (item .: "trust" >>= parseTrust)
    <*> item .:! "replay"
  where
    parseLabels = withObject "failure labels" \labels ->
      labels .: "kind" >>= \case
        ("verified" :: Text) -> LabelsVerified <$> labels .: "values"
        "unavailable" -> LabelsUnavailable <$> labels .: "reason"
        _ -> fail "unknown label availability"
    parsePackage = withObject "resolved package" \package -> do
      source <-
        package .: "source" >>= \case
          ("hackage" :: Text) -> pure ScopeHackage
          "git" -> ScopeGit <$> package .: "revision"
          "other" -> pure ScopeOther
          _ -> fail "unknown package source"
      ScopePackage <$> package .: "name" <*> package .: "version" <*> pure source

observationSourceValue :: ObservationSource -> Value
observationSourceValue = \case
  PublishedRecord concept -> object ["kind" .= ("published-record" :: Text), "reference" .= concept]
  SealedRun path -> object ["kind" .= ("sealed-run" :: Text), "path" .= path]

parseObservationSource :: Value -> Parser ObservationSource
parseObservationSource = withObject "observation source" \source ->
  source .: "kind" >>= \case
    ("published-record" :: Text) -> PublishedRecord <$> source .: "reference"
    "sealed-run" -> SealedRun <$> source .: "path"
    _ -> fail "unknown observation source"

parseTrust :: Text -> Parser Trust
parseTrust raw = maybe (fail "unknown evidence trust") pure (find ((== raw) . renderTrust) [minBound .. maxBound])

-- Reports -------------------------------------------------------------------

renderDisposition :: Disposition -> Text
renderDisposition = \case
  VerifiedFixed -> "verified-fixed"
  StillReproduces -> "still-reproduces"
  ReproducesAsExpected -> "reproduces-as-expected"
  NotReproduced -> "not-reproduced"
  Regressed -> "regressed"
  DifferentFailure -> "different-failure"
  NotYetReleased -> "not-yet-released"
  NotRun -> "not-run"
  Unverifiable -> "unverifiable"

renderSide :: CohortSide -> Text
renderSide = \case
  FixedSide -> "fixed-side"
  AffectedSide -> "affected-side"
  Open -> "open"
  UnreleasedFix -> "unreleased-fix"
  Unknown _ -> "unknown"

renderResult :: ObservationResult -> Text
renderResult = \case
  ResultPassed -> "passed"
  ResultReproduced -> "reproduced"
  ResultDifferentFailure -> "different-failure"
  ResultSiblingDefect -> "sibling-defect"
  ResultLabelsUnavailable -> "labels-unavailable"
  ResultNoSignal -> "no-signal"

summaryCounts :: [Conclusion] -> [(Text, Int)]
summaryCounts conclusions =
  [ (key, length (filter ((== disposition) . (.disposition)) conclusions))
  | (key, disposition) <-
      [ ("verifiedFixed", VerifiedFixed),
        ("stillReproduces", StillReproduces),
        ("reproducesAsExpected", ReproducesAsExpected),
        ("notReproduced", NotReproduced),
        ("regressed", Regressed),
        ("differentFailure", DifferentFailure),
        ("notYetReleased", NotYetReleased),
        ("notRun", NotRun),
        ("unverifiable", Unverifiable)
      ]
  ]

dispositionsValue :: DispositionInput -> [Conclusion] -> Value
dispositionsValue input conclusions =
  object
    [ "schema" .= ("kenshou.dispositions/v1" :: Text),
      "capturedAt" .= input.capturedAt,
      "snapshot" .= input.owners.snapshotDigest,
      "catalogDigest" .= input.catalogDigest,
      "packageMapDigest" .= input.packageMapDigest,
      "conclusions" .= map conclusionValue conclusions,
      "summary" .= object [Key.fromText key .= count | (key, count) <- summaryCounts conclusions]
    ]
  where
    conclusionValue :: Conclusion -> Value
    conclusionValue conclusion =
      object
        [ "owner" .= conclusion.owner,
          "claim" .= fmap claimValue conclusion.claim,
          "cohort" .= fmap (\(name, hash) -> object ["name" .= name, "planHash" .= hash]) conclusion.cohort,
          "side" .= fmap sideValue conclusion.side,
          "disposition" .= renderDisposition conclusion.disposition,
          "reasons" .= map reasonValue conclusion.reasons,
          "required" .= [object ["scenario" .= scenario, "latest" .= latest] | (scenario, latest) <- Map.toAscList conclusion.required],
          "considered" .= map classifiedValue conclusion.considered,
          "incompatible" .= map observationValue conclusion.incompatible
        ]
    claimValue :: Owner.OwnerRecord -> Value
    claimValue claim = object ["status" .= claim.status, "versions" .= Owner.ownerVersionsValue claim]
    sideValue side = object (["kind" .= renderSide side] <> ["reason" .= why | Unknown why <- [side]])
    reasonValue :: DispositionReason -> Value
    reasonValue why = object (["code" .= why.code, "runs" .= why.runs, "scenarios" .= why.scenarios] <> ["detail" .= detail | Just detail <- [why.detail]])
    classifiedValue :: ClassifiedObservation -> Value
    classifiedValue run =
      object
        [ "observation" .= observationValue run.observation,
          "result" .= renderResult run.result,
          "otherFailures" .= run.otherFailures,
          "scope" .= [object ["reference" .= reference, "evaluation" .= scopeValue' evaluated] | (reference, evaluated) <- run.scope]
        ]
    scopeValue' evaluated = object ["applies" .= scopeApplies evaluated, "conditions" .= conditions evaluated]
    conditions AppliesToAll = []
    conditions (Evaluated values) =
      [object (["condition" .= conditionValue condition, "result" .= conditionResult result] <> ["malformed" .= raw | ConditionMalformed raw <- [result]]) | (condition, result) <- toList values]
    conditionResult :: ConditionResult -> Text
    conditionResult = \case
      ConditionHolds -> "holds"
      ConditionFails -> "fails"
      ConditionPackageMissing -> "package-missing"
      ConditionMalformed _ -> "malformed-version"

renderDispositionsText :: [Conclusion] -> Text
renderDispositionsText conclusions =
  Text.unlines (concatMap ownerBlock (groupBy (\left right -> left.owner == right.owner) conclusions) <> ["summary " <> Text.unwords [key <> "=" <> Text.pack (show count) | (key, count) <- summaryCounts conclusions]])
  where
    ownerBlock [] = []
    ownerBlock group@(firstConclusion : _) =
      [ firstConclusion.owner <> maybe "" reportClaim firstConclusion.claim
      ]
        <> concatMap cohortBlock group
        <> [""]
    reportClaim :: Owner.OwnerRecord -> Text
    reportClaim claim = "  status=" <> fromMaybe "(absent)" claim.status <> "  fixedVersion=" <> fromMaybe "(absent)" (versionClaimRaw claim.fixedVersion)
    cohortBlock :: Conclusion -> [Text]
    cohortBlock conclusion =
      [ "  "
          <> maybe "(no cohort)" (\(name, hash) -> name <> " (" <> hash <> ")") conclusion.cohort
          <> maybe "" (\side -> "  " <> renderSide side) conclusion.side
          <> "  "
          <> renderDisposition conclusion.disposition
      ]
        <> map reportReason conclusion.reasons
        <> [reportRun (renderResult run.result) run.observation | run <- conclusion.considered]
        <> map (reportRun "incompatible-revision") conclusion.incompatible
    reportReason :: DispositionReason -> Text
    reportReason why =
      "    "
        <> why.code
        <> maybe "" ("  " <>) why.detail
        <> Text.concat ["  " <> Text.intercalate ", " names | names <- [map renderScenarioId why.scenarios, why.runs], not (null names)]
    reportRun :: Text -> Observation -> Text
    reportRun result run =
      "    "
        <> renderScenarioId run.scenario
        <> "  "
        <> result
        <> labelText run
        <> "  "
        <> renderTrust run.trust
        <> "  run "
        <> run.runId

    labelText :: Observation -> Text
    labelText run = case run.labels of
      LabelsVerified labels | run.outcome == Failed, not (null labels) -> " [" <> Text.intercalate ", " labels <> "]"
      _ -> ""
