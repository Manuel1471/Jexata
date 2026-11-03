# Benchmark comparison

This is the current 1.0.0 comparison. The base is commit `b9d0016` and the candidate is `5c8b908`. The workloads, raw observations, and summary statistics are in [benchmark_comparison_results.json](benchmark_comparison_results.json). Exact expressions and iteration counts are in `scripts/benchmark_compare.exs`.

On a Mac16,12 (arm64), Elixir 1.20.2 / OTP 29, each commit ran in a separate detached Git worktree. Five rounds alternated checkout order: base/current, current/base, and so on. Each workload used a fresh BEAM process, three warm-up calls, and 30–10,000 measured calls depending on cost. The table reports the median and min–max of the five per-operation times, median reductions, and median **minor GCs of that workload's process**. The two checkouts returned the same result hash for all 22 workloads. A negative time delta means the candidate was faster.

The common input has 1,000 orders with price, customer, text, padded text, decimal text, non-canonical date text, and milliseconds. It also has a 1,000-entry catalog for wildcard selection. `compile_field` measures compilation; all other rows evaluate a previously compiled expression. The added coverage includes grouping with an object constructor, descendants, wildcards, index predicates, chaining, regex match and replacement per item, non-canonical `$toMillis`, `$fromMillis`, `$formatNumber`, `$merge`, and `$spread`.

## Paired results

| Workload | Base `b9d0016` µs med [min–max] | Current `5c8b908` µs med [min–max] | Δ time | Reductions med base → current | Minor GCs/op med base → current |
| --- | ---: | ---: | ---: | ---: | ---: |
| `compile_field` | 0.67 [0.64–1.04] | 0.61 [0.60–0.62] | -8.8% | 274 → 267 (-2.5%) | 0.016 → 0.025 |
| `filter` | 100.17 [99.06–102.41] | 96.36 [94.19–97.04] | -3.8% | 27,700 → 25,754 (-7.0%) | 1.550 → 0.933 |
| `sum` | 41.58 [41.11–43.31] | 41.51 [40.62–43.07] | -0.2% | 15,248 → 13,247 (-13.1%) | 0.799 → 0.799 |
| `map_lambda` | 189.19 [186.91–191.70] | 145.75 [142.23–146.95] | -23.0% | 63,284 → 49,469 (-21.8%) | 0.817 → 1.830 |
| `reduce_recursive` | 1,683.70 [1,665.17–1,699.80] | 1,605.47 [1,560.13–1,634.97] | -4.6% | 381,970 → 354,204 (-7.3%) | 12.133 → 39.367 |
| `sort_comparator` | 1,521.10 [1,511.97–1,596.10] | 1,269.93 [1,244.73–1,273.20] | -16.5% | 521,911 → 413,242 (-20.8%) | 5.833 → 4.667 |
| `group_object` | 154.59 [152.17–160.40] | 149.30 [145.75–152.09] | -3.4% | 25,909 → 24,786 (-4.3%) | 0.150 → 2.580 |
| `descendants` | 351.17 [334.95–368.07] | 327.35 [325.60–339.02] | -6.8% | 203,207 → 205,687 (+1.2%) | 0.130 → 0.040 |
| `wildcard` | 56.75 [55.34–58.70] | 56.01 [55.56–56.81] | -1.3% | 23,695 → 21,675 (-8.5%) | 1.990 → 1.990 |
| `index_zero` | 13.29 [12.54–13.80] | 0.20 [0.18–0.20] | -98.5% | 7,141 → 80 (-98.9%) | 0.625 → 0.001 |
| `index_negative` | 18.56 [18.07–18.65] | 1.73 [1.66–1.94] | -90.7% | 11,140 → 1,142 (-89.7%) | 1.291 → 0.001 |
| `chain_sum` | 41.86 [41.38–42.93] | 41.89 [40.45–42.97] | +0.1% | 15,319 → 13,316 (-13.1%) | 1.334 → 1.334 |
| `match_each` | 1,046.64 [1,035.39–1,414.76] | 1,023.73 [1,019.40–1,042.78] | -2.2% | 176,583 → 162,825 (-7.8%) | 0.040 → 0.360 |
| `replace_each` | 1,884.41 [1,856.53–1,967.09] | 682.51 [655.82–733.00] | -63.8% | 171,409 → 94,290 (-45.0%) | 2.210 → 0.270 |
| `trim_each` | 1,913.25 [1,892.75–2,021.69] | 1,737.13 [1,689.87–1,760.08] | -9.2% | 157,564 → 133,171 (-15.5%) | 1.340 → 0.770 |
| `number_float_each` | 3,285.30 [3,133.86–3,422.52] | 500.21 [484.66–521.12] | -84.8% | 142,723 → 105,736 (-25.9%) | 3.870 → 1.890 |
| `to_millis_picture` | 3,373.48 [3,320.74–3,506.92] | 3,371.58 [3,346.70–3,553.24] | -0.1% | 464,960 → 451,014 (-3.0%) | 4.840 → 4.800 |
| `from_millis_each` | 564.32 [550.09–587.39] | 556.24 [545.18–586.92] | -1.4% | 161,610 → 149,558 (-7.5%) | 1.480 → 1.600 |
| `format_number_each` | 7,182.02 [7,122.64–7,671.82] | 7,322.78 [7,168.68–7,734.68] | +2.0% | 1,367,430 → 1,353,669 (-1.0%) | 0.320 → 0.860 |
| `merge_objects` | 16.96 [16.55–17.00] | 16.84 [16.60–17.98] | -0.7% | 7,149 → 7,147 (-0.0%) | 0.010 → 0.010 |
| `spread_each` | 754.56 [742.71–764.15] | 735.52 [731.05–753.99] | -2.5% | 287,609 → 283,583 (-1.4%) | 0.230 → 0.220 |
| `serialize_orders` | 912.30 [900.47–1,330.71] | 918.96 [914.46–930.06] | +0.7% | 307,551 → 307,393 (-0.1%) | 0.060 → 0.270 |

