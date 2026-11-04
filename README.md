# Jexata

Jexata 1.0.0 compiles [JSONata](https://docs.jsonata.org/) expressions and evaluates them against native Elixir data. It is a pure Elixir library with no production dependencies. Its local runner passes 1,676 of 1,679 JSONata v2.2.0 reference cases, with three output-order differences and no unsupported cases in that suite. See the [compatibility report](docs/COMPATIBILITY.md) for the test method and remaining gaps.

Jason decodes or encodes JSON. Jexata queries and transforms already decoded Elixir maps and lists. String keys in maps correspond to JSON object properties.

## Find what you need

| If you want to… | Go to… |
| --- | --- |
| Run your first expression | [Start here](#start-here) |
| Select, filter, sort, or aggregate records | [Query recipes](#query-recipes) |
| Build a new document | [Complete report](#complete-report) |
| Use functions, bindings, or repeated expressions | [Functions and reuse](#functions-and-reuse) |
| Work with text, regex, and dates | [Text, regex, and dates](#text-regex-and-dates) |
| Update a document without mutating it | [Transforms](#transforms) |
| Understand values and errors | [Results and errors](#results-and-errors) |
| Limit user-supplied expressions | [Limits and trust](#limits-and-trust) |
| Check differences from jsonata.js | [Supported scope](#supported-scope) |
| Combine JSONata with database queries | [Jexata and Ecto](#jexata-and-ecto) |

## Start here

Jexata requires Elixir 1.20 or later. While the package is unpublished, add a path dependency to your application's `mix.exs`:

```elixir
defp deps do
  [{:jexata, path: "../Jexata"}]
end
```

Then run `mix deps.get`. After version 1.0.0 is published on Hex, replace the path dependency with `{:jexata, "~> 1.0"}`. Use string keys in maps, as you would get from decoded JSON:

```elixir
data = %{"customer" => %{"name" => "Ada"}}

{:ok, "Ada"} = Jexata.run("customer.name", data)
```

`run/2` compiles and evaluates once. For repeated use, compile once and evaluate each document:

```elixir
expression = Jexata.compile!("customer.name")

{:ok, "Ada"} = Jexata.evaluate(expression, %{"customer" => %{"name" => "Ada"}})
{:ok, "Lin"} = Jexata.evaluate(expression, %{"customer" => %{"name" => "Lin"}})
```

The compiled expression is immutable and can be shared across BEAM processes.

## Query recipes

The examples below use this document:

```elixir
data = %{
  "customer" => %{"name" => "Ada"},
  "orders" => [
    %{"product" => "Book", "price" => 20, "qty" => 2},
    %{"product" => "Pen", "price" => 90, "qty" => 1},
    %{"product" => "Book", "price" => 40, "qty" => 3}
  ]
}
```

### Select and filter

```elixir
{:ok, "Ada"} = Jexata.run("customer.name", data)
{:ok, [20, 90, 40]} = Jexata.run("orders.price", data)
{:ok, "Pen"} = Jexata.run("orders[price >= 50].product", data)
{:ok, "Book"} = Jexata.run("orders[0].product", data)
{:ok, "Book"} = Jexata.run("orders[-1].product", data)
```

`[price >= 50]` tests each order. Numeric predicates select by position, including a negative position from the end. JSONata sequences collapse a single match to a scalar; an explicit array keeps its array shape.

### Aggregate, group, and sort

```elixir
{:ok, 150} = Jexata.run("$sum(orders.price)", data)
{:ok, 50.0} = Jexata.run("$average(orders.price)", data)

{:ok, %{"Book" => 60, "Pen" => 90}} =
  Jexata.run("orders{product: $sum(price)}", data)

{:ok, ["Pen", "Book", "Book"]} =
  Jexata.run("orders^(>price).product", data)
```

The object expression groups orders by `product` and sums each group's prices. `^` sorts orders by descending `price` before the path selects the product.

### Map and reduce

```elixir
{:ok, [40, 90, 120]} =
  Jexata.run("$map(orders, function($o){$o.price * $o.qty})", data)

{:ok, 150} =
  Jexata.run("$reduce(orders, function($sum, $o){$sum + $o.price}, 0)", data)

{:ok, [20, 40, 90]} = Jexata.run("$sort(orders.price)", data)
```

### Complete report

The same expression can produce a new document for different minimum prices. `~S"""` keeps JSONata's quotes readable inside the Elixir string:

```elixir
source = ~S"""
{
  "customer": customer.name,
  "total": $sum(orders.price),
  "expensive": orders[price >= $minPrice].product,
  "byProduct": orders{product: $sum(price)}
}
"""

expression = Jexata.compile!(source)
{:ok, report} = Jexata.evaluate(expression, data, %{"minPrice" => 50})

report == %{
  "customer" => "Ada",
  "total" => 150,
  "expensive" => "Pen",
  "byProduct" => %{"Book" => 60, "Pen" => 90}
}
# => true
```

For local values, a JSONata block can assign a variable before using it:

```elixir
{:ok, 180.0} = Jexata.run("($tax := 1.2; $sum(orders.price) * $tax)", data)
```

## Functions and reuse

| Function | Purpose |
| --- | --- |
| `compile(source, options \\ [])` | Parse once; return `{:ok, expression}` or an error. |
| `evaluate(expression, data, bindings \\ %{})` | Run a compiled expression on a document. |
| `evaluate(expression, data, bindings, options)` | Set `max_function_depth` for recursive calls. |
| `run(source, data, bindings \\ %{})` | Compile and evaluate in one call. |
| `evaluate_bounded(expression, data, options \\ [])` | Evaluate in a monitored process with resource limits. |
| `compile!/1`, `evaluate!/2`, `run!/2` | Raise `Jexata.Error` instead of returning an error tuple. |

External binding keys omit the leading `$`. They apply only to that evaluation:

```elixir
{:ok, ["Pen", "Book"]} =
  Jexata.run("orders[price > $min].product", data, %{"min" => 30})
```

The example uses `data` from [Query recipes](#query-recipes). `run/2` recompiles every time; for repeated dynamic queries, keep compiled expressions in an application-owned cache with a bounded number of entries. Jexata has no global mutable cache. Use `evaluate/4` or `run/4` with `max_function_depth: n` to set a per-evaluation recursion limit.

For accumulating arrays, avoid repeatedly calling `$append` inside `$reduce`: appending copies the growing list. Build large arrays in Elixir or use a transformation that produces the desired sequence directly.

## Text, regex, and dates

```elixir
{:ok, "HELLO WORLD"} =
  Jexata.run(~S|$trim("  hello   world  ") ~> $uppercase()|, %{})

{:ok, "a/b/c"} = Jexata.run(~S|$replace("a-b-c", "-", "/")|, %{})
{:ok, "123"} = Jexata.run(~S|$match("AB-123", /[0-9]+/).match|, %{})
{:ok, "1,234,567"} = Jexata.run(~S|$formatInteger(1234567, "#,##0")|, %{})
{:ok, 1} = Jexata.run(~S|$toMillis("1970-01-01T00:00:00.001Z")|, %{})
{:ok, "1970-01-01T00:00:00.001Z"} = Jexata.run("$fromMillis(1)", %{})
```

`~>` passes the left result to the function on the right. Regex literals use JSONata syntax. Number and date pictures are supported; consult [Compatibility](docs/COMPATIBILITY.md) for their tested scope.

## Transforms

A transform creates an updated value without mutating its input:

```elixir
original = %{
  "orders" => [
    %{"product" => "Book", "price" => 20},
    %{"product" => "Pen", "price" => 90}
  ]
}

{:ok, updated} =
  Jexata.run(~S($ ~> |orders|{"discounted": price * 0.9}|), original)

Enum.map(updated["orders"], & &1["discounted"])
# => [18.0, 81.0]

Enum.any?(original["orders"], &Map.has_key?(&1, "discounted"))
# => false
```

The pattern selects each order, and the update object adds its `discounted` field. The `|...|...|` delimiters are part of JSONata's transform syntax.

## Results and errors

Non-bang functions return `{:ok, value}` or `{:error, %Jexata.Error{code: ..., message: ..., position: ...}}`. Pass `:undefined` as the input data when there is no root JSON value. An expression that selects nothing returns `{:ok, :undefined}`. Explicit JSON `null` is Elixir `nil`. A JSONata sequence with one item returns that item; a sequence with multiple items returns a list. An explicit array stays a list even when it contains one item. A top-level function result is represented as `:function`.

| JSON value or result | Elixir value |
| --- | --- |
| Object | Map with string keys, such as `%{"name" => "Ada"}` |
| Array | List |
| String, number, boolean | Binary, integer or float, boolean |
| `null` | `nil` |
| No selected value | `:undefined` |

If you later encode the result as JSON, handle `:undefined` and `:function` before calling your JSON encoder.

```elixir
{:ok, :undefined} = Jexata.run("missing", %{})
{:ok, nil} = Jexata.run("value", %{"value" => nil})
{:error, %Jexata.Error{code: "T2001"}} = Jexata.run("'x' + 2", %{})
{:ok, [20]} = Jexata.run("[orders.price]", %{"orders" => [%{"price" => 20}]})
```

Use `case` when you want to handle an error without raising:

```elixir
case Jexata.run("'x' + 2", %{}) do
  {:ok, value} -> {:ok, value}
  {:error, %Jexata.Error{code: code, message: message}} -> {:error, {code, message}}
end
```

## Limits and trust

`compile/2` accepts positive integer `max_source_bytes`, `max_tokens`, and `max_nesting` options. Defaults are 100,000 bytes, 10,000 tokens, and 128 delimiter levels. Direct integer ranges are capped at 1,000,000 generated values. For example:

```elixir
Jexata.compile("orders.price", max_source_bytes: 1_000, max_tokens: 100)
```

There is a function recursion depth limit of 1,024 for ordinary calls (configurable per evaluation), a 100,000 iteration limit for supported tail calls, and a one-million-codepoint output limit for `$pad`. For untrusted or expensive expressions, `evaluate_bounded/3` runs the compiled expression in a separate BEAM process with time, process-heap, collection, AST-visit, reduction, and result-size limits:

```elixir
expression = Jexata.compile!("orders.price")
Jexata.evaluate_bounded(expression, data,
  timeout_ms: 500, max_heap_words: 1_000_000, max_result_bytes: 200_000,
  max_reductions: 500_000, max_collection_items: 10_000, max_steps: 100_000)
```

The result limit is measured as Erlang external-term size, not JSON bytes. The copied input and bindings count against the worker's heap limit; raise `max_heap_words` when processing large input. A separate watcher enforces the timeout even if the caller exits. Unknown option names return `J0007`. Bounded evaluation also passes `regex_match_limit` and `regex_recursion_limit` to Erlang's regex engine; they default to 100,000 and 10,000 respectively. Optional `max_reductions`, `max_collection_items`, and `max_steps` return `J1010`, `J1011`, and `J1012` when exceeded. The collection limit checks input, bindings, literal and constructed collections, generated sequences, selected built-ins, and the result. The step limit counts visits to evaluator AST nodes; it does not count work inside a built-in. The reduction budget counts BEAM work, including worker setup, with periodic checks. Use the deadline and heap limit alongside these optional limits. A bounded BEAM process is useful for containment but does not make arbitrary expressions a complete security sandbox. Jexata does not provide file, network, shell, or arbitrary Elixir execution capabilities. See [SECURITY.md](SECURITY.md).

## Supported scope

The interpreter supports literals, quoted field names, comments, field paths, wildcards, array predicates, descendants, arithmetic, comparisons, `and`/`or`, concatenation, bounded integer ranges, conditional/default/coalescing expressions, array and object constructors, grouping and order-by, index and focus bindings, parent navigation, blocks, local variable bindings, lambdas, closures, chaining and composition, partial application, immutable transforms, and higher-order functions. It includes numeric, text, regex, array, object, boolean, URL, Base64, integer-picture formatting/parsing, and date/time picture functions. See [the compatibility report](docs/COMPATIBILITY.md) for exact coverage and gaps.

The three remaining reference-fixture mismatches involve `$keys(%)` on input objects: Elixir maps do not preserve JSON source key order. A broader [64-expression comparison with jsonata.js](docs/JSONATA_JS_COMPARISON.md) also found the same order difference for `*` over an input object; its `$match` inside `$map` case now agrees after preserving the nested array boundary. `$string` preserves literal object key order directly but may serialize objects obtained from input maps in a different order. `$random` and `$clone` are available; `$clone` returns the same immutable value for JSON-shaped native input. Check the expressions your application needs before using Jexata as a drop-in replacement.

## Jexata and Ecto

Jexata evaluates [JSONata expressions](https://docs.jsonata.org/overview.html) against data already in memory, including API payloads, event messages, configuration, and values fetched from a database. [Ecto queries](https://ecto.hexdocs.pm/Ecto.Query.html) retrieve and update stored data through a repository and let the database filter, join, aggregate, and use indexes. Ecto also supports [schemaless queries](https://ecto.hexdocs.pm/schemaless-queries.html), including queries over database fields without an Ecto schema.

| Need | Use |
| --- | --- |
| Filter or aggregate a large database table before loading rows | Ecto query and the database |
| Persist changes, use transactions, or enforce database constraints | Ecto and `Repo` |
| Apply a reusable JSONata transformation to an API response or an already loaded document | Jexata |
| Transform data fetched with Ecto before sending it elsewhere | Ecto to fetch, then Jexata on a JSON-shaped map |

Jexata does not connect to a database, translate JSONata into SQL, or replace Ecto's persistence features. Its role is useful when the input is already a document and the application needs JSONata's path, sequence, function, and transformation semantics. For a simple database aggregate such as `SUM(price)`, run the aggregate in the database with Ecto rather than loading every row to evaluate `$sum` in Jexata.

For a small set of rows already selected by Ecto, convert the fields you need into a JSON-shaped map. This example assumes your application imports `Ecto.Query` and has `MyApp.Repo` and `MyApp.Order`:

```elixir
orders =
  MyApp.Repo.all(
    from o in MyApp.Order,
      select: %{product: o.product, price_cents: o.price_cents}
  )
  |> Enum.map(fn row ->
    %{"product" => row.product, "price_cents" => row.price_cents}
  end)

{:ok, total_cents} = Jexata.run("$sum(orders.price_cents)", %{"orders" => orders})
```

Using integer cents here avoids passing database-specific decimal structs to an API intended for JSON-shaped values.

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

See [architecture](docs/ARCHITECTURE.md), [compatibility](docs/COMPATIBILITY.md), [benchmark](docs/BENCHMARK.md), [jsonata.js comparison](docs/JSONATA_JS_COMPARISON.md), and [contributing](CONTRIBUTING.md). The 1.0.0 package metadata is prepared for publication.

CI checks at least 85% ExUnit line coverage with the complete JSONata v2.2.0 reference fixtures included, and a maximum of 1,300 **physical** lines for every Elixir source file in `lib/`. The local combined run passed 114 tests at **90.23%** line coverage. Set `JEXATA_REFERENCE_SUITE` to the fixture directory before running `mix test --cover` locally. CI uploads the per-module HTML coverage report and runs the reference compatibility baseline separately as well.

## Hex publication

[GitHub Actions](https://github.com/Manuel1471/Jexata/blob/master/.github/workflows/hex.yml) runs formatting, warning-free compilation, and tests on Elixir 1.20.0 / OTP 27 and Elixir 1.20.5 / OTP 29 for pull requests to `master` and pushes to `master` or `release/**`. A separate job runs Dialyzer; the recent toolchain also runs performance guards and a Hex package dry run. A successful push to `master` publishes the version in `mix.exs` if that version does not already exist on Hex. An existing version is skipped.

To enable publication, create a Hex API key with publish permission and add it to the GitHub repository as the `HEX_API_KEY` Actions secret. The first public release needs a key that can create the package; later releases can use a key scoped to `jexata`. If the secret is absent, the publication job fails with a setup message. The package is MIT licensed. This repository does not include a deployment step or publish from a release branch.
