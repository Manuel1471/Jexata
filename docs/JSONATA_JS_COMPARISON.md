# Jexata versus jsonata.js

This local benchmark compares Jexata 1.0.0 at commit `daef50e` with the official [jsonata.js v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0) source checkout at commit `8ee4476f8a228bfc7a62979ae0a9c13a4043cd03`. It uses the public compile and evaluate APIs. JavaScript evaluations await the promise returned by `evaluate`; compilations are synchronous in both engines. These are end-to-end API costs in two different runtimes, not a comparison of identical virtual-machine operations.

Both engines read the same generated JSON fixture: 1,000 orders plus a customer. For every case, the driver checks that their JSON results agree before reporting a timing. Compiled expressions are reused for evaluation cases; data creation and process startup are outside the timed section. Each engine runs seven rounds in alternating order, with three warm-up calls per case. Times below are medians and min–max ranges in microseconds per operation. The raw seven-round observations and exact expressions are in [jsonata_js_comparison.json](jsonata_js_comparison.json) and [compare_jsonata.py](../scripts/compare_jsonata.py).

Measured on a Mac16,12 arm64 host with Elixir 1.20.2 / OTP 29 and Node v26.5.0. The laptop was connected to AC power; low-power mode was off. A ratio above 1 means Jexata was faster; below 1 means jsonata.js was faster. Results are specific to this host, input, runtime versions, and expression mix.

| Workload | Jexata µs med [min–max] | jsonata.js µs med [min–max] | JS − Jexata µs | JS / Jexata | ns/order J / JS |
| --- | ---: | ---: | ---: | ---: | ---: |
| `compile_field` | 0.61 [0.60–0.64] | 13.09 [12.98–13.63] | +12.48 | 21.37× | — |
| `field` | 0.10 [0.10–0.10] | 1.78 [1.74–1.88] | +1.67 | 17.46× | — |
| `filter` | 83.63 [81.64–84.98] | 756.98 [746.92–790.50] | +673.35 | 9.05× | 83.6 / 757.0 |
| `sum` | 34.35 [33.53–35.74] | 148.40 [144.09–156.31] | +114.06 | 4.32× | 34.3 / 148.4 |
| `map_lambda` | 138.11 [134.25–143.45] | 1,232.07 [1,218.16–1,256.57] | +1,093.95 | 8.92× | 138.1 / 1232.1 |
| `reduce_lambda` | 156.69 [152.17–159.75] | 1,240.22 [1,214.85–1,290.51] | +1,083.53 | 7.92× | 156.7 / 1240.2 |
| `sort_comparator` | 1,144.09 [1,125.24–1,165.66] | 9,585.27 [9,465.05–9,860.94] | +8,441.18 | 8.38× | 1144.1 / 9585.3 |
| `group_object` | 140.48 [138.13–144.31] | 717.99 [709.77–739.83] | +577.50 | 5.11× | 140.5 / 718.0 |
| `index_zero` | 0.19 [0.18–0.22] | 1.11 [1.08–1.16] | +0.92 | 5.77× | — |
| `number_decimal` | 485.21 [472.36–497.44] | 1,640.75 [1,617.65–1,679.91] | +1,155.54 | 3.38× | 485.2 / 1640.8 |
| `trim` | 1,691.18 [1,592.86–1,701.54] | 1,688.57 [1,671.04–1,749.56] | -2.60 | 1.00× | 1691.2 / 1688.6 |
| `replace` | 668.35 [636.03–684.38] | 2,230.74 [2,223.74–2,293.46] | +1,562.39 | 3.34× | 668.3 / 2230.7 |

Jexata had a lower median in eleven of twelve cases. The literal-index fast path brings `orders[0].price` to 0.19 µs versus 1.11 µs in JS. Resolved `$replace` with a plain `/Order/` regex takes 668.35 µs versus 2,230.74 µs in JS for 1,000 items. `$trim` is approximately tied on this input. The simple-field ratio represents only 1.67 µs of absolute difference. The JS API's promise scheduling is included in evaluation time. The empty `await Promise.resolve()` loop measured a 0.060 µs median (0.055–0.068); it is a lower bound for one await, not a correction to subtract from full evaluations. This benchmark does not measure throughput under concurrent load, memory use, or application-level request latency.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py \
  --reference /tmp/jexata-reference-2.2.0 \
  --rounds 7 --output docs/jsonata_js_comparison.json
```

The JSON also stores each round's order, CPU model, power-source and low-power settings, Node flags and `NODE_OPTIONS`, the promise-floor samples, absolute time differences, and per-element costs for workloads that process 1,000 orders. The net cost of a built-in cannot be inferred exactly by subtracting `map_lambda`, because the lambda bodies access different fields and do different work.

The comparison driver requires Python 3, Node.js, and the Elixir/OTP versions supported by this project. `jsonata.js` is used only by this development benchmark; Jexata has no JavaScript runtime dependency. Run both engines on the same otherwise idle machine when comparing changes. The driver rejects an unexpected reference commit or a result mismatch.
