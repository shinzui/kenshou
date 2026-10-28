module Kenshou.Measure.MethodologySpec (spec) where

import Kenshou.Core.Bundle (LayerBundle (..), mkBundle, mkRegistry)
import Kenshou.Core.Id (mkLayerId, selftestLayer)
import Kenshou.Measure.Methodology (PoolMethodology (..), poolMethodologyFor)
import Test.Hspec

spec :: Spec
spec = describe "pool methodology" do
  it "reads the methodology a layer's bundle contributes" do
    let methodology = PoolMethodology 12 (10, 13)
        other = either (error . show) id (mkLayerId "acme")
    registry <- either (fail . show) pure (mkRegistry [(mkBundle selftestLayer [] []) {methodology = Just methodology}, mkBundle other [] []])
    poolMethodologyFor registry selftestLayer `shouldBe` Just methodology
    poolMethodologyFor registry other `shouldBe` Nothing
