set shell := ["zsh", "-cu"]

[group('meta')]
default:
    just --list

[group('haskell')]
haskell-build:
    cabal build all

[group('format')]
fmt:
    nix fmt

[group('format')]
fmt-check:
    nix fmt -- --fail-on-change
