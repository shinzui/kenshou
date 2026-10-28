-- | A named resource the synthetic suite provisions itself: a loopback TCP echo
-- server. The provider starts it around a local run, workers find its address in the
-- @resources@ block of their initialization document, and
-- @synthetic/echo/correctness/resource-roundtrip@ checks every message comes back.
module Kenshou.Suite.Synthetic.Echo
  ( echoResource,
    echoProvider,
    echoClientRole,
    resourceRoundtrip,
  )
where

import Control.Concurrent (forkIO, killThread)
import Control.Exception (bracket, finally)
import Control.Monad (forM, forever, void)
import Data.Aeson (Value (..), object, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as ByteString
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Scientific (toBoundedInteger)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Kenshou.Core.Context (RunContext (..))
import Kenshou.Core.Dimension (noDimensions)
import Kenshou.Core.Env (requiresResource)
import Kenshou.Core.Id (parseScenarioId)
import Kenshou.Core.Knob
import Kenshou.Core.Phase (zeroPhases)
import Kenshou.Core.Resource (ProvisionedResource (..), ResourceName, ResourceProvider (..), mkResourceName)
import Kenshou.Core.Role
import Kenshou.Core.Role.Spawn (WorkerHandle (..), withWorker)
import Kenshou.Core.Scenario
import Kenshou.Suite.Synthetic.Knobs (intKnob, knob)
import Kenshou.Suite.Synthetic.Roles (roleName)
import Network.Socket
import Network.Socket.ByteString (recv, sendAll)

echoResource :: ResourceName
echoResource = either (error . Text.unpack) id (mkResourceName "echo")

-- | Starts the echo server for one local run. It has no cell binding, so a scenario
-- that requires it cannot be placed on a cell.
echoProvider :: ResourceProvider
echoProvider =
  ResourceProvider
    { name = echoResource,
      summary = "Loopback TCP echo server",
      normalize = Right . fromMaybe (object []),
      withLocal = \_ _ action -> withEchoServer \port ->
        action (ProvisionedResource (object ["host" .= ("127.0.0.1" :: Text), "port" .= port]) (object ["kind" .= ("loopback-echo" :: Text)])),
      cell = Nothing
    }

withEchoServer :: (Int -> IO a) -> IO a
withEchoServer action = do
  address : _ <- getAddrInfo (Just defaultHints {addrFlags = [AI_PASSIVE], addrSocketType = Stream}) (Just "127.0.0.1") (Just "0")
  bracket (openSocket address) close \listener -> do
    setSocketOption listener ReuseAddr 1
    bind listener (addrAddress address)
    listen listener 16
    port <- fromIntegral <$> socketPort listener
    acceptor <- forkIO (forever (accept listener >>= \(connection, _) -> void (forkIO (echo connection `finally` close connection))))
    action port `finally` killThread acceptor
  where
    echo connection = do
      bytes <- recv connection 4096
      if ByteString.null bytes then pure () else sendAll connection bytes >> echo connection

-- | Sends @messages@ lines to the echo server in its initialization document and
-- reports how many came back unchanged.
echoClientRole :: WorkerRole
echoClientRole = WorkerRole (roleName "synthetic/echo-client") "Round-trips messages through the echo resource." \context -> do
  context.send WrkReady
  context.receive >>= \case
    Just (CtlCustom "echo" (Object request)) -> do
      let messages = fromMaybe 0 (KeyMap.lookup "messages" request >>= number)
      (host, port) <- maybe (fail "the worker has no echo resource") pure (Map.lookup echoResource context.init.resources >>= endpoint)
      address : _ <- getAddrInfo (Just defaultHints {addrSocketType = Stream}) (Just (Text.unpack host)) (Just (show port))
      matched <- bracket (openSocket address) close \connection -> do
        connect connection (addrAddress address)
        results <- forM [1 .. messages] \index -> do
          let line = Text.encodeUtf8 ("message-" <> Text.pack (show index) <> "\n")
          sendAll connection line
          received <- receiveExactly connection (ByteString.length line)
          pure (received == line)
        pure (length (filter id results))
      context.send (WrkCustom "echoed" (object ["sent" .= messages, "matched" .= matched]))
    _ -> pure ()
  where
    number (Number value) = toBoundedInteger value :: Maybe Int
    number _ = Nothing
    endpoint (Object fields) = case (KeyMap.lookup (Key.fromText "host") fields, KeyMap.lookup (Key.fromText "port") fields >>= number) of
      (Just (String host), Just port) -> Just (host, port)
      _ -> Nothing
    endpoint _ = Nothing
    receiveExactly connection size = go ByteString.empty
      where
        go acquired
          | ByteString.length acquired >= size = pure acquired
          | otherwise = do
              chunk <- recv connection (size - ByteString.length acquired)
              if ByteString.null chunk then pure acquired else go (acquired <> chunk)

resourceRoundtrip :: Scenario
resourceRoundtrip =
  Scenario
    { id = either (error . show) id (parseScenarioId "synthetic/echo/correctness/resource-roundtrip"),
      revision = 1,
      summary = "Provisions the suite's echo resource and round-trips messages through it from a worker.",
      tier = TierSmoke,
      placement = PlaceLocal,
      knobs = [intKnob "echo.messages" "Messages to round-trip" 100 1 100000],
      dimensions = noDimensions,
      phases = zeroPhases,
      requires = requiresResource echoResource,
      knownDefect = Nothing,
      run = \context -> withWorker context (roleName "synthetic/echo-client") "echo-1" (object []) \worker -> do
        let messages = knobInt context.knobs (knob "echo.messages")
        ready <- worker.receive 10000
        case ready of
          Just WrkReady -> do
            worker.send (CtlCustom "echo" (object ["messages" .= messages]))
            reply <- worker.receive 30000
            pure case reply of
              Just (WrkCustom "echoed" (Object result))
                | KeyMap.lookup "matched" result == Just (Number (fromIntegral messages)) -> passed
                | otherwise -> failedWith ["echo-mismatch"] "some echoes differed from what was sent"
              _ -> failedWith ["echo-timeout"] "the echo client did not report"
          _ -> pure (failedWith ["echo-not-ready"] "the echo client did not become ready")
    }
