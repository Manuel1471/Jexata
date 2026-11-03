# Jexata versus jsonata.js

This local benchmark compares Jexata 1.0.0 with the official [jsonata.js v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0) source checkout at commit `8ee4476f8a228bfc7a62979ae0a9c13a4043cd03`. It uses the public compile and evaluate APIs. JavaScript evaluations await the promise returned by `evaluate`; compilations are synchronous in both engines. These are end-to-end API costs in two different runtimes, not a comparison of identical virtual-machine operations.

Both engines read the same generated JSON fixture: 1,000 orders plus a customer. For every case, the driver checks that their JSON results agree before reporting a timing. Compiled expressions are reused for evaluation cases; data creation and process startup are outside the timed section. Each engine runs seven rounds in alternating order, with three warm-up calls per case. Times below are medians and min–max ranges in microseconds per operation. The raw seven-round observations and exact expressions are in [jsonata_js_comparison.json](jsonata_js_comparison.json) and [compare_jsonata.py](../scripts/compare_jsonata.py).

Measured on a Mac16,12 arm64 host with Elixir 1.20.2 / OTP 29 and Node v26.5.0. The laptop was on battery power; low-power mode was off. A ratio above 1 means Jexata was faster; below 1 means jsonata.js was faster. Results are specific to this host, input, runtime versions, and expression mix.

| Workload | Jexata µs med [min–max] | jsonata.js µs med [min–max] | JS − Jexata µs | JS / Jexata | ns/order J / JS |
| --- | ---: | ---: | ---: | ---: | ---: |
| `compile_field` | 0.64 [0.63–0.66] | 13.17 [13.00–13.78] | +12.53 | 20.74× | — |
| `field` | 0.11 [0.10–0.11] | 1.81 [1.77–1.98] | +1.70 | 17.05× | — |
| `filter` | 83.60 [82.25–85.21] | 755.89 [741.81–766.26] | +672.28 | 9.04× | 83.6 / 755.9 |
| `sum` | 35.70 [34.39–52.29] | 148.85 [143.82–150.96] | +113.15 | 4.17× | 35.7 / 148.9 |
| `map_lambda` | 139.98 [138.79–143.69] | 1,231.12 [1,201.39–1,237.30] | +1,091.14 | 8.80× | 140.0 / 1231.1 |
| `reduce_lambda` | 157.15 [155.26–160.39] | 1,247.36 [1,222.71–1,265.59] | +1,090.21 | 7.94× | 157.1 / 1247.4 |
| `sort_comparator` | 1,154.45 [1,132.48–1,177.07] | 9,702.76 [9,420.15–10,018.36] | +8,548.31 | 8.40× | 1154.4 / 9702.8 |
| `group_object` | 142.09 [139.51–144.68] | 727.30 [707.86–737.80] | +585.21 | 5.12× | 142.1 / 727.3 |
| `index_zero` | 0.19 [0.18–0.24] | 1.12 [1.10–1.17] | +0.93 | 5.77× | — |
| `number_decimal` | 490.44 [480.35–513.53] | 1,637.87 [1,613.68–1,683.53] | +1,147.42 | 3.34× | 490.4 / 1637.9 |
| `trim` | 1,696.43 [1,675.73–1,739.75] | 1,700.65 [1,667.49–1,710.46] | +4.22 | 1.00× | 1696.4 / 1700.7 |
| `replace` | 660.47 [639.43–683.33] | 2,237.27 [2,221.84–2,285.94] | +1,576.80 | 3.39× | 660.5 / 2237.3 |

Jexata was faster in eleven of twelve cases. The literal-index fast path brings `orders[0].price` to 0.19 µs versus 1.12 µs in JS. Resolved `$replace` with a plain `/Order/` regex now takes 660.47 µs versus 2,237.27 µs in JS for 1,000 items. `$trim` is approximately tied on this input. The simple-field ratio represents only 1.70 µs of absolute difference. The JS API's promise scheduling is included in evaluation time. The empty `await Promise.resolve()` loop measured a 0.061 µs median (0.059–0.069); it is a lower bound for one await, not a correction to subtract from full evaluations. This benchmark does not measure throughput under concurrent load, memory use, or application-level request latency.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py \
  --reference /tmp/jexata-reference-2.2.0 \
  --rounds 7 --output docs/jsonata_js_comparison.json
```

The JSON also stores each round's order, CPU model, power-source and low-power settings, Node flags and `NODE_OPTIONS`, the promise-floor samples, absolute time differences, and per-element costs for workloads that process 1,000 orders. The net cost of a built-in cannot be inferred exactly by subtracting `map_lambda`, because the lambda bodies access different fields and do different work.

The comparison driver requires Python 3, Node.js, and the Elixir/OTP versions supported by this project. `jsonata.js` is used only by this development benchmark; Jexata has no JavaScript runtime dependency. Run both engines on the same otherwise idle machine when comparing changes. The driver rejects an unexpected reference commit or a result mismatch.
