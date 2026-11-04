# Benchmark comparison

This 1.0.0 comparison measures base commit `b9d0016` and candidate `ab8bfd5`. The workloads, raw observations, and summary statistics are in [benchmark_comparison_results.json](benchmark_comparison_results.json). Exact expressions and iteration counts are in `scripts/benchmark_compare.exs`.

On a Mac16,12 (arm64), Elixir 1.20.2 / OTP 29, each commit ran in a separate detached Git worktree. Five rounds alternated checkout order: base/current, current/base, and so on. Each workload used a fresh BEAM process, three warm-up calls, and 30–10,000 measured calls depending on cost. The table reports the median and min–max of the five per-operation times, median reductions, and median **minor GCs of that workload's process**. The two checkouts returned the same result hash for all 22 workloads. A negative time delta means the candidate was faster.

The common input has 1,000 orders with price, customer, text, padded text, decimal text, non-canonical date text, and milliseconds. It also has a 1,000-entry catalog for wildcard selection. `compile_field` measures compilation; all other rows evaluate a previously compiled expression. The added coverage includes grouping with an object constructor, descendants, wildcards, index predicates, chaining, regex match and replacement per item, non-canonical `$toMillis`, `$fromMillis`, `$formatNumber`, `$merge`, and `$spread`.

## Paired results

| Workload | Base `b9d0016` µs med [min–max] | Current `ab8bfd5` µs med [min–max] | Δ time | Reductions med base → current | Minor GCs/op med base → current |
| --- | ---: | ---: | ---: | ---: | ---: |
| `chain_sum` | 42.23 [41.37–42.88] | 42.70 [40.68–44.00] | +1.1% | 15,319 → 13,316 (-13.1%) | 1.334 → 1.334 |
| `compile_field` | 0.64 [0.63–0.65] | 0.61 [0.61–0.92] | -4.5% | 274 → 255 (-6.9%) | 0.016 → 0.009 |
| `descendants` | 352.24 [326.66–370.70] | 323.97 [320.54–328.57] | -8.0% | 203,208 → 205,687 (+1.2%) | 0.130 → 0.040 |
| `filter` | 99.86 [98.91–102.13] | 96.23 [93.66–97.47] | -3.6% | 27,700 → 25,754 (-7.0%) | 1.550 → 0.933 |
| `format_number_each` | 7,261.90 [7,030.84–7,339.48] | 7,199.08 [7,152.70–7,337.96] | -0.9% | 1,367,430 → 1,353,511 (-1.0%) | 0.320 → 1.380 |
| `from_millis_each` | 556.79 [547.56–574.72] | 543.35 [527.13–573.87] | -2.4% | 161,611 → 149,556 (-7.5%) | 1.480 → 1.600 |
| `group_object` | 151.46 [150.29–162.75] | 149.51 [147.37–151.02] | -1.3% | 25,910 → 24,786 (-4.3%) | 0.150 → 2.580 |
| `index_negative` | 18.24 [17.95–18.85] | 1.89 [1.64–2.04] | -89.6% | 11,140 → 1,142 (-89.7%) | 1.291 → 0.001 |
| `index_zero` | 13.15 [12.48–13.33] | 0.20 [0.19–0.20] | -98.5% | 7,141 → 80 (-98.9%) | 0.625 → 0.001 |
| `map_lambda` | 189.06 [187.24–207.45] | 146.62 [143.15–148.28] | -22.5% | 63,284 → 49,469 (-21.8%) | 0.817 → 1.830 |
| `match_each` | 1,083.32 [1,037.76–1,096.56] | 1,055.11 [1,008.61–1,072.25] | -2.6% | 176,581 → 168,823 (-4.4%) | 0.040 → 0.360 |
| `merge_objects` | 16.91 [16.42–17.44] | 16.99 [16.78–17.60] | +0.5% | 7,149 → 7,147 (-0.0%) | 0.010 → 0.010 |
| `number_float_each` | 3,421.80 [3,220.99–3,466.68] | 501.35 [492.98–627.60] | -85.3% | 142,727 → 105,735 (-25.9%) | 3.870 → 1.890 |
| `reduce_recursive` | 1,679.97 [1,677.87–1,736.57] | 1,573.40 [1,555.37–1,612.00] | -6.3% | 381,970 → 354,204 (-7.3%) | 12.133 → 39.367 |
| `replace_each` | 2,002.39 [1,913.65–2,323.55] | 674.90 [664.38–694.25] | -66.3% | 171,408 → 94,290 (-45.0%) | 2.210 → 0.270 |
| `serialize_orders` | 901.94 [886.61–930.00] | 902.80 [895.02–927.64] | +0.1% | 307,541 → 307,538 (-0.0%) | 0.060 → 0.060 |
| `sort_comparator` | 1,537.80 [1,485.43–1,563.43] | 1,257.60 [1,250.10–1,278.43] | -18.2% | 521,911 → 413,242 (-20.8%) | 5.833 → 4.667 |
| `spread_each` | 754.04 [736.20–758.42] | 735.24 [719.56–776.76] | -2.5% | 287,603 → 283,573 (-1.4%) | 0.230 → 0.220 |
| `sum` | 42.61 [41.65–43.53] | 42.61 [41.00–43.48] | +0.0% | 15,248 → 13,247 (-13.1%) | 0.799 → 0.799 |
| `to_millis_picture` | 3,483.90 [3,398.50–3,517.70] | 3,407.56 [3,313.72–3,483.16] | -2.2% | 464,960 → 451,014 (-3.0%) | 4.840 → 4.800 |
| `trim_each` | 1,990.50 [1,984.43–2,005.46] | 1,723.87 [1,656.04–1,763.12] | -13.4% | 157,564 → 133,170 (-15.5%) | 1.340 → 0.770 |
| `wildcard` | 56.89 [53.94–66.69] | 56.42 [54.24–56.78] | -0.8% | 23,695 → 21,675 (-8.5%) | 1.990 → 1.990 |

