# Jexata versus jsonata.js

This local benchmark compares Jexata 1.0.0 with the official [jsonata.js v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0) source checkout at commit `8ee4476f8a228bfc7a62979ae0a9c13a4043cd03`. It uses the public compile and evaluate APIs. JavaScript evaluations await the promise returned by `evaluate`; compilations are synchronous in both engines. These are end-to-end API costs in two different runtimes, not a comparison of identical virtual-machine operations.

Both engines read the same generated JSON fixture: 1,000 orders plus a customer. For every case, the driver checks that their JSON results agree before reporting a timing. Compiled expressions are reused for evaluation cases; data creation and process startup are outside the timed section. Each engine runs five rounds in alternating order, with three warm-up calls per case. Times below are medians and min–max ranges in microseconds per operation. The raw five-round observations and exact expressions are in [jsonata_js_comparison.json](jsonata_js_comparison.json) and [compare_jsonata.py](../scripts/compare_jsonata.py).

Measured on the same Mac16,12 arm64 host with Elixir 1.20.2 / OTP 29 and Node v26.5.0. A ratio above 1 means Jexata was faster; below 1 means jsonata.js was faster. Results are specific to this host, input, runtime versions, and expression mix.

| Workload | Jexata µs med [min–max] | jsonata.js µs med [min–max] | JS / Jexata |
| --- | ---: | ---: | ---: |
| `compile_field` | 0.63 [0.63–0.67] | 13.55 [12.58–14.04] | 21.53× |
| `field` | 0.10 [0.09–0.10] | 1.87 [1.59–2.54] | 19.02× |
| `filter` | 104.14 [101.12–105.36] | 790.55 [747.08–848.69] | 7.59× |
| `sum` | 34.76 [33.93–36.65] | 150.94 [143.72–153.04] | 4.34× |
| `map_lambda` | 149.65 [144.70–150.37] | 1,249.23 [1,213.23–1,275.60] | 8.35× |
| `reduce_lambda` | 165.54 [163.24–165.96] | 1,268.53 [1,211.10–1,300.92] | 7.66× |
| `sort_comparator` | 1,190.12 [1,172.54–1,208.41] | 9,853.37 [9,521.75–11,144.24] | 8.28× |
| `group_object` | 138.77 [136.88–139.79] | 725.77 [700.73–760.86] | 5.23× |
| `index_zero` | 7.77 [7.63–7.93] | 1.13 [1.11–1.55] | 0.15× |
| `number_decimal` | 490.69 [475.83–497.97] | 1,712.98 [1,640.86–1,892.36] | 3.49× |
| `trim` | 1,686.27 [1,670.34–2,024.04] | 1,679.07 [1,616.86–2,351.57] | 1.00× |
| `replace` | 1,989.21 [1,876.37–2,219.85] | 2,330.11 [2,239.13–2,590.60] | 1.17× |

Jexata was faster in ten of twelve cases. JavaScript was about 6.9× faster on `orders[0].price`; `$trim` was effectively tied at this resolution. The large compile and simple-field ratios should be read as tiny absolute differences: about 13 µs and 1.8 µs per operation, respectively. The JS API's promise scheduling is included in evaluation time. This benchmark does not measure throughput under concurrent load, memory use, or application-level request latency.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py \
  --reference /tmp/jexata-reference-2.2.0 \
  --rounds 5 --output docs/jsonata_js_comparison.json
```

The comparison driver requires Python 3, Node.js, and the Elixir/OTP versions supported by this project. `jsonata.js` is used only by this development benchmark; Jexata has no JavaScript runtime dependency. Run both engines on the same otherwise idle machine when comparing changes. The driver rejects an unexpected reference commit or a result mismatch.
