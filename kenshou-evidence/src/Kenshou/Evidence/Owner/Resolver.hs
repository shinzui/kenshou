-- | Resolvers turn a canonical owner-record reference into the record's bytes and
-- where they came from. A resolver never writes, and the provenance it records
-- holds only relative locations, so documents built from it do not depend on the
-- machine that read the bytes.
module Kenshou.Evidence.Owner.Resolver
  ( Provenance (..),
    ResolveResult (..),
    OwnerResolver (..),
    ConceptReference (..),
    parseConceptReference,
    mappedResolver,
    moriResolver,
    chainResolvers,
    withGitProvenance,
    memoryResolver,
  )
where

import Control.Exception (IOException, try)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Kenshou.Core.Canonical (sha256Hex)
import Kenshou.Evidence.Owner.Record (RecordKind, conceptHandle)
import System.Directory (doesDirectoryExist, doesFileExist, doesPathExist, listDirectory, makeAbsolute)
import System.Exit (ExitCode (..))
import System.FilePath (isRelative, makeRelative, takeDirectory, takeExtension, takeFileName, (</>))
import System.Process (readProcessWithExitCode)

-- | Where a record's bytes came from. 'location' is relative (to a mapped bundle
-- directory, or to the checkout that holds the file); 'revision' and 'dirty' are
-- filled only by 'withGitProvenance'.
data Provenance = Provenance
  { resolver :: Text,
    location :: Maybe Text,
    sha256 :: Text,
    revision :: Maybe Text,
    dirty :: Maybe Bool
  }
  deriving stock (Eq, Show)

-- | A resolver's answer. 'ResolvedBytes' carries the local file it read, for
-- decorators such as 'withGitProvenance'; that path is never written to a document.
data ResolveResult
  = ResolvedBytes ByteString Provenance (Maybe FilePath)
  | NoMapping
  | NotFound Text
  | Ambiguous [Text]
  | ResolverFailed Text
  deriving stock (Eq, Show)

data OwnerResolver = OwnerResolver {name :: Text, resolve :: Text -> IO ResolveResult}

-- | A reference of the form @mori://<namespace>/<project>/okf/<bundle>/concepts/<HANDLE>@,
-- split into its bundle URI (everything before @/concepts/@) and its handle.
data ConceptReference = ConceptReference {bundle :: Text, handle :: Text}
  deriving stock (Eq, Ord, Show)

parseConceptReference :: Text -> Maybe ConceptReference
parseConceptReference reference = do
  rest <- Text.stripPrefix "mori://" reference
  let segments = Text.splitOn "/" rest
  case segments of
    namespace : project : "okf" : more
      | not (Text.null namespace),
        not (Text.null project),
        handle : "concepts" : bundleSegments@(_ : _) <- reverse more,
        all (not . Text.null) (handle : bundleSegments),
        Text.all (/= '#') handle,
        Text.all (/= '?') handle ->
          Just ConceptReference {bundle = Text.intercalate "/" (["mori:/", namespace, project, "okf"] <> reverse bundleSegments), handle}
    _ -> Nothing

-- | Resolve references under mapped bundle URIs from local bundle directories. A
-- record is selected by the handle in its frontmatter ('conceptHandle'), never by
-- its file name; @index.md@ and @log.md@ are not records. Locations are relative to
-- the mapped directory.
mappedResolver :: [RecordKind] -> [(Text, FilePath)] -> OwnerResolver
mappedResolver kinds mappings = OwnerResolver "mapped" \reference -> case parseConceptReference reference of
  Nothing -> pure NoMapping
  Just concept -> case lookup concept.bundle normalised of
    Nothing -> pure NoMapping
    Just directory -> do
      present <- doesDirectoryExist directory
      if not present
        then pure (ResolverFailed ("mapped bundle directory does not exist: " <> Text.pack directory))
        else do
          files <- markdownFiles directory
          candidates <- traverse (\relative -> (relative,) <$> ByteString.readFile (directory </> relative)) files
          case [(relative, bytes) | (relative, bytes) <- candidates, conceptHandle kinds bytes == Just concept.handle] of
            [] -> pure (NotFound ("no record in the mapped bundle carries the handle " <> concept.handle))
            [(relative, bytes)] -> do
              absolute <- makeAbsolute (directory </> relative)
              pure (ResolvedBytes bytes (Provenance "mapped" (Just (Text.pack relative)) (sha256Hex bytes) Nothing Nothing) (Just absolute))
            several -> pure (Ambiguous [Text.pack relative | (relative, _) <- several])
  where
    normalised = [(Text.dropWhileEnd (== '/') prefix, directory) | (prefix, directory) <- mappings]