## Reading the result

- The decimal `$number` workload is 3,421.80 → 501.35 µs/op (-85.3%); literal `[0]` is 13.15 → 0.20 µs/op (-98.5%).
- The filter regression was traced to `69c64cd`, which inlined field-literal binary evaluation. Removing that shortcut in `bc2139c` improved the filter despite raising reductions relative to the immediately preceding revision. In this five-round release comparison, filter time is 99.86 → 96.23 µs/op (-3.6%); reductions are 27,700 → 25,754. See [filter_regression_analysis.json](filter_regression_analysis.json) for focused predicate and selection measurements.
- Exact-arity closure binding was improved in `959e9b0`; a paired five-round run against `bc2139c` measured `$map` with lambda at 151.36 → 143.53 µs/op (−5.2%). Plain unflagged ASCII regex patterns are now dispatched through binary operations in resolved `$replace`, `$contains`, and `$split` calls; the broad `replace_each` workload is 2,002.39 → 674.90 µs/op (-66.3%). Small or overlapping time differences should not be inferred as wins solely from lower reductions.
- Minor GC counts come from `Process.info(self(), :garbage_collection)[:minor_gcs]` and depend on each worker's heap; use them as diagnostics.

## Filter regression bisect

The focused [filter_profile.exs](../scripts/filter_profile.exs) benchmark separates the full expression, the filter without field selection, the boolean predicate as a path step, and plain field selection. Five alternating rounds immediately before and after `69c64cd` locate the regression in its field-literal binary shortcut:

| Expression | Before `69c64cd` µs med | After `69c64cd` µs med | After removal in `bc2139c` µs med |
| --- | ---: | ---: | ---: |
| `orders[price > 50].price` | 68.48 | 88.37 | 68.93 |
| `orders[price > 50]` | 78.40 | 97.16 | 76.36 |
| `orders.(price > 50)` | 75.02 | 92.69 | 68.82 |
| `orders.price` | 35.13 | 35.35 | 35.66 |

The last column comes from a separate paired run against `cfbe669`, whose full-filter median was 90.91 µs. Therefore the rows are not one continuous three-way trial. See the raw [introduction](filter_regression_bisect.json) and [removal](filter_regression_analysis.json) observations. The broader 22-workload comparison between `cfbe669` and `bc2139c` showed an 18.8% median filter improvement; no other workload moved by more than 5% in that paired run.

```bash
python3 scripts/compare_checkouts.py \
  --base 69c64cd^ --current 69c64cd --rounds 5 \
  --benchmark scripts/filter_profile.exs --output /tmp/filter-introduction.json
python3 scripts/compare_checkouts.py \
  --base cfbe669 --current bc2139c --rounds 5 \
  --benchmark scripts/filter_profile.exs --output /tmp/filter-removal.json
```

## Plain regex fast path

The resolved `$replace`, `$contains`, and `$split` built-ins use binary operations when their regex argument contains only ASCII letters, digits, spaces, underscores, or hyphens and has no flags. Regexes with metacharacters, flags, or replacement templates keep the regex path. This choice is made after built-in resolution, so user-defined functions that shadow these names still receive a regex value.

Five alternating rounds on 1,000 strings measured the following medians; [raw observations](plain_regex_comparison.json) and the [focused script](../scripts/regex_profile.exs) are available:

