# Performance of Jexata 1.0.0

The [Jexata versus jsonata.js report](JSONATA_JS_COMPARISON.md) is the release comparison. Its [raw observations](jsonata_js_comparison.json) contain the expressions, result digests, seven timing rounds, engine order, host and runtime versions, and the Node promise floor. Compilation is measured separately from evaluation; evaluation reuses compiled expressions. The 64 cases cover scalar expressions, paths, predicates, grouping, collections, higher-order functions, numeric and string operations, regular expressions, and dates. One input-object key-order mismatch has no timing ratio.

On the recorded Mac16,12 arm64 run (Elixir 1.20.2 / OTP 29, Node 26.5.0), 63 cases produced equal results in every round. Jexata had the lower median in 60; JSONata.js had the lower median in three. These are local API measurements, not predictions for another machine or application.

| Workload | Jexata µs/op | JSONata.js µs/op | Scope |
| --- | ---: | ---: | --- |
| Compile `customer.name` | 0.63 | 12.95 | Compilation only |
| `orders[0].price` | 0.14 | 1.05 | Single indexed selection |
| Filter 1,000 orders | 107.85 | 785.88 | Full expression; see detailed report for exact fixture |
| `$fromMillis` with date picture over 1,000 orders | 460.48 | 2,557.97 | Canonical date picture |
| `$formatNumber` with `#,##0` over 1,000 orders | 267.62 | 3,439.26 | Grouped integer picture |
| `$replace` with captures over 1,000 orders | 3,041.19 | 2,271.18 | JSONata.js is faster |
| `$trim` over 1,000 orders | 1,707.78 | 1,694.55 | Ranges overlap |

For a comprehensive table with exact expressions and min–max ranges, use the [64-case report](JSONATA_JS_COMPARISON.md). Small scalar timings include the cost of awaiting the JavaScript API promise; the recorded empty-promise floor is a diagnostic and is not subtracted from results. The laptop was on battery with low-power mode off. Do not compare these values with unrelated machines or older fixtures.

## Other release checks

`mix run scripts/reductions_guard.exs` compares selected evaluator workloads against a recorded reductions budget. `mix run scripts/time_canaries.exs` watches decimal parsing, trimming, regex replacement templates, and serialization with a broad relative time threshold. These are regression alarms, not latency guarantees. `MIX_ENV=prod mix run scripts/concurrent_benchmark.exs` measures throughput and p99 for one compiled filter at 1, 4, and 10 BEAM processes. The local median throughput was about 13,175, 40,555, and 72,649 evaluations/s; p99 was 107, 165, and 253 µs. The nightly workflow reruns the JS and concurrent comparisons on Ubuntu x86 and uploads the raw artifacts.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py --reference /tmp/jexata-reference-2.2.0 \
  --rounds 7 --output docs/jsonata_js_comparison.json
python3 scripts/render_jsonata_comparison.py
MIX_ENV=prod mix run scripts/benchmark.exs
MIX_ENV=prod mix run scripts/concurrent_benchmark.exs
```

The comparison driver verifies the reference version and checks outputs before publishing ratios. Node.js is needed only to run the development comparison; Jexata has no JavaScript runtime dependency.
