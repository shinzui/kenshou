module RoundSpec (spec, runChild) where

import Control.Exception (finally)
import Control.Monad (forM)
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as BS
import Data.List (sort)
import Data.Text qualified as Text
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import Kenshou.Cli (Program (..), RoundConfig (..), defaultRoundConfig, roundCommandWith, runWithArgsWith, selfTestAssembly, withCommand)
import Kenshou.Core.Bundle (mkBundle)
import Kenshou.Core.Canonical (sha256Hex)
import Kenshou.Core.Cohort (CohortIdentity (..), CohortName (..), PlanHash (..))
import Kenshou.Core.Dimension (noDimensions)
import Kenshou.Core.Env (noEnvironment)
import Kenshou.Core.Id (mkLayerId, parseScenarioId)
import Kenshou.Core.Phase (zeroPhases)
import Kenshou.Core.Scenario (CohortScope (..), KnownDefect (..), Placement (..), Scenario (..), Tier (..), failedWith, passed)
import Kenshou.Evidence.Owner (defaultRecordKinds)
import Kenshou.Evidence.Owner.Cli (OwnerConfig (..), defaultOwnerConfig, ownersCommandWith)
import Kenshou.Evidence.Owner.Resolver (mappedResolver)
import System.Directory (createDirectory, doesFileExist, doesPathExist, listDirectory)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (hClose, hFlush, stdout)
import System.IO.Temp (withSystemTempDirectory, withSystemTempFile)
import Test.Hspec

spec :: Spec
spec = describe "round command" do
  it "opens, plans, executes and replays a consumer round through public command contributions" $
    withSystemTempDirectory "kenshou-round-cli" \root -> do
      baseProgram <- consumerProgram
      let ownerRoot = root </> "owner"
          ownerFile = ownerRoot </> "dial-failure.md"
          ownerConfig = defaultOwnerConfig {resolver = Just (mappedResolver defaultRecordKinds [("mori://fixture/adapter/okf/bug-reports", ownerRoot)])}
          roundConfig = defaultRoundConfig {owners = ownerConfig}
          program = baseProgram {commands = withCommand (roundCommandWith roundConfig) (withCommand (ownersCommandWith ownerConfig) baseProgram.commands)}
          run = runWithArgsWith program
          snapshot = root </> "snapshot"
          identitySource = root </> "active.json"
          baseline = root </> "baseline.json"
          candidate = root </> "candidate.json"
          packages = root </> "packages.json"
          baselineRuns = root </> "baseline-runs.json"
          roundDir = root </> "round"
          command name = ["round", name, "--round", roundDir]
          planRun = roundDir </> "plans/smoke.run-plan.json"
          execution = root </> "execution"
          report = command "report" <> ["--evaluation", "first", "--json"]
          markdown = root </> "dated.md"
          roundOpen =
            [ "round",
              "open",
              "--id",
              "day-one",
              "--out",
              roundDir,
              "--mode",
              "release",
              "--owners",
              snapshot,
              "--package-map",
              packages,
              "--baseline-identity",
              baseline,
              "--candidate-identity",
              candidate,
              "--baseline-runs",
              baselineRuns
            ]
          policy = ["--max-tier", "smoke", "--placement", "local", "--seed", "112", "--budget-minutes", "3", "--select", "adapter/kernel/**"]
          roundPlan = command "plan" <> ["--arm", "candidate", "--out", "smoke"] <> policy
          evaluate = command "evaluate" <> ["--id", "first", "--runs", execution, "--plan", "smoke"]
      createDirectory ownerRoot
      BS.writeFile ownerFile "---\ntype: Bug Report\nbugId: BUG-1\ntitle: Fixture defect\nstatus: confirmed\n---\n\n# Fixture defect\n"
      ownerBytes <- BS.readFile ownerFile
      let identity =
            CohortIdentity
              (CohortName "fixture")
              "ghc-9.12.4"
              "3.16.1.0"
              "fixture-os"
              "fixture-arch"
              Nothing
              (PlanHash ("sha256:" <> Text.replicate 64 "a"))
              (Text.replicate 64 "b")
              []
              Nothing
      Aeson.encodeFile identitySource identity
      BS.writeFile packages "{\"schema\":\"kenshou.owner-package-map/v1\",\"owners\":[]}"
      BS.writeFile baselineRuns "[]"
      run ["owners", "snapshot", "--out", snapshot] `shouldReturn` ExitSuccess
      withCohort identitySource do
        (code, bytes) <- capture (run ["cohort", "show", "--json"])
        code `shouldBe` ExitSuccess
        BS.writeFile baseline bytes
        BS.writeFile candidate bytes
        run roundOpen `shouldReturn` ExitSuccess
        run roundOpen `shouldReturn` ExitFailure 2
        run roundPlan `shouldReturn` ExitSuccess
        run roundPlan `shouldReturn` ExitFailure 2
        let standardPlan = root </> "standard.json"
        run (["plan", "--all", "--out", standardPlan] <> policy) `shouldReturn` ExitSuccess
        standardPolicy <- field "policy" <$> readJson standardPlan
        standardPolicy `shouldSatisfy` (/= Nothing)
        (field "policy" <$> readJson planRun) `shouldReturn` standardPolicy
        run ["execute", "--plan", planRun, "--out", execution] `shouldReturn` ExitSuccess
      sealedDigests <- digests execution
      run report `shouldReturn` ExitFailure 4
      doesPathExist (roundDir </> "evaluations") `shouldReturn` False
      run (command "evaluate" <> ["--id", "empty"]) `shouldReturn` ExitFailure 2
      run evaluate `shouldReturn` ExitSuccess
      run evaluate `shouldReturn` ExitFailure 2
      (reportCode, reportBytes) <- capture (run report)
      reportCode `shouldBe` ExitFailure 3
      reportBytes `shouldSatisfy` BS.isInfixOf "\"disposition\":\"reproduces-as-expected\""
      reportBytes `shouldSatisfy` BS.isInfixOf "\"childExitCode\":0"
      reportBytes `shouldSatisfy` BS.isInfixOf "\"trust\":\"local-sealed\""
      capture (run report) `shouldReturn` (reportCode, reportBytes)
      let dated identifier day = if identifier == "day-one" && length (show day) == 10 then markdown else root </> "invalid-date"
          datedProgram = program {commands = withCommand (roundCommandWith roundConfig {reportPath = Just dated}) program.commands}
      capture (runWithArgsWith datedProgram report) `shouldReturn` (reportCode, reportBytes)
      BS.readFile markdown >>= (\bytes -> bytes `shouldSatisfy` BS.isPrefixOf "# Round day-one")
      run (report <> ["--write-report", markdown]) `shouldReturn` ExitFailure 2
      digests execution `shouldReturn` sealedDigests
      BS.readFile ownerFile `shouldReturn` ownerBytes