## Reading the result

- The decimal `$number` workload remains the largest gain: 3,285.30 → 500.21 µs/op. Literal `[0]` now selects directly and falls from 13.29 to 0.20 µs/op.
- The filter regression was traced to `69c64cd`, which inlined field-literal binary evaluation. Removing that shortcut in `bc2139c` improved the filter despite raising reductions relative to the immediately preceding revision. In this five-round release comparison, filter time is 100.17 → 96.36 µs/op (-3.8%), with reductions 27,700 → 25,754. See [filter_regression_analysis.json](filter_regression_analysis.json) for focused predicate and selection measurements.
- Exact-arity closure binding was improved in `959e9b0`; a paired five-round run against `bc2139c` measured `$map` with lambda at 151.36 → 143.53 µs/op (−5.2%). Plain unflagged ASCII regex patterns are now dispatched through binary operations in resolved `$replace`, `$contains`, and `$split` calls; the broad `replace_each` workload falls from 1,884.41 to 682.51 µs/op. Small or overlapping time differences should not be inferred as wins solely from lower reductions.
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

## Reproduce

```bash
python3 scripts/compare_checkouts.py \
  --base b9d0016 --current 5c8b908 --rounds 5 \
  --output docs/benchmark_comparison_results.json
mix run scripts/time_canaries.exs
MIX_ENV=prod mix run scripts/benchmark.exs
```

`compare_checkouts.py` creates and removes temporary detached worktrees, alternates the checkouts, checks identical result hashes, and writes every round plus the summary. `benchmark.exs` remains the broader compilation/evaluation/one-shot smoke benchmark for 10, 100, and 1,000 orders; it now reports process minor GCs/op. Historical benchmark milestones have moved to `CHANGELOG.md`.

## Concurrent throughput

`MIX_ENV=prod mix run scripts/concurrent_benchmark.exs` evaluates one compiled filter against the same immutable 1,000-order input from 1, 4, or 10 BEAM processes. Each process performs 1,000 evaluations per round. Three rounds report per-process operation latency and overall throughput; the result hashes must agree. On this Mac16,12, median throughput was about 13,175, 40,555, and 72,649 evaluations/second, respectively; the median p99 latencies were 107, 165, and 253 µs. These are local diagnostics, not service-level targets.

The [nightly benchmark workflow](../.github/workflows/benchmark.yml) runs the JSONata.js comparison and concurrent benchmark on Ubuntu 24.04 x86, then uploads raw artifacts. Its schedule takes effect when the workflow is on the repository's default branch. It does not fail CI for timing changes, because cross-host microsecond thresholds would be unreliable.
