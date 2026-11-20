module Kenshou.Cli.PlanOptions
  ( PolicyOptions (..),
    policyOptionsParser,
    SelectionOptions (..),
    selectionOptionsParser,
    parseSelections,
    validateKnobPins,
    makeSeed,
    makePolicy,
  )
where

import Control.Monad (unless)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Kenshou.Core.Id qualified as Id
import Kenshou.Core.Knob (KnobSpec (..), renderKnobName)
import Kenshou.Core.RunSpec (SpecPlacement (..))
import Kenshou.Core.Scenario (Tier (..))
import Kenshou.Plan.Catalog (ScenarioInfo (..))
import Kenshou.Plan.Change (Selected (..))
import Kenshou.Plan.Policy
import Kenshou.Plan.Selector (Selector, parseSelector)
import Kenshou.Plan.Suite (Suite, suitePolicy)
import Options.Applicative hiding (value)
import System.Random (randomIO)

data SelectionOptions = SelectionOptions {includes :: [Text], excludes :: [Text]}

selectionOptionsParser :: Parser SelectionOptions
selectionOptionsParser =
  SelectionOptions
    <$> many (Text.pack <$> strOption (long "select" <> metavar "SELECTOR" <> help "Keep matching scenarios"))
    <*> many (Text.pack <$> strOption (long "exclude" <> metavar "SELECTOR" <> help "Remove matching scenarios"))

parseSelections :: SelectionOptions -> Either Text ([Selector], [Selector])
parseSelections options =
  (,) <$> traverse parseSelector options.includes <*> traverse parseSelector options.excludes

data PolicyOptions = PolicyOptions
  { maxTierText :: Maybe Text,
    kindTexts :: [Text],
    placementText :: Maybe Text,
    dimensionPolicyText :: Maybe Text,
    knobPolicyText :: Maybe Text,
    trialCount :: Maybe Int,
    budget :: Maybe Int,
    seedValue :: Maybe Integer,
    knobPins :: [Text],
    dimensionPins :: [Text]
  }

policyOptionsParser :: Parser PolicyOptions
policyOptionsParser =
  PolicyOptions
    <$> optional (Text.pack <$> strOption (long "max-tier" <> metavar "TIER" <> help "Maximum cost tier"))
    <*> many (Text.pack <$> strOption (long "kind" <> metavar "KIND" <> help "Include a scenario kind; repeatable"))
    <*> optional (Text.pack <$> strOption (long "placement" <> metavar "local|cell" <> help "Target placement"))
    <*> optional (Text.pack <$> strOption (long "dimension-policy" <> metavar "POLICY" <> help "default-only, telemetry-corners, pairwise, or full"))
    <*> optional (Text.pack <$> strOption (long "knob-policy" <> metavar "POLICY" <> help "defaults or declared-variants"))
    <*> optional (option auto (long "trials" <> metavar "N" <> help "Benchmark trials (minimum 3)"))
    <*> optional (option auto (long "budget-minutes" <> metavar "N" <> help "Maximum estimated run time"))
    <*> optional (option auto (long "seed" <> metavar "N" <> help "Deterministic plan seed"))
    <*> many (Text.pack <$> strOption (long "set" <> metavar "NAME=VALUE" <> help "Pin a knob value"))
    <*> many (Text.pack <$> strOption (long "dim" <> metavar "NAME=VALUE" <> help "Pin a dimension value"))

validateKnobPins :: PolicyOptions -> [Selected] -> Either Text ()
validateKnobPins options selected =
  unless (null unmatchedPins) (Left ("no selected scenario declares knob: " <> Text.intercalate ", " unmatchedPins))
  where
    unmatchedPins =
      [ name
      | raw <- options.knobPins,
        let (name, _) = splitAssignment raw,
        all (\selection -> not (declares name selection.scenario)) selected
      ]
    declares name scenario = any ((== name) . renderKnobName . (.name)) scenario.knobs

makeSeed :: Maybe Integer -> IO (Either Text Id.Seed)
makeSeed (Just value)
  | value < 0 = pure (Left "seed must be non-negative")
  | otherwise = pure (Id.mkSeed (fromInteger value))
makeSeed Nothing = do
  value <- randomIO
  pure (Id.mkSeed (value `mod` 9007199254740992))

makePolicy :: PolicyOptions -> Maybe Suite -> Id.Seed -> Either Text PlanPolicy
makePolicy options suite seed = do
  base <- maybe (Right (defaultPlanPolicy seed)) (suitePolicy seed) suite
  maxTier <- maybe (Right base.maxTier) parseTierValue options.maxTierText
  let kindInputs = concatMap (filter (not . Text.null) . fmap Text.strip . Text.splitOn ",") options.kindTexts
  kinds <- if null kindInputs then Right base.kinds else Set.fromList <$> traverse Id.parseKind kindInputs
  placement <- maybe (Right base.placement) parsePlacementValue options.placementText
  dimensionPolicy <- maybe (Right base.dimensionPolicy) (maybe (Left "unknown dimension policy") Right . parseDimensionPolicy) options.dimensionPolicyText
  knobPolicy <- maybe (Right base.knobPolicy) (maybe (Left "unknown knob policy") Right . parseKnobPolicy) options.knobPolicyText
  let trials = maybe base.trials (\value -> value) options.trialCount
  if trials < 3 then Left "--trials must be at least 3" else pure ()
  case options.budget of Just value | value < 0 -> Left "--budget-minutes must be non-negative"; _ -> pure ()
  pinnedKnobs <- traverse parseAssignmentText options.knobPins
  pinnedDimensions <- traverse parseAssignmentText options.dimensionPins
  pure
    base
      { maxTier,
        kinds,
        placement,
        dimensionPolicy,
        knobPolicy,
        trials,
        budgetMinutes = options.budget <|> base.budgetMinutes,
        pinnedKnobs,
        pinnedDimensions
      }

parseTierValue :: Text -> Either Text Tier
parseTierValue "smoke" = Right TierSmoke
parseTierValue "standard" = Right TierStandard
parseTierValue "extended" = Right TierExtended
parseTierValue "soak" = Right TierSoak
parseTierValue value = Left ("unknown tier " <> value)

parsePlacementValue :: Text -> Either Text SpecPlacement
parsePlacementValue "local" = Right RunLocal
parsePlacementValue "cell" = Right RunOnCell
parsePlacementValue value = Left ("unknown placement " <> value)

parseAssignmentText :: Text -> Either Text (Text, Text)
parseAssignmentText raw = case splitAssignment raw of
  (name, value) | Text.null name || Text.null value -> Left "expected NAME=VALUE"
  pair -> Right pair

splitAssignment :: Text -> (Text, Text)
splitAssignment raw = let (name, rest) = Text.breakOn "=" raw in (name, Text.drop 1 rest)
