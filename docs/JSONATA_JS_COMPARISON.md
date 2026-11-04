# Jexata versus jsonata.js

This comparison uses Jexata 1.0.0 at commit `8d70298` and the official [jsonata.js v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0) source at `8ee4476f8a228bfc7a62979ae0a9c13a4043cd03`. The harness exercises the public compile and evaluate APIs. JavaScript evaluations await the promise returned by `evaluate`. These are API costs in different runtimes, not identical virtual-machine operations.

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
| `compile_field` | `customer.name` | 0.64 [0.62–0.67] | 12.98 [12.76–13.76] | 20.32× |
| `compile_filter` | `orders[price > 50].price` | 2.83 [2.57–3.01] | 21.39 [21.22–26.65] | 7.56× |
| `compile_lambda` | `$map(orders,function($o){$o.price*2})` | 4.25 [3.91–4.52] | 27.11 [24.23–82.37] | 6.38× |
| `compile_object` | `orders{customer:$sum(price)}` | 2.08 [2.01–2.10] | 19.06 [18.92–19.48] | 9.17× |
| `compile_picture` | `$fromMillis(1704164645000,'[Y0001]-[M01]-[D01]')` | 2.85 [2.64–3.00] | 17.14 [16.88–17.70] | 6.01× |
| `compile_regex` | `$replace(text,/Order/,'Item')` | 4.19 [3.87–4.62] | 14.78 [14.57–18.34] | 3.53× |

### Scalar expressions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `arithmetic` | `(12 + 8) * 3 / 2` | 0.14 [0.14–0.15] | 2.39 [2.32–2.50] | 16.82× |
| `coalesce` | `customer.missing ?? 'unknown'` | 0.14 [0.13–0.15] | 2.09 [2.01–3.30] | 14.45× |
| `concat` | `customer.name & ' Lovelace'` | 0.28 [0.25–0.31] | 1.44 [1.40–1.48] | 5.14× |
| `conditional` | `customer.name = 'Ada' ? 'yes' : 'no'` | 0.17 [0.15–0.17] | 1.71 [1.66–1.73] | 10.16× |
| `field` | `customer.name` | 0.11 [0.10–0.12] | 1.36 [1.33–1.46] | 11.96× |
| `missing_field` | `customer.missing` | 0.14 [0.13–0.14] | 0.99 [0.98–1.00] | 7.17× |

### Paths and predicates

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `descendants` | `customer.**` | 0.16 [0.14–0.18] | 1.51 [1.47–1.53] | 9.57× |
| `filter` | `orders[price > 50].price` | 113.10 [105.90–121.15] | 803.62 [783.31–816.89] | 7.11× |
| `filter_boolean` | `orders[active].price` | 56.48 [54.10–62.59] | 460.53 [450.23–498.68] | 8.15× |
| `filter_narrow` | `orders[price > 900].price` | 56.51 [54.54–61.63] | 681.90 [665.05–695.23] | 12.07× |
| `focus_binding` | `orders@$o[$o.price > 900].price` | 164.44 [155.81–176.19] | 1,179.93 [1,145.56–1,356.40] | 7.18× |
| `index_binding` | `orders#$i[$i < 10].price` | 99.99 [95.39–111.40] | 555.80 [543.74–632.06] | 5.56× |
| `index_last` | `orders[-1].price` | 1.44 [1.30–1.57] | 1.02 [1.00–1.05] | 0.71× |
| `index_zero` | `orders[0].price` | 0.15 [0.14–0.15] | 1.06 [1.03–1.10] | 7.25× |
| `order_projection` | `orders[0].(price & ':' & customer)` | 0.62 [0.58–0.75] | 3.31 [3.23–3.43] | 5.37× |
| `path_customers` | `orders.customer` | 37.63 [35.66–39.10] | 127.96 [127.19–137.80] | 3.40× |
| `path_prices` | `orders.price` | 56.59 [54.46–61.04] | 144.38 [140.68–172.54] | 2.55× |

### Aggregates and grouping

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `average` | `$average(orders.price)` | 48.96 [47.89–51.00] | 161.68 [157.24–168.06] | 3.30× |
| `count` | `$count(orders.price)` | 48.41 [47.81–50.12] | 136.43 [130.50–139.51] | 2.82× |
| `distinct` | `$distinct(orders.customer)` | 67.28 [65.73–68.17] | 160.59 [157.33–163.38] | 2.39× |
| `group_object` | `orders{customer:$sum(price)}` | 163.59 [158.21–165.45] | 728.41 [717.05–766.91] | 4.45× |
| `max` | `$max(orders.price)` | 48.40 [47.47–53.21] | 150.58 [142.61–154.25] | 3.11× |
| `min` | `$min(orders.price)` | 48.53 [45.97–52.95] | 152.74 [143.80–157.81] | 3.15× |
| `sum` | `$sum(orders.price)` | 48.02 [46.24–51.51] | 156.15 [152.16–171.39] | 3.25× |

