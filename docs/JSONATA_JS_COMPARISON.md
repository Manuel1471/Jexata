# Jexata versus jsonata.js

This comparison uses Jexata 1.0.0 at commit `0a48431` and the official [jsonata.js v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0) source at `8ee4476f8a228bfc7a62979ae0a9c13a4043cd03`. The harness exercises the public compile and evaluate APIs. JavaScript evaluations await the promise returned by `evaluate`. These are API costs in different runtimes, not identical virtual-machine operations.

## Method

The fixture contains 1,000 orders and a customer. The 64 named expressions cover compilation, scalar expressions, paths and predicates, aggregates, collections, higher-order functions, numeric and string functions, regex, and date/time. Every case has a fixed expression and iteration count recorded in [raw results](jsonata_js_comparison.json). Compiled expressions are reused for evaluation. Each engine gets three warm-up calls per case. Seven rounds alternate engine order; startup and data generation are outside the timed section. A case gets a timing ratio only when both engines return the same JSON result in **every** round. A stable SHA-256 digest of each matching result is recorded in the JSON.

The run used a Mac16,12 arm64 host, Elixir 1.20.2 / OTP 29, and Node v26.5.0. The laptop was on battery power (76% when metadata was captured) with low-power mode off. Times are medians with min–max ranges in µs per operation. **JS / Jexata above 1 means Jexata's median was lower.** The ratio reflects this machine, input and API usage. Short scalar cases include JavaScript promise overhead; the measured median of an empty `await Promise.resolve()` was recorded in the JSON and must not be subtracted as if it were the entire evaluation overhead.

<!-- BEGIN GENERATED RESULTS -->
**64 expressions:** 62 matching results; 2 mismatches excluded from timing ratios.

| Category | Matching cases | Lower Jexata median | Lower JS median |
| --- | ---: | ---: | ---: |
| Compilation | 6 | 6 | 0 |
| Scalar expressions | 6 | 6 | 0 |
| Paths and predicates | 11 | 10 | 1 |
| Aggregates and grouping | 7 | 7 | 0 |
| Collections and sorting | 5 | 5 | 0 |
| Higher-order functions | 6 | 6 | 0 |
| Numeric functions | 5 | 4 | 1 |
| String functions | 8 | 7 | 1 |
| Regular expressions | 5 | 4 | 1 |
| Date and time | 3 | 2 | 1 |

### Compilation

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `compile_field` | `customer.name` | 0.64 [0.60–1.02] | 13.07 [12.69–13.26] | 20.45× |
| `compile_filter` | `orders[price > 50].price` | 2.83 [2.63–3.73] | 21.66 [21.08–22.07] | 7.64× |
| `compile_lambda` | `$map(orders,function($o){$o.price*2})` | 4.30 [3.85–4.38] | 27.18 [24.32–28.21] | 6.32× |
| `compile_object` | `orders{customer:$sum(price)}` | 2.07 [1.91–2.16] | 19.32 [18.85–20.22] | 9.35× |
| `compile_picture` | `$fromMillis(1704164645000,'[Y0001]-[M01]-[D01]')` | 2.84 [2.53–2.91] | 17.60 [17.03–19.71] | 6.19× |
| `compile_regex` | `$replace(text,/Order/,'Item')` | 4.12 [3.82–4.29] | 14.76 [14.60–15.01] | 3.58× |

### Scalar expressions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `arithmetic` | `(12 + 8) * 3 / 2` | 0.14 [0.13–0.15] | 2.42 [2.34–2.51] | 17.32× |
| `coalesce` | `customer.missing ?? 'unknown'` | 0.15 [0.13–0.16] | 2.06 [2.03–2.09] | 14.14× |
| `concat` | `customer.name & ' Lovelace'` | 0.27 [0.25–0.29] | 1.47 [1.38–1.50] | 5.39× |
| `conditional` | `customer.name = 'Ada' ? 'yes' : 'no'` | 0.17 [0.16–0.19] | 1.70 [1.65–1.75] | 10.21× |
| `field` | `customer.name` | 0.11 [0.10–0.11] | 1.37 [1.34–1.45] | 12.64× |
| `missing_field` | `customer.missing` | 0.13 [0.13–0.14] | 1.01 [0.98–1.16] | 7.70× |

### Paths and predicates

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `descendants` | `customer.**` | 0.15 [0.14–0.18] | 1.49 [1.48–1.52] | 9.91× |
| `filter` | `orders[price > 50].price` | 107.58 [105.63–109.89] | 791.82 [775.86–806.83] | 7.36× |
| `filter_boolean` | `orders[active].price` | 56.17 [55.02–58.08] | 460.68 [446.14–466.50] | 8.20× |
| `filter_narrow` | `orders[price > 900].price` | 57.54 [53.39–58.27] | 672.62 [656.70–685.76] | 11.69× |
| `focus_binding` | `orders@$o[$o.price > 900].price` | 159.97 [151.38–161.30] | 1,156.85 [1,147.82–1,189.89] | 7.23× |
| `index_binding` | `orders#$i[$i < 10].price` | 95.81 [89.54–105.85] | 557.32 [547.79–576.78] | 5.82× |
| `index_last` | `orders[-1].price` | 1.69 [1.58–1.77] | 1.02 [1.00–1.03] | 0.60× |
| `index_zero` | `orders[0].price` | 0.14 [0.13–0.15] | 1.06 [1.03–1.08] | 7.62× |
| `order_projection` | `orders[0].(price & ':' & customer)` | 0.61 [0.58–0.66] | 3.28 [3.23–3.39] | 5.42× |
| `path_customers` | `orders.customer` | 37.14 [34.92–38.66] | 129.02 [124.97–132.65] | 3.47× |
| `path_prices` | `orders.price` | 56.00 [53.59–58.16] | 141.70 [139.71–148.75] | 2.53× |

