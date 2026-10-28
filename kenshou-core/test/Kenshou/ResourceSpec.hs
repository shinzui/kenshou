module Kenshou.ResourceSpec (spec) where

import Data.Aeson (FromJSON, Value (..), eitherDecodeFileStrict', object, toJSON, (.=))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Either (isLeft)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Kenshou.Core.Canonical (canonicalEncode)
import Kenshou.Core.Compat (renderResourceInputs)
import Kenshou.Core.Resource.Types (ResourceName, mkResourceName, renderResourceName)
import Kenshou.Core.Role (WorkerInit (..))
import Kenshou.Core.RunSpec (RunSpec (..))
import Kenshou.Core.RunSpec qualified as RunSpec
import Test.Hspec

spec :: Spec
spec = describe "named resources" do
  it "validates resource names" do
    renderResourceName <$> mkResourceName "object-store" `shouldBe` Right "object-store"
    mapM_ (\bad -> isLeft (mkResourceName bad) `shouldBe` True) ["", "Object", "9lives", "has space", "x_y"]
  it "round-trips a run specification with a resource map to identical canonical JSON" do
    raw <- decodeFile "test/golden/resources/run-spec.resources.json" :: IO Value
    decoded <- decodeFile "test/golden/resources/run-spec.resources.json" :: IO RunSpec
    Map.keys decoded.environment.resources `shouldBe` [name "broker", name "object-store"]
    canonicalEncode (toJSON decoded) `shouldBe` canonicalEncode raw
  it "round-trips a worker initialization with a resource map to identical canonical JSON" do
    raw <- decodeFile "test/golden/resources/worker-init.resources.json" :: IO Value
    decoded <- decodeFile "test/golden/resources/worker-init.resources.json" :: IO WorkerInit
    Map.keys decoded.resources `shouldBe` [name "broker", name "object-store"]
    canonicalEncode (toJSON decoded) `shouldBe` canonicalEncode raw
  it "omits an empty resource map from the run specification but always writes it for workers" do
    decoded <- decodeFile "test/golden/resources/run-spec.resources.json" :: IO RunSpec
    let emptied = decoded {environment = decoded.environment {RunSpec.resources = Map.empty}}
    environmentKeys (toJSON emptied) `shouldSatisfy` notElem "resources"
    worker <- decodeFile "test/golden/resources/worker-init.resources.json" :: IO WorkerInit
    case toJSON worker {resources = Map.empty} of
      Object fields -> KeyMap.lookup "resources" fields `shouldBe` Just (object [])
      _ -> expectationFailure "worker-init is not an object"
  it "renders resources under one compatibility member, omitted when empty" do
    let value = object ["bucket" .= ("fixture" :: Text)]
    object (renderResourceInputs (Map.singleton (name "object-store") value)) `shouldBe` object ["resources" .= object ["object-store" .= value]]
    object (renderResourceInputs Map.empty) `shouldBe` object []
  where
    name text = either (error . show) id (mkResourceName text) :: ResourceName
    environmentKeys (Object fields) = case KeyMap.lookup "environment" fields of
      Just (Object environment) -> KeyMap.keys environment
      _ -> []
    environmentKeys _ = []

decodeFile :: (FromJSON a) => FilePath -> IO a
decodeFile path = eitherDecodeFileStrict' path >>= either fail pure