| Built-in | Before `bb9b98d` µs/op | After `5c8b908` µs/op | Change |
| --- | ---: | ---: | ---: |
| `$replace` | 1,910.45 | 646.70 | −66.1% |
| `$contains` | 526.21 | 438.35 | −16.7% |
| `$split` | 978.09 | 515.55 | −47.3% |

```bash
python3 scripts/compare_checkouts.py \
  --base bb9b98d --current 5c8b908 --rounds 5 \
  --benchmark scripts/regex_profile.exs \
  --output /tmp/plain-regex-comparison.json
```

## Time canaries in CI

`mix run scripts/time_canaries.exs` measures four BIF-heavy operations: decimal `$number`, ASCII `$trim`, regex replacement templates, and object serialization. For each operation it measures five alternating batches against a comparable native Elixir/Erlang operation in the same process. CI fails when the median candidate/control time ratio exceeds **2× its recorded baseline ratio** in [time_canaries_baseline.json](../scripts/time_canaries_baseline.json). This relative threshold is more portable than an absolute microsecond ceiling. The script also reports the candidate process's minor GCs/op. It is a coarse regression alarm, not a stable latency SLO.

## Profile of remaining evaluator cost

An earlier `mix profile.eprof` run on the evaluator showed 100,000 lambda invocations for 100 evaluations of `$map` on 1,000 orders. There were 100,000 signature binds, environment merges, and process-depth reads, along with 400,300 `eval/3` calls. In ten evaluations of the recursive `$reduce`, there were 56,000 closure invocations, 102,000 process-depth writes, and 434,060 `eval/3` calls. The exact-arity binding and environment merge paths have since been improved; these historical call counts should not be treated as a current profile. `eprof` tracing also perturbs absolute timings.

For 100 evaluations of the 1,000-order filter, `eprof` recorded 195,100 field selections, 100,000 predicate checks, and 95,100 flattened selected values. The focused bisect above found the regression in field-literal binary evaluation; selection-only time stayed stable. The prior `$sum(orders.price)` profile identified path selection and flattening as more costly than the arithmetic aggregate itself.

## Evaluator module extraction

Commit `e28a06f` moved binary operators into [the operators module](../lib/jexata/evaluator/operators.ex), reducing `evaluator.ex` from 2,068 to 1,902 lines. A [five-round paired comparison](evaluator_split_comparison.json) against `b1a855e` returned identical result hashes on all 22 workloads. The filter median was 96.31 → 94.98 µs, map with lambda 143.60 → 141.99 µs, and comparator sort 1,250.07 → 1,252.33 µs. No workload had a positive median time change above 0.8%; differences this small are within observed run-to-run noise. This measures the extraction itself, not later safety changes.

## String serialization module extraction

Commit `8e583f5` moved JSON serialization into [the serialization module](../lib/jexata/functions/string/serialization.ex), reducing `functions/string.ex` from 517 to 434 lines. A [five-round paired comparison](string_split_comparison.json) against `50b8a1c` returned identical result hashes on all 22 workloads. `serialize_orders` moved from 911.33 to 875.84 µs/op (−3.9%); no workload had a positive median time change above 5%. The serialization difference is small enough to treat as diagnostic rather than a proven speedup.

## Further evaluator extraction and navigation

Commit `cc9afe0` moved transforms and higher-order functions to focused modules, reducing the main evaluator to 1,441 lines. A [five-round paired comparison](evaluator_modularity_comparison.json) against `3da8ae3` returned identical result hashes on all 22 workloads. The filter median was 96.48 → 96.15 µs/op, map with lambda 143.37 → 143.41, recursive reduce 1,587.90 → 1,578.40, and comparator sort 1,250.80 → 1,252.50. No workload had a positive median time change above 4%.

The navigation implementation adds parent paths, focus and index joins, and date/integer picture support. The main evaluator is 1,487 lines after the direct grouping path restored its previous speed. A second [five-round paired comparison](navigation_comparison.json), `eefc5ab` against `8925601`, returned identical result hashes on all 22 workloads. Median times (µs/op) and reductions are:

| Workload | Before µs | After µs | Before reductions | After reductions |
| --- | ---: | ---: | ---: | ---: |
| Filter, 1,000 orders | 96.84 | 94.23 | 25,754 | 25,758 |
| Object grouping | 149.82 | 150.09 | 24,786 | 24,792 |
| Map with lambda | 145.79 | 148.98 | 50,466 | 52,460 |
| Comparator sort | 1,263.47 | 1,299.70 | 418,142 | 437,909 |
| Recursive reduce | 1,593.37 | 1,590.50 | 355,204 | 357,337 |

The largest positive median change among the 22 workloads was below 3%; this is a check against a broad regression, not proof that each individual operation became faster. The parent-navigation mode is prepared at compile time, so expressions without `%` do not scan their AST during evaluation.

