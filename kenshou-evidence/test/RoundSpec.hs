module RoundSpec (spec) where

import Data.Aeson qualified as Aeson
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import Kenshou.Core.Canonical (sha256Hex)
import Kenshou.Core.Cohort (CohortIdentity (..), CohortName (..), PlanHash (..))
import Kenshou.Evidence.Disposition qualified as D
import Kenshou.Evidence.Observation qualified as O
import Kenshou.Evidence.Round qualified as R
import Kenshou.Plan.Components (selftestGraphBytes)
import System.Directory (doesPathExist)
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
              catalog
              "test/fixtures/reconcile/package-map.json"
              selftestGraphBytes
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
