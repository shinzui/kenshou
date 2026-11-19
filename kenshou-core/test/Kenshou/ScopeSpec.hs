-- | The scope evaluator against a frozen copy of the scope semantics execution
-- used before 'evaluateScope' existed. Any disagreement means the meaning of a
-- known-defect scope moved.
module Kenshou.ScopeSpec (spec) where

import Data.List.NonEmpty (NonEmpty (..))
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Version (parseVersion)
import Hedgehog (Gen, forAll)
import Hedgehog.Gen qualified as Gen
import Hedgehog.Range qualified as Range
import Kenshou.Core.Cohort
import Kenshou.Core.Scenario
import Test.Hspec
import Test.Hspec.Hedgehog (hedgehog, (===))
import Text.ParserCombinators.ReadP (readP_to_S)

spec :: Spec
spec = describe "Kenshou.Core.Scenario.evaluateScope" do
  it "agrees with the pre-evaluator cohortScopeApplies on every table case" do
    mapM_ (\(label, packages, scope) -> (label, cohortScopeApplies (cohortOf packages) scope) `shouldBe` (label, oracleCohortScopeApplies (cohortOf packages) scope)) table

  it "gives each table case its expected answer" do
    [(label, cohortScopeApplies (cohortOf packages) scope) | (label, packages, scope) <- table] `shouldBe` [(label, expected) | ((label, _, _), expected) <- zip table expectations]

  it "agrees with the pre-evaluator cohortScopeApplies on generated cohorts and scopes" $ hedgehog do
    packages <- forAll (Gen.list (Range.linear 0 6) genPackage)
    scope <- forAll genScope
    cohortScopeApplies (cohortOf packages) scope === oracleCohortScopeApplies (cohortOf packages) scope

  it "applies a group member's scope independently of the other members" do
    let cohort = cohortOf [hackage "fixture-store" "1.2.0"]
        group = KnownDefectGroup (defect AllCohorts :| [defect (only [ResolvedFromGit "fixture-store"]), defect (only [VersionBelow "fixture-store" "1.3.0"])])
    [cohortScopeApplies cohort member.appliesTo | member <- individualKnownDefects group] `shouldBe` [True, False, True]
    [oracleCohortScopeApplies cohort member.appliesTo | member <- individualKnownDefects group] `shouldBe` [True, False, True]

  it "reports missing packages and malformed versions as such" do
    let packages = cohortScopePackages (cohortOf [hackage "fixture-store" "1.2.0", hackage "fixture-queue" "not-a-version", git "fixture-git" "abc"])
        evaluation =
          evaluateScope packages $
            only
              [ VersionBelow "fixture-store" "1.3.0",
                VersionBelow "fixture-store" "1.1.0",
                VersionBelow "fixture-absent" "1.0.0",
                VersionBelow "fixture-store" "one",
                VersionBelow "fixture-queue" "2.0.0",
                RevisionIs "fixture-git" "def",
                ResolvedFromHackage "fixture-git"
              ]
    fmap (fmap snd) (results evaluation)
      `shouldBe` Just
        [ ConditionHolds,
          ConditionFails,
          ConditionPackageMissing,
          ConditionMalformed "one",
          ConditionMalformed "not-a-version",
          ConditionFails,
          ConditionFails
        ]
    scopeApplies evaluation `shouldBe` False
    evaluateScope [] AllCohorts `shouldBe` AppliesToAll
    scopeApplies AppliesToAll `shouldBe` True

  it "reads cohort packages with their sources" do
    cohortScopePackages (cohortOf [hackage "a" "1.0", git "b" "rev", ResolvedPackage "c" "2.0" FromBoot, ResolvedPackage "d" "3.0" (FromLocalPath "x")])
      `shouldBe` [ScopePackage "a" "1.0" ScopeHackage, ScopePackage "b" "1.0.0" (ScopeGit "rev"), ScopePackage "c" "2.0" ScopeOther, ScopePackage "d" "3.0" ScopeOther]
  where
    results = \case
      AppliesToAll -> Nothing
      Evaluated items -> Just (NonEmpty.toList items)

