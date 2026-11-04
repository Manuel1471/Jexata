# Jexata versus jsonata.js

This comparison uses Jexata 1.0.0 and the official [jsonata.js v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0). The exact reference revision and release metadata are recorded in the raw results. The harness exercises the public compile and evaluate APIs. JavaScript evaluations await the promise returned by `evaluate`. These are API costs in different runtimes, not identical virtual-machine operations.

## Method

The fixture contains 1,000 orders and a customer. The 64 named expressions cover compilation, scalar expressions, paths and predicates, aggregates, collections, higher-order functions, numeric and string functions, regex, and date/time. Every case has a fixed expression and iteration count recorded in [raw results](jsonata_js_comparison.json). Compiled expressions are reused for evaluation. Each engine gets three warm-up calls per case. Seven rounds alternate engine order; startup and data generation are outside the timed section. A case gets a timing ratio only when both engines return the same JSON result in **every** round. A stable SHA-256 digest of each matching result is recorded in the JSON.

The run used a Mac16,12 arm64 host, Elixir 1.20.2 / OTP 29, and Node v26.5.0. The laptop was on battery power (100% when metadata was captured) with low-power mode off. Times are medians with min–max ranges in µs per operation. **JS / Jexata above 1 means Jexata's median was lower.** The ratio reflects this machine, input and API usage. Short scalar cases include JavaScript promise overhead; the measured median of an empty `await Promise.resolve()` was recorded in the JSON and must not be subtracted as if it were the entire evaluation overhead.

<!-- BEGIN GENERATED RESULTS -->
**64 expressions:** 63 matching results; 1 mismatch excluded from timing ratios.

| Category | Matching cases | Lower Jexata median | Lower JS median |
| --- | ---: | ---: | ---: |
| Compilation | 6 | 6 | 0 |
| Scalar expressions | 6 | 6 | 0 |
| Paths and predicates | 11 | 10 | 1 |
| Aggregates and grouping | 7 | 7 | 0 |
| Collections and sorting | 5 | 5 | 0 |
| Higher-order functions | 6 | 6 | 0 |
| Numeric functions | 5 | 5 | 0 |
| String functions | 8 | 7 | 1 |
| Regular expressions | 6 | 6 | 0 |
| Date and time | 3 | 3 | 0 |

### Compilation

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `compile_field` | `customer.name` | 0.63 [0.61–0.66] | 13.06 [12.80–13.83] | 20.59× |
| `compile_filter` | `orders[price > 50].price` | 2.79 [2.65–2.84] | 21.37 [21.02–24.39] | 7.65× |
| `compile_lambda` | `$map(orders,function($o){$o.price*2})` | 4.28 [4.08–4.38] | 24.98 [24.20–41.52] | 5.84× |
| `compile_object` | `orders{customer:$sum(price)}` | 2.08 [2.05–2.13] | 19.19 [18.81–20.60] | 9.20× |
| `compile_picture` | `$fromMillis(1704164645000,'[Y0001]-[M01]-[D01]')` | 2.81 [2.72–2.97] | 17.37 [17.09–18.50] | 6.17× |
| `compile_regex` | `$replace(text,/Order/,'Item')` | 4.13 [4.02–4.47] | 14.99 [14.42–35.85] | 3.63× |

### Scalar expressions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `arithmetic` | `(12 + 8) * 3 / 2` | 0.14 [0.13–0.16] | 2.41 [2.29–2.55] | 16.99× |
| `coalesce` | `customer.missing ?? 'unknown'` | 0.14 [0.14–0.16] | 2.04 [2.01–2.08] | 14.09× |
| `concat` | `customer.name & ' Lovelace'` | 0.29 [0.27–0.31] | 1.42 [1.40–1.48] | 4.95× |
| `conditional` | `customer.name = 'Ada' ? 'yes' : 'no'` | 0.16 [0.16–0.17] | 1.69 [1.66–1.80] | 10.27× |
| `field` | `customer.name` | 0.11 [0.10–0.12] | 1.35 [1.33–1.39] | 11.81× |
| `missing_field` | `customer.missing` | 0.13 [0.13–0.14] | 1.00 [0.97–1.16] | 7.48× |

### Paths and predicates

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `descendants` | `customer.**` | 0.16 [0.15–0.17] | 1.51 [1.49–1.54] | 9.32× |
| `filter` | `orders[price > 50].price` | 108.78 [106.42–110.68] | 791.13 [779.72–821.96] | 7.27× |
| `filter_boolean` | `orders[active].price` | 57.15 [56.23–61.30] | 456.81 [451.76–472.75] | 7.99× |
| `filter_narrow` | `orders[price > 900].price` | 57.84 [55.26–61.35] | 668.78 [662.03–693.21] | 11.56× |
| `focus_binding` | `orders@$o[$o.price > 900].price` | 160.19 [153.76–167.93] | 1,159.64 [1,141.82–1,202.16] | 7.24× |
| `index_binding` | `orders#$i[$i < 10].price` | 98.46 [91.69–103.54] | 557.48 [543.35–585.81] | 5.66× |
| `index_last` | `orders[-1].price` | 1.42 [1.31–1.49] | 1.03 [1.00–1.08] | 0.72× |
| `index_zero` | `orders[0].price` | 0.15 [0.14–0.16] | 1.04 [1.03–1.12] | 7.11× |
| `order_projection` | `orders[0].(price & ':' & customer)` | 0.61 [0.56–0.66] | 3.24 [3.21–3.29] | 5.29× |
| `path_customers` | `orders.customer` | 38.14 [36.26–62.77] | 126.72 [124.16–138.89] | 3.32× |
| `path_prices` | `orders.price` | 56.22 [54.80–57.22] | 142.89 [139.71–154.64] | 2.54× |

