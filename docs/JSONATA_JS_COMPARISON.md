# Jexata versus jsonata.js

This comparison uses Jexata 1.0.0 at commit `7118619` and the official [jsonata.js v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0) source at `8ee4476f8a228bfc7a62979ae0a9c13a4043cd03`. The harness exercises the public compile and evaluate APIs. JavaScript evaluations await the promise returned by `evaluate`. These are API costs in different runtimes, not identical virtual-machine operations.

## Method

The fixture contains 1,000 orders and a customer. The 64 named expressions cover compilation, scalar expressions, paths and predicates, aggregates, collections, higher-order functions, numeric and string functions, regex, and date/time. Every case has a fixed expression and iteration count recorded in [raw results](jsonata_js_comparison.json). Compiled expressions are reused for evaluation. Each engine gets three warm-up calls per case. Seven rounds alternate engine order; startup and data generation are outside the timed section. A case gets a timing ratio only when both engines return the same JSON result in **every** round. A stable SHA-256 digest of each matching result is recorded in the JSON.

The run used a Mac16,12 arm64 host, Elixir 1.20.2 / OTP 29, and Node v26.5.0. The laptop was on battery power (100% when metadata was captured) with low-power mode off. Times are medians with min–max ranges in µs per operation. **JS / Jexata above 1 means Jexata's median was lower.** The ratio reflects this machine, input and API usage. Short scalar cases include JavaScript promise overhead; the measured median of an empty `await Promise.resolve()` was recorded in the JSON and must not be subtracted as if it were the entire evaluation overhead.

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
| Date and time | 3 | 3 | 0 |

### Compilation

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `compile_field` | `customer.name` | 0.62 [0.62–0.65] | 12.93 [12.55–13.02] | 20.72× |
| `compile_filter` | `orders[price > 50].price` | 2.77 [2.55–2.84] | 21.23 [21.08–21.55] | 7.68× |
| `compile_lambda` | `$map(orders,function($o){$o.price*2})` | 4.23 [4.11–4.38] | 26.93 [24.63–27.31] | 6.36× |
| `compile_object` | `orders{customer:$sum(price)}` | 2.06 [1.95–2.09] | 19.12 [18.88–19.50] | 9.27× |
| `compile_picture` | `$fromMillis(1704164645000,'[Y0001]-[M01]-[D01]')` | 2.83 [2.61–2.92] | 17.27 [16.95–17.47] | 6.10× |
| `compile_regex` | `$replace(text,/Order/,'Item')` | 4.16 [3.75–5.37] | 14.77 [14.55–14.79] | 3.55× |

### Scalar expressions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `arithmetic` | `(12 + 8) * 3 / 2` | 0.13 [0.13–0.14] | 2.36 [2.30–2.51] | 17.70× |
| `coalesce` | `customer.missing ?? 'unknown'` | 0.14 [0.13–0.15] | 2.05 [2.00–2.07] | 14.27× |
| `concat` | `customer.name & ' Lovelace'` | 0.27 [0.24–0.30] | 1.44 [1.42–1.48] | 5.40× |
| `conditional` | `customer.name = 'Ada' ? 'yes' : 'no'` | 0.17 [0.15–0.19] | 1.69 [1.66–1.73] | 10.22× |
| `field` | `customer.name` | 0.11 [0.10–0.11] | 1.34 [1.32–1.35] | 12.14× |
| `missing_field` | `customer.missing` | 0.13 [0.12–0.14] | 1.00 [0.97–1.03] | 7.66× |

### Paths and predicates

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `descendants` | `customer.**` | 0.15 [0.14–0.16] | 1.48 [1.46–1.51] | 9.87× |
| `filter` | `orders[price > 50].price` | 108.46 [106.72–114.75] | 790.05 [778.79–801.15] | 7.28× |
| `filter_boolean` | `orders[active].price` | 56.23 [54.75–63.58] | 458.53 [454.07–469.26] | 8.15× |
| `filter_narrow` | `orders[price > 900].price` | 56.91 [55.46–61.01] | 673.76 [671.66–683.30] | 11.84× |
| `focus_binding` | `orders@$o[$o.price > 900].price` | 158.50 [151.47–162.11] | 1,149.85 [1,137.33–1,207.72] | 7.25× |
| `index_binding` | `orders#$i[$i < 10].price` | 95.91 [91.63–97.87] | 554.22 [547.45–564.33] | 5.78× |
| `index_last` | `orders[-1].price` | 1.65 [1.54–1.86] | 1.01 [1.00–1.02] | 0.61× |
| `index_zero` | `orders[0].price` | 0.14 [0.13–0.14] | 1.04 [1.03–1.07] | 7.46× |
| `order_projection` | `orders[0].(price & ':' & customer)` | 0.60 [0.55–0.64] | 3.23 [3.20–3.30] | 5.41× |
| `path_customers` | `orders.customer` | 36.86 [34.18–41.78] | 128.50 [125.56–130.82] | 3.49× |
| `path_prices` | `orders.price` | 55.76 [55.09–57.09] | 141.57 [140.61–144.57] | 2.54× |

