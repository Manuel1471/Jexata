# Contributing

Keep changes small and include ExUnit cases for each behavior. Use JSONata v2.2.0 documentation and the reference implementation as the semantic baseline. Add a regression test for every bug fix, especially when changing sequence or undefined behavior.

Run `mix format`, `mix compile --warnings-as-errors`, and `mix test`. If a change affects compatibility, rerun `scripts/compatibility.exs` against the pinned v2.2.0 suite and update `docs/COMPATIBILITY.md` with the actual counts. For performance changes, run `scripts/benchmark.exs` on the same host before and after; keep parsing and evaluation measurements separate.

Do not copy reference fixtures without retaining their MIT license notice. Do not claim complete JSONata support while reference cases still fail or remain unsupported.
