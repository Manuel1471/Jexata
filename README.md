# Jexata

Jexata compiles a subset of [JSONata](https://docs.jsonata.org/) expressions and evaluates them against native Elixir data. It is a pure Elixir library with no production dependencies. The `release/v1.0.0` branch is **development work**, not a stable 1.0 release.

Jason decodes or encodes JSON. Jexata queries and transforms already decoded Elixir maps and lists. String keys in maps correspond to JSON object properties.

## Use

```elixir
{:ok, expression} = Jexata.compile("$sum(orders.price)")

{:ok, 350} =
  Jexata.evaluate(expression, %{
    "orders" => [%{"price" => 100}, %{"price" => 250}]
  })

{:ok, "Ada"} = Jexata.run("customer.name", %{"customer" => %{"name" => "Ada"}})
```

Compile once and reuse the returned `%Jexata.Expression{}` for repeated evaluations. The expression is immutable and evaluations keep their own state, including when called from multiple processes. `compile!/1`, `evaluate!/2`, and `run!/2` raise `Jexata.Error` instead of returning an error tuple.

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

The current interpreter supports literals, quoted field names, comments, field paths, immediate wildcards, array predicates, descendants, arithmetic, basic comparisons, `and`/`or`, concatenation, integer ranges, conditional/default/coalescing expressions, array and object constructors, basic grouping and order-by, blocks, local variable bindings, lambdas, closures, value-to-function chaining, and `$map`/`$filter`/`$reduce`. It includes selected numeric, text, array, object, and boolean functions. See [the compatibility report](docs/COMPATIBILITY.md) for exact coverage and gaps.

It does **not** yet implement the complete JSONata grammar or function library. In particular, full grouping and sorting semantics, regular expressions, transforms, function composition, date/time functions, and several operators and built-ins remain incomplete. Do not use it as a drop-in replacement for the reference implementation.

## Limits and trust

`compile/2` accepts positive integer `max_source_bytes`, `max_tokens`, and `max_nesting` options. Defaults are 100,000 bytes, 10,000 tokens, and 128 delimiter levels. Integer ranges are capped at 100,000 generated values. For example:

```elixir
Jexata.compile("orders.price", max_source_bytes: 1_000, max_tokens: 100)
```

There is no general evaluation time, step, memory, output size, or regular expression limit yet. These compilation checks do not make execution of arbitrary user expressions sandbox safe. Jexata does not provide file, network, shell, or arbitrary Elixir execution capabilities.

## Development

```bash
mix format
mix compile --warnings-as-errors
mix test
MIX_ENV=prod mix run scripts/benchmark.exs
```

See [architecture](docs/ARCHITECTURE.md), [compatibility](docs/COMPATIBILITY.md), and [contributing](CONTRIBUTING.md). No Hex package, GitHub release, or remote branch has been published for this work.
