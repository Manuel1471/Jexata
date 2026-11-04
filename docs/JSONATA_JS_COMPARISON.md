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
| Regular expressions | 6 | 5 | 1 |
| Date and time | 3 | 3 | 0 |

### Compilation

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `compile_field` | `customer.name` | 0.63 [0.62–0.63] | 12.95 [12.72–13.27] | 20.70× |
| `compile_filter` | `orders[price > 50].price` | 2.80 [2.62–2.85] | 21.55 [21.31–22.09] | 7.69× |
| `compile_lambda` | `$map(orders,function($o){$o.price*2})` | 4.25 [4.17–4.36] | 26.96 [24.25–29.83] | 6.35× |
| `compile_object` | `orders{customer:$sum(price)}` | 2.08 [2.04–2.21] | 19.14 [18.99–23.91] | 9.21× |
| `compile_picture` | `$fromMillis(1704164645000,'[Y0001]-[M01]-[D01]')` | 2.81 [2.61–2.91] | 17.42 [16.90–17.68] | 6.20× |
| `compile_regex` | `$replace(text,/Order/,'Item')` | 4.26 [4.08–4.44] | 14.70 [14.60–15.32] | 3.45× |

### Scalar expressions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `arithmetic` | `(12 + 8) * 3 / 2` | 0.14 [0.13–0.15] | 2.33 [2.30–2.60] | 16.51× |
| `coalesce` | `customer.missing ?? 'unknown'` | 0.15 [0.13–0.15] | 2.05 [2.03–2.25] | 14.01× |
| `concat` | `customer.name & ' Lovelace'` | 0.27 [0.25–0.30] | 1.44 [1.40–1.57] | 5.27× |
| `conditional` | `customer.name = 'Ada' ? 'yes' : 'no'` | 0.16 [0.15–0.17] | 1.68 [1.65–1.72] | 10.25× |
| `field` | `customer.name` | 0.11 [0.10–0.12] | 1.35 [1.30–1.57] | 12.23× |
| `missing_field` | `customer.missing` | 0.14 [0.12–0.14] | 0.99 [0.97–0.99] | 7.29× |

### Paths and predicates

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `descendants` | `customer.**` | 0.15 [0.14–0.17] | 1.50 [1.46–1.54] | 9.71× |
| `filter` | `orders[price > 50].price` | 107.85 [104.26–111.54] | 785.88 [775.46–812.00] | 7.29× |
| `filter_boolean` | `orders[active].price` | 56.17 [54.98–57.71] | 455.19 [450.14–470.83] | 8.10× |
| `filter_narrow` | `orders[price > 900].price` | 57.81 [55.40–63.89] | 669.50 [665.11–688.61] | 11.58× |
| `focus_binding` | `orders@$o[$o.price > 900].price` | 158.88 [150.84–165.25] | 1,144.35 [1,134.06–1,197.80] | 7.20× |
| `index_binding` | `orders#$i[$i < 10].price` | 98.95 [94.69–103.26] | 554.75 [547.59–570.35] | 5.61× |
| `index_last` | `orders[-1].price` | 1.41 [1.30–1.45] | 1.01 [0.99–1.04] | 0.72× |
| `index_zero` | `orders[0].price` | 0.14 [0.14–0.16] | 1.05 [1.03–1.08] | 7.32× |
| `order_projection` | `orders[0].(price & ':' & customer)` | 0.61 [0.58–0.67] | 3.24 [3.20–3.35] | 5.33× |
| `path_customers` | `orders.customer` | 37.79 [34.36–38.54] | 127.70 [123.16–135.18] | 3.38× |
| `path_prices` | `orders.price` | 55.47 [53.89–57.60] | 140.57 [139.58–151.61] | 2.53× |

### Aggregates and grouping

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `average` | `$average(orders.price)` | 48.51 [46.02–51.26] | 159.79 [153.97–162.98] | 3.29× |
| `count` | `$count(orders.price)` | 47.58 [45.59–50.24] | 134.84 [131.60–138.34] | 2.83× |
| `distinct` | `$distinct(orders.customer)` | 66.56 [63.82–67.86] | 157.35 [155.54–161.79] | 2.36× |
| `group_object` | `orders{customer:$sum(price)}` | 160.11 [156.10–166.16] | 722.39 [712.03–730.46] | 4.51× |
| `max` | `$max(orders.price)` | 48.38 [47.69–51.09] | 147.87 [144.30–151.01] | 3.06× |
| `min` | `$min(orders.price)` | 48.66 [47.61–50.97] | 149.04 [145.29–158.81] | 3.06× |
| `sum` | `$sum(orders.price)` | 48.16 [46.93–49.92] | 155.04 [151.52–159.45] | 3.22× |

