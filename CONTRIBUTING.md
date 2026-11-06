# Contributing

Keep changes small and include ExUnit cases for each behavior. Use JSONata v2.2.0 documentation and the reference implementation as the semantic baseline. Add a regression test for every bug fix, especially when changing sequence or undefined behavior.

Run `mix format`, `mix compile --warnings-as-errors`, and `mix test`. If a change affects compatibility, rerun `scripts/compatibility.exs` against the pinned v2.2.0 suite and update `docs/COMPATIBILITY.md` with the actual counts. For performance changes, run `scripts/benchmark.exs` on the same host before and after; keep parsing and evaluation measurements separate.

Do not copy reference fixtures without retaining their MIT license notice. Do not claim complete JSONata support while reference cases still fail or remain unsupported.

## Release titles

Name each GitHub release `Jexata vMAJOR.MINOR.PATCH — Short description of the release`. The description should identify its main milestone or change, rather than repeat the version number. For example, the first release is `Jexata v1.0.0 — First Public Release`. Use `vMAJOR.MINOR.PATCH` for the Git tag and `MAJOR.MINOR.PATCH` for the Hex package version. Make the first heading of the release notes match the GitHub release title.
