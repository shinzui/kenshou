-- | The first consumer's performance contracts, read from
-- ../fixtures/consumer-baseline/perf-contracts.json. The captured preparation in
-- that directory pins the consumer's reviewed benchmark revisions, so validating it
-- needs the same contracts the consumer supplies.
module Kenshou.ConsumerBaseline (consumerContracts) where

import Data.Aeson (eitherDecodeFileStrict', withObject, (.:))
import Data.Aeson.Types (Parser, Value, parseEither)
import Data.Text (Text)
import Kenshou.Core.Knob (mkKnobName)
import Kenshou.Perf.Contracts (PerfContracts (..), noPerfContracts)

consumerContracts :: IO PerfContracts
consumerContracts = do
  document <- eitherDecodeFileStrict' "../fixtures/consumer-baseline/perf-contracts.json" >>= either fail pure
  (reviewed, knob) <- either fail pure (parseEither contractsParser (document :: Value))
  countKnob <- either (fail . show) pure (mkKnobName knob)
  pure noPerfContracts {reviewedPhaseContracts = reviewed, steadyCountKnob = Just countKnob}
  where
    contractsParser :: Value -> Parser ([(Text, Int)], Text)
    contractsParser = withObject "PerfContracts" \value -> do
      entries <- value .: "reviewedPhaseContracts"
      reviewed <- traverse (withObject "ReviewedPhaseContract" \entry -> (,) <$> entry .: "scenario" <*> entry .: "revision") entries
      knob <- value .: "steadyCountKnob"
      pure (reviewed, knob)
