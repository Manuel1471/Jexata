# Jexata versus jsonata.js

This comparison uses Jexata 1.0.0 at commit `d061955` and the official [jsonata.js v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0) source at `8ee4476f8a228bfc7a62979ae0a9c13a4043cd03`. The harness exercises the public compile and evaluate APIs. JavaScript evaluations await the promise returned by `evaluate`. These are API costs in different runtimes, not identical virtual-machine operations.

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
| `compile_field` | `customer.name` | 0.64 [0.63–0.66] | 12.92 [12.75–13.19] | 20.31× |
| `compile_filter` | `orders[price > 50].price` | 2.83 [2.78–3.27] | 21.33 [18.37–21.78] | 7.54× |
| `compile_lambda` | `$map(orders,function($o){$o.price*2})` | 4.25 [4.19–4.34] | 26.98 [24.83–27.47] | 6.34× |
| `compile_object` | `orders{customer:$sum(price)}` | 2.07 [2.04–2.11] | 19.20 [18.77–19.81] | 9.27× |
| `compile_picture` | `$fromMillis(1704164645000,'[Y0001]-[M01]-[D01]')` | 2.81 [2.75–2.83] | 17.26 [17.11–17.77] | 6.14× |
| `compile_regex` | `$replace(text,/Order/,'Item')` | 4.09 [4.01–4.22] | 14.86 [14.53–15.16] | 3.63× |

### Scalar expressions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `arithmetic` | `(12 + 8) * 3 / 2` | 0.14 [0.13–0.15] | 2.39 [2.34–2.49] | 17.37× |
| `coalesce` | `customer.missing ?? 'unknown'` | 0.15 [0.14–0.16] | 2.04 [2.02–2.15] | 14.05× |
| `concat` | `customer.name & ' Lovelace'` | 0.28 [0.25–0.30] | 1.45 [1.43–1.68] | 5.26× |
| `conditional` | `customer.name = 'Ada' ? 'yes' : 'no'` | 0.16 [0.16–0.18] | 1.70 [1.69–1.73] | 10.30× |
| `field` | `customer.name` | 0.11 [0.11–0.11] | 1.36 [1.34–1.51] | 12.05× |
| `missing_field` | `customer.missing` | 0.13 [0.13–0.15] | 1.01 [0.99–1.11] | 7.51× |

### Paths and predicates

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `descendants` | `customer.**` | 0.16 [0.14–0.17] | 1.50 [1.47–1.52] | 9.67× |
| `filter` | `orders[price > 50].price` | 110.05 [105.78–113.24] | 790.49 [782.60–805.12] | 7.18× |
| `filter_boolean` | `orders[active].price` | 57.58 [54.02–62.61] | 458.52 [454.39–539.86] | 7.96× |
| `filter_narrow` | `orders[price > 900].price` | 57.53 [56.24–61.90] | 675.63 [671.02–769.62] | 11.74× |
| `focus_binding` | `orders@$o[$o.price > 900].price` | 161.25 [152.72–165.33] | 1,155.05 [1,140.39–1,179.70] | 7.16× |
| `index_binding` | `orders#$i[$i < 10].price` | 96.29 [91.26–100.15] | 554.14 [544.54–568.97] | 5.75× |
| `index_last` | `orders[-1].price` | 1.68 [1.54–1.71] | 1.02 [1.01–1.04] | 0.61× |
| `index_zero` | `orders[0].price` | 0.14 [0.13–0.15] | 1.05 [1.03–1.07] | 7.43× |
| `order_projection` | `orders[0].(price & ':' & customer)` | 0.60 [0.59–0.62] | 3.28 [3.24–3.41] | 5.49× |
| `path_customers` | `orders.customer` | 38.44 [37.73–43.57] | 129.84 [125.83–133.16] | 3.38× |
| `path_prices` | `orders.price` | 56.69 [54.16–57.66] | 142.42 [138.20–145.69] | 2.51× |

### Aggregates and grouping

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `average` | `$average(orders.price)` | 49.47 [47.25–50.86] | 160.16 [158.43–162.76] | 3.24× |
| `count` | `$count(orders.price)` | 48.99 [47.63–53.37] | 135.06 [133.64–138.31] | 2.76× |
| `distinct` | `$distinct(orders.customer)` | 66.10 [65.11–68.47] | 159.39 [158.40–161.99] | 2.41× |
| `group_object` | `orders{customer:$sum(price)}` | 160.53 [155.29–164.94] | 726.71 [712.76–735.05] | 4.53× |
| `max` | `$max(orders.price)` | 48.99 [48.50–54.01] | 148.27 [145.68–151.97] | 3.03× |
| `min` | `$min(orders.price)` | 49.97 [49.24–50.76] | 148.87 [146.69–151.58] | 2.98× |
| `sum` | `$sum(orders.price)` | 48.26 [47.28–53.67] | 156.12 [155.25–161.20] | 3.24× |

