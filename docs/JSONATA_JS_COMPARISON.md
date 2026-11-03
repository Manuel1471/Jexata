# Jexata versus jsonata.js

This local benchmark compares Jexata 1.0.0 with the official [jsonata.js v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0) source checkout at commit `8ee4476f8a228bfc7a62979ae0a9c13a4043cd03`. It uses the public compile and evaluate APIs. JavaScript evaluations await the promise returned by `evaluate`; compilations are synchronous in both engines. These are end-to-end API costs in two different runtimes, not a comparison of identical virtual-machine operations.

Both engines read the same generated JSON fixture: 1,000 orders plus a customer. For every case, the driver checks that their JSON results agree before reporting a timing. Compiled expressions are reused for evaluation cases; data creation and process startup are outside the timed section. Each engine runs seven rounds in alternating order, with three warm-up calls per case. Times below are medians and min–max ranges in microseconds per operation. The raw seven-round observations and exact expressions are in [jsonata_js_comparison.json](jsonata_js_comparison.json) and [compare_jsonata.py](../scripts/compare_jsonata.py).

Measured on a Mac16,12 arm64 host with Elixir 1.20.2 / OTP 29 and Node v26.5.0. The laptop was on battery power; low-power mode was off. A ratio above 1 means Jexata was faster; below 1 means jsonata.js was faster. Results are specific to this host, input, runtime versions, and expression mix.

| Workload | Jexata µs med [min–max] | jsonata.js µs med [min–max] | JS − Jexata µs | JS / Jexata | ns/order J / JS |
| --- | ---: | ---: | ---: | ---: | ---: |
| `compile_field` | 0.64 [0.62–0.66] | 13.03 [12.85–13.45] | +12.39 | 20.44× | — |
| `field` | 0.10 [0.10–0.11] | 1.74 [1.08–1.86] | +1.64 | 16.89× | — |
| `filter` | 85.54 [81.45–86.27] | 745.13 [734.95–754.62] | +659.58 | 8.71× | 85.5 / 745.1 |
| `sum` | 34.93 [33.72–36.30] | 145.92 [140.13–149.49] | +110.99 | 4.18× | 34.9 / 145.9 |
| `map_lambda` | 140.66 [137.31–150.82] | 1,201.83 [1,189.06–1,223.01] | +1,061.18 | 8.54× | 140.7 / 1201.8 |
| `reduce_lambda` | 156.57 [151.89–162.13] | 1,211.20 [1,201.02–1,229.23] | +1,054.63 | 7.74× | 156.6 / 1211.2 |
| `sort_comparator` | 1,140.96 [1,120.82–1,165.41] | 9,443.47 [9,340.02–9,637.20] | +8,302.52 | 8.28× | 1141.0 / 9443.5 |
| `group_object` | 139.70 [138.62–146.50] | 706.09 [699.48–721.53] | +566.39 | 5.05× | 139.7 / 706.1 |
| `index_zero` | 0.20 [0.19–0.21] | 1.11 [1.10–1.13] | +0.92 | 5.66× | — |
| `number_decimal` | 486.81 [473.68–493.74] | 1,605.75 [1,600.00–1,629.62] | +1,118.94 | 3.30× | 486.8 / 1605.7 |
| `trim` | 1,697.22 [1,678.06–1,716.94] | 1,674.03 [1,658.29–1,686.12] | -23.20 | 0.99× | 1697.2 / 1674.0 |
| `replace` | 1,964.68 [1,829.92–2,058.22] | 2,235.51 [2,200.75–2,277.83] | +270.83 | 1.14× | 1964.7 / 2235.5 |

Jexata was faster in eleven of twelve cases. The literal-index fast path brings `orders[0].price` to 0.20 µs versus 1.11 µs in JS. `$trim` remains approximately tied on this input, with overlapping ranges. The simple-field ratio represents only 1.64 µs of absolute difference. The JS API's promise scheduling is included in evaluation time. The empty `await Promise.resolve()` loop measured a 0.060 µs median (0.057–0.066); it is a lower bound for one await, not a correction to subtract from full evaluations. This benchmark does not measure throughput under concurrent load, memory use, or application-level request latency.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py \
  --reference /tmp/jexata-reference-2.2.0 \
  --rounds 7 --output docs/jsonata_js_comparison.json
```

The JSON also stores each round's order, CPU model, power-source and low-power settings, Node flags and `NODE_OPTIONS`, the promise-floor samples, absolute time differences, and per-element costs for workloads that process 1,000 orders. The net cost of a built-in cannot be inferred exactly by subtracting `map_lambda`, because the lambda bodies access different fields and do different work.

The comparison driver requires Python 3, Node.js, and the Elixir/OTP versions supported by this project. `jsonata.js` is used only by this development benchmark; Jexata has no JavaScript runtime dependency. Run both engines on the same otherwise idle machine when comparing changes. The driver rejects an unexpected reference commit or a result mismatch.
