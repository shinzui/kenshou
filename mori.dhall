let Schema =
      https://raw.githubusercontent.com/shinzui/mori-schema/3522f4a51181d73c9c90fc27a7c0838bd29ae95f/package.dhall
        sha256:dcb19e2312e790bad14e622cc98a1281cd2298c5b564a2f0d0534d3c718d8803

in  Schema.Project::{
    , project = Schema.ProjectIdentity::{
      , name = "kenshou"
      , namespace = "shinzui"
      , stableId = Some "project_01m615zvfqe8esvekhvzth4ynr"
      , type = Schema.PackageType.Library
      , language = Schema.Language.Haskell
      , lifecycle = Schema.Lifecycle.Experimental
      , description = Some
          "Package-agnostic verification harness for Haskell systems: the scenario kernel plus the correctness, measurement, diagnostics, telemetry, evidence, and remote-cell toolkits, extracted from mori://shinzui/keiro-runtime-kenshou so any project can register its own layer suites."
      , domains = [ "Testing", "Benchmarking", "Verification" ]
      , owners = [ "shinzui" ]
      }
    , repos =
      [ Schema.Repo::{ name = "kenshou", github = Some "shinzui/kenshou" } ]
    , packages =
      [ Schema.Package::{
        , name = "kenshou-core"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "./kenshou-core"
        , description = Some
            "Scenario kernel: run specs, results, roles, knobs, dimensions, cohort identity, and change-aware planning"
        }
      , Schema.Package::{
        , name = "kenshou-check"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "./kenshou-check"
        , description = Some
            "Correctness toolkit: fact ledgers, invariants, fault injection, process control, and linearizability checking"
        }
      , Schema.Package::{
        , name = "kenshou-measure"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "./kenshou-measure"
        , description = Some
            "Measurement toolkit: load generation, latency recording, samplers, statistics, and paired comparison"
        }
      , Schema.Package::{
        , name = "kenshou-diagnose"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "./kenshou-diagnose"
        , description = Some
            "Diagnostics toolkit: heap-leak verdicts, stall capture, lock graphs, and profiling guards"
        }
      , Schema.Package::{
        , name = "kenshou-telemetry"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "./kenshou-telemetry"
        , description = Some
            "Telemetry arms, endpoint scraping, and observability-overhead reports"
        }
      , Schema.Package::{
        , name = "kenshou-evidence"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "./kenshou-evidence"
        , description = Some
            "Immutable run records, evidence bundles, attestation, and history"
        }
      , Schema.Package::{
        , name = "kenshou-remote"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "./kenshou-remote"
        , description = Some
            "Leased verification cells, payload publishing, and object stores"
        }
      , Schema.Package::{
        , name = "kenshou-cli"
        , type = Schema.PackageType.Library
        , language = Schema.Language.Haskell
        , path = Some "./kenshou-cli"
        , description = Some
            "Operator command set that a consuming project assembles into its own verification executable"
        }
      , Schema.Package::{
        , name = "kenshou-synthetic"
        , type = Schema.PackageType.Application
        , language = Schema.Language.Haskell
        , path = Some "./kenshou-synthetic"
        , description = Some
            "Synthetic reference layer and standalone executable that prove the harness boundary and show consumers how to register a suite"
        }
      ]
    , dependencies =
      [ "shinzui/pg-migrate"
      , "shinzui/ephemeral-pg"
      , "shinzui/settei"
      , "iand675/hs-opentelemetry"
      , "shinzui/okf"
      ]
    , dependencyRefs =
      [ Schema.MoriRef::{ namespace = "shinzui", name = "pg-migrate" }
      , Schema.MoriRef::{ namespace = "shinzui", name = "ephemeral-pg" }
      , Schema.MoriRef::{ namespace = "shinzui", name = "settei" }
      , Schema.MoriRef::{ namespace = "iand675", name = "hs-opentelemetry" }
      , Schema.MoriRef::{ namespace = "shinzui", name = "okf" }
      ]
    , docs =
      [ Schema.DocRef::{
        , key = "masterplan"
        , kind = Schema.DocKind.Spec
        , audience = Schema.DocAudience.Module
        , description = Some
            "Initiative plan for extracting the package-agnostic verification harness"
        , location =
            Schema.DocLocation.LocalFile
              "./docs/masterplans/1-extract-a-package-agnostic-verification-harness-into-kenshou.md"
        }
      ]
    }
