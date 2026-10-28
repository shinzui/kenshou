-- | The synthetic suite's migration set: one schema holding an append-only items
-- table and a leases table, composed into the run's one pg-migrate ledger by the
-- kernel like any suite's migrations.
module Kenshou.Suite.Synthetic.Schema
  ( syntheticSchema,
    syntheticMigrationSet,
  )
where

import Data.List.NonEmpty (NonEmpty (..))
import Data.Set qualified as Set
import Data.Text qualified as Text
import Database.PostgreSQL.Migrate (migrationComponent, sqlMigration)
import Kenshou.Core.Env (MigrationSet (..), MigrationSetName (..))

syntheticSchema :: MigrationSetName
syntheticSchema = MigrationSetName "synthetic"

syntheticMigrationSet :: MigrationSet
syntheticMigrationSet =
  MigrationSet
    { name = syntheticSchema,
      requires = [],
      component = either (Left . Text.pack . show) Right do
        tables <-
          sqlMigration
            "create-tables"
            "create schema synthetic;\n\
            \create table synthetic.items (key text not null, seq bigint not null, item text not null, writer text not null, written_at timestamptz not null default now(), primary key (key, seq));\n\
            \create table synthetic.leases (key text primary key, owner text not null, acquired_at timestamptz not null, expires_at timestamptz not null);\n"
        migrationComponent "synthetic" Set.empty (tables :| [])
    }