### Collections and sorting

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `append` | `$append(orders.price,[1001])` | 58.46 [57.38–60.65] | 139.46 [138.18–144.02] | 2.39× |
| `reverse` | `$reverse(orders.price)` | 58.06 [57.20–60.75] | 136.76 [134.02–139.94] | 2.36× |
| `sort_comparator` | `$sort(orders,function($a,$b){$a.price>$b.price})` | 1,392.49 [1,364.14–1,448.00] | 9,976.10 [9,594.63–10,134.70] | 7.16× |
| `sort_key` | `orders^(price)` | 208.68 [196.29–220.81] | 4,829.93 [4,776.93–5,022.77] | 23.14× |
| `zip` | `$zip(orders.price,orders.customer)` | 141.09 [139.03–146.23] | 294.65 [288.45–302.47] | 2.09× |

### Higher-order functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `each_object` | `$each(customer,function($value,$key){$key & ':' & $value})` | 0.75 [0.72–0.85] | 3.03 [3.01–3.04] | 4.04× |
| `filter_lambda` | `$filter(orders,function($o){$o.price>900})` | 146.78 [142.05–156.23] | 1,260.06 [1,251.54–1,374.79] | 8.58× |
| `map_index` | `$map(orders,function($o,$i){$o.price+$i})` | 195.95 [192.34–205.32] | 1,302.16 [1,292.72–1,328.06] | 6.65× |
| `map_lambda` | `$map(orders,function($o){$o.price*2})` | 156.11 [150.32–160.96] | 1,264.74 [1,236.10–1,287.71] | 8.10× |
| `reduce_lambda` | `$reduce(orders,function($a,$o){$a+$o.price},0)` | 179.34 [178.13–187.38] | 1,312.57 [1,290.00–1,341.68] | 7.32× |
| `sift_object` | `$sift(customer,function($value,$key){$key='name'})` | 0.53 [0.49–0.56] | 2.64 [2.59–2.75] | 5.00× |

### Numeric functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `floor` | `$map(orders,function($o){$floor($o.price / 3)})` | 357.06 [351.95–371.64] | 1,906.48 [1,859.72–1,953.58] | 5.34× |
| `format_integer` | `$map(orders,function($o){$formatInteger($o.price,'I')})` | 813.46 [789.81–838.49] | 1,893.32 [1,875.25–2,130.40] | 2.33× |
| `format_number` | `$map(orders,function($o){$formatNumber($o.price,'#,##0')})` | 267.62 [259.80–282.02] | 3,439.26 [3,382.80–3,774.78] | 12.85× |
| `number_decimal` | `$map(orders,function($o){$number($o.decimal)})` | 511.56 [509.52–530.72] | 1,669.54 [1,646.25–2,046.72] | 3.26× |
| `round` | `$map(orders,function($o){$round($o.price / 3,2)})` | 1,387.31 [1,318.57–1,449.18] | 2,333.44 [2,280.54–2,385.97] | 1.68× |

### String functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `contains_text` | `$map(orders,function($o){$contains($o.text,'Order')})` | 468.71 [452.09–475.67] | 1,782.78 [1,671.02–1,831.79] | 3.80× |
| `length` | `$map(orders,function($o){$length($o.text)})` | 302.96 [292.79–317.46] | 1,643.76 [1,506.76–1,760.30] | 5.43× |
| `lowercase` | `$map(orders,function($o){$lowercase($o.text)})` | 391.40 [382.93–407.07] | 1,541.98 [1,440.72–1,576.10] | 3.94× |
| `pad` | `$map(orders,function($o){$pad($o.text,20,'-')})` | 512.79 [481.02–527.39] | 2,012.40 [1,907.31–2,048.66] | 3.92× |
| `split_text` | `$map(orders,function($o){$split($o.text,' ')})` | 450.30 [440.23–480.05] | 1,839.23 [1,780.28–1,926.69] | 4.08× |
| `substring` | `$map(orders,function($o){$substring($o.text,0,5)})` | 315.54 [309.62–323.23] | 2,075.83 [2,011.61–2,154.55] | 6.58× |
| `trim` | `$map(orders,function($o){$trim($o.padded)})` | 1,707.78 [1,622.88–1,728.30] | 1,694.55 [1,555.68–1,739.83] | 0.99× |
| `uppercase` | `$map(orders,function($o){$uppercase($o.text)})` | 385.71 [373.61–402.25] | 1,611.90 [1,425.39–1,675.43] | 4.18× |