table :: [(Text, [ResolvedPackage], CohortScope)]
table =
  [ ("all cohorts, empty cohort", [], AllCohorts),
    ("hackage below the bound", [hackage "fixture-store" "1.2.9"], only [VersionBelow "fixture-store" "1.3.0"]),
    ("hackage at the bound", [hackage "fixture-store" "1.3.0"], only [VersionBelow "fixture-store" "1.3.0"]),
    ("hackage above the bound", [hackage "fixture-store" "1.10.0"], only [VersionBelow "fixture-store" "1.3.0"]),
    ("shorter version below the bound", [hackage "fixture-store" "1.3"], only [VersionBelow "fixture-store" "1.3.0"]),
    ("git at the named revision", [git "fixture-store" "aaa"], only [RevisionIs "fixture-store" "aaa"]),
    ("git at another revision", [git "fixture-store" "bbb"], only [RevisionIs "fixture-store" "aaa"]),
    ("hackage under a revision condition", [hackage "fixture-store" "1.0.0"], only [RevisionIs "fixture-store" "aaa"]),
    ("hackage under the hackage condition", [hackage "fixture-store" "1.0.0"], only [ResolvedFromHackage "fixture-store"]),
    ("hackage under the git condition", [hackage "fixture-store" "1.0.0"], only [ResolvedFromGit "fixture-store"]),
    ("git under the hackage condition", [git "fixture-store" "aaa"], only [ResolvedFromHackage "fixture-store"]),
    ("git under the git condition", [git "fixture-store" "aaa"], only [ResolvedFromGit "fixture-store"]),
    ("several conditions all holding", [hackage "fixture-store" "1.2.0", git "fixture-queue" "ccc"], only [ResolvedFromHackage "fixture-store", VersionBelow "fixture-store" "1.3.0", RevisionIs "fixture-queue" "ccc"]),
    ("several conditions, one failing", [hackage "fixture-store" "1.4.0", git "fixture-queue" "ccc"], only [ResolvedFromHackage "fixture-store", VersionBelow "fixture-store" "1.3.0", RevisionIs "fixture-queue" "ccc"]),
    ("cohort missing the package", [hackage "fixture-queue" "1.0.0"], only [VersionBelow "fixture-store" "1.3.0"]),
    ("resolved version does not parse", [hackage "fixture-store" "1.x"], only [VersionBelow "fixture-store" "1.3.0"]),
    ("bound does not parse", [hackage "fixture-store" "1.2.0"], only [VersionBelow "fixture-store" "next"]),
    ("tagged versions", [hackage "fixture-store" "1.2.0-rc1"], only [VersionBelow "fixture-store" "1.3.0"]),
    ("same name twice, one satisfying", [hackage "fixture-store" "2.0.0", git "fixture-store" "aaa"], only [ResolvedFromGit "fixture-store", VersionBelow "fixture-store" "1.0.0"]),
    ("boot package under the hackage condition", [ResolvedPackage "fixture-store" "1.0.0" FromBoot], only [ResolvedFromHackage "fixture-store"]),
    ("local package under a bound", [ResolvedPackage "fixture-store" "1.0.0" (FromLocalPath "../store")], only [VersionBelow "fixture-store" "1.3.0"])
  ]

expectations :: [Bool]
expectations = [True, True, False, False, True, True, False, False, True, False, False, True, True, False, False, False, False, True, False, False, True]

genPackage :: Gen ResolvedPackage
genPackage = ResolvedPackage <$> genName <*> genVersion <*> genSource
  where
    genSource = Gen.choice [FromHackage <$> Gen.maybe (pure "rev"), (\revision -> FromGit "https://example.invalid/repo" revision Nothing) <$> genRevision, pure FromBoot, pure (FromLocalPath "local")]

genScope :: Gen CohortScope
genScope = Gen.choice [pure AllCohorts, OnlyWhen <$> Gen.nonEmpty (Range.linear 1 4) genCondition]
  where
    genCondition = Gen.choice [ResolvedFromHackage <$> genName, ResolvedFromGit <$> genName, VersionBelow <$> genName <*> genVersion, RevisionIs <$> genName <*> genRevision]

genName :: Gen Text
genName = Gen.element ["fixture-store", "fixture-queue", "fixture-client"]

genVersion :: Gen Text
genVersion = Gen.choice [Text.intercalate "." <$> Gen.list (Range.linear 1 4) (Text.pack . show <$> Gen.int (Range.linear 0 12)), Gen.element ["", "1.x", "next", "1.0-rc1", "1..2", "01.2"]]

genRevision :: Gen Text
genRevision = Gen.element ["aaa", "bbb", "ccc"]

only :: [PackageCondition] -> CohortScope
only conditions = OnlyWhen (NonEmpty.fromList conditions)

defect :: CohortScope -> KnownDefect
defect appliesTo = KnownDefect {reference = "mori://fixture/owner-a/okf/bug-reports/concepts/BUG-1", summary = "Fixture", expectedFailures = ["failure"], appliesTo}

hackage :: Text -> Text -> ResolvedPackage
hackage name version = ResolvedPackage name version (FromHackage Nothing)

git :: Text -> Text -> ResolvedPackage
git name revision = ResolvedPackage name "1.0.0" (FromGit "https://example.invalid/repo" revision Nothing)

cohortOf :: [ResolvedPackage] -> CohortIdentity
cohortOf packages =
  CohortIdentity
    (CohortName "released")
    "ghc-9.12.4"
    "3.16.1.0"
    "linux"
    "x86_64"
    Nothing
    (PlanHash "sha256:fixture")
    "fixture"
    [ResolvedComponent (ComponentId "fixture") "mori://example/fixture" packages]
    Nothing

-- Oracle: a verbatim copy of 'cohortScopeApplies' and its private
-- 'conditionApplies' from before 'evaluateScope' was introduced. Do not edit.

oracleCohortScopeApplies :: CohortIdentity -> CohortScope -> Bool
oracleCohortScopeApplies _ AllCohorts = True
oracleCohortScopeApplies cohort (OnlyWhen conditions) = all (conditionApplies packages) conditions
  where
    packages = concatMap (.resolvedComponentPackages) cohort.identityComponents

conditionApplies :: [ResolvedPackage] -> PackageCondition -> Bool
conditionApplies packages condition = any matches packages
  where
    matches package = case condition of
      ResolvedFromHackage name -> package.resolvedPackageName == name && case package.resolvedPackageSource of FromHackage _ -> True; _ -> False
      ResolvedFromGit name -> package.resolvedPackageName == name && case package.resolvedPackageSource of FromGit _ _ _ -> True; _ -> False
      VersionBelow name boundary -> package.resolvedPackageName == name && maybe False (uncurry (<)) ((,) <$> parse package.resolvedPackageVersion <*> parse boundary)
      RevisionIs name revision -> package.resolvedPackageName == name && case package.resolvedPackageSource of FromGit _ actual _ -> actual == revision; _ -> False
    parse value = case [version | (version, "") <- readP_to_S parseVersion (Text.unpack value)] of [] -> Nothing; versions -> Just (last versions)
