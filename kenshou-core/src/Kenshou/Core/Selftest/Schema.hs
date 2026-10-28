-- | The kernel's own migration set: one schema and one table that the self-test
-- scenarios of every toolkit may use without depending on a suite's schema.
module Kenshou.Core.Selftest.Schema
  ( selftestSchema,
    selftestMigrationSet,
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Set qualified as Set
import Data.Text qualified as Text
import Database.PostgreSQL.Migrate (migrationComponent, sqlMigration)
import Kenshou.Core.Env (MigrationSet (..), MigrationSetName (..))

selftestSchema :: MigrationSetName
selftestSchema = MigrationSetName "kenshou-selftest"

selftestMigrationSet :: MigrationSet
selftestMigrationSet =
  MigrationSet
    { name = selftestSchema,
      requires = [],
      component = either (Left . Text.pack . show) Right do
        roundtrip <- sqlMigration "create-roundtrip" "create schema kenshou_selftest;\ncreate table kenshou_selftest.roundtrip (id bigint primary key, payload text not null);\n"
        migrationComponent "kenshou-selftest" Set.empty (roundtrip :| [])
    }
