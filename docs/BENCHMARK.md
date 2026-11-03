# Benchmark comparison

This is the current 1.0.0 comparison. The base is commit `b9d0016` and the candidate is `959e9b0`. The workloads, raw observations, and summary statistics are in [benchmark_comparison_results.json](benchmark_comparison_results.json). Exact expressions and iteration counts are in `scripts/benchmark_compare.exs`.

On a Mac16,12 (arm64), Elixir 1.20.2 / OTP 29, each commit ran in a separate detached Git worktree. Five rounds alternated checkout order: base/current, current/base, and so on. Each workload used a fresh BEAM process, three warm-up calls, and 30–10,000 measured calls depending on cost. The table reports the median and min–max of the five per-operation times, median reductions, and median **minor GCs of that workload's process**. The two checkouts returned the same result hash for all 22 workloads. A negative time delta means the candidate was faster.

The common input has 1,000 orders with price, customer, text, padded text, decimal text, non-canonical date text, and milliseconds. It also has a 1,000-entry catalog for wildcard selection. `compile_field` measures compilation; all other rows evaluate a previously compiled expression. The added coverage includes grouping with an object constructor, descendants, wildcards, index predicates, chaining, regex match and replacement per item, non-canonical `$toMillis`, `$fromMillis`, `$formatNumber`, `$merge`, and `$spread`.

## Paired results

| Workload | Base `b9d0016` µs med [min–max] | Current `959e9b0` µs med [min–max] | Δ time | Reductions med base → current | Minor GCs/op med base → current |
| --- | ---: | ---: | ---: | ---: | ---: |
| `compile_field` | 0.65 [0.64–0.65] | 0.62 [0.61–0.63] | -4.3% | 274 → 267 (-2.5%) | 0.016 → 0.025 |
| `filter` | 98.92 [98.05–99.56] | 96.60 [94.34–97.90] | -2.3% | 27,700 → 25,754 (-7.0%) | 1.550 → 0.933 |
| `sum` | 41.95 [40.89–42.43] | 41.05 [40.58–41.83] | -2.1% | 15,248 → 13,247 (-13.1%) | 0.799 → 0.799 |
| `map_lambda` | 190.76 [184.94–201.03] | 146.65 [142.96–153.06] | -23.1% | 63,284 → 49,469 (-21.8%) | 0.817 → 1.830 |
| `reduce_recursive` | 1,658.17 [1,647.60–1,690.67] | 1,590.63 [1,571.37–1,592.67] | -4.1% | 381,971 → 354,226 (-7.3%) | 12.133 → 40.533 |
| `sort_comparator` | 1,536.20 [1,490.53–1,567.53] | 1,265.37 [1,234.27–1,280.97] | -17.6% | 521,910 → 413,241 (-20.8%) | 5.833 → 4.667 |
| `group_object` | 151.93 [150.23–159.18] | 148.91 [145.98–150.43] | -2.0% | 25,909 → 24,786 (-4.3%) | 0.150 → 2.580 |
| `descendants` | 330.89 [324.59–365.42] | 324.06 [317.66–331.84] | -2.1% | 203,206 → 205,683 (+1.2%) | 0.130 → 0.040 |
| `wildcard` | 56.21 [55.79–56.60] | 55.80 [55.44–56.46] | -0.7% | 23,695 → 21,675 (-8.5%) | 1.990 → 1.990 |
| `index_zero` | 12.98 [12.59–13.57] | 0.19 [0.19–0.20] | -98.5% | 7,141 → 80 (-98.9%) | 0.625 → 0.001 |
| `index_negative` | 18.18 [17.89–19.25] | 1.74 [1.68–1.75] | -90.5% | 11,140 → 1,142 (-89.7%) | 1.291 → 0.001 |
| `chain_sum` | 42.14 [41.12–43.05] | 40.95 [40.87–42.54] | -2.8% | 15,319 → 13,316 (-13.1%) | 1.334 → 1.334 |
| `match_each` | 1,036.61 [1,035.05–1,058.76] | 1,018.25 [1,013.93–1,050.47] | -1.8% | 176,578 → 162,400 (-8.0%) | 0.040 → 1.140 |
| `replace_each` | 1,881.42 [1,857.97–1,984.67] | 1,890.80 [1,860.85–2,014.40] | +0.5% | 171,407 → 190,568 (+11.2%) | 2.210 → 1.500 |
| `trim_each` | 1,901.00 [1,870.91–2,039.85] | 1,730.67 [1,706.13–1,759.63] | -9.0% | 157,564 → 133,206 (-15.5%) | 1.340 → 0.220 |
| `number_float_each` | 3,425.69 [3,255.36–3,435.08] | 507.22 [498.49–514.59] | -85.2% | 142,723 → 105,698 (-25.9%) | 3.870 → 0.230 |
| `to_millis_picture` | 3,515.76 [3,238.36–3,620.26] | 3,405.40 [3,352.68–3,426.54] | -3.1% | 464,960 → 450,982 (-3.0%) | 4.840 → 4.820 |
| `from_millis_each` | 561.06 [545.28–571.77] | 553.49 [538.10–556.56] | -1.3% | 161,609 → 149,580 (-7.4%) | 1.070 → 1.460 |
| `format_number_each` | 7,171.82 [7,067.28–7,443.62] | 7,204.28 [6,992.28–7,407.76] | +0.5% | 1,367,173 → 1,353,345 (-1.0%) | 0.680 → 1.160 |
| `merge_objects` | 17.05 [16.84–17.39] | 17.25 [16.58–17.35] | +1.2% | 7,149 → 7,147 (-0.0%) | 0.010 → 0.010 |
| `spread_each` | 744.48 [730.17–759.58] | 727.28 [720.09–740.63] | -2.3% | 287,595 → 282,587 (-1.7%) | 0.230 → 0.190 |
| `serialize_orders` | 894.20 [871.63–908.47] | 898.23 [884.95–916.57] | +0.5% | 307,528 → 307,384 (-0.0%) | 0.060 → 0.270 |

