# Unmanaged, project-specific flake-parts module. This file must be tracked so
# Nix includes it in the flake source.
{ inputs, ... }:
{
  perSystem = { pkgs, ... }:
    let
      # PostgreSQL's major version is a run-time dimension (pg.major), resolved by
      # Kenshou.Core.Env.Postgres through these two variables. PostgreSQL 18 stays
      # on PATH while both bin directories remain directly addressable.
      pgEnvHook = pkgs.makeSetupHook { name = "kenshou-pg-env"; }
        (pkgs.writeText "kenshou-pg-env.sh" ''
          export KENSHOU_PG17_BIN="${pkgs.postgresql_17}/bin"
          export KENSHOU_PG18_BIN="${pkgs.postgresql_18}/bin"
        '');

      haskellLib = pkgs.haskell.lib.compose;
      # The harness cohort (cohort/harness.project) pins these below the versions in
      # the shared package set; build the exact Hackage releases Cabal resolves.
      cohortPins = {
        settei = { ver = "0.2.0.0"; sha256 = "sha256-lO9pMRWuzls8mj0ahRx9W/D8wChUBEorTbjwka/WzYk="; };
        settei-env = { ver = "0.2.0.0"; sha256 = "sha256-d4phi519sflWNQufM0XkxN59TaT4XQYArO7f3Jxj9TQ="; };
        settei-yaml = { ver = "0.2.0.0"; sha256 = "sha256-5lZa3KJBOXLGdaFN1otNvXOLM5G5hqZbb/5L6PDPDCE="; };
        settei-optparse-applicative = { ver = "0.2.0.0"; sha256 = "sha256-Jtws+RO/6FRn1WSP5fyjlBhZXadVWWNjy8PxJwO/PgI="; };
        okf-core = { ver = "0.9.0.0"; sha256 = "sha256-a34kTE5G3o+6Q+Kv/TVRpbGVzfTiaoPvKxsMZmeqYcE="; };
        pg-migrate = { ver = "1.1.0.0"; sha256 = "sha256-S+ixJ+pi96TR6+LUu5C5MDpqP2bOQmpl3hcU29oSfoA="; };
        pg-migrate-embed = { ver = "1.1.0.0"; sha256 = "sha256-ZQz4EIAP8iJbsWRgliynePLqu2XBmWeWwIYmh1nG/QU="; };
        hs-opentelemetry-exporter-prometheus = { ver = "1.0.0.0"; sha256 = "sha256-6yCjTQ/1hriFD2n3zprJDHKBsjLAD5jzlSfOuN/3ej0="; };
      };
      cohortOverlay = hself: _hsuper:
        pkgs.lib.mapAttrs
          (name: pin: haskellLib.dontCheck (haskellLib.doJailbreak (hself.callHackageDirect
            {
              pkg = name;
              inherit (pin) ver sha256;
            }
            { })))
          cohortPins;
      haskellPackages = pkgs.haskell.packages.ghc9124.override {
        overrides = pkgs.lib.composeExtensions
          (inputs.haskell-nix.lib.haskellExtension haskellLib pkgs)
          cohortOverlay;
      };
      # The unit tests start PostgreSQL servers and run under `just verify`; the Nix
      # outputs are builds of the libraries and the executable.
      local = name: path: deps: haskellLib.dontCheck (haskellPackages.callCabal2nix name (inputs.self + path) deps);
      gitRev = inputs.self.shortRev or "dirty";
      kenshou-core =
        local "kenshou-core" "/kenshou-core" { };
      kenshou-check =
        local "kenshou-check" "/kenshou-check" {
          inherit kenshou-core;
        };
      kenshou-measure =
        local "kenshou-measure" "/kenshou-measure" {
          inherit kenshou-core;
        };
      kenshou-diagnose =
        local "kenshou-diagnose" "/kenshou-diagnose" {
          inherit kenshou-core kenshou-measure;
        };
      kenshou-telemetry =
        local "kenshou-telemetry" "/kenshou-telemetry" {
          inherit kenshou-core kenshou-measure;
        };
      kenshou-evidence =
        local "kenshou-evidence" "/kenshou-evidence" {
          inherit kenshou-core kenshou-remote;
        };
      kenshou-remote =
        local "kenshou-remote" "/kenshou-remote" {
          inherit kenshou-core kenshou-measure;
        };
      kenshou-cli = pkgs.haskell.lib.compose.overrideCabal
        (drv: {
          configureFlags = (drv.configureFlags or [ ]) ++ [
            "--ghc-option=-DGIT_HASH=\"${builtins.substring 0 7 gitRev}\""
          ];
        })
        (local "kenshou-cli" "/kenshou-cli" {
          inherit kenshou-check kenshou-core kenshou-diagnose kenshou-evidence kenshou-measure kenshou-remote kenshou-telemetry;
        });
      kenshou-synthetic =
        local "kenshou-synthetic" "/kenshou-synthetic" {
          inherit kenshou-check kenshou-cli kenshou-core kenshou-diagnose kenshou-measure;
        };
    in
    {
      haskellProject.extraDevPackages =
        [ pkgs.git pkgs.jq pkgs.check-jsonschema pkgs.dhall pgEnvHook ];

      treefmt.programs.fourmolu.package = pkgs.haskell.packages.ghc9124.fourmolu;

      packages.kenshou-core = kenshou-core;
      packages.kenshou-cli = kenshou-cli;
      packages.kenshou-synthetic = kenshou-synthetic;
    };
}
