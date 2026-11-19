-- | Scope reconciliation against the checked-in fixture matrix, a golden report,
-- and generated owner records and scopes.
module ReconcileSpec (spec) where

import Data.ByteString qualified as ByteString
import Data.Foldable (toList)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime (..), fromGregorian)
import Data.Version (makeVersion)
import Hedgehog (Gen, annotateShow, assert, forAll, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Kenshou.Core.Dimension (noDimensions)
import Kenshou.Core.Id (parseScenarioId, renderScenarioId)
import Kenshou.Core.Scenario (CohortScope (..), KnownDefect (..), PackageCondition (..), Placement (..), Tier (..), individualKnownDefects)
import Kenshou.Evidence.Owner
import Kenshou.Evidence.Owner.Reconcile
import Kenshou.Evidence.Owner.Snapshot (readSnapshot)
import Kenshou.Plan.Catalog (ScenarioInfo (..), readCatalogFile)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import Test.Hspec
import Test.Hspec.Hedgehog (hedgehog)

spec :: Spec
spec = describe "scope reconciliation" do
  it "gives each fixture case its finding code, severity, and proposal" do
    (_, findings) <- fixtureFindings
    [(scenarioName finding, finding.code, finding.severity, fmap (.appliesTo) finding.proposed) | finding <- findings] `shouldBe` expectedFindings

  it "reports the canonical record of a duplicate and the source location the map supplies" do
    (status, findings) <- fixtureFindings
    let duplicate = only "duplicate-record" findings
        lease = only "lease-release" findings
        chosen = only "several-packages-chosen" findings
    duplicate.reference `shouldBe` ownerA "BUG-6"
    duplicate.canonical `shouldBe` Just (ownerA "BUG-1")
    duplicate.ownerFixedVersion `shouldBe` ClaimReleased (makeVersion [1, 3, 0]) "1.3.0"
    lease.location `shouldBe` Just ("consumer/src/Lease.hs", Just 41)
    chosen.location `shouldBe` Just ("consumer/src/Queue.hs", Nothing)
    lease.snapshot `shouldBe` status.snapshotDigest
    isJust status.snapshotDigest `shouldBe` True

  it "notes a fixedVersion carried by a record without the fixed status" do
    (_, findings) <- fixtureFindings
    (only "open-stray-fixed-version" findings).notes `shouldBe` ["fixed-version-without-fixed-status"]
    (only "open-speculative-bound" findings).notes `shouldBe` []

  it "never changes a defect's reference, summary, or labels, and never invents a version" do
    (_, findings) <- fixtureFindings
    mapM_ proposalIsConservative findings

  it "encodes the fixture report exactly as the golden document" do
    (status, findings) <- fixtureFindings
    let encoded = prettyJson (reconciliationValue status findings)
    accept <- lookupEnv "KENSHOU_ACCEPT_GOLDEN"
    case accept of
      Just "1" -> ByteString.writeFile (fixtureRoot </> "report.golden.json") encoded
      _ -> pure ()
    golden <- ByteString.readFile (fixtureRoot </> "report.golden.json")
    encoded `shouldBe` golden

  it "counts contradictions and warnings in the text report" do
    (status, findings) <- fixtureFindings
    findingCounts findings `shouldBe` FindingCounts {contradictions = 9, warnings = 12, consistent = 5}
    Text.lines (renderReconciliationText status findings) `shouldContain` ["9 contradictions, 12 warnings"]
    Text.lines (renderReconciliationText status findings) `shouldContain` ["  source    consumer/src/Lease.hs:41"]

  it "chooses a package only when the map or the scope makes it unambiguous" do
    let single = OwnerPackages ["fixture-store"] ["fixture-store"]
        several = OwnerPackages ["fixture-queue", "fixture-queue-client"] ["fixture-queue"]
    choosePackage single AllCohorts `shouldBe` Right "fixture-store"
    choosePackage several AllCohorts `shouldBe` Left "ambiguous-package-mapping"
    choosePackage several (OnlyWhen (ResolvedFromHackage "fixture-queue-client" :| [])) `shouldBe` Right "fixture-queue-client"
    choosePackage several (OnlyWhen (ResolvedFromHackage "fixture-queue-client" :| [VersionBelow "fixture-queue" "2.0.0"])) `shouldBe` Left "ambiguous-package-mapping"
    choosePackage several (OnlyWhen (ResolvedFromHackage "fixture-other" :| [])) `shouldBe` Left "ambiguous-package-mapping"

  it "rejects package maps that leave the version correspondence unstated or contradictory" do
    let decode owners = decodePackageMap ("{\"schema\":\"kenshou.owner-package-map/v1\",\"owners\":[" <> owners <> "]}")
        rejected = either (const True) (const False)
    rejected (decode "{\"affects\":\"mori://fixture/owner-a\",\"packages\":[\"a\"]}") `shouldBe` True
    rejected (decode "{\"affects\":\"mori://fixture/owner-a\",\"packages\":[\"a\"],\"versionsApplyTo\":[\"b\"]}") `shouldBe` True
    rejected (decode "{\"affects\":\"mori://fixture/owner-a\",\"packages\":[],\"versionsApplyTo\":[]}") `shouldBe` True
    rejected (decode "{\"affects\":\"mori://fixture/owner-a\",\"reference\":\"r\",\"packages\":[\"a\"],\"versionsApplyTo\":[]}") `shouldBe` True
    rejected (decode "{\"affects\":\"x\",\"packages\":[\"a\"],\"versionsApplyTo\":[]},{\"affects\":\"x\",\"packages\":[\"b\"],\"versionsApplyTo\":[]}") `shouldBe` True
    fmap (Map.keys . (.byAffects)) (decode "{\"affects\":\"x\",\"packages\":[\"a\"],\"versionsApplyTo\":[]}") `shouldBe` Right ["x"]

  it "returns exactly one primary finding per individual defect for generated records and scopes" $ hedgehog do
    entries <- forAll genEntries
    scenarios <- forAll (Gen.list (Range.linear 0 6) (genScenario (fmap (.reference) entries)))
    let status = OwnerStatus fixedTime (Just "sha256:generated") entries
        findings = reconcileScopes status generatedMap scenarios
        defects = [(info.id, defect.reference) | info <- scenarios, defect <- maybe [] individualKnownDefects info.knownDefect]
    annotateShow findings
    [(finding.scenario, finding.reference) | finding <- findings, finding.primary] === defects
    assert (all (\finding -> finding.primary || finding.code == "scope-package-not-mapped") findings)
    assert (all conservative findings)

-- | The expected primary and secondary findings of the fixture catalog, in order:
-- scenario name, code, severity, and the proposed scope.
expectedFindings :: [(Text, Text, Severity, Maybe CohortScope)]
expectedFindings =
  [ ("released-fix-bound-correct", "consistent", Consistent, Nothing),
    ("lease-release", "bound-above-fixed-version", Contradiction, scope [ResolvedFromHackage store, VersionBelow store "1.3.0"]),
    ("released-fix-bound-below", "bound-below-fixed-version", Contradiction, scope [VersionBelow store "1.3.0"]),
    ("released-fix-no-bound", "missing-upper-bound", Contradiction, scope [VersionBelow store "1.3.0"]),
    ("released-fix-two-bounds", "bound-above-fixed-version", Contradiction, scope [VersionBelow store "1.3.0", ResolvedFromHackage store]),
    ("released-fix-git-revision", "bound-above-fixed-version", Contradiction, scope [ResolvedFromGit store, RevisionIs store "0123456789abcdef0123456789abcdef01234567", VersionBelow store "1.3.0"]),
    ("released-fix-unmapped-condition", "consistent", Consistent, Nothing),
    ("released-fix-unmapped-condition", "scope-package-not-mapped", Warning, Nothing),
    ("unparseable-bound", "unsupported-claim", Warning, Nothing),
    ("unreleased-fix-bound", "speculative-bound", Contradiction, Just AllCohorts),
    ("unreleased-fix-no-bound", "fix-unreleased", Warning, Nothing),
    ("open-speculative-bound", "speculative-bound", Contradiction, Just AllCohorts),
    ("open-stray-fixed-version", "consistent", Consistent, Nothing),
    ("fixed-no-version-bound", "unsupported-claim", Warning, Nothing),
    ("fixed-no-version-no-bound", "unsupported-claim", Warning, Nothing),
    ("duplicate-record", "bound-above-fixed-version", Contradiction, scope [VersionBelow store "1.3.0"]),
    ("unparseable-fixed-version", "unsupported-claim", Warning, Nothing),
    ("unknown-fixed-version", "unsupported-claim", Warning, Nothing),
    ("missing-record", "no-owner-claim", Warning, Nothing),
    ("several-packages-ambiguous", "ambiguous-package-mapping", Warning, Nothing),
    ("several-packages-chosen", "bound-above-fixed-version", Contradiction, scope [VersionBelow "fixture-queue" "2.0.0"]),
    ("several-packages-other-version", "owner-version-not-package-version", Warning, Nothing),
    ("reference-override", "owner-version-not-package-version", Warning, Nothing),
    ("unmapped-owner", "unmapped-owner", Warning, Nothing),
    ("grouped-defects", "consistent", Consistent, Nothing),
    ("grouped-defects", "consistent", Consistent, Nothing)
  ]
  where
    store = "fixture-store"
    scope conditions = case conditions of
      [] -> Just AllCohorts
      first : rest -> Just (OnlyWhen (first :| rest))

fixtureRoot :: FilePath
fixtureRoot = "test/fixtures/reconcile"

fixtureFindings :: IO (OwnerStatus, [ScopeFinding])
fixtureFindings = do
  status <- readSnapshot (fixtureRoot </> "snapshot") >>= either (fail . Text.unpack) pure
  packageMap <- ByteString.readFile (fixtureRoot </> "package-map.json") >>= either (fail . Text.unpack) pure . decodePackageMap
  catalog <- readCatalogFile (fixtureRoot </> "catalog.json") >>= either (fail . Text.unpack) pure
  pure (status, reconcileScopes status packageMap catalog)

scenarioName :: ScopeFinding -> Text
scenarioName finding = Text.takeWhileEnd (/= '/') (renderScenarioId finding.scenario)

only :: Text -> [ScopeFinding] -> ScopeFinding
only name findings = case [finding | finding <- findings, scenarioName finding == name, finding.primary] of
  [finding] -> finding
  other -> error ("expected one primary finding for " <> Text.unpack name <> ", found " <> show (length other))

proposalIsConservative :: ScopeFinding -> Expectation
proposalIsConservative finding = (renderScenarioId finding.scenario, conservative finding) `shouldBe` (renderScenarioId finding.scenario, True)

-- | A proposal keeps the defect's reference, summary, and labels, keeps every
-- condition that is not a version bound, and adds only a bound for the compared
-- package at the owner's released fixed version, which the map says is a version
-- of that package.
conservative :: ScopeFinding -> Bool
conservative finding = case (finding.current, finding.proposed) of
  (_, Nothing) -> True
  (KnownDefect currentReference currentSummary currentLabels currentScope, Just (KnownDefect reference summary labels proposedScope)) ->
    reference == currentReference
      && summary == currentSummary
      && labels == currentLabels
      && all (`elem` conditions proposedScope) [condition | condition <- conditions currentScope, not (isBound condition)]
      && all addedBoundIsClaimed [condition | condition <- conditions proposedScope, condition `notElem` conditions currentScope]
  _ -> False
  where
    conditions AllCohorts = []
    conditions (OnlyWhen items) = toList items
    isBound = \case VersionBelow _ _ -> True; _ -> False
    addedBoundIsClaimed = \case
      VersionBelow package version -> case finding.ownerFixedVersion of
        ClaimReleased _ raw -> raw == version && Just package == finding.package && finding.ownerStatus == Just "fixed" && package `elem` concatMap (.versionsApplyTo) (Map.elems generatedMap.byAffects <> Map.elems generatedMap.byReference <> fixtureVersionOwners)
        _ -> False
      _ -> False
    fixtureVersionOwners = [OwnerPackages ["fixture-store"] ["fixture-store"], OwnerPackages ["fixture-queue", "fixture-queue-client"] ["fixture-queue"]]

-- Generated inputs -----------------------------------------------------------

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 11 18) 0

