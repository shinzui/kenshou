module RoundSpec (spec) where

import Control.Monad (forM_)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Foldable (toList)
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Kenshou.Core.Canonical (sha256Hex)
import Kenshou.Core.Cohort (CohortIdentity (..), CohortName (..), ComponentId (..), PackageSource (..), PlanHash (..), ResolvedComponent (..), ResolvedPackage (..))
import Kenshou.Core.Id (mkSeed, parseScenarioId)
import Kenshou.Core.RunSpec (CohortExpectation (..), RunSpec (..), SpecPlacement (..))
import Kenshou.Core.Scenario (Placement (..))
import Kenshou.Evidence.Disposition qualified as D
import Kenshou.Evidence.Observation qualified as O
import Kenshou.Evidence.Round (RoundDefinition (mode, scopeOverrides), RoundInputs (candidateIdentity))
import Kenshou.Evidence.Round qualified as R
import Kenshou.Evidence.Round.Plan qualified as P
import Kenshou.Evidence.Round.Report qualified as Report
import Kenshou.Plan.Catalog qualified as Catalog
import Kenshou.Plan.Change (Change (..), ChangeSource (..), Reason (..))
import Kenshou.Plan.Components (selftestGraphBytes)
import Kenshou.Plan.Policy (PlanPolicy (..), defaultPlanPolicy)
import Kenshou.Plan.RunPlan (PlanSkeleton (..))
import Kenshou.Plan.RunPlan qualified as RunPlan
import Kenshou.Plan.Selector (parseSelector)
import System.Directory (copyFile, createDirectory, doesDirectoryExist, doesPathExist, listDirectory)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

