module Kenshou.Evidence.Config
  ( EvidenceDefaults (..),
    evidenceConfig,
    bundleRootKey,
    projectKey,
    dataBaseUriKey,
    defaultSubjectKey,
    bundleUriKey,
    resolveEvidenceDefaults,
  )
where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Kenshou.Core.Cli.Config (ConfigInputs (..), loadConfigSources)
import Settei
import Settei.Env

data EvidenceDefaults = EvidenceDefaults
  { bundleRoot :: !Text,
    project :: !(Maybe Text),
    dataBaseUri :: !(Maybe Text),
    -- | The evidence subject for runs whose layer's bundle declares none.
    defaultSubject :: !(Maybe Text),
    -- | The canonical Mori URI of the evidence bundle that history documents cite.
    bundleUri :: !(Maybe Text)
  }
  deriving stock (Eq, Show)

evidenceConfig :: Config EvidenceDefaults
evidenceConfig =
  EvidenceDefaults
    <$> required (publicSetting bundleRootKey "OKF verification bundle" textDecoder)
    <*> optional (publicSetting projectKey "GCP project for durable evidence" textDecoder)
    <*> optional (publicSetting dataBaseUriKey "GCS prefix for run data" textDecoder)
    <*> optional (publicSetting defaultSubjectKey "Mori URI recorded as the subject of runs whose layer declares none" textDecoder)
    <*> optional (publicSetting bundleUriKey "Mori URI of the evidence bundle cited by history documents" textDecoder)

resolveEvidenceDefaults :: EnvSnapshot -> ConfigInputs -> IO (Either Text (ResolveResult EvidenceDefaults))
resolveEvidenceDefaults snapshot inputs = do
  loaded <- loadConfigSources inputs {namedSources = []}
  pure $ do
    files <- loaded
    pure (resolve defaultResolveOptions {unknownKeyPolicy = RejectUnknownKeys} ([builtIns] <> files <> [environmentSource environmentBindings snapshot] <> inputs.namedSources) evidenceConfig)

environmentBindings :: Bindings
environmentBindings =
  either
    (error . Text.unpack . renderEnvErrorsText)
    id
    ( bindings
        [ binding (EnvName "KENSHOU_EVIDENCE_BUNDLE") bundleRootKey,
          binding (EnvName "KENSHOU_GCP_PROJECT") projectKey,
          binding (EnvName "KENSHOU_EVIDENCE_DATA_BASE_URI") dataBaseUriKey,
          binding (EnvName "KENSHOU_EVIDENCE_SUBJECT") defaultSubjectKey,
          binding (EnvName "KENSHOU_EVIDENCE_BUNDLE_URI") bundleUriKey
        ]
    )

builtIns :: Source
builtIns = source "kenshou built-ins" BuiltInSource (RawObject (Map.singleton "evidence" (RawObject (Map.singleton "bundle-root" (RawText "docs/verification")))))

bundleRootKey, projectKey, dataBaseUriKey, defaultSubjectKey, bundleUriKey :: Key
bundleRootKey = validKey "evidence.bundle-root"
projectKey = validKey "gcp.project"
dataBaseUriKey = validKey "evidence.data-base-uri"
defaultSubjectKey = validKey "evidence.default-subject"
bundleUriKey = validKey "evidence.bundle-uri"

validKey :: Text -> Key
validKey value = either (error . show) id (parseKey value)
