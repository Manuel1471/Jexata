# Jexata

Jexata 1.0.0 compiles [JSONata](https://docs.jsonata.org/) expressions and evaluates them against native Elixir data. It is a pure Elixir library with no production dependencies. Its local runner passes all 1,271 cases in the portable JSONata v2.2.0 test suite; see the [compatibility report](docs/COMPATIBILITY.md) for the test method and limits of that result.

Jason decodes or encodes JSON. Jexata queries and transforms already decoded Elixir maps and lists. String keys in maps correspond to JSON object properties.

## Use

```elixir
{:ok, expression} = Jexata.compile("$sum(orders.price)")

{:ok, 350} =
  Jexata.evaluate(expression, %{
    "orders" => [%{"price" => 100}, %{"price" => 250}]
  })

{:ok, "Ada"} = Jexata.run("customer.name", %{"customer" => %{"name" => "Ada"}})

{:ok, 45} = Jexata.run("$price.foo.bar", %{}, %{"price" => %{"foo" => %{"bar" => 45}}})
```

Compile once and reuse the returned `%Jexata.Expression{}` for repeated evaluations. The expression is immutable and evaluations keep their own state, including when called from multiple processes. `compile!/1`, `evaluate!/2`, and `run!/2` raise `Jexata.Error` instead of returning an error tuple.

Use `evaluate/3` or `run/3` for external variable bindings. Keys omit the leading `$`; bindings are local to that evaluation.

Use `evaluate/4` or `run/4` with `max_function_depth: n` to limit recursive function calls for one evaluation.

`run/2` recompiles its source on every call. For dynamic expressions used repeatedly, keep compiled expressions in an application-owned cache with a bounded number of entries, keyed by source and compilation options. Jexata itself does not maintain global mutable cache state.

For a local application, use a path dependency while the package is unpublished:

```elixir
{:jexata, path: "../Jexata"}
```

Jexata requires Elixir 1.20 or later. It was checked on Elixir 1.20.2 and OTP 29.

## Results and errors

Non-bang functions return `{:ok, value}` or `{:error, %Jexata.Error{code: ..., message: ..., position: ...}}`. Pass `:undefined` as the input data when there is no root JSON value. An expression that selects nothing returns `{:ok, :undefined}`. Explicit JSON `null` is Elixir `nil`. A JSONata sequence with one item returns that item; a sequence with multiple items returns a list. An explicit array stays a list even when it contains one item. A top-level function result is represented as `:function`.

```elixir
{:ok, :undefined} = Jexata.run("missing", %{})
{:ok, nil} = Jexata.run("value", %{"value" => nil})
{:error, %Jexata.Error{code: "T2001"}} = Jexata.run("'x' + 2", %{})
```

## Supported scope

The interpreter supports literals, quoted field names, comments, field paths, wildcards, array predicates, descendants, arithmetic, comparisons, `and`/`or`, concatenation, bounded integer ranges, conditional/default/coalescing expressions, array and object constructors, grouping and order-by, index bindings, blocks, local variable bindings, lambdas, closures, chaining and composition, partial application, immutable transforms, and higher-order functions. It includes numeric, text, regex, array, object, boolean, URL, Base64, and selected date/time functions. See [the compatibility report](docs/COMPATIBILITY.md) for exact coverage and gaps.

Passing the portable suite does not establish compatibility with every JSONata expression. In particular, Elixir maps do not preserve source key order, so `$string` preserves literal object key order directly but may serialize objects obtained from input maps in a different order. Check the expressions your application needs before using it as a drop-in replacement.

## Limits and trust

`compile/2` accepts positive integer `max_source_bytes`, `max_tokens`, and `max_nesting` options. Defaults are 100,000 bytes, 10,000 tokens, and 128 delimiter levels. Integer ranges are capped at 100,000 generated values. For example:

```elixir
Jexata.compile("orders.price", max_source_bytes: 1_000, max_tokens: 100)
```

There is a function recursion depth limit of 1,024 for ordinary calls (configurable per evaluation) and a 100,000 iteration limit for supported tail calls, but no general evaluation time, step, memory, output size, or regular expression limit. These compilation checks do not make execution of arbitrary user expressions sandbox safe. Jexata does not provide file, network, shell, or arbitrary Elixir execution capabilities.

## Development

```bash
mix format
mix compile --warnings-as-errors
mix test
MIX_ENV=prod mix run scripts/benchmark.exs
```

See [architecture](docs/ARCHITECTURE.md), [compatibility](docs/COMPATIBILITY.md), [benchmark](docs/BENCHMARK.md), and [contributing](CONTRIBUTING.md). The 1.0.0 package metadata and branch are prepared locally; no Hex package or GitHub release has been published by this work.

## Hex publication

[GitHub Actions](.github/workflows/hex.yml) runs formatting, warning-free compilation, tests, and a Hex package dry run for pull requests to `master` and pushes to `master` or `release/**`. A successful push to `master` publishes the version in `mix.exs` if that version does not already exist on Hex. An existing version is skipped.

To enable publication, create a Hex API key with publish permission and add it to the GitHub repository as the `HEX_API_KEY` Actions secret. The first public release needs a key that can create the package; later releases can use a key scoped to `jexata`. If the secret is absent, the publication job fails with a setup message. The package is MIT licensed. This repository does not include a deployment step or publish from a release branch.
