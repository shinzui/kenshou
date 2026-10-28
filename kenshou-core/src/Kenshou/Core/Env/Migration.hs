module Kenshou.Core.Env.Migration
  ( MigrationSetupError (..),
    composePlan,
    orderMigrationSets,
    migrateDatabase,
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Database.PostgreSQL.Migrate (MigrationPlan, defaultRunOptions, migrationPlan, runMigrationPlan)
import Hasql.Connection.Settings qualified as Settings
import Kenshou.Core.Env (MigrationSet (..), MigrationSetName, renderMigrationSetName)

newtype MigrationSetupError = MigrationSetupError Text deriving stock (Eq, Show)

-- | Compose the requested migration sets into one ordered pg-migrate plan, applied
-- as one ledger, in the order 'orderMigrationSets' gives.
composePlan :: Map MigrationSetName MigrationSet -> [MigrationSetName] -> Either MigrationSetupError MigrationPlan
composePlan sets requested = do
  ordered <- orderMigrationSets sets requested
  components <- traverse component ordered
  case components of
    [] -> Left (MigrationSetupError "cannot compose an empty migration plan")
    first : rest -> mapError (migrationPlan (first :| rest))
  where
    component set = either (\problem -> Left (MigrationSetupError (renderMigrationSetName set.name <> ": " <> problem))) Right set.component
    mapError :: (Show problem) => Either problem value -> Either MigrationSetupError value
    mapError = either (Left . MigrationSetupError . Text.pack . show) Right

-- | The sets to apply, in application order. Sets keep the order the scenario
-- declared them; each set's 'requires' are inserted, transitively, before the set
-- that needs them, and a set appears once, at its first position.
orderMigrationSets :: Map MigrationSetName MigrationSet -> [MigrationSetName] -> Either MigrationSetupError [MigrationSet]
orderMigrationSets sets requested = fmap (fmap snd) (foldlM (visit []) [] requested)
  where
    visit path placed wanted
      | wanted `elem` fmap fst placed = Right placed
      | wanted `elem` path = Left (MigrationSetupError ("migration sets require one another in a cycle: " <> render (reverse (wanted : path))))
      | otherwise = case Map.lookup wanted sets of
          Nothing -> Left (MigrationSetupError ("no registered bundle defines migration set " <> renderMigrationSetName wanted))
          Just set -> do
            withRequired <- foldlM (visit (wanted : path)) placed set.requires
            Right (withRequired <> [(wanted, set)])
    render = Text.intercalate " -> " . fmap renderMigrationSetName
    foldlM step initial = foldl (\accumulated item -> accumulated >>= (`step` item)) (Right initial)

migrateDatabase :: Text -> MigrationPlan -> IO (Either MigrationSetupError ())
migrateDatabase connectionString plan = do
  result <- runMigrationPlan defaultRunOptions (Settings.connectionString connectionString) plan
  pure (either (Left . MigrationSetupError . Text.pack . show) (const (Right ())) result)