### Collections and sorting

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `append` | `$append(orders.price,[1001])` | 58.25 [55.71–60.92] | 141.33 [136.71–142.79] | 2.43× |
| `reverse` | `$reverse(orders.price)` | 59.23 [54.85–62.42] | 138.69 [135.03–140.22] | 2.34× |
| `sort_comparator` | `$sort(orders,function($a,$b){$a.price>$b.price})` | 1,396.98 [1,375.62–1,443.27] | 9,943.16 [9,882.10–10,296.68] | 7.12× |
| `sort_key` | `orders^(price)` | 207.21 [202.95–212.66] | 4,873.43 [4,807.99–4,949.47] | 23.52× |
| `zip` | `$zip(orders.price,orders.customer)` | 139.05 [136.74–141.39] | 295.30 [289.85–305.41] | 2.12× |

### Higher-order functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `each_object` | `$each(customer,function($value,$key){$key & ':' & $value})` | 0.75 [0.71–0.79] | 3.03 [2.97–3.12] | 4.01× |
| `filter_lambda` | `$filter(orders,function($o){$o.price>900})` | 147.02 [144.19–150.51] | 1,270.32 [1,241.26–1,284.40] | 8.64× |
| `map_index` | `$map(orders,function($o,$i){$o.price+$i})` | 199.47 [193.14–204.62] | 1,333.07 [1,278.43–1,359.39] | 6.68× |
| `map_lambda` | `$map(orders,function($o){$o.price*2})` | 153.97 [151.57–161.70] | 1,277.53 [1,250.77–1,301.12] | 8.30× |
| `reduce_lambda` | `$reduce(orders,function($a,$o){$a+$o.price},0)` | 183.08 [176.78–187.86] | 1,306.16 [1,281.96–1,318.61] | 7.13× |
| `sift_object` | `$sift(customer,function($value,$key){$key='name'})` | 0.52 [0.47–0.54] | 2.69 [2.61–3.28] | 5.16× |

### Numeric functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `floor` | `$map(orders,function($o){$floor($o.price / 3)})` | 353.44 [350.95–368.20] | 1,929.70 [1,890.28–1,969.62] | 5.46× |
| `format_integer` | `$map(orders,function($o){$formatInteger($o.price,'I')})` | 808.42 [789.08–821.01] | 1,910.22 [1,846.09–1,921.66] | 2.36× |
| `format_number` | `$map(orders,function($o){$formatNumber($o.price,'#,##0')})` | 266.07 [254.22–276.55] | 3,435.84 [3,371.19–3,761.90] | 12.91× |
| `number_decimal` | `$map(orders,function($o){$number($o.decimal)})` | 513.50 [505.28–541.03] | 1,669.98 [1,658.13–1,756.37] | 3.25× |
| `round` | `$map(orders,function($o){$round($o.price / 3,2)})` | 1,432.92 [1,352.79–1,466.70] | 2,351.47 [2,315.17–2,363.03] | 1.64× |

### String functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `contains_text` | `$map(orders,function($o){$contains($o.text,'Order')})` | 471.30 [457.58–476.17] | 1,762.84 [1,638.36–1,826.98] | 3.74× |
| `length` | `$map(orders,function($o){$length($o.text)})` | 302.06 [296.87–308.70] | 1,646.06 [1,480.08–1,724.80] | 5.45× |
| `lowercase` | `$map(orders,function($o){$lowercase($o.text)})` | 395.28 [391.43–407.49] | 1,561.54 [1,408.75–1,636.87] | 3.95× |
| `pad` | `$map(orders,function($o){$pad($o.text,20,'-')})` | 522.00 [505.21–541.25] | 2,019.08 [1,893.68–2,035.94] | 3.87× |
| `split_text` | `$map(orders,function($o){$split($o.text,' ')})` | 471.87 [445.82–477.64] | 1,830.94 [1,791.12–1,908.91] | 3.88× |
| `substring` | `$map(orders,function($o){$substring($o.text,0,5)})` | 315.57 [309.27–330.42] | 2,033.47 [2,005.60–2,102.79] | 6.44× |
| `trim` | `$map(orders,function($o){$trim($o.padded)})` | 1,714.90 [1,666.19–1,737.51] | 1,694.15 [1,544.13–1,715.46] | 0.99× |
| `uppercase` | `$map(orders,function($o){$uppercase($o.text)})` | 386.07 [378.91–393.36] | 1,590.88 [1,412.17–1,638.01] | 4.12× |

