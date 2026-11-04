# Jexata

Jexata 1.0.0 compiles [JSONata](https://docs.jsonata.org/) expressions and evaluates them against native Elixir data. It is a pure Elixir library with no production dependencies. Its local runner passes 1,676 of 1,679 JSONata v2.2.0 reference cases, with three output-order differences and no unsupported cases in that suite. The earlier 1,271/1,271 figure covered only files named `case*.json`. See the [compatibility report](docs/COMPATIBILITY.md) for the test method and remaining gaps.

Jason decodes or encodes JSON. Jexata queries and transforms already decoded Elixir maps and lists. String keys in maps correspond to JSON object properties.

## Jexata and Ecto

Jexata evaluates [JSONata expressions](https://docs.jsonata.org/overview.html) against data already in memory, including API payloads, event messages, configuration, and values fetched from a database. [Ecto queries](https://ecto.hexdocs.pm/Ecto.Query.html) retrieve and update stored data through a repository and let the database filter, join, aggregate, and use indexes. Ecto also supports [schemaless queries](https://ecto.hexdocs.pm/schemaless-queries.html), including queries over database fields without an Ecto schema.

| Need | Use |
| --- | --- |
| Filter or aggregate a large database table before loading rows | Ecto query and the database |
| Persist changes, use transactions, or enforce database constraints | Ecto and `Repo` |
| Apply a reusable JSONata transformation to an API response or an already loaded document | Jexata |
| Transform data fetched with Ecto before sending it elsewhere | Ecto to fetch, then Jexata on a JSON-shaped map |

Jexata does not connect to a database, translate JSONata into SQL, or replace Ecto's persistence features. Its role is useful when the input is already a document and the application needs JSONata's path, sequence, function, and transformation semantics. For a simple database aggregate such as `SUM(price)`, run the aggregate in the database with Ecto rather than loading every row to evaluate `$sum` in Jexata.

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

For accumulating arrays, avoid repeatedly calling `$append` inside `$reduce`: appending copies the accumulated list on each step. Build the list in the host application or use a transformation that produces the desired sequence directly.

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

The interpreter supports literals, quoted field names, comments, field paths, wildcards, array predicates, descendants, arithmetic, comparisons, `and`/`or`, concatenation, bounded integer ranges, conditional/default/coalescing expressions, array and object constructors, grouping and order-by, index and focus bindings, parent navigation, blocks, local variable bindings, lambdas, closures, chaining and composition, partial application, immutable transforms, and higher-order functions. It includes numeric, text, regex, array, object, boolean, URL, Base64, integer-picture formatting/parsing, and date/time picture functions. See [the compatibility report](docs/COMPATIBILITY.md) for exact coverage and gaps.

The three remaining reference-fixture mismatches involve `$keys(%)` on input objects: Elixir maps do not preserve JSON source key order. A broader [64-expression comparison with jsonata.js](docs/JSONATA_JS_COMPARISON.md) also found the same order difference for `*` over an input object; its `$match` inside `$map` case now agrees after preserving the nested array boundary. `$string` preserves literal object key order directly but may serialize objects obtained from input maps in a different order. `$random` and `$clone` are available; `$clone` returns the same immutable value for JSON-shaped native input. Check the expressions your application needs before using Jexata as a drop-in replacement.

## Limits and trust

`compile/2` accepts positive integer `max_source_bytes`, `max_tokens`, and `max_nesting` options. Defaults are 100,000 bytes, 10,000 tokens, and 128 delimiter levels. Direct integer ranges are capped at 1,000,000 generated values. For example:

```elixir
Jexata.compile("orders.price", max_source_bytes: 1_000, max_tokens: 100)
```

There is a function recursion depth limit of 1,024 for ordinary calls (configurable per evaluation), a 100,000 iteration limit for supported tail calls, and a one-million-codepoint output limit for `$pad`. For untrusted or expensive expressions, `evaluate_bounded/3` runs the compiled expression in a separate BEAM process with time, process-heap, and result-size limits:

```elixir
expression = Jexata.compile!("orders.price")
Jexata.evaluate_bounded(expression, data,
  timeout_ms: 500, max_heap_words: 1_000_000, max_result_bytes: 200_000)
```

The result limit is measured as Erlang external-term size, not JSON bytes. The copied input and bindings count against the worker's heap limit; raise `max_heap_words` when processing large input. A separate watcher enforces the timeout even if the caller exits. Unknown option names return `J0007`. Bounded evaluation also passes `regex_match_limit` and `regex_recursion_limit` to Erlang's regex engine; they default to 100,000 and 10,000 respectively. There is no global step count. A bounded BEAM process is useful for containment but does not make arbitrary expressions a complete security sandbox. Jexata does not provide file, network, shell, or arbitrary Elixir execution capabilities. See [SECURITY.md](SECURITY.md).

## Development

```bash
mix format
mix compile --warnings-as-errors
mix test
mix test --cover
mix dialyzer --format github
mix run scripts/reductions_guard.exs
MIX_ENV=prod mix run scripts/benchmark.exs
```

See [architecture](docs/ARCHITECTURE.md), [compatibility](docs/COMPATIBILITY.md), [benchmark](docs/BENCHMARK.md), [jsonata.js comparison](docs/JSONATA_JS_COMPARISON.md), and [contributing](CONTRIBUTING.md). The 1.0.0 package metadata and branch are prepared locally; no Hex package or GitHub release has been published by this work.

CI checks a minimum 70% ExUnit line coverage and a maximum of 1,300 **physical** lines in `lib/jexata/evaluator.ex`. The reference compatibility runner is a separate gate; its cases are not included in the ExUnit coverage percentage.

## Hex publication

[GitHub Actions](.github/workflows/hex.yml) runs formatting, warning-free compilation, and tests on Elixir 1.20.0 / OTP 27 and Elixir 1.20.5 / OTP 29 for pull requests to `master` and pushes to `master` or `release/**`. A separate job runs Dialyzer; the recent toolchain also runs performance guards and a Hex package dry run. A successful push to `master` publishes the version in `mix.exs` if that version does not already exist on Hex. An existing version is skipped.

To enable publication, create a Hex API key with publish permission and add it to the GitHub repository as the `HEX_API_KEY` Actions secret. The first public release needs a key that can create the package; later releases can use a key scoped to `jexata`. If the secret is absent, the publication job fails with a setup message. The package is MIT licensed. This repository does not include a deployment step or publish from a release branch.
