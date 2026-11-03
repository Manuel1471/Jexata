# Jexata versus jsonata.js

This local benchmark compares Jexata 1.0.0 with the official [jsonata.js v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0) source checkout at commit `8ee4476f8a228bfc7a62979ae0a9c13a4043cd03`. It uses the public compile and evaluate APIs. JavaScript evaluations await the promise returned by `evaluate`; compilations are synchronous in both engines. These are end-to-end API costs in two different runtimes, not a comparison of identical virtual-machine operations.

Both engines read the same generated JSON fixture: 1,000 orders plus a customer. For every case, the driver checks that their JSON results agree before reporting a timing. Compiled expressions are reused for evaluation cases; data creation and process startup are outside the timed section. Each engine runs seven rounds in alternating order, with three warm-up calls per case. Times below are medians and min–max ranges in microseconds per operation. The raw seven-round observations and exact expressions are in [jsonata_js_comparison.json](jsonata_js_comparison.json) and [compare_jsonata.py](../scripts/compare_jsonata.py).

Measured on a Mac16,12 arm64 host with Elixir 1.20.2 / OTP 29 and Node v26.5.0. The laptop was on battery (59%, discharging); low-power mode was off. A ratio above 1 means Jexata was faster; below 1 means jsonata.js was faster. Results are specific to this host, input, runtime versions, and expression mix.

| Workload | Jexata µs med [min–max] | jsonata.js µs med [min–max] | JS − Jexata µs | JS / Jexata | ns/order J / JS |
| --- | ---: | ---: | ---: | ---: | ---: |
| `compile_field` | 0.62 [0.58–0.64] | 12.89 [12.54–13.06] | +12.27 | 20.63× | — |
| `field` | 0.10 [0.10–0.10] | 1.73 [1.11–1.79] | +1.63 | 17.47× | — |
| `filter` | 102.19 [98.51–106.40] | 748.43 [730.44–768.79] | +646.24 | 7.32× | 102.2 / 748.4 |
| `sum` | 34.89 [33.67–35.90] | 148.13 [142.85–149.71] | +113.24 | 4.25× | 34.9 / 148.1 |
| `map_lambda` | 149.25 [140.28–154.71] | 1,202.30 [1,192.16–1,219.84] | +1,053.04 | 8.06× | 149.3 / 1202.3 |
| `reduce_lambda` | 167.65 [159.71–174.65] | 1,221.36 [1,214.46–1,248.68] | +1,053.70 | 7.29× | 167.7 / 1221.4 |
| `sort_comparator` | 1,198.74 [1,148.11–1,251.25] | 9,376.89 [9,319.69–9,944.64] | +8,178.15 | 7.82× | 1198.7 / 9376.9 |
| `group_object` | 140.73 [133.62–144.08] | 711.28 [701.65–726.56] | +570.55 | 5.05× | 140.7 / 711.3 |
| `index_zero` | 0.19 [0.18–0.20] | 1.11 [1.10–1.12] | +0.92 | 5.85× | — |
| `number_decimal` | 505.21 [479.10–522.66] | 1,597.99 [1,574.28–1,638.02] | +1,092.77 | 3.16× | 505.2 / 1598.0 |
| `trim` | 1,713.51 [1,591.51–1,853.02] | 1,665.32 [1,634.38–1,707.24] | -48.20 | 0.97× | 1713.5 / 1665.3 |
| `replace` | 1,955.93 [1,894.79–2,731.28] | 2,213.97 [2,182.26–2,257.08] | +258.04 | 1.13× | 1955.9 / 2214.0 |

Jexata was faster in eleven of twelve cases after the literal-index fast path. JavaScript remains marginally faster on `$trim` in this sample, with overlapping ranges. The large compile and simple-field ratios are tiny absolute differences: 12.27 µs and 1.63 µs per operation. The JS API's promise scheduling is included in evaluation time. The measured empty `await Promise.resolve()` loop had a 0.058 µs median (0.055–0.063), which is a lower bound for one await, not a correction to subtract from full evaluations. This benchmark does not measure throughput under concurrent load, memory use, or application-level request latency.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py \
  --reference /tmp/jexata-reference-2.2.0 \
  --rounds 7 --output docs/jsonata_js_comparison.json
```

The JSON also stores each round's order, CPU model, power-source and low-power settings, Node flags and `NODE_OPTIONS`, the promise-floor samples, absolute time differences, and per-element costs for workloads that process 1,000 orders. The net cost of a built-in cannot be inferred exactly by subtracting `map_lambda`, because the lambda bodies access different fields and do different work.

The comparison driver requires Python 3, Node.js, and the Elixir/OTP versions supported by this project. `jsonata.js` is used only by this development benchmark; Jexata has no JavaScript runtime dependency. Run both engines on the same otherwise idle machine when comparing changes. The driver rejects an unexpected reference commit or a result mismatch.