### Regular expressions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `contains_regex` | `$map(orders,function($o){$contains($o.text,/Order/)})` | 472.37 [468.92–501.61] | 1,975.27 [1,873.21–2,047.49] | 4.18× |
| `match_regex` | `$map(orders,function($o){$match($o.text,/Order/)})` | 1,068.38 [1,034.77–1,128.01] | 2,091.59 [1,988.27–4,195.83] | 1.96× |
| `match_scalar` | `$match(orders[0].text,/Order/).match` | 1.24 [1.21–1.36] | 3.51 [3.40–4.37] | 2.82× |
| `replace` | `$map(orders,function($o){$replace($o.text,/Order/,'Item')})` | 689.15 [666.39–714.95] | 2,251.69 [2,152.74–2,306.48] | 3.27× |
| `replace_capture` | `$map(orders,function($o){$replace($o.text,/(Order) (\d+)/,'$2 $1')})` | 3,041.19 [3,008.70–3,185.33] | 2,271.18 [2,198.22–2,340.58] | 0.75× |
| `split_regex` | `$map(orders,function($o){$split($o.text,/\s+/)})` | 1,307.59 [1,267.84–1,366.01] | 2,159.71 [2,066.26–2,643.53] | 1.65× |

### Date and time

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `from_millis` | `$map(orders,function($o){$fromMillis($o.epoch)})` | 586.91 [581.68–591.25] | 2,065.32 [2,011.66–2,179.55] | 3.52× |
| `from_millis_picture` | `$map(orders,function($o){$fromMillis($o.epoch,'[Y0001]-[M01]-[D01]')})` | 460.48 [452.42–487.52] | 2,557.97 [2,494.50–2,669.61] | 5.55× |
| `to_millis` | `$map(orders,function($o){$toMillis($o.date)})` | 391.37 [388.61–412.48] | 1,613.41 [1,579.62–1,749.81] | 4.12× |

<!-- END GENERATED RESULTS -->

## Observed differences

One of 64 expressions returned a different result and has **no timing ratio**:

| Case | Expression | Jexata | jsonata.js |
| --- | --- | --- | --- |
| `wildcard_order` | `orders[0].*` | Same eight values, ordered by the native Elixir map | Values ordered by the source JSON object |

The remaining difference is another form of the input-object key-order limitation. The `$match`-inside-`$map` case now agrees, including its nested array shape. The order mismatch is additional to the **three** `$keys(%)` failures in the [1,679-case reference fixture suite](COMPATIBILITY.md). The reference fixtures report 1,676 passes, zero unsupported and zero skipped cases. The expanded [differential fuzzer](differential_fuzz_results.json) ran 20,000 cases with one known difference and no unexpected mismatches; its grammar remains narrower than the full language. Jexata now provides `$random` and `$clone`, but these functions are not covered by the official fixtures or the timed workloads in this report.

Among the 63 matching cases, Jexata had a lower median in 60 and JSONata.js in three. The clearest JS wins are regex replacement with captures and the negative index path; `$trim` also had a lower JS median in this run. The canonical `$fromMillis` date picture and grouped integer `$formatNumber` are faster in Jexata on the recorded 1,000-order workload. Timing ranges, exact expressions and absolute differences are in the tables above. These ratios are specific to the host and API usage; they do not measure concurrent throughput, memory consumption or end-to-end request latency.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py \
  --reference /tmp/jexata-reference-2.2.0 \
  --rounds 7 --output docs/jsonata_js_comparison.json
python3 scripts/render_jsonata_comparison.py
```

The driver verifies the reference version, records every round and its engine order, checks that results are stable across rounds, and separates mismatches from comparable workloads. The raw file also records CPU and power metadata, Node flags, an empty-promise floor, exact expressions, iteration counts, result digests and the fixture digest. The benchmark needs Python 3, Node.js and Elixir for development; Jexata itself has no production JavaScript dependency.