### Aggregates and grouping

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `average` | `$average(orders.price)` | 48.25 [47.63–50.22] | 160.38 [157.58–162.55] | 3.32× |
| `count` | `$count(orders.price)` | 47.31 [46.75–49.49] | 134.04 [133.45–137.74] | 2.83× |
| `distinct` | `$distinct(orders.customer)` | 65.62 [64.31–67.40] | 158.22 [156.15–159.88] | 2.41× |
| `group_object` | `orders{customer:$sum(price)}` | 160.64 [158.15–162.58] | 723.15 [713.46–736.87] | 4.50× |
| `max` | `$max(orders.price)` | 48.23 [47.37–49.59] | 146.16 [145.09–157.67] | 3.03× |
| `min` | `$min(orders.price)` | 48.58 [47.54–51.74] | 149.00 [147.10–150.62] | 3.07× |
| `sum` | `$sum(orders.price)` | 47.50 [47.23–48.37] | 156.35 [153.51–161.21] | 3.29× |

### Collections and sorting

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `append` | `$append(orders.price,[1001])` | 58.02 [55.90–60.89] | 140.37 [137.62–144.69] | 2.42× |
| `reverse` | `$reverse(orders.price)` | 59.78 [56.07–60.62] | 136.50 [135.03–141.25] | 2.28× |
| `sort_comparator` | `$sort(orders,function($a,$b){$a.price>$b.price})` | 1,399.30 [1,379.22–1,427.65] | 9,897.45 [9,605.54–10,124.53] | 7.07× |
| `sort_key` | `orders^(price)` | 207.60 [201.92–213.35] | 4,859.65 [4,788.94–4,926.11] | 23.41× |
| `zip` | `$zip(orders.price,orders.customer)` | 137.70 [133.34–140.31] | 292.15 [289.08–300.06] | 2.12× |

### Higher-order functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `each_object` | `$each(customer,function($value,$key){$key & ':' & $value})` | 0.75 [0.73–0.82] | 2.99 [2.97–3.19] | 4.00× |
| `filter_lambda` | `$filter(orders,function($o){$o.price>900})` | 144.85 [142.51–150.03] | 1,266.77 [1,242.74–1,291.47] | 8.75× |
| `map_index` | `$map(orders,function($o,$i){$o.price+$i})` | 199.24 [196.43–205.52] | 1,323.67 [1,300.49–1,355.55] | 6.64× |
| `map_lambda` | `$map(orders,function($o){$o.price*2})` | 159.82 [154.29–163.27] | 1,281.60 [1,275.53–1,302.88] | 8.02× |
| `reduce_lambda` | `$reduce(orders,function($a,$o){$a+$o.price},0)` | 180.77 [177.81–183.80] | 1,306.37 [1,281.02–1,332.57] | 7.23× |
| `sift_object` | `$sift(customer,function($value,$key){$key='name'})` | 0.51 [0.46–0.54] | 2.63 [2.35–2.66] | 5.14× |

### Numeric functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `floor` | `$map(orders,function($o){$floor($o.price / 3)})` | 359.23 [348.67–444.22] | 1,922.30 [1,789.89–1,954.84] | 5.35× |
| `format_integer` | `$map(orders,function($o){$formatInteger($o.price,'I')})` | 772.06 [737.75–786.17] | 1,890.89 [1,758.42–1,908.14] | 2.45× |
| `format_number` | `$map(orders,function($o){$formatNumber($o.price,'#,##0')})` | 5,566.21 [5,493.07–5,625.76] | 3,438.10 [3,213.23–3,541.89] | 0.62× |
| `number_decimal` | `$map(orders,function($o){$number($o.decimal)})` | 514.46 [499.23–525.97] | 1,654.99 [1,627.48–1,697.19] | 3.22× |
| `round` | `$map(orders,function($o){$round($o.price / 3,2)})` | 1,409.79 [1,372.96–1,432.33] | 2,318.59 [2,277.70–2,373.91] | 1.64× |

### String functions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `contains_text` | `$map(orders,function($o){$contains($o.text,'Order')})` | 463.23 [447.01–540.65] | 1,697.40 [1,656.35–1,838.39] | 3.66× |
| `length` | `$map(orders,function($o){$length($o.text)})` | 299.99 [295.44–313.88] | 1,583.56 [1,472.89–1,711.26] | 5.28× |
| `lowercase` | `$map(orders,function($o){$lowercase($o.text)})` | 399.60 [389.61–409.17] | 1,463.79 [1,418.43–1,572.43] | 3.66× |
| `pad` | `$map(orders,function($o){$pad($o.text,20,'-')})` | 513.72 [505.66–525.18] | 1,911.58 [1,880.44–2,057.90] | 3.72× |
| `split_text` | `$map(orders,function($o){$split($o.text,' ')})` | 469.63 [449.37–486.37] | 1,839.15 [1,813.76–1,972.83] | 3.92× |
| `substring` | `$map(orders,function($o){$substring($o.text,0,5)})` | 316.36 [312.83–326.16] | 2,037.45 [1,919.67–2,103.46] | 6.44× |
| `trim` | `$map(orders,function($o){$trim($o.padded)})` | 1,703.67 [1,615.80–1,729.81] | 1,561.83 [1,553.43–1,718.71] | 0.92× |
| `uppercase` | `$map(orders,function($o){$uppercase($o.text)})` | 393.02 [387.00–399.12] | 1,463.93 [1,419.36–1,678.87] | 3.72× |