### Regular expressions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `contains_regex` | `$map(orders,function($o){$contains($o.text,/Order/)})` | 488.06 [471.27–491.87] | 1,998.11 [1,860.14–2,020.11] | 4.09× |
| `match_regex` | `$map(orders,function($o){$match($o.text,/Order/)})` | 1,098.04 [1,057.68–1,120.30] | 2,056.71 [1,979.34–2,110.57] | 1.87× |
| `match_scalar` | `$match(orders[0].text,/Order/).match` | 1.23 [1.07–1.29] | 3.45 [3.39–4.48] | 2.80× |
| `replace` | `$map(orders,function($o){$replace($o.text,/Order/,'Item')})` | 702.68 [682.67–718.61] | 2,248.21 [2,099.08–2,313.70] | 3.20× |
| `replace_capture` | `$map(orders,function($o){$replace($o.text,/(Order) (\d+)/,'$2 $1')})` | 3,180.56 [3,025.03–3,247.18] | 2,271.26 [2,203.35–2,363.53] | 0.71× |
| `split_regex` | `$map(orders,function($o){$split($o.text,/\s+/)})` | 1,316.52 [1,272.21–1,362.22] | 2,102.14 [2,068.43–2,329.12] | 1.60× |

### Date and time

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `from_millis` | `$map(orders,function($o){$fromMillis($o.epoch)})` | 585.83 [582.56–597.42] | 2,040.84 [2,012.09–2,172.24] | 3.48× |
| `from_millis_picture` | `$map(orders,function($o){$fromMillis($o.epoch,'[Y0001]-[M01]-[D01]')})` | 475.01 [460.39–481.55] | 2,510.86 [2,477.10–2,671.47] | 5.29× |
| `to_millis` | `$map(orders,function($o){$toMillis($o.date)})` | 402.19 [395.50–410.29] | 1,568.14 [1,545.03–1,707.86] | 3.90× |

<!-- END GENERATED RESULTS -->

## Observed differences

One of 64 expressions returned a different result and has **no timing ratio**:

| Case | Expression | Jexata | jsonata.js |
| --- | --- | --- | --- |
| `wildcard_order` | `orders[0].*` | Same eight values, ordered by the native Elixir map | Values ordered by the source JSON object |

The remaining difference is another form of the input-object key-order limitation. The `$match`-inside-`$map` case now agrees, including its nested array shape. The order mismatch is additional to the **three** `$keys(%)` failures in the [1,679-case reference fixture suite](COMPATIBILITY.md). The reference fixtures report 1,676 passes, zero unsupported and zero skipped cases. The expanded [differential fuzzer](differential_fuzz_results.json) ran 20,000 cases with one known difference and no unexpected mismatches; its grammar remains narrower than the full language. Jexata now provides `$random` and `$clone`, but these functions are not covered by the official fixtures or the timed workloads in this report.

Among the 63 matching cases, Jexata had a lower median in 60 and JS in three. The canonical `$fromMillis` date picture and grouped integer `$formatNumber` measure 475 versus 2,511 µs and 266 versus 3,436 µs, respectively, on 1,000 orders. The `$match`-inside-`$map` case now matches and measures 1,098 versus 2,057 µs. The clearest remaining JS wins are regex replacement with captures and the negative index path. JS also had a slightly lower `$trim` median in this run, but its timing ranges overlap Jexata's. The new 64-case fixture has more object fields than the old 12-case fixture, so its path and filter times should not be compared directly with the historical table. None of these ratios is a claim about concurrent throughput, memory consumption or end-to-end request latency.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py \
  --reference /tmp/jexata-reference-2.2.0 \
  --rounds 7 --output docs/jsonata_js_comparison.json
python3 scripts/render_jsonata_comparison.py
```

The driver verifies the reference commit, records every round and its engine order, checks that results are stable across rounds, and separates mismatches from comparable workloads. The raw file also records CPU and power metadata, Node flags, an empty-promise floor, exact expressions, iteration counts, result digests and the fixture digest. The benchmark needs Python 3, Node.js and Elixir for development; Jexata itself has no production JavaScript dependency.
