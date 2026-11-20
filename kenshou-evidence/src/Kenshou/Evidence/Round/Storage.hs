module Kenshou.Evidence.Round.Storage
  ( RoundError (..),
    RoundIO,
    failRound,
    usageError,
    runRoundIO,
    readDocument,
    requireUnused,
    requireName,
    createDirectoryOnce,
    writeFileOnce,
    readTree,
  )
where

import Control.Exception (IOException, displayException, try)
import Control.Monad (forM, unless, when)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Except (ExceptT (..), except, runExceptT, throwE)
import Data.Bifunctor (first)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Char (isAlphaNum, isAscii)
import Data.List (sort)
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory (createDirectoryIfMissing, doesDirectoryExist, doesFileExist, doesPathExist, listDirectory, pathIsSymbolicLink, renameDirectory)
import System.FilePath (dropTrailingPathSeparator, takeDirectory, takeFileName, (</>))
import System.IO (hFlush)
import System.IO.Error (isAlreadyExistsError, isDoesNotExistError)
import System.IO.Temp (withTempDirectory, withTempFile)
import System.Posix.Files (createLink)

data RoundError = RoundUsage Text | RoundInput Text
  deriving stock (Eq, Show)

type RoundIO = ExceptT RoundError IO

failRound :: Text -> RoundIO a
failRound = throwE . RoundInput

usageError :: Text -> RoundIO a
usageError = throwE . RoundUsage

runRoundIO :: RoundIO a -> IO (Either RoundError a)
runRoundIO action = do
  result <- try @IOException (runExceptT action)
  pure (either (Left . RoundInput . Text.pack . displayException) id result)

readDocument :: (ByteString -> Either Text a) -> FilePath -> RoundIO a
readDocument decode path = do
  bytes <- lift (BS.readFile path)
  except (first (RoundInput . ((Text.pack path <> ": ") <>)) (decode bytes))

requireName :: Text -> RoundIO ()
requireName name =
  unless
    (not (Text.null name) && Text.all valid name && name /= "." && name /= "..")
    (usageError "expected a name made of ASCII letters, digits, dots, hyphens or underscores")
  where
    valid c = isAscii c && (isAlphaNum c || c `elem` ("-._" :: String))

requireUnused :: FilePath -> RoundIO ()
requireUnused path = do
  exists <- lift (doesPathExist path)
  link <- lift (isLink path)
  when (exists || link) (usageError ("refusing to overwrite " <> Text.pack path))

isLink :: FilePath -> IO Bool
isLink path = do
  result <- try @IOException (pathIsSymbolicLink path)
  case result of
    Left err | isDoesNotExistError err -> pure False
    Left err -> ioError err
    Right link -> pure link

createDirectoryOnce :: FilePath -> (FilePath -> RoundIO a) -> RoundIO a
createDirectoryOnce requested populate = do
  requireUnused target
  lift (createDirectoryIfMissing True parent)
  ExceptT $ withTempDirectory parent ("." <> takeFileName target <> ".partial") \stage -> runExceptT do
    result <- populate stage
    requireUnused target
    published <- lift (try @IOException (renameDirectory stage target))
    case published of
      Right () -> pure result
      Left err -> requireUnused target >> lift (ioError err)
  where
    target = dropTrailingPathSeparator requested
    parent = takeDirectory target

writeFileOnce :: FilePath -> ByteString -> IO (Either RoundError ())
writeFileOnce target bytes = runRoundIO do
  requireUnused target
  lift (createDirectoryIfMissing True (takeDirectory target))
  result <- lift $ withTempFile (takeDirectory target) ".round-report.partial" \temp handle -> do
    BS.hPut handle bytes
    hFlush handle
    try @IOException (createLink temp target)
  case result of
    Right () -> pure ()
    Left err
      | isAlreadyExistsError err -> usageError ("refusing to overwrite " <> Text.pack target)
      | otherwise -> lift (ioError err)

-- | Round inputs are regular files under their captured names. Refuse symlinks
-- before following them, including in adopted captures.
readTree :: FilePath -> RoundIO [(FilePath, ByteString)]
readTree root = walk "" root
  where
    walk relative path = do
      link <- lift (isLink path)
      when link (failRound ("symbolic link in round inputs: " <> Text.pack path))
      directory <- lift (doesDirectoryExist path)
      if directory
        then do
          names <- lift (sort <$> listDirectory path)
          fmap concat $ forM names \name -> walk (relative </> name) (path </> name)
        else do
          regular <- lift (doesFileExist path)
          unless regular (failRound ("expected a round input file at " <> Text.pack path))
          bytes <- lift (BS.readFile path)
          pure [(relative, bytes)]