### Collections and sorting

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `append` | `$append(orders.price,[1001])` | 60.78 [55.86–69.58] | 140.44 [139.64–143.88] | 2.31× |
| `reverse` | `$reverse(orders.price)` | 58.89 [57.65–60.71] | 137.01 [135.79–141.81] | 2.33× |
| `sort_comparator` | `$sort(orders,function($a,$b){$a.price>$b.price})` | 1,425.07 [1,369.15–1,456.16] | 9,980.94 [9,666.86–10,210.33] | 7.00× |
| `sort_key` | `orders^(price)` | 209.02 [200.74–221.89] | 4,900.76 [4,802.17–5,216.67] | 23.45× |
| `zip` | `$zip(orders.price,orders.customer)` | 140.04 [137.28–146.30] | 290.73 [290.30–301.83] | 2.08× |

### Higher-order functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `each_object` | `$each(customer,function($value,$key){$key & ':' & $value})` | 0.78 [0.77–0.79] | 3.03 [2.97–3.09] | 3.91× |
| `filter_lambda` | `$filter(orders,function($o){$o.price>900})` | 147.83 [143.37–179.79] | 1,270.07 [1,224.27–1,290.96] | 8.59× |
| `map_index` | `$map(orders,function($o,$i){$o.price+$i})` | 197.54 [194.66–207.41] | 1,310.04 [1,278.58–1,349.23] | 6.63× |
| `map_lambda` | `$map(orders,function($o){$o.price*2})` | 155.44 [152.70–167.16] | 1,275.15 [1,242.12–1,301.87] | 8.20× |
| `reduce_lambda` | `$reduce(orders,function($a,$o){$a+$o.price},0)` | 185.12 [178.85–194.45] | 1,301.33 [1,269.88–1,326.06] | 7.03× |
| `sift_object` | `$sift(customer,function($value,$key){$key='name'})` | 0.52 [0.52–0.55] | 2.70 [2.60–2.75] | 5.15× |

### Numeric functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `floor` | `$map(orders,function($o){$floor($o.price / 3)})` | 351.05 [345.03–369.27] | 1,952.43 [1,881.41–2,348.07] | 5.56× |
| `format_integer` | `$map(orders,function($o){$formatInteger($o.price,'I')})` | 815.22 [796.67–822.59] | 1,892.08 [1,847.09–1,949.94] | 2.32× |
| `format_number` | `$map(orders,function($o){$formatNumber($o.price,'#,##0')})` | 260.40 [252.67–285.84] | 3,475.57 [3,364.31–3,866.42] | 13.35× |
| `number_decimal` | `$map(orders,function($o){$number($o.decimal)})` | 508.51 [495.33–543.23] | 1,670.57 [1,636.94–1,705.18] | 3.29× |
| `round` | `$map(orders,function($o){$round($o.price / 3,2)})` | 1,425.19 [1,385.45–1,487.27] | 2,333.94 [2,294.12–2,436.57] | 1.64× |

### String functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `contains_text` | `$map(orders,function($o){$contains($o.text,'Order')})` | 464.63 [451.34–470.02] | 1,795.53 [1,763.24–1,968.42] | 3.86× |
| `length` | `$map(orders,function($o){$length($o.text)})` | 294.49 [291.68–312.59] | 1,656.62 [1,593.45–1,727.10] | 5.63× |
| `lowercase` | `$map(orders,function($o){$lowercase($o.text)})` | 390.79 [384.26–487.86] | 1,569.55 [1,529.45–1,595.94] | 4.02× |
| `pad` | `$map(orders,function($o){$pad($o.text,20,'-')})` | 513.26 [488.60–571.59] | 2,028.00 [1,974.96–2,392.08] | 3.95× |
| `split_text` | `$map(orders,function($o){$split($o.text,' ')})` | 457.83 [437.79–590.59] | 1,916.72 [1,851.35–1,947.58] | 4.19× |
| `substring` | `$map(orders,function($o){$substring($o.text,0,5)})` | 321.12 [304.40–336.02] | 2,022.17 [1,983.55–2,156.11] | 6.30× |
| `trim` | `$map(orders,function($o){$trim($o.padded)})` | 1,727.79 [1,666.72–1,891.90] | 1,726.93 [1,695.26–1,769.99] | 1.00× |
| `uppercase` | `$map(orders,function($o){$uppercase($o.text)})` | 382.87 [379.48–396.03] | 1,626.08 [1,551.42–1,694.92] | 4.25× |

