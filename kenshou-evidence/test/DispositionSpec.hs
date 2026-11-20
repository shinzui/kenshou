module DispositionSpec (spec) where

import Control.Monad (forM_)
import Data.ByteString qualified as ByteString
import Data.List (sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Hedgehog (Gen, evalIO, forAll, (===))
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Kenshou.Core.Defect (ScopePackage (..), ScopeSource (..), scopeApplies)
import Kenshou.Core.Id (parseScenarioId)
import Kenshou.Core.Outcome (Outcome (..))
import Kenshou.Core.Scenario (CohortScope (..), KnownDefect (..))
import Kenshou.Evidence.Disposition qualified as D
import Kenshou.Evidence.Observation qualified as O
import Kenshou.Evidence.Owner qualified as Owner
import Kenshou.Evidence.Owner.Reconcile (OwnerPackages (..), PackageMap (..))
import Kenshou.Evidence.Owner.Record (classifyVersion)
import Kenshou.Plan.Catalog qualified as Catalog
import Test.Hspec
import Test.Hspec.Hedgehog (hedgehog)

spec :: Spec
spec = describe "fix-verification dispositions" do
  it "attributes passes without defect references, sharing the scope evaluator and preserving resolved package versions" do
    input <- fixture
    [affected, fixed, local] <- pure (D.deriveDispositions input)
    map (.disposition) [affected, fixed, local] `shouldBe` [D.ReproducesAsExpected, D.VerifiedFixed, D.NotReproduced]
    map (map (.observation.runId) . (.considered)) [affected, fixed, local] `shouldBe` map (pure . (.runId)) input.observations
    map (scopeApplies . snd) (concatMap (.scope) affected.considered) `shouldBe` [True]
    map (scopeApplies . snd) (concatMap (.scope) fixed.considered) `shouldBe` [False]
    map (.observation.packages) fixed.considered `shouldBe` [[ScopePackage "fixture-table" "1.3.0" ScopeHackage]]
    codes local `shouldBe` ["insufficient-trust"]
    replay <- either (fail . Text.unpack) pure (D.decodeDispositionInput (Owner.prettyJson (D.dispositionInputValue input)))
    D.dispositionInputValue replay `shouldBe` D.dispositionInputValue input

  it "preserves the distinctions between reproduction, unrelated failure, and missing labels" do
    (input, pass) <- fixedFixture
    let failed = pass {O.outcome = Failed}
    forM_
      [ (O.LabelsVerified ["lease-held"], D.StillReproduces, [], D.ResultReproduced),
        (O.LabelsVerified ["new-failure"], D.DifferentFailure, [], D.ResultDifferentFailure),
        (O.LabelsVerified [], D.DifferentFailure, [], D.ResultDifferentFailure),
        (O.LabelsVerified ["lease-held", "new-failure"], D.StillReproduces, ["other-failures-present"], D.ResultReproduced),
        (O.LabelsUnavailable "labels-absent", D.Unverifiable, ["labels-unavailable"], D.ResultLabelsUnavailable)
      ]
      \(labels, disposition, why, expectedResult) -> do
        conclusion <- onlyConclusion input {D.observations = [failed {O.labels = labels}]}
        (conclusion.disposition, codes conclusion) `shouldBe` (disposition, why)
        map (\item -> (item.result, item.observation.runId, item.observation.labels)) conclusion.considered
          `shouldBe` [(expectedResult, pass.runId, labels)]

  it "keeps later no-signal runs and lets newer unreadable failures block a pass" do
    (input, pass) <- fixedFixture
    let later = pass {O.runId = "01997f3a-5b7c-7e21-8a44-0d6c2f9b1e56", O.startedAt = "2026-11-17T17:00:00.1Z"}
    noSignal <- onlyConclusion input {D.observations = [later {O.outcome = InfrastructureFailure}, pass]}
    (noSignal.disposition, codes noSignal) `shouldBe` (D.VerifiedFixed, ["later-run-without-signal"])
    map (.runs) noSignal.reasons `shouldBe` [[later.runId]]
    missing <- onlyConclusion input {D.observations = [later {O.outcome = Failed, O.labels = O.LabelsUnavailable "labels-absent"}, pass]}
    (missing.disposition, codes missing) `shouldBe` (D.Unverifiable, ["labels-unavailable"])
    map (.runs) missing.reasons `shouldBe` [[later.runId]]

  it "links a regression to an earlier confirmed pass in another fixed cohort" do
    (input, pass) <- fixedFixture
    let again = pass {O.runId = "01997f3a-5b7c-7e21-8a44-0d6c2f9b1e56", O.startedAt = "2026-11-17T18:00:00Z", O.planHash = "sha256:" <> Text.replicate 64 "4", O.outcome = Failed, O.labels = O.LabelsVerified ["lease-held"]}
    [previous, regressed] <- pure (D.deriveDispositions input {D.observations = [again, pass]})
    (previous.disposition, regressed.disposition) `shouldBe` (D.VerifiedFixed, D.Regressed)
    map (.runs) regressed.reasons `shouldBe` [[pass.runId, again.runId]]
    claimed <- onlyConclusion (editClaim (\record -> record {Owner.lastWorkingVersion = classifyVersion "1.3.0"}) input) {D.observations = [again]}
    claimed.disposition `shouldBe` D.StillReproduces
    [_, weak] <- pure (D.deriveDispositions input {D.observations = [again, pass {O.trust = O.Unverified}]})
    weak.disposition `shouldBe` D.StillReproduces

  it "requires compatible, confirmed passes for every required scenario" do
    (input, pass) <- fixedFixture
    forM_ [O.Unverified, O.LocalSealed] \trust -> do
      result <- onlyConclusion input {D.observations = [pass {O.trust = trust}]}
      (result.disposition, codes result) `shouldBe` (D.NotReproduced, ["insufficient-trust"])
    incompatible <- onlyConclusion input {D.observations = [pass {O.scenarioRevision = Just 1}]}
    (incompatible.disposition, codes incompatible, map (.runId) incompatible.incompatible)
      `shouldBe` (D.NotRun, ["incompatible-revision"], [pass.runId])
    [first] <- pure input.catalog
    secondId <- either (fail . Text.unpack) pure (parseScenarioId "consumer/table/correctness/another-release")
    let two = input {D.catalog = [first, first {Catalog.id = secondId}]}
    partial <- onlyConclusion two
    (partial.disposition, codes partial) `shouldBe` (D.NotReproduced, ["incomplete-coverage"])
    Map.lookup secondId partial.required `shouldBe` Just Nothing
    let second = pass {O.scenario = secondId, O.runId = "01997f3a-5b7c-7e21-8a44-0d6c2f9b1e56"}
    complete <- onlyConclusion two {D.observations = [pass, second {O.trust = O.HumanReviewed}]}
    complete.disposition `shouldBe` D.VerifiedFixed
    conflicted <- onlyConclusion two {D.observations = [pass, second {O.outcome = Failed, O.labels = O.LabelsVerified ["lease-held"]}]}
    conflicted.disposition `shouldBe` D.StillReproduces
    scoped <- onlyConclusion two {D.coverage = Map.singleton complete.owner [pass.scenario]}
    scoped.disposition `shouldBe` D.VerifiedFixed
    empty <- onlyConclusion two {D.coverage = Map.singleton complete.owner []}
    empty.disposition `shouldBe` D.Unverifiable

  it "distinguishes no runs, unresolved owners, and released, unreleased and unsupported claims" do
    (input, pass) <- fixedFixture
    [entry] <- pure input.owners.records
    missing <- onlyConclusion input {D.observations = []}
    (missing.disposition, missing.cohort) `shouldBe` (D.NotRun, Nothing)
    let unresolved = entry {Owner.resolution = Owner.Unresolved, Owner.canonical = Nothing, Owner.record = Nothing, Owner.reasons = [Owner.NoResolver]}
    unknown <- onlyConclusion (replaceOwners input [unresolved])
    (unknown.disposition, codes unknown, unknown.cohort) `shouldBe` (D.Unverifiable, ["no-mapping"], Nothing)
    let gitPass = pass {O.packages = [ScopePackage "fixture-table" "1.3.0" (ScopeGit "branch-tip")]}
        git = input {D.observations = [gitPass]}
    check git D.Unverifiable ["git-cohort"]
    check (editClaim (setFix "unreleased") git) D.NotYetReleased []
    check (editClaim (setFix "vNext") input) D.Unverifiable ["unsupported-claim"]
    check (editClaim (\claim -> claim {Owner.status = Just "confirmed"}) input) D.NotReproduced []
    let mapping = input.packageMap
        projectVersion = mapping {byAffects = Map.map (\owner -> owner {versionsApplyTo = []}) mapping.byAffects}
    check input {D.packageMap = projectVersion} D.Unverifiable ["owner-version-not-package-version"]

  it "attributes duplicates once and treats applicable sibling labels as their owner's evidence" do
    (input, pass) <- fixedFixture
    [entry] <- pure input.owners.records
    [info] <- pure input.catalog
    Just defect@KnownDefect {} <- pure info.knownDefect
    let alias = entry {Owner.reference = entry.reference <> "-alias", Owner.canonical = Just entry.reference}
        aliasCatalog = info {Catalog.knownDefect = Just defect {reference = alias.reference}}
    canonical <- onlyConclusion (replaceOwners input [entry, alias]) {D.catalog = [aliasCatalog]}
    (canonical.owner, canonical.disposition) `shouldBe` (entry.reference, D.VerifiedFixed)
    concatMap (map fst . (.scope)) canonical.considered `shouldBe` [alias.reference]
    let siblingRef = entry.reference <> "-sibling"
        sibling = entry {Owner.reference = siblingRef, Owner.canonical = Just siblingRef}
        siblingDefect = defect {reference = siblingRef, expectedFailures = ["stalled"], appliesTo = AllCohorts}
        grouped = info {Catalog.knownDefect = Just (KnownDefectGroup (defect :| [siblingDefect]))}
        failed = pass {O.outcome = Failed, O.labels = O.LabelsVerified ["stalled"]}
    [first, second] <- pure (D.deriveDispositions (replaceOwners input [entry, sibling]) {D.catalog = [grouped], D.observations = [failed]})
    (first.disposition, codes first, map (.result) first.considered) `shouldBe` (D.Unverifiable, ["sibling-defect"], [D.ResultSiblingDefect])
    (second.disposition, map (.result) second.considered) `shouldBe` (D.StillReproduces, [D.ResultReproduced])

  it "returns one conclusion per canonical owner and compatible plan hash" $ hedgehog do
    (input, pass) <- evalIO fixedFixture
    cohorts <- forAll (Gen.list (Range.linear 1 20) (Gen.int (Range.linear 1 5)))
    outcomes <- forAll (traverse (const (Gen.enumBounded :: Gen Outcome)) cohorts)
    let runs =
          [ pass {O.planHash = Text.pack (show hash), O.runId = Text.pack (show index), O.outcome = outcome}
          | (index, (hash, outcome)) <- zip [1 :: Int ..] (zip cohorts outcomes)
          ]
    map (.cohort) (D.deriveDispositions input {D.observations = runs})
      === sort (Map.keys (Map.fromList [(Just (run.cohortName, run.planHash), ()) | run <- runs]))

fixture :: IO D.DispositionInput
fixture = ByteString.readFile "test/fixtures/dispositions/input.json" >>= either (fail . Text.unpack) pure . D.decodeDispositionInput

fixedFixture :: IO (D.DispositionInput, O.Observation)
fixedFixture = do
  input <- fixture
  [_, pass, _] <- pure input.observations
  pure (input {D.observations = [pass]}, pass)

onlyConclusion :: D.DispositionInput -> IO D.Conclusion
onlyConclusion input = case D.deriveDispositions input of
  [one] -> pure one
  other -> fail ("expected one conclusion, got " <> show other)

check :: D.DispositionInput -> D.Disposition -> [Text] -> Expectation
check input disposition why = do
  result <- onlyConclusion input
  (result.disposition, codes result) `shouldBe` (disposition, why)

codes :: D.Conclusion -> [Text]
codes conclusion = map (.code) conclusion.reasons

replaceOwners :: D.DispositionInput -> [Owner.OwnerEntry] -> D.DispositionInput
replaceOwners input records = input {D.owners = input.owners {Owner.records = records}}

editClaim :: (Owner.OwnerRecord -> Owner.OwnerRecord) -> D.DispositionInput -> D.DispositionInput
editClaim change input =
  replaceOwners input [entry {Owner.record = change <$> entry.record} | entry <- input.owners.records]

setFix :: Text -> Owner.OwnerRecord -> Owner.OwnerRecord
setFix raw claim = claim {Owner.fixedVersion = classifyVersion raw}
