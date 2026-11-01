# Local benchmark

Run `MIX_ENV=prod mix run scripts/benchmark.exs` to measure compilation, evaluation of a compiled expression, and compile-plus-evaluate (`run/2`). Each reported value is the mean of 10,000 consecutive calls after one warm-up call. The script uses generated maps with 10, 100, or 1,000 orders. Results are local measurements, not a comparison with the JavaScript reference.

Measurement environment: Mac16,12 (arm64), Elixir 1.20.2, OTP 29, 10 online schedulers. Selected results from the 1.0.0 run, in microseconds per operation:

| Expression | Orders | Compile | Evaluate compiled | Run |
| --- | ---: | ---: | ---: | ---: |
| `customer.name` | 10 | 1.118 | 0.509 | 1.012 |
| `orders[price > 50].price` | 100 | 3.131 | 8.753 | 12.048 |
| `$sum(orders.price)` | 100 | 1.767 | 3.753 | 5.388 |
| `orders[price > 50].price` | 1,000 | 3.134 | 130.630 | 140.976 |
| `$sum(orders.price)` | 1,000 | 1.684 | 35.598 | 47.807 |

The script reports all 45 measurements. Repeated runs may vary with system load and BEAM runtime state. The benchmark does not measure memory use, tail latency, or adversarial expressions.

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

The official compatibility suite remains at 1,204 passing, 42 failing, 16 unsupported, and 9 skipped cases. Full compilation of `customer.name` measured 8.421 µs per call before the tokenizer optimization and 1.153 µs per call in a later run on this host; these are separate runs and should be treated as indicative rather than a controlled compiler comparison.