### Aggregates and grouping

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `average` | `$average(orders.price)` | 50.37 [47.87–52.61] | 159.29 [156.79–171.33] | 3.16× |
| `count` | `$count(orders.price)` | 48.54 [45.28–51.21] | 133.13 [132.30–139.76] | 2.74× |
| `distinct` | `$distinct(orders.customer)` | 67.22 [66.06–73.37] | 157.36 [155.76–161.55] | 2.34× |
| `group_object` | `orders{customer:$sum(price)}` | 161.79 [158.93–165.14] | 725.53 [713.20–746.41] | 4.48× |
| `max` | `$max(orders.price)` | 49.94 [46.31–54.50] | 145.03 [143.53–151.54] | 2.90× |
| `min` | `$min(orders.price)` | 49.01 [47.10–54.66] | 146.86 [146.12–154.04] | 3.00× |
| `sum` | `$sum(orders.price)` | 49.05 [46.75–52.30] | 154.09 [152.97–160.00] | 3.14× |

### Collections and sorting

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `append` | `$append(orders.price,[1001])` | 60.19 [57.53–61.95] | 137.55 [135.15–142.97] | 2.29× |
| `reverse` | `$reverse(orders.price)` | 59.66 [58.93–64.15] | 136.36 [132.55–142.76] | 2.29× |
| `sort_comparator` | `$sort(orders,function($a,$b){$a.price>$b.price})` | 1,403.49 [1,387.14–1,462.48] | 9,937.59 [9,592.16–10,784.88] | 7.08× |
| `sort_key` | `orders^(price)` | 210.68 [199.04–233.01] | 4,822.86 [4,804.15–5,038.72] | 22.89× |
| `zip` | `$zip(orders.price,orders.customer)` | 140.50 [138.09–143.10] | 289.10 [281.86–305.58] | 2.06× |

### Higher-order functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `each_object` | `$each(customer,function($value,$key){$key & ':' & $value})` | 0.76 [0.71–0.81] | 3.07 [3.01–3.14] | 4.06× |
| `filter_lambda` | `$filter(orders,function($o){$o.price>900})` | 148.41 [145.59–157.41] | 1,273.15 [1,234.54–1,305.05] | 8.58× |
| `map_index` | `$map(orders,function($o,$i){$o.price+$i})` | 195.42 [194.00–203.87] | 1,330.51 [1,281.31–1,350.28] | 6.81× |
| `map_lambda` | `$map(orders,function($o){$o.price*2})` | 156.68 [154.67–158.16] | 1,276.82 [1,237.44–1,306.36] | 8.15× |
| `reduce_lambda` | `$reduce(orders,function($a,$o){$a+$o.price},0)` | 181.06 [179.56–191.34] | 1,316.60 [1,289.98–1,338.10] | 7.27× |
| `sift_object` | `$sift(customer,function($value,$key){$key='name'})` | 0.53 [0.47–0.55] | 2.66 [2.59–2.74] | 5.04× |

### Numeric functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `floor` | `$map(orders,function($o){$floor($o.price / 3)})` | 355.24 [351.82–362.62] | 1,902.55 [1,845.04–2,061.38] | 5.36× |
| `format_integer` | `$map(orders,function($o){$formatInteger($o.price,'I')})` | 836.47 [813.84–849.62] | 1,869.35 [1,705.14–1,935.48] | 2.23× |
| `format_number` | `$map(orders,function($o){$formatNumber($o.price,'#,##0')})` | 261.85 [250.53–277.76] | 3,646.06 [3,429.11–3,745.85] | 13.92× |
| `number_decimal` | `$map(orders,function($o){$number($o.decimal)})` | 508.46 [500.04–529.07] | 1,683.60 [1,640.44–1,710.33] | 3.31× |
| `round` | `$map(orders,function($o){$round($o.price / 3,2)})` | 1,072.94 [1,064.51–1,169.87] | 2,321.28 [2,272.59–2,601.13] | 2.16× |