-- The executor re-enters the test executable with its usual run arguments.
runChild :: [String] -> IO ExitCode
runChild arguments = consumerProgram >>= flip runWithArgsWith arguments

consumerProgram :: IO Program
consumerProgram = do
  layer <- either (fail . Text.unpack) pure (mkLayerId "adapter")
  good <- either (fail . Text.unpack) pure (parseScenarioId "adapter/kernel/correctness/works")
  defect <- either (fail . Text.unpack) pure (parseScenarioId "adapter/kernel/correctness/known-defect")
  let scenario identifier known result =
        Scenario
          { id = identifier,
            revision = 1,
            summary = "Consumer verification scenario",
            tier = TierSmoke,
            placement = PlaceLocal,
            phases = zeroPhases,
            knobs = [],
            dimensions = noDimensions,
            requires = noEnvironment,
            knownDefect = known,
            run = const (pure result)
          }
      declaration = KnownDefect "mori://fixture/adapter/okf/bug-reports/concepts/BUG-1" "dial settles too early" ["early-dial"] AllCohorts
      graph = "{\"schema\":\"kenshou.component-graph/v1\",\"repositoryPaths\":[],\"components\":[{\"id\":\"adapter\",\"repository\":\"adapter\",\"kind\":\"library\",\"selectors\":[\"adapter/**\"]}]}"
  pure selfTestAssembly {bundles = [mkBundle layer [scenario good Nothing passed, scenario defect (Just declaration) (failedWith ["early-dial"] "known failure")] []], componentGraph = graph}

withCohort :: FilePath -> IO a -> IO a
withCohort path action = do
  original <- lookupEnv "KENSHOU_COHORT_IDENTITY"
  setEnv "KENSHOU_COHORT_IDENTITY" path
  action `finally` maybe (unsetEnv "KENSHOU_COHORT_IDENTITY") (setEnv "KENSHOU_COHORT_IDENTITY") original

capture :: IO a -> IO (a, BS.ByteString)
capture action = withSystemTempFile "round-stdout" \path handle -> do
  hFlush stdout
  saved <- hDuplicate stdout
  hDuplicateTo handle stdout
  result <- action `finally` (hFlush stdout >> hDuplicateTo saved stdout >> hClose saved)
  hClose handle
  (result,) <$> BS.readFile path

digests :: FilePath -> IO [(FilePath, Text.Text)]
digests root = do
  names <- sort <$> listDirectory root
  fmap concat $ forM names \name -> do
    let path = root </> name
    isFile <- doesFileExist path
    if isFile then pure . (path,) . sha256Hex <$> BS.readFile path else digests path

field :: Text.Text -> Aeson.Value -> Maybe Aeson.Value
field name (Aeson.Object fields) = KeyMap.lookup (Key.fromText name) fields
field _ _ = Nothing

readJson :: FilePath -> IO Aeson.Value
readJson path = Aeson.eitherDecodeFileStrict' path >>= either fail pure
