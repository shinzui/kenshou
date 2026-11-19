-- | Complete known-defect declarations in the catalog: the encoding round-trips
-- every scope and condition constructor and nested groups, both catalog encoders
-- carry it, and the older @knownDefect@ reference field is unchanged.
module Kenshou.DefectSpec (spec) where

import Data.Aeson (Value (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Aeson.Types (parseEither)
import Data.ByteString qualified as ByteString
import Data.Foldable (toList)
import Data.List.NonEmpty (NonEmpty (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Kenshou.Core.Bundle (LayerBundle (..), scenarioListDocumentFor)
import Kenshou.Core.Defect (defectValue, parseDefect)
import Kenshou.Core.Dimension (noDimensions)
import Kenshou.Core.Env (noEnvironment)
import Kenshou.Core.Id (parseScenarioId)
import Kenshou.Core.Phase (zeroPhases)
import Kenshou.Core.Scenario
import Kenshou.Core.Selftest qualified as Selftest
import Kenshou.Plan.Catalog (CatalogDocument (CatalogDocument), ScenarioInfo (knownDefect), decodeCatalog, fromScenario)
import Test.Hspec

spec :: Spec
spec = describe "Kenshou.Core.Defect" do
  it "round-trips every scope and condition constructor, a group, and a nested group" do
    mapM_ (\defect -> parseEither parseDefect (defectValue defect) `shouldBe` Right defect) declarations

  it "encodes the documented shape" do
    Aeson.encode (defectValue hackageBound)
      `shouldBe` "{\"appliesTo\":{\"conditions\":[{\"kind\":\"resolved-from-hackage\",\"package\":\"fixture-store\"},{\"kind\":\"version-below\",\"package\":\"fixture-store\",\"version\":\"1.3.0\"}],\"kind\":\"only-when\"},\"expectedFailures\":[\"lease-held\"],\"kind\":\"single\",\"reference\":\"mori://fixture/owner-a/okf/bug-reports/concepts/BUG-2\",\"summary\":\"Lease is not released after a cancelled write\"}"

  it "rejects unknown kinds and empty groups or condition lists" do
    let rejects text = either (const True) (const False) (Aeson.eitherDecodeStrict' text >>= parseEither parseDefect)
    rejects "{\"kind\":\"triple\"}" `shouldBe` True
    rejects "{\"kind\":\"group\",\"defects\":[]}" `shouldBe` True
    rejects "{\"kind\":\"single\",\"reference\":\"r\",\"summary\":\"s\",\"expectedFailures\":[],\"appliesTo\":{\"kind\":\"only-when\",\"conditions\":[]}}" `shouldBe` True
    rejects "{\"kind\":\"single\",\"reference\":\"r\",\"summary\":\"s\",\"expectedFailures\":[],\"appliesTo\":{\"kind\":\"only-when\",\"conditions\":[{\"kind\":\"version-above\",\"package\":\"p\",\"version\":\"1\"}]}}" `shouldBe` True

  it "keeps declarations through a planning catalog written and read back" do
    let infos = fmap fromScenario (declared <> [scenarioWith "none" Nothing])
        bytes = ByteString.toStrict (Aeson.encode (CatalogDocument infos))
    decoded <- either (fail . Text.unpack) pure (decodeCatalog bytes)
    fmap (.knownDefect) decoded `shouldBe` fmap (.knownDefect) infos

  it "keeps declarations through the kenshou list --json document read back" do
    let scenarios = declared <> Selftest.bundle.scenarios
        bytes = ByteString.toStrict (Aeson.encode (scenarioListDocumentFor scenarios []))
    decoded <- either (fail . Text.unpack) pure (decodeCatalog bytes)
    fmap (.knownDefect) decoded `shouldBe` fmap (.knownDefect) scenarios

  it "leaves the knownDefect reference field as it was before declarations were added" do
    let scenarios = declared <> Selftest.bundle.scenarios
        listed = scenarioEntries (scenarioListDocumentFor scenarios [])
        planned = scenarioEntries (Aeson.toJSON (CatalogDocument (fmap fromScenario scenarios)))
        expected = fmap (maybe Null previousReferences . (.knownDefect)) scenarios
    fmap (field "knownDefect") listed `shouldBe` expected
    fmap (field "knownDefect") planned `shouldBe` expected
    fmap (field "knownDefectDeclaration") listed `shouldBe` fmap (maybe Null defectValue . (.knownDefect)) scenarios

  it "still decodes catalogs without the declaration field" do
    golden <- ByteString.readFile "test/golden/scenario-list.json"
    planned <- ByteString.readFile "test/fixtures/plan/catalog-planned.json"
    let stripped = ByteString.toStrict (Aeson.encode (withoutDeclarations (either error id (Aeson.eitherDecodeStrict' golden))))
    fmap (fmap (.knownDefect)) (decodeCatalog golden) `shouldBe` Right [Nothing]
    fmap (fmap (.knownDefect)) (decodeCatalog stripped) `shouldBe` Right [Nothing]
    fmap (all ((== Nothing) . (.knownDefect))) (decodeCatalog planned) `shouldBe` Right True

-- | One declaration per scope and condition constructor, a group whose members
-- have different scopes, and a group nested in a group.
declarations :: [KnownDefect]
declarations =
  [ single "BUG-1" AllCohorts,
    hackageBound,
    single "BUG-3" (OnlyWhen (ResolvedFromGit "fixture-queue" :| [RevisionIs "fixture-queue" "0123456789abcdef0123456789abcdef01234567"])),
    group,
    KnownDefectGroup (group :| [single "BUG-6" (OnlyWhen (VersionBelow "fixture-queue" "2.0.0" :| []))])
  ]
  where
    group = KnownDefectGroup (single "BUG-4" AllCohorts :| [single "BUG-5" (OnlyWhen (ResolvedFromHackage "fixture-queue" :| []))])

hackageBound :: KnownDefect
hackageBound =
  KnownDefect
    { reference = "mori://fixture/owner-a/okf/bug-reports/concepts/BUG-2",
      summary = "Lease is not released after a cancelled write",
      expectedFailures = ["lease-held"],
      appliesTo = OnlyWhen (ResolvedFromHackage "fixture-store" :| [VersionBelow "fixture-store" "1.3.0"])
    }

single :: Text -> CohortScope -> KnownDefect
single handle appliesTo =
  KnownDefect
    { reference = "mori://fixture/owner-a/okf/bug-reports/concepts/" <> handle,
      summary = "Fixture defect " <> handle,
      expectedFailures = ["failure-" <> Text.toLower handle, "shared-failure"],
      appliesTo
    }

-- | A copy of the reference encoding the catalog used before declarations were
-- added, kept here so a change to it is caught.
previousReferences :: KnownDefect -> Value
previousReferences defect = case individualKnownDefects defect of
  [one] -> Aeson.toJSON one.reference
  many -> Aeson.toJSON (fmap (.reference) many)

-- | A scenario for each declaration.
declared :: [Scenario]
declared = zipWith (\name defect -> scenarioWith name (Just defect)) ["single", "bounded", "git", "group", "nested"] declarations

scenarioWith :: Text -> Maybe KnownDefect -> Scenario
scenarioWith name knownDefect =
  Scenario
    { id = either (error . Text.unpack) id (parseScenarioId ("consumer/table/correctness/defect-" <> name)),
      revision = 1,
      summary = "Synthetic defect scenario.",
      tier = TierSmoke,
      placement = PlaceEither,
      knobs = [],
      dimensions = noDimensions,
      phases = zeroPhases,
      requires = noEnvironment,
      knownDefect,
      run = const (pure passed)
    }

scenarioEntries :: Value -> [Value]
scenarioEntries document = case field "scenarios" document of
  Array items -> toList items
  _ -> []

field :: Text -> Value -> Value
field name (Object fields) = maybe Null id (KeyMap.lookup (Key.fromText name) fields)
field _ _ = Null

withoutDeclarations :: Value -> Value
withoutDeclarations (Object fields) = Object (fmap withoutDeclarations (KeyMap.delete "knownDefectDeclaration" fields))
withoutDeclarations (Array items) = Array (fmap withoutDeclarations items)
withoutDeclarations other = other
