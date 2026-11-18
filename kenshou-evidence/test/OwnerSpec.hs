module OwnerSpec (spec) where

import Control.Monad (forM_)
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString.Char8
import Data.List (find, sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime (..), fromGregorian)
import Data.Version (makeVersion)
import Kenshou.Core.Id (parseScenarioId, renderScenarioId)
import Kenshou.Evidence.Owner
import Kenshou.Evidence.Owner.Record (reasonCode)
import Kenshou.Evidence.Owner.Resolver (ConceptReference (..), chainResolvers, mappedResolver, memoryResolver, parseConceptReference, withGitProvenance)
import Kenshou.Evidence.Owner.Snapshot (SnapshotError (..), readSnapshot, writeSnapshot)
import System.Directory (createDirectory, doesPathExist, listDirectory)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)
import Test.Hspec

spec :: Spec
spec = describe "owner records" do
  it "accepts only canonical concept references" do
    fmap (.handle) (parseConceptReference (ownerA "BUG-1")) `shouldBe` Just "BUG-1"
    fmap (.bundle) (parseConceptReference (ownerA "BUG-1")) `shouldBe` Just "mori://fixture/owner-a/okf/bug-reports"
    parseConceptReference planReference `shouldBe` Nothing
    parseConceptReference "https://example.org/issues/12" `shouldBe` Nothing
    parseConceptReference "mori://fixture/owner-a/okf/bug-reports/concepts/" `shouldBe` Nothing

  it "keeps two owners' records with the same local handle distinct" do
    entries <- fixtureEntries
    let a = entryFor entries (ownerA "BUG-1")
        b = entryFor entries (ownerB "BUG-1")
    a.resolution `shouldBe` Resolved
    b.resolution `shouldBe` Resolved
    fmap (.status) a.record `shouldBe` Just (Just "fixed")
    fmap (.status) b.record `shouldBe` Just (Just "confirmed")
    a.canonical `shouldBe` Just (ownerA "BUG-1")
    b.canonical `shouldBe` Just (ownerB "BUG-1")
    fmap (.location) a.source `shouldBe` Just (Just "reader-loses-last-item.md")
    citers a `shouldBe` ["finding F-1", "scenario consumer/table/correctness/reader-restart"]
    citers b `shouldBe` ["finding F-3"]

  it "follows a duplicate chain to its canonical record and keeps the aliases" do
    entries <- fixtureEntries
    let canonical = entryFor entries (ownerA "BUG-2")
    canonical.canonical `shouldBe` Just (ownerA "BUG-2")
    canonical.aliases `shouldBe` [ownerA "BUG-4", ownerA "BUG-8"]
    (entryFor entries (ownerA "BUG-4")).canonical `shouldBe` Just (ownerA "BUG-2")
    (entryFor entries (ownerA "BUG-8")).canonical `shouldBe` Just (ownerA "BUG-2")
    (entryFor entries (ownerA "BUG-4")).citedBy `shouldBe` []
    [(citer citation, via) | (citation, via) <- canonical.citedBy]
      `shouldBe` [ ("finding F-2", Nothing),
                   ("scenario consumer/table/correctness/lease-release", Just (ownerA "BUG-8")),
                   ("finding F-2", Just (ownerA "BUG-8"))
                 ]

  it "names a duplicate cycle and gives its members no canonical record" do
    entries <- fixtureEntries
    forM_ [ownerA "BUG-5", ownerA "BUG-6"] \reference -> do
      let entry = entryFor entries reference
      entry.resolution `shouldBe` Resolved
      codes entry `shouldBe` ["duplicate-cycle"]
      entry.canonical `shouldBe` Nothing
    (entryFor entries (ownerA "BUG-6")).citedBy `shouldBe` []

  it "reports a missing record and a missing duplicate target" do
    entries <- fixtureEntries
    let missing = entryFor entries (ownerA "BUG-404")
        chain = entryFor entries (ownerA "BUG-7")
        target = entryFor entries (ownerA "BUG-99")
    missing.resolution `shouldBe` Unresolved
    codes missing `shouldBe` ["not-found"]
    missing.record `shouldBe` Nothing
    chain.reasons `shouldBe` [DuplicateTargetUnresolved (ownerA "BUG-99")]
    chain.canonical `shouldBe` Nothing
    target.resolution `shouldBe` Unresolved
    target.citedBy `shouldBe` []

  it "reports documentation, links, and other concept types as not owner records" do
    entries <- fixtureEntries
    let guide = entryFor entries (ownerA "BUG-11")
        link = entryFor entries "https://example.org/issues/12"
        plan = entryFor entries planReference
    guide.resolution `shouldBe` NotARecord
    guide.reasons `shouldBe` [UnconfiguredType "Guide"]
    link.resolution `shouldBe` NotARecord
    link.reasons `shouldBe` [NotAConcept]
    link.source `shouldBe` Nothing
    plan.resolution `shouldBe` NotARecord
    citers plan `shouldBe` ["scenario selftest/kernel/correctness/known-defect"]

  it "keeps released, unreleased, unknown, unparseable, and malformed versions distinct" do
    entries <- fixtureEntries
    let versions reference = fmap (\record -> (record.affectedVersion, record.fixedVersion, record.lastWorkingVersion)) (entryFor entries reference).record
    versions (ownerA "BUG-1") `shouldBe` Just (ClaimReleased (makeVersion [1, 2, 0]) "1.2.0", ClaimReleased (makeVersion [1, 3, 0]) "1.3.0", ClaimReleased (makeVersion [1, 1, 4]) "1.1.4")
    versions (ownerA "BUG-3") `shouldBe` Just (ClaimReleased (makeVersion [1, 2, 0]) "1.2.0", ClaimUnreleased, ClaimAbsent)
    versions (ownerA "BUG-10") `shouldBe` Just (ClaimUnknown, ClaimUnknown, ClaimAbsent)
    versions (ownerB "BUG-2") `shouldBe` Just (ClaimReleased (makeVersion [0, 4, 1]) "0.4.1", ClaimUnparseable "after the next release", ClaimAbsent)
    versions (ownerA "BUG-9") `shouldBe` Just (ClaimReleased (makeVersion [1, 2, 0]) "1.2.0", ClaimMalformed, ClaimAbsent)
    (entryFor entries (ownerA "BUG-9")).reasons `shouldBe` [MalformedField "fixedVersion" "text"]
    (entryFor entries (ownerA "BUG-9")).resolution `shouldBe` Resolved

  it "never selects a record by file name and reports a handle two records share" do
    entries <- fixtureEntries
    let shared = entryFor entries (ownerB "BUG-3")
    shared.resolution `shouldBe` Unresolved
    shared.reasons `shouldBe` [AmbiguousHandle ["shutdown-hangs-again.md", "shutdown-hangs.md"]]
    -- index.md also carries BUG-1; it is not a record, so owner-a BUG-1 stays unique.
    codes (entryFor entries (ownerA "BUG-1")) `shouldBe` []

  it "does not treat a record whose own handle differs from the reference as resolved" do
    let reference = "mori://fixture/owner-c/okf/bug-reports/concepts/BUG-1"
        bytes = "---\ntype: Bug Report\ntitle: Other\nbugId: BUG-2\nstatus: fixed\n---\n"
        resolver = memoryResolver "memory" [(reference, ("other.md", bytes))]
    [entry] <- resolveOwners defaultRecordKinds resolver [OwnerCitation reference (CitedByFinding "F-9") Nothing]
    entry.resolution `shouldBe` Unresolved
    entry.reasons `shouldBe` [HandleMismatch "BUG-1" "BUG-2"]
    fmap (.handle) entry.record `shouldBe` Just "BUG-2"
    entry.canonical `shouldBe` Nothing

  it "reports a reference no resolver maps" do
    [entry] <- resolveOwners defaultRecordKinds (chainResolvers []) [OwnerCitation (ownerA "BUG-1") (CitedByFinding "F-1") Nothing]
    entry.reasons `shouldBe` [NoResolver]

  it "maps every reference to its canonical entry" do
    entries <- fixtureEntries
    let joined = canonicalOwners (OwnerStatus fixedTime Nothing entries)
    fmap (.reference) (Map.lookup (ownerA "BUG-8") joined) `shouldBe` Just (ownerA "BUG-2")
    fmap (.reference) (Map.lookup (ownerA "BUG-5") joined) `shouldBe` Just (ownerA "BUG-5")
    fmap (.reference) (Map.lookup (ownerB "BUG-1") joined) `shouldBe` Just (ownerB "BUG-1")

  it "encodes the fixture set exactly as the golden status document" do
    entries <- fixtureEntries
    let encoded = prettyJson (ownerStatusValue (OwnerStatus fixedTime Nothing entries))
    accept <- lookupEnv "KENSHOU_ACCEPT_GOLDEN"
    case accept of
      Just "1" -> ByteString.writeFile goldenPath encoded
      _ -> pure ()
    golden <- ByteString.readFile goldenPath
    encoded `shouldBe` golden

  it "records no git state unless asked, and none outside a checkout" do
    withSystemTempDirectory "kenshou-owner-nogit" \directory -> do
      let bundle = directory </> "bugs"
      createDirectory bundle
      ByteString.writeFile (bundle </> "report.md") "---\ntype: Bug Report\ntitle: One\nbugId: BUG-1\nstatus: reported\n---\n"
      let resolver = withGitProvenance (mappedResolver defaultRecordKinds [("mori://fixture/temp/okf/bugs", bundle)])
      [entry] <- resolveOwners defaultRecordKinds resolver [OwnerCitation "mori://fixture/temp/okf/bugs/concepts/BUG-1" (CitedByFinding "F-1") Nothing]
      entry.resolution `shouldBe` Resolved
      fmap (.revision) entry.source `shouldBe` Just Nothing
      fmap (.dirty) entry.source `shouldBe` Just Nothing
      fmap (.location) entry.source `shouldBe` Just (Just "report.md")

  it "replays a snapshot to the same entries and refuses to overwrite it" do
    withSystemTempDirectory "kenshou-owner-snapshot" \directory -> do
      citations <- fixtureCitations
      (entries, answers) <- resolveOwnersObserved defaultRecordKinds fixtureResolver citations
      let status = OwnerStatus fixedTime Nothing entries
          first = directory </> "first"
          second = directory </> "second"
      Right digest <- writeSnapshot first defaultRecordKinds citations answers status
      Right _ <- writeSnapshot second defaultRecordKinds citations answers status
      writeSnapshot first defaultRecordKinds citations answers status `shouldReturn` Left SnapshotExists
      firstIndex <- ByteString.readFile (first </> "snapshot.json")
      secondIndex <- ByteString.readFile (second </> "snapshot.json")
      firstIndex `shouldBe` secondIndex
      ByteString.Char8.pack directory `shouldNotSatisfy` (`ByteString.isInfixOf` firstIndex)
      Right replayed <- readSnapshot first
      replayed.snapshotDigest `shouldBe` Just digest
      replayed.observedAt `shouldBe` fixedTime
      replayed.records `shouldBe` entries
      -- every reference reached, including uncited duplicate targets, is stored
      records <- listDirectory (first </> "records")
      length records `shouldBe` length [() | entry <- entries, Just _ <- [entry.source]]
      siblings <- listDirectory directory
      sort siblings `shouldBe` ["first", "second"]

  it "writes the golden snapshot index for the fixture set" do
    withSystemTempDirectory "kenshou-owner-snapshot-golden" \directory -> do
      citations <- fixtureCitations
      (entries, answers) <- resolveOwnersObserved defaultRecordKinds fixtureResolver citations
      Right _ <- writeSnapshot (directory </> "snapshot") defaultRecordKinds citations answers (OwnerStatus fixedTime Nothing entries)
      index <- ByteString.readFile (directory </> "snapshot" </> "snapshot.json")
      accept <- lookupEnv "KENSHOU_ACCEPT_GOLDEN"
      case accept of
        Just "1" -> ByteString.writeFile snapshotGoldenPath index
        _ -> pure ()
      golden <- ByteString.readFile snapshotGoldenPath
      index `shouldBe` golden

  it "rejects a snapshot whose record bytes changed" do
    withSystemTempDirectory "kenshou-owner-tamper" \directory -> do
      citations <- fixtureCitations
      (entries, answers) <- resolveOwnersObserved defaultRecordKinds fixtureResolver citations
      let target = directory </> "snapshot"
      Right _ <- writeSnapshot target defaultRecordKinds citations answers (OwnerStatus fixedTime Nothing entries)
      record : _ <- listDirectory (target </> "records")
      ByteString.appendFile (target </> "records" </> record) "tampered\n"
      replayed <- readSnapshot target
      either (const True) (const False) replayed `shouldBe` True
      doesPathExist (target </> "snapshot.json") `shouldReturn` True

