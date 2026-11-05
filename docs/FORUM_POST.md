# Jexata 1.0.0 — JSONata expressions in Elixir

Hi everyone! 👋

I originally started using JSONata for a few dynamic JSON evaluations in pipelines at work. The expressions were useful, but the supporting code gradually grew beyond those initial cases. I organized it into a standalone Elixir library, added tests and documentation, and published it in case it helps someone with a similar problem.

**Jexata** compiles JSONata expressions and evaluates them against Elixir maps and lists. A small example:

```elixir
data = %{
  "orders" => [
    %{"product" => "Book", "price" => 20},
    %{"product" => "Pen", "price" => 30}
  ]
}

{:ok, 50} = Jexata.run("$sum(orders.price)", data)
```

For expressions used repeatedly, you can compile once and evaluate them against different documents.

## Why I built it

My use case was transforming data that was *already in memory*: JSON payloads moving through pipelines, where the expression could vary without changing the Elixir code around it. I wanted a reusable way to select fields, filter records, aggregate values, and build new documents.

Jexata is written in Elixir and does not need a JavaScript runtime in production. It also works alongside tools such as Ecto: I would still use the database to filter or aggregate large tables, then use Jexata when I need to transform the resulting document.

## Compatibility and performance

I tested version 1.0.0 against the JSONata.js v2.2.0 reference suite: **1,676 of 1,679 cases pass**. The three remaining differences involve the order of keys in input objects, since native Elixir maps do not retain JSON source order. I’ve documented that limitation rather than presenting the library as a perfect drop-in replacement.

I also compared 64 expressions with JSONata.js, checking results before comparing timings. Results matched for 63 expressions; on that recorded Apple Silicon run, Jexata had a lower median time in 61 of those 63. For example, filtering 1,000 orders took about **109 µs** with Jexata and **791 µs** with JSONata.js in that benchmark. These are measurements of the public APIs on one machine, not a general performance guarantee; short JavaScript evaluations also include its async API cost. The [full comparison and methodology](https://github.com/Manuel1471/Jexata/blob/master/docs/JSONATA_JS_COMPARISON.md) include the workloads and timing ranges.

## Try it

```elixir
defp deps do
  [{:jexata, "~> 1.0"}]
end
```

The package is on [Hex](https://hex.pm/packages/jexata), and the [README](https://github.com/Manuel1471/Jexata) has examples from simple paths to larger transformations.

This began as a practical tool for my own pipelines. I’d love to hear whether it fits any of your use cases, and especially where the API or documentation could be clearer.
