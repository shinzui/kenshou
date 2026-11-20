-- | The @owners@ command through the program entry point: snapshot replay against
-- changed owner files, and a synthetic consumer that supplies its own source,
-- resolver, record kind, and enrichment through the public extension points.
module OwnersSpec (spec) where

import Control.Exception (finally)
import Control.Monad (forM, forM_)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.Foldable (toList)
import Data.IORef (atomicModifyIORef', newIORef, readIORef)
import Data.List (sort)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text.Encoding
import Data.Time (UTCTime, addUTCTime)
import Data.Time.Format.ISO8601 (iso8601ParseM)
import GHC.IO.Handle (hDuplicate, hDuplicateTo)
import Kenshou.Cli (Program (..), runWithArgsWith, selfTestAssembly, withCommand)
import Kenshou.Core.Bundle (LayerBundle, mkBundle)
import Kenshou.Core.Canonical (sha256Hex)
import Kenshou.Core.Cli (CliCommand (..))
import Kenshou.Core.Defect (defectValue)
import Kenshou.Core.Dimension (noDimensions)
import Kenshou.Core.Env (noEnvironment)
import Kenshou.Core.Id (mkLayerId, parseRunId, parseScenarioId)
import Kenshou.Core.Manifest (writeManifest)
import Kenshou.Core.Outcome (Outcome (..))
import Kenshou.Core.Phase (zeroPhases)
import Kenshou.Core.Scenario (CohortScope (..), KnownDefect (..), PackageCondition (..), Placement (..), Scenario (..), Tier (..), passed)
import Kenshou.Evidence.Bundle (runRecordPath, writeRunRecordWith)
import Kenshou.Evidence.Observation qualified as Observation
import Kenshou.Evidence.Owner (Citer (..), OwnerCitation (..), OwnerEntry (..), OwnerLink (..), OwnerRecord (..), OwnerResolver, OwnerSource (..), RecordKind (..))
import Kenshou.Evidence.Owner.Cli (OwnerConfig (..), OwnerEnrichment (..), defaultOwnerConfig, ownersCommandWith)
import Kenshou.Evidence.Owner.Resolver (memoryResolver)
import Kenshou.Evidence.Publish (PublishOptions (..), UploadMode (..), publishRunData)
import Kenshou.Evidence.Record (RecordInput (..), buildRunRecord)
import Kenshou.Evidence.Source (loadRunSource)
import Kenshou.Evidence.Store (ObjectStore, memoryStore)
import Kenshou.Evidence.Types (Purpose (..))
import System.Directory (createDirectoryIfMissing, doesFileExist, getPermissions, listDirectory, setOwnerExecutable, setPermissions)
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.IO (Handle, hClose, hFlush, stderr, stdout)
import System.IO.Temp (withSystemTempDirectory, withSystemTempFile)
import Test.Hspec

spec :: Spec
spec = describe "owners command" do
  it "replays a snapshot unchanged after the owner files change, and never writes to them" $
    withSystemTempDirectory "kenshou-owners-cli" \root -> do
      let bundle = root </> "owner-x" </> "bug-reports"
          findings = root </> "findings.json"
          snapshot = root </> "snapshot"
          live = ["owners", "status", "--findings", findings, "--map", "mori://fixture/owner-x/okf/bug-reports=" <> bundle]
      createDirectoryIfMissing True bundle
      writeBugReport (bundle </> "writer-stall.md") "BUG-1" "fixed" ["fixedVersion: 2.0.0"]
      writeBugReport (bundle </> "stall-on-close.md") "BUG-2" "duplicate" ["duplicateOf: BUG-1"]
      writeBugReport (bundle </> "slow-scan.md") "BUG-3" "confirmed" []
      ByteString.writeFile findings (findingsDocument [("F-1", [ownerX "BUG-2"]), ("F-2", [ownerX "BUG-3"])])
      original <- digests root
      (snapshotCode, _) <- quietly (runOwners (["owners", "snapshot", "--out", snapshot] <> drop 2 live))
      snapshotCode `shouldBe` ExitSuccess
      digests root >>= (`shouldBe` original) . withoutSnapshot
      -- BUG-1 is reached only through BUG-2's duplicate chain, and still changes underneath.
      writeBugReport (bundle </> "writer-stall.md") "BUG-1" "confirmed" ["fixedVersion: 2.0.0"]
      writeBugReport (bundle </> "slow-scan.md") "BUG-3" "fixed" []
      edited <- withoutSnapshot <$> digests root
      (firstCode, first) <- quietly (runOwners ["owners", "status", "--snapshot", snapshot, "--json"])
      (secondCode, second) <- quietly (runOwners ["owners", "status", "--snapshot", snapshot, "--json"])
      (firstCode, secondCode) `shouldBe` (ExitSuccess, ExitSuccess)
      firstValue <- decodeValue first
      secondValue <- decodeValue second
      firstValue `shouldBe` secondValue
      statusOf (ownerX "BUG-1") firstValue `shouldBe` String "fixed"
      statusOf (ownerX "BUG-3") firstValue `shouldBe` String "confirmed"
      field "canonical" (recordFor (ownerX "BUG-2") firstValue) `shouldBe` String (ownerX "BUG-1")
      field "snapshot" firstValue `shouldSatisfy` (/= Null)
      (liveCode, current) <- quietly (runOwners (live <> ["--json"]))
      liveCode `shouldBe` ExitSuccess
      currentValue <- decodeValue current
      statusOf (ownerX "BUG-1") currentValue `shouldBe` String "confirmed"
      statusOf (ownerX "BUG-3") currentValue `shouldBe` String "fixed"
      field "snapshot" currentValue `shouldBe` Null
      (textCode, text) <- quietly (runOwners live)
      textCode `shouldBe` ExitSuccess
      Text.Encoding.decodeUtf8 text `shouldSatisfy` Text.isInfixOf "status=confirmed"
      withoutSnapshot <$> digests root >>= (`shouldBe` edited)

  it "refuses an existing snapshot, mixed options, unreadable inputs, and tampered snapshots" $
    withSystemTempDirectory "kenshou-owners-cli-errors" \root -> do
      let bundle = root </> "bugs"
          snapshot = root </> "snapshot"
          mapping = "mori://fixture/owner-x/okf/bug-reports=" <> bundle
          findings = root </> "findings.json"
      createDirectoryIfMissing True bundle
      writeBugReport (bundle </> "one.md") "BUG-1" "reported" []
      ByteString.writeFile findings (findingsDocument [("F-1", [ownerX "BUG-1"])])
      fst <$> quietly (runOwners ["owners", "snapshot", "--out", snapshot, "--findings", findings, "--map", mapping]) `shouldReturn` ExitSuccess
      fst <$> quietly (runOwners ["owners", "snapshot", "--out", snapshot, "--findings", findings, "--map", mapping]) `shouldReturn` ExitFailure 2
      fst <$> quietly (runOwners ["owners", "status", "--snapshot", snapshot, "--map", mapping]) `shouldReturn` ExitFailure 2
      fst <$> quietly (runOwners ["owners", "status", "--findings", root </> "absent.json"]) `shouldReturn` ExitFailure 4
      fst <$> quietly (runOwners ["owners", "status", "--snapshot", root </> "absent"]) `shouldReturn` ExitFailure 4
      record : _ <- listDirectory (snapshot </> "records")
      ByteString.appendFile (snapshot </> "records" </> record) "changed\n"
      fst <$> quietly (runOwners ["owners", "status", "--snapshot", snapshot]) `shouldReturn` ExitFailure 4

  it "reconciles scopes read-only, exits 1 on a contradiction and 0 once it is removed" $
    withSystemTempDirectory "kenshou-owners-reconcile" \root -> do
      let bundle = root </> "owner-x" </> "bug-reports"
          findings = root </> "findings.json"
          snapshot = root </> "snapshot"
          catalog = root </> "catalog.json"
          packageMap = root </> "package-map.json"
          reconcile extra = quietly (runOwners (["owners", "reconcile", "--snapshot", snapshot, "--catalog", catalog, "--package-map", packageMap] <> extra))
          stale = catalogScenario "consumer/table/correctness/writer-stall" (ownerX "BUG-1") (OnlyWhen (ResolvedFromHackage "fixture-writer" :| [VersionBelow "fixture-writer" "2.1.0"]))
          agreeing = catalogScenario "consumer/table/correctness/writer-ok" (ownerX "BUG-1") (OnlyWhen (VersionBelow "fixture-writer" "2.0.0" :| []))
          open = catalogScenario "consumer/table/correctness/slow-scan" (ownerX "BUG-3") AllCohorts
      createDirectoryIfMissing True bundle
      writeBugReport (bundle </> "writer-stall.md") "BUG-1" "fixed" ["affects: mori://fixture/owner-x", "fixedVersion: 2.0.0"]
      writeBugReport (bundle </> "slow-scan.md") "BUG-3" "confirmed" ["affects: mori://fixture/owner-x"]
      ByteString.writeFile findings (findingsDocument [("F-1", [ownerX "BUG-1", ownerX "BUG-3"])])
      fst <$> quietly (runOwners ["owners", "snapshot", "--out", snapshot, "--no-git-provenance", "--findings", findings, "--map", "mori://fixture/owner-x/okf/bug-reports=" <> bundle]) `shouldReturn` ExitSuccess
      ByteString.writeFile packageMap (packageMapDocument [Aeson.object ["affects" Aeson..= ("mori://fixture/owner-x" :: Text), "packages" Aeson..= ["fixture-writer" :: Text], "versionsApplyTo" Aeson..= ["fixture-writer" :: Text]]])
      ByteString.writeFile catalog (catalogDocument [stale, agreeing, open])
      unchanged <- digests root
      (code, text) <- reconcile []
      code `shouldBe` ExitFailure 1
      let report = Text.Encoding.decodeUtf8 text
      report `shouldSatisfy` Text.isInfixOf "finding   bound-above-fixed-version  [contradiction]"
      report `shouldSatisfy` Text.isInfixOf "proposed  resolved-from-hackage fixture-writer, version-below fixture-writer 2.0.0"
      report `shouldSatisfy` Text.isInfixOf "source    consumer/src/Writer.hs:12"
      report `shouldSatisfy` Text.isInfixOf "1 contradiction, 0 warnings"
      (jsonCode, json) <- reconcile ["--json"]
      jsonCode `shouldBe` ExitFailure 1
      document <- decodeValue json
      field "schema" document `shouldBe` String "kenshou.scope-reconciliation/v1"
      let digest = field "snapshot" document
          contradicting = [finding | finding <- toArray (field "findings" document), field "severity" finding == String "contradiction"]
      digest `shouldSatisfy` (/= Null)
      fmap (field "scenario") contradicting `shouldBe` [String "consumer/table/correctness/writer-stall"]
      forM_ contradicting \finding -> do
        field "snapshot" finding `shouldBe` digest
        field "kind" (field "current" finding) `shouldBe` String "single"
        field "kind" (field "proposed" finding) `shouldBe` String "single"
        field "rationale" finding `shouldSatisfy` (/= Null)
        field "location" finding `shouldBe` Aeson.object ["path" Aeson..= ("consumer/src/Writer.hs" :: Text), "line" Aeson..= (12 :: Int)]
      digests root `shouldReturn` unchanged
      ByteString.writeFile catalog (catalogDocument [agreeing, open])
      edited <- digests root
      fst <$> reconcile [] `shouldReturn` ExitSuccess
      fst <$> reconcile ["--json"] `shouldReturn` ExitSuccess
      digests root `shouldReturn` edited
      fst <$> quietly (runOwners ["owners", "reconcile", "--snapshot", snapshot]) `shouldReturn` ExitFailure 2
      fst <$> quietly (runOwners ["owners", "reconcile", "--snapshot", snapshot, "--package-map", root </> "absent.json"]) `shouldReturn` ExitFailure 4
      fst <$> quietly (runOwners ["owners", "reconcile", "--snapshot", root </> "absent", "--package-map", packageMap]) `shouldReturn` ExitFailure 4
      record : _ <- listDirectory (snapshot </> "records")
      ByteString.appendFile (snapshot </> "records" </> record) "changed\n"
      fst <$> reconcile [] `shouldReturn` ExitFailure 4

  it "assembles a consumer's own source, resolver, record kind, and enrichment without Mori" $
    withSystemTempDirectory "kenshou-owners-consumer" \root -> do
      calls <- newIORef (0 :: Int)
      let marker = root </> "mori-was-called"
          enrichment = OwnerEnrichment "consumer-plans" \entry -> do
            atomicModifyIORef' calls (\count -> (count + 1, ()))
            pure [OwnerLink "plan" ("mori://fixture/consumer/plans/" <> handle) | Just record <- [entry.record], let handle = record.handle]
          config =
            defaultOwnerConfig
              { sources = [OwnerSource "consumer-tracker" (pure (Right [OwnerCitation (ownerX "BUG-3") (CitedByFinding "T-1") (Just "tracker:T-1")]))],
                resolver = Just consumerResolver,
                recordKinds = [RecordKind "Incident" "incidentId"],
                enrichments = [enrichment]
              }
          program = selfTestAssembly {bundles = selfTestAssembly.bundles <> [consumerBundle], commands = withCommand (ownersCommandWith config) selfTestAssembly.commands}
      length [() | command <- program.commands, command.name == "owners"] `shouldBe` 1
      length program.commands `shouldBe` length selfTestAssembly.commands
      withFakeMori root marker do
        (code, output) <- quietly (runWithArgsWith program ["owners", "status", "--json"])
        code `shouldBe` ExitSuccess
        document <- decodeValue output
        let canonical = recordFor (ownerX "BUG-1") document
            incident = recordFor (ownerY "INC-7") document
            tracked = recordFor (ownerX "BUG-3") document
        field "resolution" incident `shouldBe` String "resolved"
        field "kind" incident `shouldBe` String "Incident"
        field "resolver" (field "source" canonical) `shouldBe` String "consumer"
        citers canonical `shouldBe` ["consumer/table/concurrency/competing-writers via " <> ownerX "BUG-2", "consumer/table/correctness/lease-release"]
        citers incident `shouldBe` ["consumer/table/concurrency/competing-writers"]
        citers tracked `shouldBe` ["T-1"]
        field "links" canonical `shouldBe` Aeson.toJSON [Aeson.object ["label" Aeson..= ("plan" :: Text), "target" Aeson..= ("mori://fixture/consumer/plans/BUG-1" :: Text)]]
        field "resolution" (recordFor "mori://shinzui/kenshou/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites" document) `shouldBe` String "not-a-record"
        let snapshot = root </> "snapshot"
        fst <$> quietly (runWithArgsWith program ["owners", "snapshot", "--out", snapshot]) `shouldReturn` ExitSuccess
        afterSnapshot <- readIORef calls
        (replayCode, replay) <- quietly (runWithArgsWith program ["owners", "status", "--snapshot", snapshot, "--json"])
        replayCode `shouldBe` ExitSuccess
        readIORef calls `shouldReturn` afterSnapshot
        replayed <- decodeValue replay
        field "links" (recordFor (ownerX "BUG-1") replayed) `shouldBe` field "links" canonical
        citers (recordFor (ownerX "BUG-3") replayed) `shouldBe` ["T-1"]
        -- Without --catalog, reconciliation reads the registered scenarios.
        let packageMap = root </> "package-map.json"
        ByteString.writeFile packageMap (packageMapDocument [Aeson.object ["reference" Aeson..= ownerX "BUG-1", "packages" Aeson..= ["fixture-store" :: Text], "versionsApplyTo" Aeson..= ["fixture-store" :: Text]]])
        (reconcileCode, reconciled) <- quietly (runWithArgsWith program ["owners", "reconcile", "--snapshot", snapshot, "--package-map", packageMap, "--json"])
        reconcileCode `shouldBe` ExitFailure 1
        reconciliation <- decodeValue reconciled
        [(field "scenario" finding, field "reference" finding, field "code" finding) | finding <- toArray (field "findings" reconciliation)]
          `shouldBe` [ (String "consumer/table/concurrency/competing-writers", String (ownerX "BUG-2"), String "missing-upper-bound"),
                       (String "consumer/table/concurrency/competing-writers", String (ownerY "INC-7"), String "unmapped-owner"),
                       (String "consumer/table/correctness/lease-release", String (ownerX "BUG-1"), String "missing-upper-bound"),
                       (String "selftest/kernel/correctness/known-defect", String "mori://shinzui/kenshou/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites", String "no-owner-claim")
                     ]
      doesFileExist marker `shouldReturn` False

  it "captures and replays dispositions through a consumer's evidence locations and replay hook" $
    withSystemTempDirectory "kenshou-dispositions-cli" \root -> do
      store <- memoryStore
      replayCalls <- newIORef (0 :: Int)
      let owners = root </> "owners"
          snapshot = root </> "snapshot"
          currentSnapshot = root </> "snapshot-current"
          evidence = root </> "evidence"
          runs = root </> "local"
          ownerFile = owners </> "lease.md"
          findings = root </> "findings.json"
          catalog = root </> "catalog.json"
          packageMap = root </> "package-map.json"
          coverage = root </> "coverage.json"
          frozen = root </> "input.json"
          reference = ownerX "BUG-1"
          scenario = "consumer/table/correctness/lease-release"
          bundleUri = "mori://fixture/consumer/okf/verification"
          config =
            defaultOwnerConfig
              { evidenceBundle = Just evidence,
                evidenceBundleUri = Just bundleUri,
                runDataLocator = Just (Observation.objectStoreRunData store),
                sealedRunRoots = [runs],
                replayObservation = \run -> do
                  atomicModifyIORef' replayCalls (\count -> (count + 1, ()))
                  pure (Right (Just (object ["replayedRun" .= run.runId])))
              }
          program = selfTestAssembly {commands = withCommand (ownersCommandWith config) selfTestAssembly.commands}
          invoke args = quietly (runWithArgsWith program ("owners" : args))
          freezeOwner directory = fst <$> invoke ["snapshot", "--out", directory, "--no-git-provenance", "--findings", findings, "--map", "mori://fixture/owner-x/okf/bug-reports=" <> owners]
          live directory = ["dispositions", "--snapshot", directory, "--catalog", catalog, "--package-map", packageMap, "--coverage", coverage, "--json"]
          replay = ["dispositions", "--input", frozen, "--json"]
          forOwner document = [item | item <- toArray (field "conclusions" document), field "owner" item == String reference]
          summaryCount key document = field key (field "summary" document)
      createDirectoryIfMissing True owners
      createDirectoryIfMissing True evidence
      createDirectoryIfMissing True runs
      writeBugReport ownerFile "BUG-1" "fixed" ["fixedVersion: 2.0.0"]
      ByteString.writeFile findings (findingsDocument [("F-1", [reference])])
      ByteString.writeFile catalog (catalogDocument [catalogScenario scenario reference (OnlyWhen (VersionBelow "fixture-writer" "2.0.0" :| []))])
      ByteString.writeFile packageMap (packageMapDocument [object ["reference" .= reference, "packages" .= ["fixture-writer" :: Text], "versionsApplyTo" .= ["fixture-writer" :: Text]]])
      Aeson.encodeFile coverage (Map.singleton reference [scenario :: Text])
      freezeOwner snapshot `shouldReturn` ExitSuccess
      firstAt <- maybe (fail "invalid fixture time") pure (iso8601ParseM "2026-11-17T17:00:00Z")
      let firstId = "01997f3a-5b7c-7e21-8a44-0d6c2f9b1e54"
          nextId = "01997f3a-5b7c-7e21-8a44-0d6c2f9b1e55"
      publishDispositionFixture store evidence runs firstId scenario firstAt Passed
      beforeCapture <- digests root
      (status, captured) <- invoke (live snapshot <> ["--write-input", frozen])
      status `shouldBe` ExitSuccess
      capturedValue <- decodeValue captured
      [conclusion] <- pure (forOwner capturedValue)
      field "disposition" conclusion `shouldBe` String "verified-fixed"
      summaryCount "verifiedFixed" capturedValue `shouldBe` Number 1
      [observed] <- pure (map (field "observation") (toArray (field "considered" conclusion)))
      field "replay" observed `shouldBe` object ["replayedRun" .= firstId]
      field "reference" (field "source" observed) `shouldSatisfy` \case
        String reference' -> Text.isPrefixOf (bundleUri <> "/concepts/") reference'
        _ -> False
      readIORef replayCalls `shouldReturn` 1
      (filter ((/= "input.json") . fst) <$> digests root) `shouldReturn` beforeCapture
      frozenBytes <- ByteString.readFile frozen
      fst <$> invoke (live snapshot <> ["--write-input", frozen]) `shouldReturn` ExitFailure 2
      ByteString.readFile frozen `shouldReturn` frozenBytes
      fst <$> invoke (replay <> ["--bundle", evidence]) `shouldReturn` ExitFailure 2
      fst <$> invoke ["dispositions", "--input", root </> "absent.json"] `shouldReturn` ExitFailure 4

      publishDispositionFixture store evidence runs nextId scenario (addUTCTime 1 firstAt) Failed
      writeBugReport ownerFile "BUG-1" "confirmed" []
      freezeOwner currentSnapshot `shouldReturn` ExitSuccess
      beforeReplay <- digests root
      countBeforeReplay <- readIORef replayCalls
      invoke replay `shouldReturn` (ExitSuccess, captured)
      invoke replay `shouldReturn` (ExitSuccess, captured)
      readIORef replayCalls `shouldReturn` countBeforeReplay
      (laterStatus, later) <- invoke (live snapshot)
      laterStatus `shouldBe` ExitSuccess
      laterValue <- decodeValue later
      summaryCount "regressed" laterValue `shouldBe` Number 1
      (currentStatus, current) <- invoke (live currentSnapshot)
      currentStatus `shouldBe` ExitSuccess
      currentValue <- decodeValue current
      summaryCount "stillReproduces" currentValue `shouldBe` Number 1
      digests root `shouldReturn` beforeReplay

-- | Create and publish a sealed result. The consumer replay uses the real
-- memory object store, including the recorded digest and attestation path.
publishDispositionFixture :: ObjectStore -> FilePath -> FilePath -> Text -> Text -> UTCTime -> Outcome -> IO ()
publishDispositionFixture store bundle runRoot identifier scenario started outcome = do
  let directory = runRoot </> Text.unpack identifier
      runSpec = object ["schema" .= ("kenshou.run-spec/v1" :: Text), "runId" .= identifier, "scenario" .= scenario, "seed" .= (7 :: Int)]
      planHash = "sha256:" <> Text.replicate 64 "a"
      revision = Text.replicate 40 "a"
      result =
        object
          [ "schema" .= ("kenshou.run-result/v1" :: Text),
            "runId" .= identifier,
            "scenario" .= scenario,
            "scenarioRevision" .= (1 :: Int),
            "outcome" .= outcome,
            "failures" .= (["lease-held" :: Text | outcome == Failed]),
            "tier" .= ("smoke" :: Text),
            "seed" .= (7 :: Int),
            "spec" .= object ["sha256" .= sha256Hex (ByteString.toStrict (Aeson.encode runSpec))],
            "timings" .= object ["startedAt" .= started, "endedAt" .= started],
            "cohort"
              .= object
                [ "schema" .= ("kenshou.cohort-identity/v1" :: Text),
                  "cohort" .= ("fixture" :: Text),
                  "compiler" .= ("ghc" :: Text),
                  "cabalVersion" .= ("3.14" :: Text),
                  "os" .= ("darwin" :: Text),
                  "arch" .= ("aarch64" :: Text),
                  "planHash" .= planHash,
                  "descriptorSha256" .= planHash,
                  "components"
                    .= [ object
                           [ "id" .= ("consumer" :: Text),
                             "moriUri" .= ("mori://fixture/consumer" :: Text),
                             "packages" .= [object ["name" .= ("fixture-writer" :: Text), "version" .= ("2.0.0" :: Text), "source" .= object ["type" .= ("hackage" :: Text)]]]
                           ]
                       ]
                ],
            "fingerprint"
              .= object
                [ "host" .= object ["os" .= ("darwin" :: Text), "arch" .= ("aarch64" :: Text), "cpuModel" .= ("fixture" :: Text), "logicalCores" .= (4 :: Int), "memoryBytes" .= (4096 :: Int)],
                  "runtime" .= object ["ghc" .= ("9.12.4" :: Text)],
                  "kenshou" .= object ["revision" .= revision, "dirty" .= False]
                ],
            "compatibility" .= object ["comparisonKey" .= planHash]
          ]
  createDirectoryIfMissing True directory
  Aeson.encodeFile (directory </> "run-spec.json") runSpec
  Aeson.encodeFile (directory </> "run-result.json") result
  runId <- either (fail . Text.unpack) pure (parseRunId identifier)
  writeManifest directory runId Map.empty >>= Aeson.encodeFile (directory </> "manifest.json")
  source <- loadRunSource directory >>= either (fail . show) pure
  links <- publishRunData store (PublishOptions "gs://fixture/data" UploadMissing False False) directory source >>= either (fail . show) pure
  let input = RecordInput Release started False Nothing [] Nothing Map.empty (Just "mori://fixture/consumer")
  record <- either (fail . show) pure (buildRunRecord input source links)
  path <- either (fail . show) pure (runRecordPath record)
  _ <- writeRunRecordWith (const (pure (Right ()))) bundle record >>= either (fail . show) pure
  ByteString.writeFile (bundle </> Text.unpack identifier <> "-attestation.md") . Text.Encoding.encodeUtf8 . Text.unlines $
    [ "---",
      "type: Attestation",
      "title: Confirmed sealed fixture",
      "run: /" <> Text.pack path,
      "verdict: confirmed",
      "attestedAt: 2026-11-17T18:00:00Z",
      "---"
    ]

ownerX :: Text -> Text
ownerX handle = "mori://fixture/owner-x/okf/bug-reports/concepts/" <> handle

ownerY :: Text -> Text
ownerY handle = "mori://fixture/owner-y/okf/incidents/concepts/" <> handle

runOwners :: [String] -> IO ExitCode
runOwners = runWithArgsWith selfTestAssembly

-- | A made-up layer whose known defects cite owner records, one of them through a
-- group of two defects.
consumerBundle :: LayerBundle
consumerBundle = mkBundle layer [leaseRelease, competingWriters] []
  where
    layer = either (error . Text.unpack) id (mkLayerId "consumer")
    leaseRelease = consumerScenario "consumer/table/correctness/lease-release" (Just (defect (ownerX "BUG-1") ["lease-held"]))
    competingWriters =
      consumerScenario
        "consumer/table/concurrency/competing-writers"
        (Just (KnownDefectGroup (defect (ownerX "BUG-2") ["lease-held"] :| [defect (ownerY "INC-7") ["stale-read"]])))
    defect reference labels = KnownDefect {reference, summary = "Owner record fixture", expectedFailures = labels, appliesTo = AllCohorts}

consumerScenario :: Text -> Maybe KnownDefect -> Scenario
consumerScenario identifier knownDefect =
  Scenario
    { id = either (error . Text.unpack) id (parseScenarioId identifier),
      revision = 1,
      summary = "Synthetic consumer scenario.",
      tier = TierSmoke,
      placement = PlaceEither,
      knobs = [],
      dimensions = noDimensions,
      phases = zeroPhases,
      requires = noEnvironment,
      knownDefect,
      run = const (pure passed)
    }

-- | The consumer's in-memory records, including a kind Kenshou does not configure.
consumerResolver :: OwnerResolver
consumerResolver =
  memoryResolver
    "consumer"
    [ (ownerX "BUG-1", ("bugs/lease.md", bugReportBytes "BUG-1" "fixed" ["fixedVersion: 3.1.0"])),
      (ownerX "BUG-2", ("bugs/writers.md", bugReportBytes "BUG-2" "duplicate" ["duplicateOf: BUG-1"])),
      (ownerX "BUG-3", ("bugs/tracker.md", bugReportBytes "BUG-3" "confirmed" [])),
      (ownerY "INC-7", ("incidents/stale.md", "---\ntype: Incident\ntitle: Stale read\nincidentId: INC-7\nstatus: open\n---\n"))
    ]

bugReportBytes :: Text -> Text -> [Text] -> ByteString
bugReportBytes handle status extra =
  Text.Encoding.encodeUtf8 . Text.unlines $
    ["---", "type: Bug Report", "title: \"Fixture " <> handle <> "\"", "bugId: " <> handle, "status: " <> status] <> extra <> ["---", "", "# Fixture " <> handle]

writeBugReport :: FilePath -> Text -> Text -> [Text] -> IO ()
writeBugReport path handle status extra = ByteString.writeFile path (bugReportBytes handle status extra)

packageMapDocument :: [Value] -> ByteString
packageMapDocument owners =
  ByteString.toStrict . Aeson.encode $
    Aeson.object
      [ "schema" Aeson..= ("kenshou.owner-package-map/v1" :: Text),
        "owners" Aeson..= owners,
        "sources" Aeson..= [Aeson.object ["scenario" Aeson..= ("consumer/table/correctness/writer-stall" :: Text), "path" Aeson..= ("consumer/src/Writer.hs" :: Text), "line" Aeson..= (12 :: Int)]]
      ]

-- | A catalog scenario carrying a single known defect's complete declaration.
catalogScenario :: Text -> Text -> CohortScope -> Value
catalogScenario identifier reference scope =
  Aeson.object
    [ "id" Aeson..= identifier,
      "summary" Aeson..= ("Reconciliation scenario" :: Text),
      "knownDefect" Aeson..= reference,
      "knownDefectDeclaration" Aeson..= defectValue KnownDefect {reference, summary = "Owner record fixture", expectedFailures = ["lease-held"], appliesTo = scope}
    ]

catalogDocument :: [Value] -> ByteString
catalogDocument scenarios =
  ByteString.toStrict . Aeson.encode $
    Aeson.object ["schema" Aeson..= ("kenshou.scenario-list/v1" :: Text), "suiteVersion" Aeson..= ("0.1.0.0" :: Text), "scenarios" Aeson..= scenarios, "roles" Aeson..= ([] :: [Value])]

findingsDocument :: [(Text, [Text])] -> ByteString
findingsDocument findings =
  ByteString.toStrict . Aeson.encode $
    Aeson.object
      [ "schema" Aeson..= ("kenshou.owner-findings/v1" :: Text),
        "findings" Aeson..= [Aeson.object ["id" Aeson..= identifier, "references" Aeson..= references] | (identifier, references) <- findings]
      ]

-- | The SHA-256 of every file under a directory, by relative path.
digests :: FilePath -> IO [(FilePath, Text)]
digests root = sort <$> go ""
  where
    go relative = do
      entries <- listDirectory (root </> relative)
      concat <$> forM entries \entry -> do
        let path = if null relative then entry else relative </> entry
        isFile <- doesFileExist (root </> path)
        if isFile then (\bytes -> [(path, sha256Hex bytes)]) <$> ByteString.readFile (root </> path) else go path

withoutSnapshot :: [(FilePath, Text)] -> [(FilePath, Text)]
withoutSnapshot = filter (not . Text.isPrefixOf "snapshot" . Text.pack . fst)

-- | Run with standard output captured and standard error discarded.
quietly :: IO a -> IO (a, ByteString)
quietly action = withSystemTempFile "owners-stderr" \_ errors -> do
  (result, output) <- capture stdout (redirect stderr errors action)
  pure (result, output)

capture :: Handle -> IO a -> IO (a, ByteString)
capture target action = withSystemTempFile "owners-stdout" \path handle -> do
  result <- redirect target handle action
  hClose handle
  bytes <- ByteString.readFile path
  pure (result, bytes)

redirect :: Handle -> Handle -> IO a -> IO a
redirect target replacement action = do
  hFlush target
  saved <- hDuplicate target
  hDuplicateTo replacement target
  action `finally` (hFlush target >> hDuplicateTo saved target >> hClose saved)

-- | Put a @mori@ on @PATH@ that records that it ran and fails.
withFakeMori :: FilePath -> FilePath -> IO a -> IO a
withFakeMori root marker action = do
  let bin = root </> "bin"
      script = bin </> "mori"
  createDirectoryIfMissing True bin
  writeFile script ("#!/bin/sh\ntouch '" <> marker <> "'\nexit 1\n")
  getPermissions script >>= setPermissions script . setOwnerExecutable True
  previous <- lookupEnv "PATH"
  setEnv "PATH" (bin <> maybe "" (":" <>) previous)
  action `finally` maybe (unsetEnv "PATH") (setEnv "PATH") previous

decodeValue :: ByteString -> IO Value
decodeValue bytes = either fail pure (Aeson.eitherDecodeStrict' bytes)

field :: Text -> Value -> Value
field name (Object fields) = maybe Null id (KeyMap.lookup (Key.fromText name) fields)
field _ _ = Null

recordFor :: Text -> Value -> Value
recordFor reference document = case [entry | entry <- toArray (field "records" document), field "reference" entry == String reference] of
  entry : _ -> entry
  [] -> error ("no record for " <> Text.unpack reference)

statusOf :: Text -> Value -> Value
statusOf reference = field "status" . recordFor reference

citers :: Value -> [Text]
citers entry =
  sort
    [ citer <> maybe "" (" via " <>) via
    | cited <- toArray (field "citedBy" entry),
      Just citer <- [textOf (field "scenario" cited) <|> textOf (field "finding" cited)],
      let via = textOf (field "via" cited)
    ]
  where
    textOf (String value) = Just value
    textOf _ = Nothing
    Nothing <|> other = other
    found <|> _ = found

toArray :: Value -> [Value]
toArray (Array items) = toList items
toArray _ = []