ownerA :: Text -> Text
ownerA handle = "mori://fixture/owner-a/okf/bug-reports/concepts/" <> handle

generatedMap :: PackageMap
generatedMap =
  PackageMap
    { byAffects =
        Map.fromList
          [ ("mori://fixture/owner-a", OwnerPackages ["fixture-store"] ["fixture-store"]),
            ("mori://fixture/owner-b", OwnerPackages ["fixture-queue", "fixture-queue-client"] ["fixture-queue"])
          ],
      byReference = Map.fromList [(ownerA "BUG-3", OwnerPackages ["fixture-queue-client"] [])],
      sources = Map.empty
    }

-- | Up to six records with handles BUG-1 to BUG-6, each resolved or not, with a
-- canonical record that is itself, another record, or absent (a cycle).
genEntries :: Gen [OwnerEntry]
genEntries = do
  count <- Gen.int (Range.linear 1 6)
  let references = [ownerA ("BUG-" <> Text.pack (show index)) | index <- [1 .. count]]
  traverse (genEntry references) references

genEntry :: [Text] -> Text -> Gen OwnerEntry
genEntry references reference = do
  resolved <- Gen.bool
  status <- Gen.element [Just "fixed", Just "confirmed", Just "duplicate", Nothing]
  fixedVersion <- Gen.element [ClaimAbsent, ClaimUnreleased, ClaimUnknown, ClaimReleased (makeVersion [1, 3, 0]) "1.3.0", ClaimReleased (makeVersion [2, 0]) "2.0", ClaimUnparseable "1.3.0-rc1", ClaimMalformed]
  affects <- Gen.element [Just "mori://fixture/owner-a", Just "mori://fixture/owner-b", Just "mori://fixture/owner-z", Nothing]
  canonical <- Gen.choice [pure (Just reference), Just <$> Gen.element references, pure Nothing]
  let record =
        OwnerRecord
          { kind = "Bug Report",
            handle = Text.takeWhileEnd (/= '/') reference,
            title = Nothing,
            status,
            affects,
            affectedVersion = ClaimAbsent,
            fixedVersion,
            lastWorkingVersion = ClaimAbsent,
            duplicateOf = Nothing,
            malformedFields = []
          }
  pure
    OwnerEntry
      { reference,
        resolution = if resolved then Resolved else Unresolved,
        reasons = [],
        record = if resolved then Just record else Nothing,
        canonical = if resolved then canonical else Nothing,
        aliases = [],
        citedBy = [],
        source = Nothing,
        links = []
      }

