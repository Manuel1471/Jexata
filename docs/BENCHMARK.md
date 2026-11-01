# Local benchmark

Run `MIX_ENV=prod mix run scripts/benchmark.exs` to measure compilation, evaluation of a compiled expression, and compile-plus-evaluate (`run/2`). Each reported value is the mean of 10,000 consecutive calls after one warm-up call. The script reports both elapsed microseconds and BEAM reductions per operation. It uses generated maps with 10, 100, or 1,000 orders. Results are local measurements, not a comparison with the JavaScript reference.

Measurement environment: Mac16,12 (arm64), Elixir 1.20.2, OTP 29, 10 online schedulers. Selected results from the 1.0.0 run, in microseconds per operation:

| Expression | Orders | Compile µs | Evaluate µs | Run µs | Evaluate reductions |
| --- | ---: | ---: | ---: | ---: | ---: |
| `customer.name` | 10 | 0.989 | 0.421 | 0.887 | 48 |
| `orders[price > 50].price` | 100 | 2.646 | 7.393 | 9.976 | 3,397 |
| `$sum(orders.price)` | 100 | 1.351 | 3.272 | 4.489 | 1,973 |
| `orders[price > 50].price` | 1,000 | 2.708 | 109.727 | 117.153 | 40,403 |
| `$sum(orders.price)` | 1,000 | 1.474 | 32.759 | 39.048 | 19,090 |

The script reports all 45 measurements. Repeated runs may vary with system load and BEAM runtime state. Reductions are less sensitive to that timing noise. The benchmark does not measure memory use, tail latency, or adversarial expressions.

## Tokenizer comparison

The tokenizer optimization is compared with the implementation immediately before commit `5f41bbd`. Reproduce the check with:

```bash
git show 5f41bbd^:lib/jexata/tokenizer.ex \
  | sed 's/defmodule Jexata\.Tokenizer do/defmodule Jexata.TokenizerLegacy do/' \
  > /tmp/jexata_tokenizer_legacy.ex
MIX_ENV=prod mix run scripts/tokenizer_bench.exs /tmp/jexata_tokenizer_legacy.ex
```

The script first compares exact tokenizer results, including errors and positions, on 42 directed inputs and 50,000 deterministic generated inputs. It stops before timing if any differ. It then alternates 25 batches of 1,000 calls per implementation for each expression. Results on the same Mac16,12 host, in microseconds per tokenization:

| Expression | Legacy median | Optimized median | Legacy p95 | Optimized p95 | Median speedup |
| --- | ---: | ---: | ---: | ---: | ---: |
| `customer.name` | 7.238 | 0.991 | 8.814 | 1.348 | 7.30× |
| `$sum(orders.price)` | 13.043 | 1.643 | 13.265 | 1.694 | 7.94× |
| `orders[price > 50].price` | 21.601 | 2.995 | 21.971 | 3.052 | 7.21× |
| `añb.日本語` | 7.347 | 2.615 | 7.448 | 2.687 | 2.81× |

The official compatibility suite now passes 1,251 cases, with 8 failures, 3 unsupported cases, and 9 skipped. Full compilation of `customer.name` measured 8.421 µs per call before the tokenizer optimization and 0.989 µs per call in this run on the same host; these are separate runs and should be treated as indicative rather than a controlled compiler comparison. The fused filter path reduced compiled evaluation on 1,000 orders from 139.573 to roughly 107–110 µs per operation in separate benchmark runs. A dedicated process measurement also dropped from about 52,116 to 40,494 reductions per operation. Increasing `min_heap_size` to 100,000 reduced the original filter timing from about 150 to 125 µs without materially changing reductions, which supports GC pressure as one contributor.

Additional local before/after measurements used compiled expressions on the same host. `$zip` with two 1,000-item arrays fell from about 1,271 to 97 µs and from 1,050,483 to 32,687 reductions per operation after replacing indexed list access with `Enum.zip/1`. The canonical `$toMillis('2024-06-17T13:42:11.123Z')` path fell from 1.782 to 0.538 µs and from 148 to 131 reductions by trying the ISO parser before the abbreviated-format regexes. These are separate runs, so timing ratios are indicative.

The tokenizer equivalence script still agrees on 42 directed and 50,000 generated inputs after first-byte dispatch, byte-pattern symbol dispatch, and contiguous quoted spans. Compared with the tokenizer before these three changes, median tokenization improved 1.25× for `customer.name`, 1.30× for `$sum(orders.price)`, and 1.22× for `orders[price > 50].price`. A 1,000-character ASCII string literal fell from 40.528 to 1.723 µs and from 2,866 to 218 reductions per tokenization in a dedicated local measurement. The long-string result should not be generalized to all compilation.

Profiling the 1,000-order filter with `mix profile.eprof` showed 1,000,000 predicate checks over 1,000 evaluations, with repeated AST dispatch, comparisons, field selections, and list traversals accounting for most observed work. `Limits` and builtin lookup were not material in that profile. Regex literals are compiled by the parser when the expression is compiled. Converting the whole AST to anonymous functions or adding a global cache would add complexity without evidence from this profile; compile once and reuse the expression for repeated evaluation.