-- | Every @.md@ file under a directory, relative to it and sorted, excluding
-- @index.md@ and @log.md@.
markdownFiles :: FilePath -> IO [FilePath]
markdownFiles root = sort <$> go ""
  where
    go relative = do
      entries <- sort <$> listDirectory (root </> relative)
      fmap concat $ traverse (visit relative) entries
    visit relative entry = do
      let path = if null relative then entry else relative </> entry
      isDirectory <- doesDirectoryExist (root </> path)
      if isDirectory
        then go path
        else pure [path | takeExtension entry == ".md", entry `notElem` ["index.md", "log.md"]]

-- | Resolve any @mori://@ reference with @mori path@, which prints the canonical
-- URI and then the file's absolute path. The location is relative to the checkout
-- that holds the file, or its bare file name outside a checkout.
moriResolver :: OwnerResolver
moriResolver = OwnerResolver "mori" \reference ->
  if not ("mori://" `Text.isPrefixOf` reference)
    then pure NoMapping
    else do
      response <- try (readProcessWithExitCode "mori" ["path", Text.unpack reference] "") :: IO (Either IOException (ExitCode, String, String))
      case response of
        Left problem -> pure (ResolverFailed ("mori could not be run: " <> Text.pack (show problem)))
        Right (ExitFailure _, _, errors) -> pure (NotFound (firstLine errors "mori path did not find the reference"))
        Right (ExitSuccess, output, _) -> case lines output of
          _ : path : _ | not (isRelative path) -> do
            exists <- doesFileExist path
            if not exists
              then pure (NotFound ("mori path printed a file that does not exist: " <> Text.pack path))
              else do
                bytes <- ByteString.readFile path
                root <- checkoutRoot (takeDirectory path)
                let location = maybe (takeFileName path) (`makeRelative` path) root
                pure (ResolvedBytes bytes (Provenance "mori" (Just (Text.pack location)) (sha256Hex bytes) Nothing Nothing) (Just path))
          _ -> pure (ResolverFailed "mori path did not print a canonical URI and an absolute path")
  where
    firstLine text fallback = case filter (not . null) (lines text) of
      line : _ -> Text.pack line
      [] -> fallback

-- | The nearest enclosing directory that holds a @.git@ entry. This looks for the
-- entry only; it does not read git state.
checkoutRoot :: FilePath -> IO (Maybe FilePath)
checkoutRoot start = go start
  where
    go directory = do
      found <- doesPathExist (directory </> ".git")
      if found
        then pure (Just directory)
        else
          let parent = takeDirectory directory
           in if parent == directory then pure Nothing else go parent

-- | Ask each resolver in order and return the first answer that is not 'NoMapping'.
chainResolvers :: [OwnerResolver] -> OwnerResolver
chainResolvers resolvers = OwnerResolver (Text.intercalate "," (fmap (.name) resolvers)) \reference -> go reference resolvers
  where
    go _ [] = pure NoMapping
    go reference (current : rest) =
      current.resolve reference >>= \case
        NoMapping -> go reference rest
        answer -> pure answer

-- | Add the checkout's @HEAD@ revision and whether the file differs from it to a
-- resolved answer. Outside a checkout, without commits, or without @git@, both stay
-- absent.
withGitProvenance :: OwnerResolver -> OwnerResolver
withGitProvenance inner = OwnerResolver inner.name \reference ->
  inner.resolve reference >>= \case
    ResolvedBytes bytes provenance (Just path) -> do
      (revision, dirty) <- gitState path
      pure (ResolvedBytes bytes (Provenance provenance.resolver provenance.location provenance.sha256 revision dirty) (Just path))
    answer -> pure answer

gitState :: FilePath -> IO (Maybe Text, Maybe Bool)
gitState path = do
  let directory = takeDirectory path
  topLevel <- git directory ["rev-parse", "--show-toplevel"]
  case topLevel of
    Nothing -> pure (Nothing, Nothing)
    Just _ -> do
      revision <- git directory ["rev-parse", "--verify", "HEAD"]
      case revision of
        Nothing -> pure (Nothing, Nothing)
        Just sha -> do
          status <- gitOutput directory ["status", "--porcelain", "--", takeFileName path]
          pure (Just sha, fmap (not . Text.null . Text.strip) status)
  where
    git directory arguments = fmap Text.strip <$> gitOutput directory arguments
    gitOutput directory arguments = do
      response <- try (readProcessWithExitCode "git" (["-C", directory] <> arguments) "") :: IO (Either IOException (ExitCode, String, String))
      pure $ case response of
        Right (ExitSuccess, output, _) -> Just (Text.pack output)
        _ -> Nothing

-- | A resolver answering from a fixed map of references to bytes, for tests and
-- consumers that hold records in memory. Unlisted references are 'NoMapping'.
memoryResolver :: Text -> [(Text, (Text, ByteString))] -> OwnerResolver
memoryResolver resolverName records = OwnerResolver resolverName \reference -> pure case Map.lookup reference table of
  Nothing -> NoMapping
  Just (location, bytes) -> ResolvedBytes bytes (Provenance resolverName (Just location) (sha256Hex bytes) Nothing Nothing) Nothing
  where
    table = Map.fromList records