### Aggregates and grouping

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `average` | `$average(orders.price)` | 49.98 [46.60–53.10] | 160.52 [155.80–163.51] | 3.21× |
| `count` | `$count(orders.price)` | 47.62 [47.24–50.11] | 134.43 [132.16–139.06] | 2.82× |
| `distinct` | `$distinct(orders.customer)` | 66.09 [64.40–69.27] | 161.37 [153.43–163.23] | 2.44× |
| `group_object` | `orders{customer:$sum(price)}` | 158.03 [148.54–165.17] | 726.82 [720.37–744.01] | 4.60× |
| `max` | `$max(orders.price)` | 48.25 [46.35–51.84] | 146.77 [142.99–152.02] | 3.04× |
| `min` | `$min(orders.price)` | 49.11 [46.49–51.22] | 149.05 [144.09–154.75] | 3.04× |
| `sum` | `$sum(orders.price)` | 47.46 [46.82–50.43] | 155.88 [151.30–161.15] | 3.28× |

### Collections and sorting

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `append` | `$append(orders.price,[1001])` | 57.93 [57.74–61.09] | 141.50 [134.81–149.12] | 2.44× |
| `reverse` | `$reverse(orders.price)` | 57.91 [54.22–61.38] | 137.46 [133.89–142.51] | 2.37× |
| `sort_comparator` | `$sort(orders,function($a,$b){$a.price>$b.price})` | 1,425.75 [1,370.40–1,455.97] | 10,135.98 [9,872.20–10,150.68] | 7.11× |
| `sort_key` | `orders^(price)` | 206.68 [193.99–224.03] | 4,901.85 [4,844.60–4,946.59] | 23.72× |
| `zip` | `$zip(orders.price,orders.customer)` | 139.58 [130.73–143.50] | 295.47 [287.00–304.96] | 2.12× |

### Higher-order functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `each_object` | `$each(customer,function($value,$key){$key & ':' & $value})` | 0.79 [0.71–0.80] | 3.06 [2.93–3.15] | 3.87× |
| `filter_lambda` | `$filter(orders,function($o){$o.price>900})` | 145.09 [138.85–148.70] | 1,283.53 [1,243.45–1,298.28] | 8.85× |
| `map_index` | `$map(orders,function($o,$i){$o.price+$i})` | 199.27 [196.81–204.92] | 1,338.28 [1,303.69–1,355.20] | 6.72× |
| `map_lambda` | `$map(orders,function($o){$o.price*2})` | 157.62 [154.23–161.83] | 1,285.28 [1,253.84–1,315.14] | 8.15× |
| `reduce_lambda` | `$reduce(orders,function($a,$o){$a+$o.price},0)` | 180.13 [174.05–185.50] | 1,316.01 [1,279.29–1,340.86] | 7.31× |
| `sift_object` | `$sift(customer,function($value,$key){$key='name'})` | 0.53 [0.49–0.57] | 2.66 [2.57–2.69] | 5.04× |

### Numeric functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `floor` | `$map(orders,function($o){$floor($o.price / 3)})` | 353.31 [346.06–357.44] | 1,929.96 [1,906.59–1,955.84] | 5.46× |
| `format_integer` | `$map(orders,function($o){$formatInteger($o.price,'I')})` | 773.86 [755.02–798.59] | 1,920.66 [1,872.04–1,957.19] | 2.48× |
| `format_number` | `$map(orders,function($o){$formatNumber($o.price,'#,##0')})` | 5,619.96 [5,416.89–5,711.18] | 3,455.57 [3,413.97–3,742.24] | 0.61× |
| `number_decimal` | `$map(orders,function($o){$number($o.decimal)})` | 504.50 [498.23–511.26] | 1,691.59 [1,642.47–1,698.92] | 3.35× |
| `round` | `$map(orders,function($o){$round($o.price / 3,2)})` | 1,417.91 [1,357.23–1,453.95] | 2,361.58 [2,289.81–2,387.62] | 1.67× |

