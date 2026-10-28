module Kenshou.Cli.Main (mainWith, runWithArgsWith) where

import Data.Text.IO qualified as Text.IO
import Kenshou.Cli.Registry (CliAssembly (..))
import Kenshou.Cli.Version (appVersionWithGit)
import Kenshou.Core.Cli (runCli)
import Kenshou.Diagnose.Profile.EventlogGuard (withEventlogGuard)
import Kenshou.Diagnose.Profile.GhcDebug (withGhcDebugIfRequested)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)

mainWith :: CliAssembly -> IO ()
mainWith assembly = withGhcDebugIfRequested (withEventlogGuard (getArgs >>= runWithArgsWith assembly >>= exitWith))

runWithArgsWith :: CliAssembly -> [String] -> IO ExitCode
runWithArgsWith _ ["--version"] = Text.IO.putStrLn appVersionWithGit >> pure ExitSuccess
runWithArgsWith assembly arguments = runCli assembly.bundles assembly.commands assembly.topics arguments