### Regular expressions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `contains_regex` | `$map(orders,function($o){$contains($o.text,/Order/)})` | 477.38 [466.89–533.78] | 2,010.19 [1,975.89–2,050.95] | 4.21× |
| `match_regex` | `$map(orders,function($o){$match($o.text,/Order/)})` | 1,109.32 [1,065.58–1,149.23] | 2,125.10 [2,057.24–2,361.90] | 1.92× |
| `match_scalar` | `$match(orders[0].text,/Order/).match` | 1.25 [1.17–1.29] | 3.44 [3.33–3.48] | 2.75× |
| `replace` | `$map(orders,function($o){$replace($o.text,/Order/,'Item')})` | 702.92 [677.24–780.88] | 2,301.79 [2,255.78–2,338.44] | 3.27× |
| `replace_capture` | `$map(orders,function($o){$replace($o.text,/(Order) (\d+)/,'$2 $1')})` | 3,174.74 [3,034.42–3,250.99] | 2,357.86 [2,265.70–2,395.61] | 0.74× |
| `split_regex` | `$map(orders,function($o){$split($o.text,/\s+/)})` | 1,361.51 [1,303.95–1,495.33] | 2,213.47 [2,092.36–2,372.63] | 1.63× |

### Date and time

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `from_millis` | `$map(orders,function($o){$fromMillis($o.epoch)})` | 591.11 [578.66–609.14] | 2,186.57 [2,031.14–2,203.22] | 3.70× |
| `from_millis_picture` | `$map(orders,function($o){$fromMillis($o.epoch,'[Y0001]-[M01]-[D01]')})` | 465.27 [451.34–504.90] | 2,666.23 [2,492.08–2,981.39] | 5.73× |
| `to_millis` | `$map(orders,function($o){$toMillis($o.date)})` | 389.43 [385.73–411.75] | 1,703.43 [1,567.79–1,893.99] | 4.37× |

<!-- END GENERATED RESULTS -->

## Observed differences

One of 64 expressions returned a different result and has **no timing ratio**:

| Case | Expression | Jexata | jsonata.js |
| --- | --- | --- | --- |
| `wildcard_order` | `orders[0].*` | Same eight values, ordered by the native Elixir map | Values ordered by the source JSON object |

The remaining difference is another form of the input-object key-order limitation. The `$match`-inside-`$map` case now agrees, including its nested array shape. The order mismatch is additional to the **three** `$keys(%)` failures in the [1,679-case reference fixture suite](COMPATIBILITY.md). The reference fixtures report 1,676 passes, zero unsupported and zero skipped cases. The expanded [differential fuzzer](differential_fuzz_results.json) ran 20,000 cases with one known difference and no unexpected mismatches; its grammar remains narrower than the full language. Jexata now provides `$random` and `$clone`, but these functions are not covered by the official fixtures or the timed workloads in this report.

Among the 63 matching cases, Jexata had a lower median in 60 and JS in three. The canonical `$fromMillis` date picture and grouped integer `$formatNumber` measure 465 versus 2,666 µs and 260 versus 3,476 µs, respectively, on 1,000 orders. The `$match`-inside-`$map` case now matches and measures 1,109 versus 2,125 µs. The clearest remaining JS wins are regex replacement with captures and the negative index path. `$trim` has nearly equal medians in this run and overlapping timing ranges. The new 64-case fixture has more object fields than the old 12-case fixture, so its path and filter times should not be compared directly with the historical table. None of these ratios is a claim about concurrent throughput, memory consumption or end-to-end request latency.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py \
  --reference /tmp/jexata-reference-2.2.0 \
  --rounds 7 --output docs/jsonata_js_comparison.json
python3 scripts/render_jsonata_comparison.py
```

The driver verifies the reference commit, records every round and its engine order, checks that results are stable across rounds, and separates mismatches from comparable workloads. The raw file also records CPU and power metadata, Node flags, an empty-promise floor, exact expressions, iteration counts, result digests and the fixture digest. The benchmark needs Python 3, Node.js and Elixir for development; Jexata itself has no production JavaScript dependency.