### String functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `contains_text` | `$map(orders,function($o){$contains($o.text,'Order')})` | 462.77 [450.40–480.17] | 1,809.70 [1,799.05–1,840.99] | 3.91× |
| `length` | `$map(orders,function($o){$length($o.text)})` | 306.21 [299.02–317.59] | 1,653.86 [1,585.43–1,725.15] | 5.40× |
| `lowercase` | `$map(orders,function($o){$lowercase($o.text)})` | 399.83 [394.85–415.52] | 1,569.23 [1,523.09–1,587.44] | 3.92× |
| `pad` | `$map(orders,function($o){$pad($o.text,20,'-')})` | 518.86 [503.22–535.00] | 2,035.09 [1,974.02–2,057.57] | 3.92× |
| `split_text` | `$map(orders,function($o){$split($o.text,' ')})` | 468.65 [454.50–478.88] | 1,946.60 [1,810.71–1,991.95] | 4.15× |
| `substring` | `$map(orders,function($o){$substring($o.text,0,5)})` | 314.90 [307.12–330.43] | 2,076.43 [2,022.25–2,122.19] | 6.59× |
| `trim` | `$map(orders,function($o){$trim($o.padded)})` | 1,727.11 [1,582.84–1,742.58] | 1,705.32 [1,676.25–1,772.48] | 0.99× |
| `uppercase` | `$map(orders,function($o){$uppercase($o.text)})` | 391.51 [386.14–399.21] | 1,603.98 [1,566.60–1,674.84] | 4.10× |

### Regular expressions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `contains_regex` | `$map(orders,function($o){$contains($o.text,/Order/)})` | 477.05 [465.06–493.21] | 2,002.96 [1,971.28–2,036.93] | 4.20× |
| `match_scalar` | `$match(orders[0].text,/Order/).match` | 1.20 [1.13–1.28] | 3.43 [3.37–4.74] | 2.86× |
| `replace` | `$map(orders,function($o){$replace($o.text,/Order/,'Item')})` | 701.17 [660.84–733.39] | 2,313.54 [2,267.44–2,335.29] | 3.30× |
| `replace_capture` | `$map(orders,function($o){$replace($o.text,/(Order) (\d+)/,'$2 $1')})` | 3,141.38 [2,984.65–3,260.26] | 2,386.46 [2,258.52–2,410.05] | 0.76× |
| `split_regex` | `$map(orders,function($o){$split($o.text,/\s+/)})` | 1,298.30 [1,254.47–1,367.13] | 2,254.02 [2,092.62–2,285.06] | 1.74× |

### Date and time

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `from_millis` | `$map(orders,function($o){$fromMillis($o.epoch)})` | 592.71 [584.67–607.34] | 2,181.48 [2,044.64–2,219.08] | 3.68× |
| `from_millis_picture` | `$map(orders,function($o){$fromMillis($o.epoch,'[Y0001]-[M01]-[D01]')})` | 5,184.37 [5,039.16–5,448.25] | 2,681.37 [2,531.15–2,699.53] | 0.52× |
| `to_millis` | `$map(orders,function($o){$toMillis($o.date)})` | 397.01 [391.39–437.20] | 1,741.47 [1,578.04–1,801.29] | 4.39× |

<!-- END GENERATED RESULTS -->

## Observed differences

Two of 64 expressions returned different results and have **no timing ratio**:

| Case | Expression | Jexata | jsonata.js |
| --- | --- | --- | --- |
| `wildcard_order` | `orders[0].*` | Same eight values, ordered by the native Elixir map | Values ordered by the source JSON object |
| `match_regex` | `$map(orders,function($o){$match($o.text,/Order/)})` | A flat list of 1,000 match objects | A list of 1,000 one-element match arrays |

The first difference is another form of the input-object key-order limitation. The second is a sequence/array-shape difference in `$match` results inside `$map`; a scalar `$match` case is included among the matching workloads. These observations are additional to the **three** `$keys(%)` failures in the [1,679-case reference fixture suite](COMPATIBILITY.md). The reference fixtures report 1,676 passes, zero unsupported and zero skipped cases. The expanded [differential fuzzer](differential_fuzz_results.json) ran 20,000 cases with these two known differences and no unexpected mismatches; its grammar remains narrower than the full language. Jexata now provides `$random` and `$clone`, but these functions are not covered by the official fixtures or the timed workloads in this report.

Among the 62 matching cases, Jexata had a lower median in 57 and JS in five. The largest clear JS wins in this run were `$fromMillis` with a picture, `$formatNumber`, regex replacement with captures, and the negative index path. `$trim` differed by less than 1% and its timing ranges overlap; treat it as a tie. The new 64-case fixture has more object fields than the old 12-case fixture, so its path and filter times should not be compared directly with the historical table. None of these ratios is a claim about concurrent throughput, memory consumption or end-to-end request latency.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py \
  --reference /tmp/jexata-reference-2.2.0 \
  --rounds 7 --output docs/jsonata_js_comparison.json
python3 scripts/render_jsonata_comparison.py
```

The driver verifies the reference commit, records every round and its engine order, checks that results are stable across rounds, and separates mismatches from comparable workloads. The raw file also records CPU and power metadata, Node flags, an empty-promise floor, exact expressions, iteration counts, result digests and the fixture digest. The benchmark needs Python 3, Node.js and Elixir for development; Jexata itself has no production JavaScript dependency.