### String functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `contains_text` | `$map(orders,function($o){$contains($o.text,'Order')})` | 472.78 [460.04–487.29] | 1,777.26 [1,603.59–1,854.91] | 3.76× |
| `length` | `$map(orders,function($o){$length($o.text)})` | 305.97 [295.88–319.83] | 1,694.71 [1,434.91–1,787.51] | 5.54× |
| `lowercase` | `$map(orders,function($o){$lowercase($o.text)})` | 398.52 [390.71–423.82] | 1,546.98 [1,400.66–1,596.50] | 3.88× |
| `pad` | `$map(orders,function($o){$pad($o.text,20,'-')})` | 520.61 [494.95–532.96] | 2,006.02 [1,866.80–2,089.23] | 3.85× |
| `split_text` | `$map(orders,function($o){$split($o.text,' ')})` | 452.97 [442.19–480.24] | 1,925.89 [1,790.39–9,281.26] | 4.25× |
| `substring` | `$map(orders,function($o){$substring($o.text,0,5)})` | 318.68 [304.42–332.08] | 2,007.40 [1,877.74–2,127.00] | 6.30× |
| `trim` | `$map(orders,function($o){$trim($o.padded)})` | 1,734.87 [1,638.55–2,092.29] | 1,702.43 [1,532.71–1,735.15] | 0.98× |
| `uppercase` | `$map(orders,function($o){$uppercase($o.text)})` | 390.19 [381.91–415.29] | 1,578.79 [1,407.55–1,648.16] | 4.05× |

### Regular expressions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `contains_regex` | `$map(orders,function($o){$contains($o.text,/Order/)})` | 482.98 [466.52–507.16] | 1,987.46 [1,857.00–2,085.21] | 4.12× |
| `match_regex` | `$map(orders,function($o){$match($o.text,/Order/)})` | 1,071.39 [1,055.08–1,083.12] | 2,151.68 [2,097.78–4,760.55] | 2.01× |
| `match_scalar` | `$match(orders[0].text,/Order/).match` | 1.25 [1.07–1.40] | 3.48 [3.35–3.76] | 2.78× |
| `replace` | `$map(orders,function($o){$replace($o.text,/Order/,'Item')})` | 698.75 [666.92–718.68] | 2,267.56 [2,098.40–2,361.72] | 3.25× |
| `replace_capture` | `$map(orders,function($o){$replace($o.text,/(Order) (\d+)/,'$2 $1')})` | 2,161.82 [2,092.48–2,531.50] | 2,351.43 [2,207.28–4,674.12] | 1.09× |
| `split_regex` | `$map(orders,function($o){$split($o.text,/\s+/)})` | 1,305.03 [1,271.58–1,330.31] | 2,257.39 [2,117.62–5,181.05] | 1.73× |

### Date and time

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `from_millis` | `$map(orders,function($o){$fromMillis($o.epoch)})` | 598.47 [587.03–626.25] | 2,142.00 [2,029.33–2,201.86] | 3.58× |
| `from_millis_picture` | `$map(orders,function($o){$fromMillis($o.epoch,'[Y0001]-[M01]-[D01]')})` | 467.01 [457.13–512.01] | 2,643.58 [2,489.96–2,771.09] | 5.66× |
| `to_millis` | `$map(orders,function($o){$toMillis($o.date)})` | 392.91 [387.21–428.98] | 1,697.48 [1,573.61–1,808.33] | 4.32× |

<!-- END GENERATED RESULTS -->

## Observed differences

One of 64 expressions returned a different result and has **no timing ratio**:

| Case | Expression | Jexata | jsonata.js |
| --- | --- | --- | --- |
| `wildcard_order` | `orders[0].*` | Same eight values, ordered by the native Elixir map | Values ordered by the source JSON object |

The remaining difference is another form of the input-object key-order limitation. The `$match`-inside-`$map` case now agrees, including its nested array shape. The order mismatch is additional to the **three** `$keys(%)` failures in the [1,679-case reference fixture suite](COMPATIBILITY.md). The reference fixtures report 1,676 passes, zero unsupported and zero skipped cases. The expanded [differential fuzzer](differential_fuzz_results.json) ran 20,000 cases with one known difference and no unexpected mismatches; its grammar remains narrower than the full language. Jexata now provides `$random` and `$clone`, but these functions are not covered by the official fixtures or the timed workloads in this report.

Among the 63 matching cases, Jexata had a lower median in 61 and JSONata.js in two. The negative index path is the clearest JS advantage. `$trim` has overlapping timing ranges, and `$replace` with captures now has a slightly lower Jexata median with overlapping ranges; neither small difference is a general speed claim. `$round` with precision, the canonical `$fromMillis` date picture, and grouped integer `$formatNumber` have lower Jexata medians on the recorded 1,000-order workloads. Timing ranges and exact expressions are in the tables above. These ratios are specific to the host and API usage; they do not measure concurrent throughput, memory consumption or end-to-end request latency.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py \
  --reference /tmp/jexata-reference-2.2.0 \
  --rounds 7 --output docs/jsonata_js_comparison.json
python3 scripts/render_jsonata_comparison.py
```

The driver verifies the reference version, records every round and its engine order, checks that results are stable across rounds, and separates mismatches from comparable workloads. The raw file also records CPU and power metadata, Node flags, an empty-promise floor, exact expressions, iteration counts, result digests and the fixture digest. The benchmark needs Python 3, Node.js and Elixir for development; Jexata itself has no production JavaScript dependency.