spec :: Spec
spec = describe "verification rounds" do
  it "freezes exact baseline evidence and can adopt the same files offline" $
    withSystemTempDirectory "kenshou-round" \root -> do
      input <- BS.readFile "test/fixtures/dispositions/input.json" >>= right . D.decodeDispositionInput
      baseline : newer <- pure input.observations
      let snapshot = "test/fixtures/reconcile/snapshot"
          roundDir = root </> "r1"
          adoptDir = root </> "adopted"
          identity = root </> "identity.json"
          candidate = root </> "candidate.json"
          baselineHistory = root </> "history.json"
          ownerFile = root </> "owner.md"
      Aeson.encodeFile identity (cohort baseline.cohortName baseline.planHash)
      Aeson.encodeFile candidate (cohort "candidate" ("sha256:" <> Text.replicate 64 "a"))
      Aeson.encodeFile baselineHistory (map D.observationValue [baseline])
      BS.writeFile ownerFile "original"
      catalog <- BS.readFile "test/fixtures/reconcile/catalog.json"
      let fresh =
            R.FreshInputs
              snapshot
              (pure catalog)
              "test/fixtures/reconcile/package-map.json"
              (pure selftestGraphBytes)
              identity
              candidate
              (R.decodeObservations <$> BS.readFile baselineHistory)
              Nothing
              Nothing
          options = R.OpenOptions "r1" roundDir R.ReleaseRefresh (R.Fresh fresh) [("supporting-notes", ownerFile)]
      opened <- R.openRound options >>= right
      opened.baseline `shouldBe` [R.BaselineEntry baseline.runId baseline.source baseline.scenario baseline.trust]
      opened.baselineCohort `shouldBe` (baseline.cohortName, baseline.planHash)
      opened.candidateCohort `shouldBe` ("candidate", "sha256:" <> Text.replicate 64 "a")
      Map.lookup "catalog.json" opened.inputs `shouldBe` Just (sha256Hex catalog)
      opened.inputs `shouldSatisfy` Map.member "owners/snapshot.json"
      let frozen = traverse (BS.readFile . ((roundDir </> "inputs") </>)) (Map.keys opened.inputs)
      frozenBefore <- frozen
      definitionBytes <- BS.readFile (roundDir </> "round.json")
      Aeson.encodeFile baselineHistory (map D.observationValue newer)
      BS.writeFile ownerFile "changed"
      stashed <- R.readRound roundDir >>= right
      fst stashed `shouldBe` opened
      (snd stashed).baselineObservations `shouldBe` [baseline]
      frozen `shouldReturn` frozenBefore
      BS.readFile (roundDir </> "round.json") `shouldReturn` definitionBytes
      adopted <- R.openRound (R.OpenOptions "adopted" adoptDir R.ChangeOnly (R.FromInputs (roundDir </> "inputs")) []) >>= right
      adopted.inputs `shouldBe` opened.inputs
      adopted.baseline `shouldBe` opened.baseline
      R.openRound options >>= (`shouldSatisfy` isUsage)
      let missing = fresh {R.loadBaseline = pure (Left "published observation not found: absent-run")}
      R.openRound (R.OpenOptions "missing" (root </> "missing") R.ReleaseRefresh (R.Fresh missing) []) >>= (`shouldSatisfy` isInput)
      doesPathExist (root </> "missing") `shouldReturn` False
      BS.appendFile (roundDir </> "inputs/catalog.json") " "
      R.readRound roundDir
        >>= ( \result -> case result of
                Left (R.RoundInput message) -> message `shouldBe` "round input digest mismatch: catalog.json"
                _ -> expectationFailure "tampered catalog was accepted"
            )

  it "plans release refreshes and change-only reproduction coverage against each arm" $
    withSystemTempDirectory "kenshou-round-plan" \root -> do
      let snapshot = "test/fixtures/reconcile/snapshot"
          roundDir = root </> "r1"
          componentId = ComponentId "store"
          identity name hash packages =
            (cohort name ("sha256:" <> Text.replicate 64 hash))
              { identityComponents = [ResolvedComponent componentId "mori://fixture/store" packages]
              }
          pkg name version = ResolvedPackage name version (FromHackage Nothing)
          base = identity "old" "b" [pkg "fixture-store" "1.0"]
          candidate = identity "new" "c" [pkg "fixture-store" "1.1"]
          graph = "{\"schema\":\"kenshou.component-graph/v1\",\"repositoryPaths\":[],\"components\":[{\"id\":\"store\",\"kind\":\"library\",\"repository\":\"store\",\"packages\":[\"fixture-store\"],\"selectors\":[\"consumer/table/correctness/affected\"]}]}"
      Aeson.encodeFile (root </> "baseline.json") base
      Aeson.encodeFile (root </> "candidate.json") candidate
      catalog <- Catalog.readCatalogFile "test/fixtures/reconcile/catalog.json" >>= right
      reproductionId <- right (parseScenarioId "consumer/table/correctness/lease-release")
      affectedId <- right (parseScenarioId "consumer/table/correctness/affected")
      unrelatedId <- right (parseScenarioId "consumer/table/correctness/unrelated")
      [reproduction] <- pure (filter ((== reproductionId) . (.id)) catalog)
      let affected = reproduction {Catalog.id = affectedId, Catalog.knownDefect = Nothing}
          unrelated = affected {Catalog.id = unrelatedId}
          fresh =
            R.FreshInputs
              snapshot
              (pure (LBS.toStrict (Aeson.encode (Catalog.CatalogDocument [reproduction {Catalog.placement = PlaceLocal}, affected, unrelated]))))
              "test/fixtures/reconcile/package-map.json"
              (pure graph)
              (root </> "baseline.json")
              (root </> "candidate.json")
              (pure (Right []))
              Nothing
              Nothing
      _ <- R.openRound (R.OpenOptions "r1" roundDir R.ChangeOnly (R.Fresh fresh) []) >>= right
      (definition, inputs) <- R.readRound roundDir >>= right
      seed <- right (mkSeed 54)
      let policy = defaultPlanPolicy seed
          (change, changeCoverage) = P.planRound definition inputs R.Candidate policy
          (release, _) = P.planRound definition {mode = R.ReleaseRefresh} inputs R.Baseline policy
          scenarios plan = sort [run.spec.scenario | run <- (plan :: PlanSkeleton).runs]
          expectations plan = map (.spec.cohortExpectation) (plan :: PlanSkeleton).runs
      scenarios change `shouldBe` sort [reproductionId, affectedId]
      scenarios release `shouldBe` sort [reproductionId, affectedId, unrelatedId]
      expectations change `shouldBe` replicate 2 (Just (CohortExpectation (Just "new") ("sha256:" <> Text.replicate 64 "c")))
      expectations release `shouldBe` replicate 3 (Just (CohortExpectation (Just "old") ("sha256:" <> Text.replicate 64 "b")))
      [run] <- pure [run | run <- release.runs, run.spec.scenario == reproductionId]
      map (.change.source) (toList run.reasons) `shouldBe` [OwnerReproduction, Everything]
      map (\item -> (item.scenario, item.reason)) changeCoverage.omissions `shouldContain` [(Just unrelatedId, "not-selected")]
      let (_, cell) = P.planRound definition inputs R.Candidate policy {placement = RunOnCell}
          (_, budget) = P.planRound definition inputs R.Candidate policy {budgetMinutes = Just 0}
          (_, missingMap) =
            P.planRound
              definition
              inputs {candidateIdentity = identity "new" "c" [pkg "fixture-store" "1.1", pkg "unknown" "1.0"]}
              R.Candidate
              policy
      include <- right (parseSelector "consumer/table/correctness/affected")
      let (_, _, filtered) = P.planRoundWithSelectors definition inputs R.Candidate policy [include] []
      forM_ [(cell, "placement"), (budget, "over-budget"), (filtered, "excluded")] \(coverage, reason) ->
        map (\item -> (item.scenario, item.reason)) coverage.omissions `shouldContain` [(Just reproductionId, reason)]
      map (.reason) missingMap.omissions `shouldContain` ["unmapped-change"]

  it "replays exact owner conclusions, failures and retried coverage offline" $
    withSystemTempDirectory "kenshou-round-report" \root -> do
      let roundDir = root </> "r1"
          readReport = do
            (definition, inputs, digest) <- R.readRoundWithDigest roundDir >>= right
            evaluation <- Report.readEvaluation roundDir "e1" definition digest >>= right
            right (Report.roundReport definition inputs evaluation)
      copyTree "test/fixtures/round/r1" roundDir
      report <- readReport
      Report.reportExitCode report `shouldBe` ExitFailure 1
      let value = Report.roundReportValue report
          counts = field "counts" value
          bytes = Aeson.encode value
      forM_ [("verifiedFixed", 1), ("reproducesAsExpected", 1), ("newFailures", 1), ("missing", 1), ("infrastructure", 1), ("incomplete", 1)] \(name, count) ->
        field name counts `shouldBe` Aeson.toJSON (count :: Int)
      let ownerRows = rows (field "owners" value)
      [fixed, expected] <- pure ownerRows
      field "transition" fixed `shouldBe` Aeson.object ["from" Aeson..= ["reproduces-as-expected" :: Text.Text], "to" Aeson..= ("verified-fixed" :: Text.Text)]
      field "transition" expected `shouldBe` Aeson.object ["from" Aeson..= ["reproduces-as-expected" :: Text.Text], "to" Aeson..= ("reproduces-as-expected" :: Text.Text)]
      map (field "code") (rows (field "reasons" (field "candidate" fixed))) `shouldContain` [Aeson.String "scope-override"]
      let newRun = (field "observation" <$> rows (field "newFailures" value))
      map (field "trust") newRun `shouldBe` [Aeson.String "machine-confirmed"]
      map (field "runId") newRun `shouldBe` [Aeson.String "01997f3a-5b7c-7e21-8a44-00000000000d"]
      map (field "scenario") (rows (field "missingCoverage" value)) `shouldBe` [Aeson.String "consumer/table/correctness/reader-restart"]
      [retried] <- pure [run | run <- rows (field "plannedRuns" value), field "scenario" run == Aeson.String "consumer/echo/correctness/roundtrip"]
      map (field "runId") (rows (field "observations" retried))
        `shouldBe` map Aeson.String ["01997f3a-5b7c-7e21-8a44-00000000000f", "01997f3a-5b7c-7e21-8a44-000000000011"]
      Report.renderRoundReportText report `shouldSatisfy` Text.isInfixOf "machine-confirmed failed revision=2 exit=0"
      (definition, inputs, digest) <- R.readRoundWithDigest roundDir >>= right
      evaluation <- Report.readEvaluation roundDir "e1" definition digest >>= right
      noOverride <- right (Report.roundReport definition {scopeOverrides = []} inputs evaluation)
      field "verifiedFixed" (field "counts" (Report.roundReportValue noOverride)) `shouldBe` Aeson.toJSON (0 :: Int)
      BS.writeFile (root </> "newer-history.json") "[\"newer-evidence\"]"
      BS.writeFile (root </> "owner.md") "Owner now says something else"
      (Aeson.encode . Report.roundReportValue <$> readReport) `shouldReturn` bytes
      BS.appendFile (roundDir </> "round.json") " "
      (_, _, changedDigest) <- R.readRoundWithDigest roundDir >>= right
      Report.readEvaluation roundDir "e1" definition changedDigest >>= (\result -> result `shouldSatisfy` isInput)

copyTree :: FilePath -> FilePath -> IO ()
copyTree source destination = do
  createDirectory destination
  names <- listDirectory source
  forM_ names \name -> do
    let from = source </> name
        to = destination </> name
    directory <- doesDirectoryExist from
    if directory then copyTree from to else copyFile from to

field :: Text.Text -> Aeson.Value -> Aeson.Value
field name (Aeson.Object fields) = maybe Aeson.Null id (KeyMap.lookup (Key.fromText name) fields)
field _ _ = Aeson.Null

rows :: Aeson.Value -> [Aeson.Value]
rows (Aeson.Array values) = toList values
rows _ = []

cohort :: Text.Text -> Text.Text -> CohortIdentity
cohort name hash =
  CohortIdentity (CohortName name) "ghc-9.12.4" "3.16.1.0" "fixture-os" "fixture-arch" Nothing (PlanHash hash) (Text.replicate 64 "b") [] Nothing

right :: (Show e) => Either e a -> IO a
right = either (fail . show) pure

isUsage :: Either R.RoundError a -> Bool
isUsage (Left (R.RoundUsage _)) = True
isUsage _ = False

isInput :: Either R.RoundError a -> Bool
isInput (Left (R.RoundInput _)) = True
isInput _ = False