### Regular expressions

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `contains_regex` | `$map(orders,function($o){$contains($o.text,/Order/)})` | 484.80 [466.77–580.90] | 1,909.59 [1,852.55–2,038.76] | 3.94× |
| `match_scalar` | `$match(orders[0].text,/Order/).match` | 1.16 [1.06–1.26] | 3.46 [3.32–4.06] | 2.99× |
| `replace` | `$map(orders,function($o){$replace($o.text,/Order/,'Item')})` | 703.91 [670.37–796.60] | 2,167.68 [2,134.20–2,336.37] | 3.08× |
| `replace_capture` | `$map(orders,function($o){$replace($o.text,/(Order) (\d+)/,'$2 $1')})` | 3,188.30 [3,098.98–3,274.60] | 2,261.04 [2,247.11–2,401.31] | 0.71× |
| `split_regex` | `$map(orders,function($o){$split($o.text,/\s+/)})` | 1,331.84 [1,302.11–1,351.46] | 2,097.03 [2,084.26–2,274.00] | 1.57× |

### Date and time

| Case | Exact expression | Jexata µs med [min–max] | JS µs med [min–max] | JS / Jexata |
| --- | --- | ---: | ---: | ---: |
| `from_millis` | `$map(orders,function($o){$fromMillis($o.epoch)})` | 586.94 [572.66–594.97] | 2,028.99 [2,007.69–2,204.77] | 3.46× |
| `from_millis_picture` | `$map(orders,function($o){$fromMillis($o.epoch,'[Y0001]-[M01]-[D01]')})` | 467.82 [459.47–500.45] | 2,536.51 [2,508.16–2,696.75] | 5.42× |
| `to_millis` | `$map(orders,function($o){$toMillis($o.date)})` | 394.32 [387.49–408.89] | 1,595.56 [1,562.98–1,852.42] | 4.05× |

<!-- END GENERATED RESULTS -->

## Observed differences

Two of 64 expressions returned different results and have **no timing ratio**:

| Case | Expression | Jexata | jsonata.js |
| --- | --- | --- | --- |
| `wildcard_order` | `orders[0].*` | Same eight values, ordered by the native Elixir map | Values ordered by the source JSON object |
| `match_regex` | `$map(orders,function($o){$match($o.text,/Order/)})` | A flat list of 1,000 match objects | A list of 1,000 one-element match arrays |

The first difference is another form of the input-object key-order limitation. The second is a sequence/array-shape difference in `$match` results inside `$map`; a scalar `$match` case is included among the matching workloads. These observations are additional to the **three** `$keys(%)` failures in the [1,679-case reference fixture suite](COMPATIBILITY.md). The reference fixtures report 1,676 passes, zero unsupported and zero skipped cases. The expanded [differential fuzzer](differential_fuzz_results.json) ran 20,000 cases with these two known differences and no unexpected mismatches; its grammar remains narrower than the full language. Jexata now provides `$random` and `$clone`, but these functions are not covered by the official fixtures or the timed workloads in this report.

Among the 62 matching cases, Jexata had a lower median in 58 and JS in four. The fast path for `$fromMillis` with the canonical date picture moved that workload to 468 µs against 2,537 µs in JS on 1,000 orders. The clearest remaining JS wins are `$formatNumber`, regex replacement with captures, and the negative index path. JS also had a lower `$trim` median in this run, but its timing ranges overlap Jexata's. The new 64-case fixture has more object fields than the old 12-case fixture, so its path and filter times should not be compared directly with the historical table. None of these ratios is a claim about concurrent throughput, memory consumption or end-to-end request latency.

## Reproduce

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
python3 scripts/compare_jsonata.py \
  --reference /tmp/jexata-reference-2.2.0 \
  --rounds 7 --output docs/jsonata_js_comparison.json
python3 scripts/render_jsonata_comparison.py
```

The driver verifies the reference commit, records every round and its engine order, checks that results are stable across rounds, and separates mismatches from comparable workloads. The raw file also records CPU and power metadata, Node flags, an empty-promise floor, exact expressions, iteration counts, result digests and the fixture digest. The benchmark needs Python 3, Node.js and Elixir for development; Jexata itself has no production JavaScript dependency.
