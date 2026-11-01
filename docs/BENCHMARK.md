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
