# Jexata versus jsonata.js

This local benchmark compares Jexata 1.0.0 at commit `3c2c356` with the official [jsonata.js v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0) source checkout at commit `8ee4476f8a228bfc7a62979ae0a9c13a4043cd03`. It uses the public compile and evaluate APIs. JavaScript evaluations await the promise returned by `evaluate`; compilations are synchronous in both engines. These are end-to-end API costs in two different runtimes, not a comparison of identical virtual-machine operations.

Both engines read the same generated JSON fixture: 1,000 orders plus a customer. For every case, the driver checks that their JSON results agree before reporting a timing. Compiled expressions are reused for evaluation cases; data creation and process startup are outside the timed section. Each engine runs seven rounds in alternating order, with three warm-up calls per case. Times below are medians and min–max ranges in microseconds per operation. The raw seven-round observations and exact expressions are in [jsonata_js_comparison.json](jsonata_js_comparison.json) and [compare_jsonata.py](../scripts/compare_jsonata.py).

Measured on a Mac16,12 arm64 host with Elixir 1.20.2 / OTP 29 and Node v26.5.0. The laptop was on battery power (78% at metadata capture); low-power mode was off. A ratio above 1 means Jexata was faster; below 1 means jsonata.js was faster. Results are specific to this host, power state, input, runtime versions, and expression mix.

| Workload | Jexata µs med [min–max] | jsonata.js µs med [min–max] | JS − Jexata µs | JS / Jexata | ns/order J / JS |
| --- | ---: | ---: | ---: | ---: | ---: |
| `compile_field` | 0.63 [0.57–0.64] | 12.90 [12.70–13.62] | +12.27 | 20.42× | — |
| `field` | 0.10 [0.10–0.11] | 1.76 [1.73–2.02] | +1.66 | 17.58× | — |
| `filter` | 83.20 [78.45–85.61] | 760.39 [742.90–774.20] | +677.19 | 9.14× | 83.2 / 760.4 |
| `sum` | 35.00 [33.44–35.46] | 149.62 [141.39–155.53] | +114.62 | 4.27× | 35.0 / 149.6 |
| `map_lambda` | 142.98 [136.78–147.40] | 1,225.23 [1,179.47–1,241.20] | +1,082.25 | 8.57× | 143.0 / 1225.2 |
| `reduce_lambda` | 162.61 [155.50–168.58] | 1,238.08 [1,235.90–1,280.14] | +1,075.47 | 7.61× | 162.6 / 1238.1 |
| `sort_comparator` | 1,207.76 [1,144.38–1,227.90] | 9,560.42 [9,387.04–10,709.50] | +8,352.66 | 7.92× | 1207.8 / 9560.4 |
| `group_object` | 140.35 [131.80–143.90] | 714.81 [704.24–744.95] | +574.46 | 5.09× | 140.4 / 714.8 |
| `index_zero` | 0.19 [0.17–0.21] | 1.11 [1.07–1.13] | +0.92 | 5.90× | — |
| `number_decimal` | 493.90 [467.58–509.45] | 1,623.05 [1,574.54–1,667.37] | +1,129.15 | 3.29× | 493.9 / 1623.0 |
| `trim` | 1,690.43 [1,584.30–1,747.28] | 1,671.55 [1,616.93–1,730.47] | -18.88 | 0.99× | 1690.4 / 1671.6 |
| `replace` | 663.29 [638.71–680.85] | 2,214.14 [2,182.25–2,252.08] | +1,550.85 | 3.34× | 663.3 / 2214.1 |

Jexata had a lower median in eleven of twelve cases. The literal-index path brings `orders[0].price` to 0.19 µs versus 1.11 µs in JS. Resolved `$replace` with a plain `/Order/` regex takes 663.29 µs versus 2,214.14 µs in JS for 1,000 items. `$trim` is approximately tied on this input; its 18.88 µs difference is small relative to the observed ranges. The simple-field ratio represents only 1.66 µs of absolute difference. The JS API's promise scheduling is included in evaluation time. The empty `await Promise.resolve()` loop measured a 0.063 µs median (0.055–0.069); it is a lower bound for one await, not a correction to subtract from full evaluations. This benchmark does not measure throughput under concurrent load, memory use, or application-level request latency.

## Behavioral differences

The benchmark verifies identical JSON results for its 12 expressions before measuring. Separately, the [full JSONata v2.2.0 reference fixture check](COMPATIBILITY.md) reports **1,676 matches out of 1,679**, with no unsupported or skipped fixture cases. The three mismatches all involve `$keys(%)` returning keys of an input object: jsonata.js retains the object's source order, whereas Jexata receives an Elixir map that has already lost that order. The [differential fuzzer](differential_fuzz_results.json) also found no mismatches in 1,000 generated expressions with seed `20261103`; its grammar is narrower than the language.

Jexata does not implement `$random` or `$clone`, although jsonata.js v2.2.0 registers them. The reference fixtures do not cover these functions. Jexata also applies its [documented resource limits](COMPATIBILITY.md), which may reject very large or expensive expressions accepted by the JS reference. These facts limit any claim of full equivalence; the numbers above describe the specified fixture and workload only.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py \
  --reference /tmp/jexata-reference-2.2.0 \
  --rounds 7 --output docs/jsonata_js_comparison.json
```

The JSON also stores each round's order, CPU model, power-source and low-power settings, Node flags and `NODE_OPTIONS`, the promise-floor samples, absolute time differences, and per-element costs for workloads that process 1,000 orders. The net cost of a built-in cannot be inferred exactly by subtracting `map_lambda`, because the lambda bodies access different fields and do different work.

The comparison driver requires Python 3, Node.js, and the Elixir/OTP versions supported by this project. `jsonata.js` is used only by this development benchmark; Jexata has no JavaScript runtime dependency. Run both engines on the same otherwise idle machine when comparing changes. The driver rejects an unexpected reference commit or a result mismatch.
