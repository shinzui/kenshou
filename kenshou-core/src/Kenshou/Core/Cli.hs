module Kenshou.Core.Cli
  ( Program (..),
    defaultProgram,
    CliEnv (..),
    CliGroup (..),
    CliCommand (..),
    HelpTopic (..),
    InputSource (..),
    parseInputSource,
    readInputSource,
    runCli,
    exitWithOutcome,
  )
where

import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.List.NonEmpty qualified as NonEmpty
import Data.Text (Text)
import Data.Text qualified as Text
import Kenshou.Core.Bundle (LayerBundle, Registry, mkRegistry)
import Kenshou.Core.Outcome (Outcome, outcomeExitCode)
import Kenshou.Perf.Contracts (PerfContracts, noPerfContracts)
import Kenshou.Plan.Components (selftestGraphBytes)
import Options.Applicative
import System.Exit (ExitCode (..))
import System.IO (hPutStrLn, stderr, stdin, stdout)

-- | Everything an executable supplies: its name and help header, the bundles it
-- registers, its commands and help topics, the component graph that change-aware
-- planning reads when no graph file is given, and its performance contracts.
data Program = Program
  { name :: String,
    header :: String,
    bundles :: [LayerBundle],
    commands :: [CliCommand],
    topics :: [HelpTopic],
    componentGraph :: ByteString,
    perf :: PerfContracts
  }

-- | A program named @kenshou@ with no bundles or commands, the self-test component
-- graph, and no performance contracts. Executables extend it with record update.
defaultProgram :: Program
defaultProgram =
  Program
    { name = "kenshou",
      header = "kenshou - run verification scenarios",
      bundles = [],
      commands = [],
      topics = [],
      componentGraph = selftestGraphBytes,
      perf = noPerfContracts
    }

data CliEnv = CliEnv
  { registry :: Registry,
    programName :: Text,
    componentGraph :: ByteString,
    perf :: PerfContracts
  }

data CliGroup = Discovery | Execution | Analysis | Evidence | Maintenance | Internal deriving stock (Eq, Ord, Show, Enum, Bounded)

data CliCommand = CliCommand
  { name :: String,
    description :: String,
    group :: CliGroup,
    hidden :: Bool,
    parser :: Parser (CliEnv -> IO ExitCode)
  }

data HelpTopic = HelpTopic {name :: Text, description :: Text, content :: Text}

data InputSource = InputFile FilePath | InputStdin deriving stock (Eq, Show)

parseInputSource :: String -> InputSource
parseInputSource "-" = InputStdin
parseInputSource path = InputFile path

readInputSource :: InputSource -> IO ByteString
readInputSource InputStdin = ByteString.hGetContents stdin
readInputSource (InputFile path) = ByteString.readFile path

runCli :: Program -> [String] -> IO ExitCode
runCli program arguments = case mkRegistry program.bundles of
  Left problems -> do
    mapM_ (hPutStrLn stderr . show) (NonEmpty.toList problems)
    pure (ExitFailure 4)
  Right registry -> case execParserPure defaultPrefs (parserInfo program) arguments of
    Success action -> action (CliEnv registry (Text.pack program.name) program.componentGraph program.perf)
    Failure failure -> do
      let (message, code) = renderFailure failure program.name
      case code of
        ExitSuccess -> hPutStrLn stdout message >> pure ExitSuccess
        ExitFailure _ -> hPutStrLn stderr message >> pure (ExitFailure 2)
    CompletionInvoked completion -> execCompletion completion program.name >>= putStr >> pure ExitSuccess

parserInfo :: Program -> ParserInfo (CliEnv -> IO ExitCode)
parserInfo program = info (commandParser program.commands <**> helper) (fullDesc <> header program.header)

commandParser :: [CliCommand] -> Parser (CliEnv -> IO ExitCode)
commandParser commands = visibleParser <|> hiddenParser
  where
    visibleCommands = filter (not . (.hidden)) commands
    hiddenCommands = filter (.hidden) commands
    populatedGroups = filter (not . null . commandsIn) [Discovery .. Internal]
    commandsIn groupValue = filter ((== groupValue) . (.group)) visibleCommands
    visibleParser = foldr1 (<|>) (fmap groupParser populatedGroups)
    hiddenParser = subparser (foldMap hiddenCommand hiddenCommands)
    groupParser groupValue = subparser (groupModifier groupValue <> foldMap commandModifier (commandsIn groupValue))
    groupModifier Internal = mempty
    groupModifier groupValue = commandGroup (groupLabel groupValue)
    commandModifier commandValue = command commandValue.name (info (commandValue.parser <**> helper) (progDesc commandValue.description))
    hiddenCommand commandValue = command commandValue.name (info (commandValue.parser <**> helper) (progDesc commandValue.description)) <> internal

groupLabel :: CliGroup -> String
groupLabel Discovery = "Discovery"
groupLabel Execution = "Execution"
groupLabel Analysis = "Analysis"
groupLabel Evidence = "Evidence"
groupLabel Maintenance = "Maintenance"
groupLabel Internal = "Internal"

exitWithOutcome :: Outcome -> ExitCode
exitWithOutcome outcome = case outcomeExitCode outcome of
  0 -> ExitSuccess
  code -> ExitFailure code
