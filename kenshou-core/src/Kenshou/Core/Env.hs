module Kenshou.Core.Env
  ( MigrationSetName (..),
    mkMigrationSetName,
    renderMigrationSetName,
    MigrationSet (..),
    PostgresRequirement (..),
    EnvRequirements (..),
    noEnvironment,
    requiresResource,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Database.PostgreSQL.Migrate (MigrationComponent, componentName)
import Kenshou.Core.Resource.Types (ResourceName)

-- | The name of a migration set, which is also its pg-migrate component name and the
-- text a scenario's comparison key records. 'Kenshou.Core.Bundle.mkRegistry' rejects
-- names that 'mkMigrationSetName' would reject.
newtype MigrationSetName = MigrationSetName Text
  deriving stock (Eq, Ord, Show)

mkMigrationSetName :: Text -> Either Text MigrationSetName
mkMigrationSetName value = either (\problem -> Left ("invalid migration set name \"" <> value <> "\": " <> Text.pack (show problem))) (const (Right (MigrationSetName value))) (componentName value)

renderMigrationSetName :: MigrationSetName -> Text
renderMigrationSetName (MigrationSetName value) = value

-- | A named group of database migrations a registered bundle contributes. Sets are
-- resolved by name across the whole registry, so a scenario may require a set that
-- another bundle defines. 'requires' names sets that must be applied first. A
-- 'Left' component names a set this build cannot provide; it fails only when a
-- scenario requires it.
data MigrationSet = MigrationSet
  { name :: MigrationSetName,
    requires :: [MigrationSetName],
    component :: Either Text MigrationComponent
  }

data PostgresRequirement = PostgresRequirement
  { schemas :: [MigrationSetName],
    settings :: [(Text, Text)],
    needsServerControl :: Bool
  }
  deriving stock (Eq, Show)

data EnvRequirements = EnvRequirements
  { postgres :: Maybe PostgresRequirement,
    extraPostgres :: [(Text, PostgresRequirement)],
    -- | Named resources the scenario needs, provisioned by registered providers.
    resources :: [ResourceName]
  }
  deriving stock (Eq, Show)

noEnvironment :: EnvRequirements
noEnvironment = EnvRequirements Nothing [] []

-- | An environment that needs one named resource and nothing else.
requiresResource :: ResourceName -> EnvRequirements
requiresResource name = noEnvironment {resources = [name]}