## Reading the result

- The decimal `$number` workload remains the largest gain: 3,425.69 → 507.22 µs/op. Literal `[0]` now selects directly and falls from 12.98 to 0.19 µs/op.
- The filter regression was traced to `69c64cd`, which inlined field-literal binary evaluation. Removing that shortcut in `bc2139c` improved the filter despite raising reductions relative to the immediately preceding revision. In this five-round release comparison, filter time is 98.92 → 96.60 µs/op (-2.3%), with reductions 27,700 → 25,754. See [filter_regression_analysis.json](filter_regression_analysis.json) for focused predicate and selection measurements.
- Exact-arity closure binding was subsequently improved in `959e9b0`; a paired five-round run against `bc2139c` measured `$map` with lambda at 151.36 → 143.53 µs/op (−5.2%). Small or overlapping time differences should not be inferred as wins solely from lower reductions. Minor GC counts come from `Process.info(self(), :garbage_collection)[:minor_gcs]` and depend on each worker's heap; use them as diagnostics.

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

## Time canaries in CI

`mix run scripts/time_canaries.exs` measures four BIF-heavy operations: decimal `$number`, ASCII `$trim`, regex replacement templates, and object serialization. For each operation it measures five alternating batches against a comparable native Elixir/Erlang operation in the same process. CI fails when the median candidate/control time ratio exceeds **2× its recorded baseline ratio** in [time_canaries_baseline.json](../scripts/time_canaries_baseline.json). This relative threshold is more portable than an absolute microsecond ceiling. The script also reports the candidate process's minor GCs/op. It is a coarse regression alarm, not a stable latency SLO.

## Profile of remaining evaluator cost

An earlier `mix profile.eprof` run on the evaluator showed 100,000 lambda invocations for 100 evaluations of `$map` on 1,000 orders. There were 100,000 signature binds, environment merges, and process-depth reads, along with 400,300 `eval/3` calls. In ten evaluations of the recursive `$reduce`, there were 56,000 closure invocations, 102,000 process-depth writes, and 434,060 `eval/3` calls. The exact-arity binding and environment merge paths have since been improved; these historical call counts should not be treated as a current profile. `eprof` tracing also perturbs absolute timings.

For 100 evaluations of the 1,000-order filter, `eprof` recorded 195,100 field selections, 100,000 predicate checks, and 95,100 flattened selected values. The focused bisect above found the regression in field-literal binary evaluation; selection-only time stayed stable. The prior `$sum(orders.price)` profile identified path selection and flattening as more costly than the arithmetic aggregate itself.

## Reproduce

```bash
python3 scripts/compare_checkouts.py \
  --base b9d0016 --current 959e9b0 --rounds 5 \
  --output docs/benchmark_comparison_results.json
mix run scripts/time_canaries.exs
MIX_ENV=prod mix run scripts/benchmark.exs
```

`compare_checkouts.py` creates and removes temporary detached worktrees, alternates the checkouts, checks identical result hashes, and writes every round plus the summary. `benchmark.exs` remains the broader compilation/evaluation/one-shot smoke benchmark for 10, 100, and 1,000 orders; it now reports process minor GCs/op. Historical benchmark milestones have moved to `CHANGELOG.md`.

## Concurrent throughput

`MIX_ENV=prod mix run scripts/concurrent_benchmark.exs` evaluates one compiled filter against the same immutable 1,000-order input from 1, 4, or 10 BEAM processes. Each process performs 1,000 evaluations per round. Three rounds report per-process operation latency and overall throughput; the result hashes must agree. On this Mac16,12, median throughput was about 13,175, 40,555, and 72,649 evaluations/second, respectively; the median p99 latencies were 107, 165, and 253 µs. These are local diagnostics, not service-level targets.

The [nightly benchmark workflow](../.github/workflows/benchmark.yml) runs the JSONata.js comparison and concurrent benchmark on Ubuntu 24.04 x86, then uploads raw artifacts. Its schedule takes effect when the workflow is on the repository's default branch. It does not fail CI for timing changes, because cross-host microsecond thresholds would be unreliable.
