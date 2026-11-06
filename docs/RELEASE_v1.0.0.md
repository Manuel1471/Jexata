# Jexata v1.0.0 — First Public Release

The first public release of **Jexata**, a JSONata expression compiler and evaluator written in Elixir. It runs expressions against JSON-shaped Elixir values such as maps and lists, with no production dependency on JavaScript or a database.

Jexata grew from dynamic JSON evaluations in data pipelines. It is intended for querying and transforming documents that an application already has in memory: API payloads, events, configuration, or records fetched elsewhere. Database filtering, joins, and persistence remain the job of a database and tools such as Ecto.

## Install

Add Jexata to your Mix dependencies:

```elixir
defp deps do
  [{:jexata, "~> 1.0"}]
end
```

Jexata requires Elixir 1.20 or later. Version 1.0.0 is available on [Hex](https://hex.pm/packages/jexata).

## Get started

```elixir
data = %{
  "customer" => %{"name" => "Ada"},
  "orders" => [%{"price" => 20}, %{"price" => 30}]
}

{:ok, "Ada"} = Jexata.run("customer.name", data)
{:ok, 50} = Jexata.run("$sum(orders.price)", data)

# Compile once when evaluating the same expression against many documents.
expression = Jexata.compile!("orders[price > $minimum].price")
{:ok, 30} = Jexata.evaluate(expression, data, %{"minimum" => 25})
```

The public API offers `compile`, `evaluate`, and one-step `run` functions, plus raising variants. Non-raising calls return `{:ok, value}` or `{:error, %Jexata.Error{}}`. Compiled expressions are immutable and can be reused across BEAM processes. External binding names omit the leading `$`.

## What is included

- JSONata paths, predicates, wildcards, descendant selection, array and object constructors, grouping, sorting, arithmetic, comparisons, conditionals, and sequence semantics.
- Lexical variables, lambdas, closures, higher-order functions such as `$map` and `$reduce`, partial application, function chaining, and immutable transforms.
- Numeric, string, array, object, regex, URL, Base64, integer-picture, and date/time-picture functions.
- Structured errors and compile-time limits for source size, token count, and nesting.
- `evaluate_bounded/3` for isolated evaluation with a deadline, worker heap and result-size limits, regex limits, and optional budgets for BEAM reductions, AST visits, and collection size. These controls contain resource use; they are not a complete sandbox.

Jexata expects JSON-shaped Elixir data. Use string keys for object properties. JSON `null` is `nil`; a missing selection returns `:undefined`. Sequence results can collapse to a scalar when only one item matches, while an explicit array remains a list.

## Compatibility with JSONata.js

The complete JSONata.js **v2.2.0** reference fixture suite produced:

| Result | Cases |
| --- | ---: |
| Passing | **1,676** |
| Differences | **3** |
| Unsupported | 0 |
| Skipped | 0 |
| Total | **1,679** |

All three fixture differences involve `$keys(%)` and the source order of keys in input objects. Jexata receives native Elixir maps, which do not preserve the order in which keys appeared in JSON source. The same ordering issue appeared in one wildcard case in a separate 64-expression comparison. This is a documented compatibility limit, not a claim of full JSONata parity. Directly constructed integer ranges are also capped at 1,000,000 generated values.

A differential fuzzer compared another 20,000 generated cases with JSONata.js: it found the known ordering difference and no unexpected mismatches within its grammar. See the [compatibility report](https://github.com/Manuel1471/Jexata/blob/master/docs/COMPATIBILITY.md) for the reference revision, runner behavior, and reproduction steps.

## Performance measurements

The release comparison uses 64 named expressions, seven alternating timing rounds, and compiled expressions reused for evaluation. Results matched for **63 of 64** expressions; Jexata had a lower median time in **61 of those 63** on the recorded Apple Silicon machine. The mismatching key-order case has no timing ratio.

| Workload | Jexata median | JSONata.js median |
| --- | ---: | ---: |
| Compile `customer.name` | 0.63 µs | 13.06 µs |
| Filter 1,000 orders with `orders[price > 50].price` | 108.78 µs | 791.13 µs |
| `$sum(orders.price)` over 1,000 orders | 49.05 µs | 154.09 µs |
| `$trim` over 1,000 strings | 1,734.87 µs | 1,702.43 µs |

These figures compare the public APIs on one host, not equivalent virtual-machine operations or expected latency in every application. Short JavaScript evaluations include the asynchronous API's promise cost; the benchmark records an empty-promise floor but does not subtract it. The `$trim` timing ranges overlap. The [full comparison](https://github.com/Manuel1471/Jexata/blob/master/docs/JSONATA_JS_COMPARISON.md) includes all workloads, min–max ranges, raw observations, and reproduction steps.

## Release checks

- **114 ExUnit tests** and **90.23% line coverage** when the complete reference fixture suite is included in the coverage run. CI requires at least 85%.
- CI checks Elixir/OTP combinations 1.20.0/27 and 1.20.5/29, formatting, warning-free compilation, Dialyzer, reference compatibility, reduction and time guards, and a Hex package dry run.
- A nightly Linux job reruns differential and concurrent performance checks and uploads the raw artifacts.

## Links

- [Package on Hex](https://hex.pm/packages/jexata)
- [README and usage examples](https://github.com/Manuel1471/Jexata)
- [Compatibility details](https://github.com/Manuel1471/Jexata/blob/master/docs/COMPATIBILITY.md)
- [Performance report](https://github.com/Manuel1471/Jexata/blob/master/docs/JSONATA_JS_COMPARISON.md)
- [Security policy and resource-limit guidance](https://github.com/Manuel1471/Jexata/blob/master/SECURITY.md)
