# Local benchmark

Run `MIX_ENV=prod mix run scripts/benchmark.exs` to measure compilation, evaluation of a compiled expression, and compile-plus-evaluate (`run/2`). Each reported value is the mean of the row's `iterations` after one warm-up call. The script reports elapsed microseconds, BEAM reductions, the process heap size after measurement in words, and VM-wide garbage collections per operation. It uses generated maps with 10, 100, or 1,000 orders, plus a root-array input. Results are local measurements, not a comparison with the JavaScript reference.

Measurement environment: Mac16,12 (arm64), Elixir 1.20.2, OTP 29, 10 online schedulers. Selected results from the 1.0.0 run, in microseconds per operation:

| Expression | Orders | Compile µs | Evaluate µs | Run µs | Evaluate reductions |
| --- | ---: | ---: | ---: | ---: | ---: |
| `customer.name` | 10 | 0.989 | 0.421 | 0.887 | 48 |
| `orders[price > 50].price` | 100 | 2.646 | 7.393 | 9.976 | 3,397 |
| `$sum(orders.price)` | 100 | 1.351 | 3.272 | 4.489 | 1,973 |
| `orders[price > 50].price` | 1,000 | 2.708 | 109.727 | 117.153 | 40,403 |
| `$sum(orders.price)` | 1,000 | 1.474 | 32.759 | 39.048 | 19,090 |

The script reports compilation, evaluation, and `run/2` measurements for each expression and size. Repeated runs may vary with system load and BEAM runtime state. Reductions are less sensitive to that timing noise. Heap size is a process snapshot, not allocated bytes per operation; VM-wide garbage collection counts include other processes and are diagnostic only. The benchmark does not measure peak memory, tail latency, or adversarial expressions.

## Evaluator hot paths

The benchmark now includes `$map` with a lambda, string functions inside `$map`, `$reduce` with a lambda, recursive calls inside `$reduce`, and `$sort` with a comparator. The last four use fewer iterations than simple paths so a quadratic sort cannot dominate the entire run. Selected compiled evaluation results for 1,000 orders on the same host:

| Workload | Before µs/op | After µs/op | Before reductions/op | After reductions/op |
| --- | ---: | ---: | ---: | ---: |
| `orders[price > 50].price`, numeric fast path | 111.394 | 91.578 | 40,434 | 30,443 |
| `$map(orders, function($o){$o.price * 2})`, exact arity binding | 232.862 | 208.692 | 96,155 | 90,144 |
| Recursive `$reduce`, targeted closure bindings | 1,956.920 | 1,967.020 | 558,099 | 498,184 |
| `$sort` with comparator, stable merge sort | 152,581.280 | 1,478.820 | 65,973,184 | 693,908 |

These are separate local runs; microsecond values are affected by host load. The reduction changes are the stronger evidence. `mix profile.eprof` on `$sum(orders.price)` showed that selecting and flattening `orders.price` dominates its cost; aggregate validation and `Enum.sum/1` were smaller contributors. A profile of `$map` showed repeated signature binding and process dictionary operations, motivating the exact arity change. A direct 1,000-character ASCII function comparison found `$length` at 17.431 versus 2.137 µs, `$substring` at 10.355 versus 2.223 µs, and `$pad` at 22.267 versus 6.379 µs per call before and after the ASCII paths.

### Additional compiled evaluation workloads

| Workload on 1,000 orders | Earlier µs/op | Current µs/op | Earlier reductions/op | Current reductions/op |
| --- | ---: | ---: | ---: | ---: |
| `price in [10,20,30]` filter, scalar array folding | 188.208 | 86.353 | 89,256 | 31,105 |
| Transform all orders, batched independent paths | 3,488.720 | 384.480 | 1,607,864 | 100,168 |
| `$number($string(price))` across orders | 3,397.850 | 656.580 | 177,578 | 149,449 |
| Signed lambda across orders | 349.940 | 269.647 | 163,174 | 131,280 |

The transform benchmark uses a list of 1,000 objects. Independent paths are updated together; overlapping paths retain sequential evaluation. Returning an unchanged nested 1,000-object subtree measured 106.474 to 72.807 µs and 51,203 to 46,161 reductions per call in a dedicated comparison. These timings come from separate runs and are indicative; the reduction counts are more stable.

### Earlier 1.0.0 candidate

After static path dispatch, prepared lambda metadata, short argument evaluation, arity-aware `$map`/`$filter`, one-pass numeric aggregates, and builtin registry dispatch, a local `MIX_ENV=prod mix run scripts/benchmark.exs` run measured the following compiled evaluation workloads. These are current values, not paired before/after trials.

| Workload on 1,000 orders | µs/op | Reductions/op |
| --- | ---: | ---: |
| `orders[price > 50].price` | 78.043 | 27,587 |
| `$sum(orders.price)` | 25.208 | 15,116 |
| `$map(orders, function($o){$o.price * 2})` | 208.101 | 63,173 |
| Recursive `$reduce` | 1,610.960 | 380,876 |
| `$sort` with comparator | 1,205.560 | 471,920 |
| `$number($string(price))` across orders | 486.940 | 106,760 |

The reduction guard baselines were refreshed from the median of three identical local runs after these changes. The guard retains its 25% ceiling.

### Further local optimization pass

The next pass removed intermediate index lists from path filters, scanned `$reduce` callbacks and long argument lists directly, checked compilation limits in one traversal, and used a stable key sort for one ascending key. It also prepared `$replace` templates once per call, added an ASCII `$trim` path, and built nested `$string` output as iodata. A later local run on the same host measured 1,000-order compiled evaluation at 91.956 µs and 25,584 reductions for the numeric filter, 88.786 µs and 29,096 reductions for the literal-membership filter, 168.666 µs and 62,166 reductions for `$map` with a lambda, and 1,765.290 µs and 376,027 reductions for recursive `$reduce`. These timing samples are from a separate run and should not be read as paired speedups. The reduction guard baselines were refreshed from the median of three measurements with the same 25% ceiling.

