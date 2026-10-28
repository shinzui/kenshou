-- | Knob helpers shared by the synthetic suite's scenarios.
module Kenshou.Suite.Synthetic.Knobs
  ( knob,
    intKnob,
  )
where

import Data.Int (Int64)
import Data.Text (Text)
import Data.Text qualified as Text
import Kenshou.Core.Knob

knob :: Text -> KnobName
knob = either (error . Text.unpack) id . mkKnobName

intKnob :: Text -> Text -> Int64 -> Int64 -> Int64 -> KnobSpec
intKnob name summary def low high = KnobSpec (knob name) summary KnobInt (VInt def) (IntRange low high) []