ownerA :: Text -> Text
ownerA handle = "mori://fixture/owner-a/okf/bug-reports/concepts/" <> handle

ownerB :: Text -> Text
ownerB handle = "mori://fixture/owner-b/okf/bug-reports/concepts/" <> handle

planReference :: Text
planReference = "mori://shinzui/kenshou/plans/2-open-the-kernel-layer-identity-and-schema-composition-to-registered-suites"

fixtureRoot :: FilePath
fixtureRoot = "test/fixtures/owners"

goldenPath :: FilePath
goldenPath = fixtureRoot </> "status.golden.json"

snapshotGoldenPath :: FilePath
snapshotGoldenPath = fixtureRoot </> "snapshot.golden.json"

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 11 17) 0

fixtureResolver :: OwnerResolver
fixtureResolver =
  mappedResolver
    defaultRecordKinds
    [ ("mori://fixture/owner-a/okf/bug-reports", fixtureRoot </> "owner-a" </> "bug-reports"),
      ("mori://fixture/owner-b/okf/bug-reports/", fixtureRoot </> "owner-b" </> "bug-reports")
    ]

-- | The findings file plus three scenario citations: one overlapping a finding,
-- one through a duplicate alias, and the self-test's reference to a plan.
fixtureCitations :: IO [OwnerCitation]
fixtureCitations = do
  Right findings <- (findingsFileSource (fixtureRoot </> "findings.json")).citations
  let scenario raw labels reference = case parseScenarioId raw of
        Right identifier -> OwnerCitation reference (CitedByScenario identifier labels) Nothing
        Left problem -> error (Text.unpack problem)
  pure $
    [ scenario "consumer/table/correctness/lease-release" ["lease-held"] (ownerA "BUG-8"),
      scenario "consumer/table/correctness/reader-restart" ["last-item-lost"] (ownerA "BUG-1"),
      scenario "selftest/kernel/correctness/known-defect" ["seeded-defect"] planReference
    ]
      <> findings

fixtureEntries :: IO [OwnerEntry]
fixtureEntries = fixtureCitations >>= resolveOwners defaultRecordKinds fixtureResolver

entryFor :: [OwnerEntry] -> Text -> OwnerEntry
entryFor entries reference = case find ((== reference) . (.reference)) entries of
  Just entry -> entry
  Nothing -> error ("no entry for " <> Text.unpack reference)

codes :: OwnerEntry -> [Text]
codes entry = fmap reasonCode entry.reasons

citer :: OwnerCitation -> Text
citer citation = case citation.citer of
  CitedByFinding identifier -> "finding " <> identifier
  CitedByScenario identifier _ -> "scenario " <> renderScenarioId identifier

citers :: OwnerEntry -> [Text]
citers entry = sort [citer citation | (citation, Nothing) <- entry.citedBy]
