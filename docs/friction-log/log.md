# Bundle Update Log

## 2026-11-20

* **Addition**: FRIC-5 records detour tooling friction with mori://shinzui/haskell-nix/okf/improvement-requests: Existing request blocks strict validation of the registry bundle


* **Update**: FRIC-4 resolved: Verified all three tests and the evidence suite on the new fixture.

* **Addition**: FRIC-4 records detour environment friction with mori://shinzui/kenshou: Evidence tests copy a bundle with missing run records

## 2026-11-19
* **Addition**: FRIC-3 records slowdown environment friction with mori://shinzui/kenshou: Vendored verification bundle still lacks its run records

## 2026-11-18
* **Addition**: FRIC-2 records detour environment friction with mori://shinzui/kenshou: Vendored verification bundle lacks its run records

## 2026-10-28
* **Update**: Moved the profile import to okf-profiles v0.25.0, the release the other documentation bundles pin.
* **Update**: FRIC-1 accepted: Accepted: a project-local overlay is the intended place for cohort pins below the shared set
* **Addition**: FRIC-1 records detour tooling friction with mori://shinzui/haskell-nix: Shared Haskell package set cannot build the harness cohort's pinned dependencies
* **Adoption**: Adopt the `friction-log` profile (`coordination.frictionLog`) from https://raw.githubusercontent.com/shinzui/okf-profiles/v0.23.0/package.dhall.
