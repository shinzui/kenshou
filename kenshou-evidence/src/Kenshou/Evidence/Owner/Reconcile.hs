-- | Scope reconciliation: compare each known defect's cohort scope with the
-- version claims of the owner record it cites, and propose reviewable
-- corrections. Nothing here edits a scenario's source or an owner's record; a
-- proposal is a value for a person to review and apply by hand.
--
-- An owner record names an affected project (@affects@); a scope names cabal
-- packages. The consumer states which packages a project's defect lives in, and
-- which of them carry the project's release version numbers, in a
-- @kenshou.owner-package-map/v1@ document. Nothing is guessed: a project mapped to
-- several packages that the scope does not disambiguate, or an owner version that
-- is not a version of the chosen package, produces a warning and no proposal.
module Kenshou.Evidence.Owner.Reconcile
  ( -- * Package map
    OwnerPackages (..),
    PackageMap (..),
    decodePackageMap,
    parsePackageMap,
    packageMapValue,
    ownerPackages,
    choosePackage,

    -- * Findings
    Severity (..),
    renderSeverity,
    ScopeFinding (..),
    reconcileScopes,
    FindingCounts (..),
    findingCounts,

    -- * Reports
    reconciliationValue,
    renderReconciliationText,
    renderScope,
  )
where

import Control.Applicative ((<|>))
import Control.Monad (unless, when)
import Data.Aeson (Value, object, (.!=), (.:), (.:?), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types (Parser, parseEither, withObject)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.Foldable (toList)
import Data.List (minimumBy, nub)
import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isNothing, mapMaybe)
import Data.Ord (comparing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time.Format.ISO8601 (iso8601Show)
import Data.Version (Version)
import Kenshou.Core.Defect (conditionPackage, defectValue, parseScopeVersion)
import Kenshou.Core.Id (ScenarioId, renderScenarioId)
import Kenshou.Core.Scenario (CohortScope (..), KnownDefect (..), PackageCondition (..), individualKnownDefects)
import Kenshou.Evidence.Owner
import Kenshou.Evidence.Owner.Record (reasonCode, versionClaimRaw, versionClaimState)
import Kenshou.Plan.Catalog (ScenarioInfo (..))

-- | The packages an owner's defect lives in, and those of them whose version
-- numbers are the ones the owner writes in its version fields.
data OwnerPackages = OwnerPackages
  { packages :: [Text],
    versionsApplyTo :: [Text]
  }
  deriving stock (Eq, Show)

-- | A decoded @kenshou.owner-package-map/v1@ document. 'byReference' entries
-- override 'byAffects' entries; 'sources' locates a scenario's declaration in the
-- consumer's source, for the reviewer.
data PackageMap = PackageMap
  { byAffects :: Map Text OwnerPackages,
    byReference :: Map Text OwnerPackages,
    sources :: Map ScenarioId (FilePath, Maybe Int)
  }
  deriving stock (Eq, Show)

-- | Decode a package map. Every owner entry names exactly one of @affects@ and
-- @reference@, a non-empty @packages@ list, and a required @versionsApplyTo@
-- list that is a subset of it; no key may appear twice.
decodePackageMap :: ByteString -> Either Text PackageMap
decodePackageMap bytes = do
  document <- first Text.pack (Aeson.eitherDecodeStrict' bytes)
  first Text.pack (parseEither parsePackageMap document)

parsePackageMap :: Value -> Parser PackageMap
parsePackageMap = withObject "owner package map" \document -> do
  schema <- document .: "schema"
  when (schema /= ("kenshou.owner-package-map/v1" :: Text)) (fail "schema must be kenshou.owner-package-map/v1")
  owners <- document .: "owners" >>= traverse ownerEntry
  located <- document .:? "sources" .!= [] >>= traverse sourceEntry
  byAffects <- unique "affects" [(key, packages) | (Left key, packages) <- owners]
  byReference <- unique "reference" [(key, packages) | (Right key, packages) <- owners]
  sources <- unique "scenario" located
  pure PackageMap {byAffects, byReference, sources}
  where
    ownerEntry = withObject "owner entry" \item -> do
      affects <- item .:? "affects"
      reference <- item .:? "reference"
      key <- case (affects, reference) of
        (Just value, Nothing) -> pure (Left value)
        (Nothing, Just value) -> pure (Right value)
        _ -> fail "an owner entry names exactly one of affects and reference"
      packages <- item .: "packages"
      when (null packages) (fail "packages must not be empty")
      versionsApplyTo <- item .: "versionsApplyTo"
      unless (all (`elem` packages) versionsApplyTo) (fail "versionsApplyTo must be a subset of packages")
      pure (key, OwnerPackages {packages, versionsApplyTo})
    sourceEntry = withObject "source" \item -> do
      scenario <- item .: "scenario"
      path <- item .: "path"
      line <- item .:? "line"
      pure (scenario, (path, line))
    unique :: (Ord key, Show key) => String -> [(key, value)] -> Parser (Map key value)
    unique label pairs = case [key | (key, count) <- Map.toList (Map.fromListWith (+) [(key, 1 :: Int) | (key, _) <- pairs]), count > 1] of
      [] -> pure (Map.fromList pairs)
      repeated -> fail ("duplicate " <> label <> " " <> show repeated)

packageMapValue :: PackageMap -> Value
packageMapValue mapping =
  object
    [ "schema" .= ("kenshou.owner-package-map/v1" :: Text),
      "owners" .= (entries "affects" mapping.byAffects <> entries "reference" mapping.byReference),
      "sources" .= [object (["scenario" .= scenario, "path" .= path] <> ["line" .= number | Just number <- [line]]) | (scenario, (path, line)) <- Map.toList mapping.sources]
    ]
  where
    entries key values =
      [object [key .= name, "packages" .= owner.packages, "versionsApplyTo" .= owner.versionsApplyTo] | (name, owner) <- Map.toList values]

-- | The packages for an owner record: the entry keyed by the record's reference,
-- otherwise the entry keyed by its @affects@ value.
ownerPackages :: PackageMap -> OwnerEntry -> Maybe OwnerPackages
ownerPackages packageMap entry =
  Map.lookup entry.reference packageMap.byReference
    <|> (entry.record >>= (.affects) >>= (`Map.lookup` packageMap.byAffects))

-- | The package a comparison is about: the only mapped package, or the only
-- mapped package a condition of the scope names. Otherwise the warning code
-- @ambiguous-package-mapping@; several packages are never resolved by picking one.
choosePackage :: OwnerPackages -> CohortScope -> Either Text Text
choosePackage owner scope = case owner.packages of
  [single] -> Right single
  several -> case nub [package | package <- several, package `elem` named] of
    [one] -> Right one
    _ -> Left "ambiguous-package-mapping"
  where
    named = scopePackages scope

scopePackages :: CohortScope -> [Text]
scopePackages AllCohorts = []
scopePackages (OnlyWhen conditions) = nub (fmap conditionPackage (toList conditions))

-- | A finding's severity. A contradiction makes @owners reconcile@ exit 1; a
-- warning asks for consumer input; 'Consistent' has no severity.
data Severity = Contradiction | Warning | Consistent
  deriving stock (Eq, Show)

renderSeverity :: Severity -> Maybe Text
renderSeverity = \case
  Contradiction -> Just "contradiction"
  Warning -> Just "warning"
  Consistent -> Nothing

-- | One finding about one individual defect of a scenario. Each individual defect
-- has exactly one 'primary' finding; a secondary @scope-package-not-mapped@
-- warning has 'primary' false. 'current' and 'proposed' are the individual defect
-- with its present and proposed scope; 'package' is the package compared.
data ScopeFinding = ScopeFinding
  { scenario :: ScenarioId,
    reference :: Text,
    canonical :: Maybe Text,
    snapshot :: Maybe Text,
    ownerStatus :: Maybe Text,
    ownerFixedVersion :: VersionClaim,
    package :: Maybe Text,
    code :: Text,
    severity :: Severity,
    primary :: Bool,
    current :: KnownDefect,
    proposed :: Maybe KnownDefect,
    rationale :: Text,
    notes :: [Text],
    location :: Maybe (FilePath, Maybe Int)
  }
  deriving stock (Eq, Show)

data Verdict = Verdict
  { code :: Text,
    severity :: Severity,
    package :: Maybe Text,
    scope :: Maybe CohortScope,
    rationale :: Text,
    notes :: [Text]
  }

-- | Reconcile every individual defect of every scenario with the owner claims in
-- a status document (normally read from a snapshot). Findings follow the
-- scenarios' order, each defect's primary finding before its secondary ones.
reconcileScopes :: OwnerStatus -> PackageMap -> [ScenarioInfo] -> [ScopeFinding]
reconcileScopes status packageMap scenarios =
  [ finding
  | info <- scenarios,
    defect@KnownDefect {} <- maybe [] individualKnownDefects info.knownDefect,
    finding <- defectFindings status packageMap info.id defect
  ]

defectFindings :: OwnerStatus -> PackageMap -> ScenarioId -> KnownDefect -> [ScopeFinding]
defectFindings status packageMap scenario defect = primaryFinding : secondary
  where
    reference = defect.reference
    scope = defect.appliesTo
    entries = Map.fromList [(entry.reference, entry) | entry <- status.records]
    own = Map.lookup reference entries
    canonicalEntry = do
      entry <- own
      target <- entry.canonical
      found <- Map.lookup target entries
      claims <- found.record
      pure (found, claims)
    record = snd <$> canonicalEntry
    mapping = case canonicalEntry of
      Nothing -> Nothing
      Just (entry, _) -> Map.lookup reference packageMap.byReference <|> ownerPackages packageMap entry
    finding verdict primary =
      ScopeFinding
        { scenario,
          reference,
          canonical = (\(entry, _) -> entry.reference) <$> canonicalEntry,
          snapshot = status.snapshotDigest,
          ownerStatus = record >>= (.status),
          ownerFixedVersion = maybe ClaimAbsent (.fixedVersion) record,
          package = verdict.package,
          code = verdict.code,
          severity = verdict.severity,
          primary,
          current = defect,
          proposed = fmap (\proposal -> KnownDefect {reference, summary = defect.summary, expectedFailures = defect.expectedFailures, appliesTo = proposal}) verdict.scope,
          rationale = verdict.rationale,
          notes = verdict.notes,
          location = Map.lookup scenario packageMap.sources
        }
    primaryFinding = finding (judge (fmap fst canonicalEntry) record mapping) True
    secondary = case mapping of
      Nothing -> []
      Just owner ->
        [ finding (Verdict "scope-package-not-mapped" Warning (Just named) Nothing ("the scope names " <> named <> ", which the package map does not list for this owner") []) False
        | named <- scopePackages scope,
          named `notElem` owner.packages
        ]

    judge Nothing _ _ = noOwnerClaim
    judge _ Nothing _ = noOwnerClaim
    judge (Just entry) (Just claims) Nothing =
      warning "unmapped-owner" Nothing ("the package map has no entry for " <> maybe ("the reference " <> entry.reference) ("the project " <>) claims.affects)
    judge (Just _) (Just claims) (Just owner) = case choosePackage owner scope of
      Left warningCode ->
        let named = filter (`elem` owner.packages) (scopePackages scope)
            namedText = if null named then "none of them" else "several of them: " <> Text.intercalate ", " named
         in warning warningCode Nothing ("the owner maps to " <> Text.intercalate ", " owner.packages <> " and the scope names " <> namedText)
      Right chosen -> judgePackage claims owner chosen

    noOwnerClaim = warning "no-owner-claim" Nothing case own of
      Nothing -> "the reference is not in the owner snapshot"
      Just entry
        | entry.resolution /= Resolved -> "the reference did not resolve to an owner record (" <> reasonsText entry <> ")"
        | otherwise -> "the reference's duplicate chain ends at no canonical record (" <> reasonsText entry <> ")"
    reasonsText entry = case entry.reasons of
      [] -> renderResolution entry.resolution
      reasons -> Text.intercalate ", " (fmap reasonCode reasons)

    judgePackage claims owner chosen =
      let bounds = [raw | VersionBelow named raw <- conditionsOf scope, named == chosen]
          unparsed = [raw | raw <- bounds, isNothing (parseScopeVersion raw)]
          parsed = mapMaybe (\raw -> (,raw) <$> parseScopeVersion raw) bounds
          bound = if null parsed then Nothing else Just (minimumBy (comparing fst) parsed)
          fixedRaw = fromMaybe "(absent)" (versionClaimRaw claims.fixedVersion)
          statusText = maybe "absent" quoted claims.status
          about = Just chosen
       in case unparsed of
            raw : _ -> warning "unsupported-claim" about ("the scope's bound " <> quoted raw <> " for " <> chosen <> " is not a version")
            []
              | claims.status /= Just "fixed" ->
                  let notes = ["fixed-version-without-fixed-status" | claims.fixedVersion /= ClaimAbsent]
                      ignored = if null notes then "" else "; its fixedVersion " <> fixedRaw <> " is not a fix claim without the fixed status"
                   in case bound of
                        Just (_, raw) -> withNotes notes (contradiction "speculative-bound" about (Just (removeBounds chosen scope)) ("the owner's status is " <> statusText <> ", which records no fix, so no owner claim supports the bound " <> raw <> " for " <> chosen <> ignored))
                        Nothing -> withNotes notes (consistent about ("the owner's status is " <> statusText <> " and the scope has no version bound for " <> chosen <> ignored))
              | otherwise -> case claims.fixedVersion of
                  ClaimUnreleased -> case bound of
                    Just (_, raw) -> contradiction "speculative-bound" about (Just (removeBounds chosen scope)) ("the owner's fix is unreleased, so no release supports the bound " <> raw <> " for " <> chosen)
                    Nothing -> warning "fix-unreleased" about "the owner's fix is unreleased; no bound can be proposed until it is released"
                  ClaimReleased version raw
                    | chosen `notElem` owner.versionsApplyTo ->
                        warning "owner-version-not-package-version" about ("the owner's fixed version " <> raw <> " is not a version of " <> chosen <> ", so no bound can be proposed")
                    | otherwise -> released chosen version raw bound
                  ClaimAbsent -> warning "unsupported-claim" about "the owner records the fix but writes no fixedVersion, so no bound can be confirmed or proposed"
                  ClaimMalformed -> warning "unsupported-claim" about "the owner records the fix but its fixedVersion is not text, so no bound can be confirmed or proposed"
                  other -> warning "unsupported-claim" about ("the owner records the fix without a released version (fixedVersion " <> maybe ("(" <> versionClaimState other <> ")") quoted (versionClaimRaw other) <> "), so no bound can be confirmed or proposed")

    released :: Text -> Version -> Text -> Maybe (Version, Text) -> Verdict
    released chosen version raw = \case
      Nothing -> contradiction "missing-upper-bound" (Just chosen) (Just (setBound chosen raw scope)) ("the owner records the fix in released version " <> raw <> ", but the scope excuses every version of " <> chosen)
      Just (boundVersion, boundRaw)
        | boundVersion > version -> contradiction "bound-above-fixed-version" (Just chosen) (Just (setBound chosen raw scope)) ("the owner records the fix in released version " <> raw <> ", but the bound " <> boundRaw <> " also excuses failures from " <> raw <> " up to " <> boundRaw)
        | boundVersion < version -> contradiction "bound-below-fixed-version" (Just chosen) (Just (setBound chosen raw scope)) ("the owner records the fix in released version " <> raw <> ", so releases from " <> boundRaw <> " up to " <> raw <> " are still affected but not covered by the bound " <> boundRaw)
        | otherwise -> consistent (Just chosen) ("the owner records the fix in released version " <> raw <> ", which is the scope's bound")

    warning code package rationale = Verdict {code, severity = Warning, package, scope = Nothing, rationale, notes = []}
    contradiction code package proposal rationale = Verdict {code, severity = Contradiction, package, scope = proposal, rationale, notes = []}
    consistent package rationale = Verdict {code = "consistent", severity = Consistent, package, scope = Nothing, rationale, notes = []}
    withNotes notes verdict = Verdict {code = verdict.code, severity = verdict.severity, package = verdict.package, scope = verdict.scope, rationale = verdict.rationale, notes}
    quoted value = "\"" <> value <> "\""

conditionsOf :: CohortScope -> [PackageCondition]
conditionsOf AllCohorts = []
conditionsOf (OnlyWhen conditions) = toList conditions

-- | The scope with one @version-below@ condition for the package, at the place of
-- the first existing one (or appended), and every other condition unchanged.
setBound :: Text -> Text -> CohortScope -> CohortScope
setBound package version scope = case conditionsOf scope of
  [] -> OnlyWhen (VersionBelow package version :| [])
  conditions
    | any isBound conditions -> OnlyWhen (NonEmpty.fromList (go conditions))
    | otherwise -> OnlyWhen (NonEmpty.fromList (conditions <> [VersionBelow package version]))
  where
    isBound = \case
      VersionBelow named _ -> named == package
      _ -> False
    go = \case
      [] -> []
      condition : rest
        | isBound condition -> VersionBelow package version : filter (not . isBound) rest
        | otherwise -> condition : go rest

-- | The scope without any @version-below@ condition for the package.
removeBounds :: Text -> CohortScope -> CohortScope
removeBounds package scope = case filter keep (conditionsOf scope) of
  [] -> AllCohorts
  first' : rest -> OnlyWhen (first' :| rest)
  where
    keep = \case
      VersionBelow named _ -> named /= package
      _ -> True

data FindingCounts = FindingCounts {contradictions :: Int, warnings :: Int, consistent :: Int}
  deriving stock (Eq, Show)

findingCounts :: [ScopeFinding] -> FindingCounts
findingCounts findings =
  FindingCounts
    { contradictions = count Contradiction,
      warnings = count Warning,
      consistent = count Consistent
    }
  where
    count severity = length [() | finding <- findings, finding.severity == severity]

-- Reports -----------------------------------------------------------------

-- | The @kenshou.scope-reconciliation/v1@ document.
reconciliationValue :: OwnerStatus -> [ScopeFinding] -> Value
reconciliationValue status findings =
  object
    [ "schema" .= ("kenshou.scope-reconciliation/v1" :: Text),
      "snapshot" .= status.snapshotDigest,
      "observedAt" .= status.observedAt,
      "counts" .= object ["contradictions" .= counts.contradictions, "warnings" .= counts.warnings, "consistent" .= counts.consistent],
      "findings" .= fmap findingValue findings
    ]
  where
    counts = findingCounts findings

findingValue :: ScopeFinding -> Value
findingValue finding =
  object
    [ "scenario" .= renderScenarioId finding.scenario,
      "reference" .= finding.reference,
      "canonical" .= finding.canonical,
      "snapshot" .= finding.snapshot,
      "owner" .= object ["status" .= finding.ownerStatus, "fixedVersion" .= object ["raw" .= versionClaimRaw finding.ownerFixedVersion, "state" .= versionClaimState finding.ownerFixedVersion]],
      "package" .= finding.package,
      "code" .= finding.code,
      "severity" .= renderSeverity finding.severity,
      "primary" .= finding.primary,
      "current" .= defectValue finding.current,
      "proposed" .= fmap defectValue finding.proposed,
      "rationale" .= finding.rationale,
      "notes" .= finding.notes,
      "location" .= fmap (\(path, line) -> object ["path" .= path, "line" .= line]) finding.location
    ]

-- | The text report: one block per finding and a final count.
renderReconciliationText :: OwnerStatus -> [ScopeFinding] -> Text
renderReconciliationText status findings = Text.unlines (heading <> concatMap block findings <> ["", total])
  where
    heading = maybe [] (\digest -> ["snapshot " <> digest]) status.snapshotDigest <> ["observed at " <> Text.pack (iso8601Show status.observedAt)]
    block finding =
      [ "",
        renderScenarioId finding.scenario,
        "  owner     " <> finding.reference <> "  (status=" <> fromMaybe "(absent)" finding.ownerStatus <> ", fixedVersion=" <> fromMaybe ("(" <> versionClaimState finding.ownerFixedVersion <> ")") (versionClaimRaw finding.ownerFixedVersion) <> ")"
      ]
        <> ["  canonical " <> canonical | Just canonical <- [finding.canonical], canonical /= finding.reference]
        <> ["  finding   " <> finding.code <> maybe "" (\severity -> "  [" <> severity <> "]") (renderSeverity finding.severity)]
        <> ["  current   " <> renderScope finding.current.appliesTo]
        <> ["  proposed  " <> renderScope proposal.appliesTo | Just proposal <- [finding.proposed]]
        <> ["  because   " <> finding.rationale]
        <> ["  note      " <> note | note <- finding.notes]
        <> ["  source    " <> Text.pack path <> maybe "" (\number -> ":" <> Text.pack (show number)) line | Just (path, line) <- [finding.location]]
    counts = findingCounts findings
    total = plural counts.contradictions "contradiction" <> ", " <> plural counts.warnings "warning"
    plural n word = Text.pack (show n) <> " " <> word <> (if n == 1 then "" else "s")

-- | A scope as one line: @all-cohorts@, or its conditions separated by commas.
renderScope :: CohortScope -> Text
renderScope AllCohorts = "all-cohorts"
renderScope (OnlyWhen conditions) = Text.intercalate ", " (fmap condition (toList conditions))
  where
    condition = \case
      ResolvedFromHackage package -> "resolved-from-hackage " <> package
      ResolvedFromGit package -> "resolved-from-git " <> package
      VersionBelow package version -> "version-below " <> package <> " " <> version
      RevisionIs package revision -> "revision-is " <> package <> " " <> revision