genScenario :: [Text] -> Gen ScenarioInfo
genScenario references = do
  name <- Gen.element ["alpha", "beta", "gamma", "delta"]
  knownDefect <- Gen.maybe (genDefect (2 :: Int))
  pure
    ScenarioInfo
      { id = either (error . Text.unpack) Prelude.id (parseScenarioId ("consumer/table/correctness/" <> name)),
        revision = 1,
        summary = "Generated scenario",
        tier = TierSmoke,
        placement = PlaceEither,
        knobs = [],
        dimensions = noDimensions,
        knownDefect
      }
  where
    genDefect depth =
      Gen.frequency
        ( [(4, genSingle)]
            <> [(1, KnownDefectGroup <$> Gen.nonEmpty (Range.linear 1 3) (genDefect (depth - 1))) | depth > 0]
        )
    genSingle = do
      reference <- Gen.element (references <> [ownerA "BUG-404", "mori://shinzui/kenshou/plans/2-a-plan"])
      appliesTo <- Gen.choice [pure AllCohorts, OnlyWhen <$> Gen.nonEmpty (Range.linear 1 4) genCondition]
      pure KnownDefect {reference, summary = "Generated", expectedFailures = ["generated-failure"], appliesTo}
    genCondition = do
      package <- Gen.element ["fixture-store", "fixture-queue", "fixture-queue-client", "fixture-other"]
      Gen.choice
        [ pure (ResolvedFromHackage package),
          pure (ResolvedFromGit package),
          VersionBelow package <$> Gen.element ["1.2.0", "1.3.0", "1.4.0", "2.0.0", "next"],
          pure (RevisionIs package "abc")
        ]