A subsequent compile pass identified lambda bodies that cannot invoke functions and avoided process dictionary writes for those calls. Field versus literal binary operations also evaluate the field directly. A fresh 1,000-order run measured 21,583 reductions for the numeric filter, 25,100 for the literal-membership filter, 57,167 for `$map` with a lambda, and 442,345 for `$sort` with a comparator. The new ascending-key workload `orders^(price).price` measured 138.960 µs and 62,219 reductions. These values come from one local run; timing varies with host load. A further direct-recursion change in path selection measured 49,167 reductions and 139.806 µs for `$map`, 363,546 reductions and 977.790 µs for comparator `$sort`, and 61,015 reductions and 112.790 µs for ascending-key sort on a subsequent run. The corresponding reduction guard medians are 49,929, 366,914, and 62,660. Index binding on `orders#$i.price` measured 141.272 µs and 45,308 reductions with the previous `flat_map`/`with_index` path versus 113.316 µs and 35,933 reductions with direct recursion in a dedicated local comparison; its new guard median is 35,651 reductions.

A direct 440-byte ASCII `$trim` comparison measured 31.464 µs per call with the previous Unicode regex path and 6.382 µs with the ASCII path. This is a dedicated local comparison, not a general string benchmark. An experiment that encoded binary operators as atoms in the optimized AST increased reductions in the filter and lambda workloads; it was reverted.

CI runs `scripts/reductions_guard.exs` against the recorded [reduction baselines](../scripts/reductions_baseline.json). It checks fourteen representative 1,000-order workloads and fails when a measurement exceeds 125% of its baseline. The margin accommodates runtime and host differences while catching large algorithmic regressions such as comparator sort returning to quadratic insertion or transforms returning to repeated list updates.

## Tokenizer comparison

The tokenizer optimization is compared with the implementation immediately before commit `5f41bbd`. Reproduce the check with:

```bash
git show 5f41bbd^:lib/jexata/tokenizer.ex \
  | sed 's/defmodule Jexata\.Tokenizer do/defmodule Jexata.TokenizerLegacy do/' \
  > /tmp/jexata_tokenizer_legacy.ex
MIX_ENV=prod mix run scripts/tokenizer_bench.exs /tmp/jexata_tokenizer_legacy.ex
```

The script first compares exact tokenizer results, including errors and positions, on 42 directed inputs and 50,000 deterministic generated inputs. It stops before timing if any differ. It then alternates 25 batches of 1,000 calls per implementation for each expression. Results on the same Mac16,12 host, in microseconds per tokenization:

| Expression | Legacy median | Optimized median | Legacy p95 | Optimized p95 | Median speedup |
| --- | ---: | ---: | ---: | ---: | ---: |
| `customer.name` | 7.238 | 0.991 | 8.814 | 1.348 | 7.30× |
| `$sum(orders.price)` | 13.043 | 1.643 | 13.265 | 1.694 | 7.94× |
| `orders[price > 50].price` | 21.601 | 2.995 | 21.971 | 3.052 | 7.21× |
| `añb.日本語` | 7.347 | 2.615 | 7.448 | 2.687 | 2.81× |

The official compatibility suite now passes all 1,271 portable cases; the measurements in this section were taken before the final compatibility fixes. Full compilation of `customer.name` measured 8.421 µs per call before the tokenizer optimization and 0.989 µs per call in this run on the same host; these are separate runs and should be treated as indicative rather than a controlled compiler comparison. The fused filter path reduced compiled evaluation on 1,000 orders from 139.573 to roughly 107–110 µs per operation in separate benchmark runs. A dedicated process measurement also dropped from about 52,116 to 40,494 reductions per operation. Increasing `min_heap_size` to 100,000 reduced the original filter timing from about 150 to 125 µs without materially changing reductions, which supports GC pressure as one contributor.

Additional local before/after measurements used compiled expressions on the same host. `$zip` with two 1,000-item arrays fell from about 1,271 to 97 µs and from 1,050,483 to 32,687 reductions per operation after replacing indexed list access with `Enum.zip/1`. The canonical `$toMillis('2024-06-17T13:42:11.123Z')` path fell from 1.782 to 0.538 µs and from 148 to 131 reductions by trying the ISO parser before the abbreviated-format regexes. These are separate runs, so timing ratios are indicative.

The tokenizer equivalence script still agrees on 42 directed and 50,000 generated inputs after first-byte dispatch, byte-pattern symbol dispatch, and contiguous quoted spans. Compared with the tokenizer before these three changes, median tokenization improved 1.25× for `customer.name`, 1.30× for `$sum(orders.price)`, and 1.22× for `orders[price > 50].price`. A 1,000-character ASCII string literal fell from 40.528 to 1.723 µs and from 2,866 to 218 reductions per tokenization in a dedicated local measurement. The long-string result should not be generalized to all compilation.

Profiling the 1,000-order filter with `mix profile.eprof` showed 1,000,000 predicate checks over 1,000 evaluations, with repeated AST dispatch, comparisons, field selections, and list traversals accounting for most observed work. `Limits` and builtin lookup were not material in that profile. Regex literals are compiled by the parser when the expression is compiled. Converting the whole AST to anonymous functions or adding a global cache would add complexity without evidence from this profile; compile once and reuse the expression for repeated evaluation.