## Evaluator below 1,300 physical lines

Commit `2d3f855` moved constructors, path selection, and regex callbacks to focused modules, leaving `evaluator.ex` at **1,296 physical lines**. CI checks the physical line count with `wc -l`. A [five-round paired comparison](evaluator_1300_comparison.json) against `2c1b0ce` returned identical result hashes for all 22 workloads. Selected medians in µs/op:

| Workload | Before | After | Reductions before → after |
| --- | ---: | ---: | ---: |
| Filter, 1,000 orders | 95.46 | 97.31 | 25,758 → 25,758 |
| Map with lambda | 147.81 | 150.85 | 52,460 → 52,460 |
| Comparator sort | 1,285.17 | 1,337.27 | 437,908 → 437,916 |
| Regex replacement | 688.92 | 685.04 | 97,292 → 97,291 |
| Object serialization | 923.78 | 932.34 | 308,802 → 308,793 |

The largest positive median change was 5.6% for a small object-merge workload; its reduction count stayed the same. The paired run is evidence that the extraction preserved outputs and did not add an algorithmic pass. Timing differences at this scale are diagnostic and may be run-to-run noise.

## Canonical date picture fast path

Commit `7118619` formats `[Y0001]-[M01]-[D01]` directly from the UTC date while retaining the general picture formatter for other formats and out-of-range years. In a [five-round paired comparison](date_picture_fast_path_comparison.json) against `568fdac`, `$fromMillis` with this picture over 1,000 orders moved from **5,002.12 to 456.02 µs/op** (−90.9%) and from 927,752 to 128,256 reductions/op. All 23 workload result hashes agreed; the ordinary `$fromMillis` case moved 547.97 → 553.69 µs/op and the filter 96.91 → 96.98 µs/op. The current [jsonata.js comparison](JSONATA_JS_COMPARISON.md) measures this workload at 465.27 µs/op in Jexata versus 2,666.23 µs/op in JS on the same host.

## Grouped integer picture fast path

Commit `f5096de` handles integer `$formatNumber` values with picture `#,##0` using byte grouping. In a [five-round paired comparison](number_picture_fast_path_comparison.json) against `3781c0d`, the 1,000-order workload moved from **5,722.62 to 254.04 µs/op** (−95.6%) and from 1,141,882 to 67,810 reductions/op. All 24 workload result hashes agreed. The general decimal picture workload `#,###.00` remained at 7,069.62 → 7,080.22 µs/op. The current [jsonata.js comparison](JSONATA_JS_COMPARISON.md) measures `#,##0` at 260.40 µs/op in Jexata versus 3,475.57 µs/op in JS. The special path applies only to integer values and this exact picture; other number formats still use the general formatter.

## Final negative index

Commit `8d70298` selects `[-1]` in one list traversal. The [five-round paired comparison](index_last_comparison.json) against `ca98feb` returned identical result hashes for all 24 workloads. `orders[-1].price` moved from **1.700 to 1.353 µs/op** (−20.4%) and from 1,146 to 573 reductions/op. The `orders[0].price` median changed 0.195 → 0.202 µs/op with the same reduction count, too small an absolute difference to interpret as a regression.

## Reproduce

```bash
python3 scripts/compare_checkouts.py \
  --base b9d0016 --current ab8bfd5 --rounds 5 \
  --output docs/benchmark_comparison_results.json
mix run scripts/time_canaries.exs
MIX_ENV=prod mix run scripts/benchmark.exs
```

`compare_checkouts.py` creates and removes temporary detached worktrees, alternates the checkouts, checks identical result hashes, and writes every round plus the summary. `benchmark.exs` remains the broader compilation/evaluation/one-shot smoke benchmark for 10, 100, and 1,000 orders; it now reports process minor GCs/op. Historical benchmark milestones have moved to `CHANGELOG.md`.

## Concurrent throughput

`MIX_ENV=prod mix run scripts/concurrent_benchmark.exs` evaluates one compiled filter against the same immutable 1,000-order input from 1, 4, or 10 BEAM processes. Each process performs 1,000 evaluations per round. Three rounds report per-process operation latency and overall throughput; the result hashes must agree. On this Mac16,12, median throughput was about 13,175, 40,555, and 72,649 evaluations/second, respectively; the median p99 latencies were 107, 165, and 253 µs. These are local diagnostics, not service-level targets.

The [nightly benchmark workflow](../.github/workflows/benchmark.yml) runs the JSONata.js comparison and concurrent benchmark on Ubuntu 24.04 x86, then uploads raw artifacts. Its schedule takes effect when the workflow is on the repository's default branch. It does not fail CI for timing changes, because cross-host microsecond thresholds would be unreliable.
