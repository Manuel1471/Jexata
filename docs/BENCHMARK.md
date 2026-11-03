# Benchmark comparison

This is the current 1.0.0 comparison. The base is commit `b9d0016` and the candidate is `ab3f6f8`. The workloads, raw observations, and summary statistics are in [benchmark_comparison_results.json](benchmark_comparison_results.json). Exact expressions and iteration counts are in `scripts/benchmark_compare.exs`.

On a Mac16,12 (arm64), Elixir 1.20.2 / OTP 29, each commit ran in a separate detached Git worktree. Five rounds alternated checkout order: base/current, current/base, and so on. Each workload used a fresh BEAM process, three warm-up calls, and 30–10,000 measured calls depending on cost. The table reports the median and min–max of the five per-operation times, median reductions, and median **minor GCs of that workload's process**. The two checkouts returned the same result hash for all 22 workloads. A negative time delta means the candidate was faster.

The common input has 1,000 orders with price, customer, text, padded text, decimal text, non-canonical date text, and milliseconds. It also has a 1,000-entry catalog for wildcard selection. `compile_field` measures compilation; all other rows evaluate a previously compiled expression. The added coverage includes grouping with an object constructor, descendants, wildcards, index predicates, chaining, regex match and replacement per item, non-canonical `$toMillis`, `$fromMillis`, `$formatNumber`, `$merge`, and `$spread`.

## Paired results

| Workload | Base `b9d0016` µs med [min–max] | Current `ab3f6f8` µs med [min–max] | Δ time | Reductions med base → current | Minor GCs/op med base → current |
| --- | ---: | ---: | ---: | ---: | ---: |
| `compile_field` | 0.66 [0.65–0.70] | 0.62 [0.61–0.63] | -5.9% | 274 → 267 (-2.5%) | 0.016 → 0.025 |
| `filter` | 100.52 [98.73–133.55] | 115.96 [114.83–118.65] | +15.4% | 27,700 → 21,657 (-21.8%) | 1.550 → 1.249 |
| `sum` | 40.98 [39.42–42.90] | 41.17 [40.68–42.76] | +0.5% | 15,248 → 13,247 (-13.1%) | 0.799 → 0.799 |
| `map_lambda` | 190.32 [183.89–205.54] | 156.10 [152.57–157.69] | -18.0% | 63,284 → 49,469 (-21.8%) | 0.817 → 1.830 |
| `reduce_recursive` | 1,686.33 [1,666.67–1,700.97] | 1,626.77 [1,609.10–1,652.60] | -3.5% | 381,970 → 354,290 (-7.2%) | 12.133 → 42.267 |
| `sort_comparator` | 1,520.80 [1,491.67–1,588.93] | 1,289.73 [1,281.07–1,309.07] | -15.2% | 521,910 → 413,257 (-20.8%) | 5.833 → 4.667 |
| `group_object` | 151.58 [150.89–157.10] | 146.76 [145.61–152.57] | -3.2% | 25,909 → 24,786 (-4.3%) | 0.150 → 2.580 |
| `descendants` | 326.21 [319.55–366.01] | 316.12 [313.35–319.78] | -3.1% | 203,206 → 205,686 (+1.2%) | 0.130 → 0.040 |
| `wildcard` | 55.66 [52.71–56.22] | 53.88 [53.30–56.15] | -3.2% | 23,695 → 21,675 (-8.5%) | 1.990 → 1.990 |
| `index_zero` | 12.78 [12.43–13.18] | 8.81 [8.56–8.94] | -31.1% | 7,141 → 5,132 (-28.1%) | 0.625 → 0.171 |
| `index_negative` | 18.21 [17.89–18.69] | 14.29 [14.21–14.56] | -21.5% | 11,140 → 9,130 (-18.0%) | 1.291 → 0.341 |
| `chain_sum` | 43.64 [40.10–50.23] | 41.26 [40.04–42.80] | -5.4% | 15,319 → 13,316 (-13.1%) | 1.334 → 1.334 |
| `match_each` | 1,046.85 [1,026.35–1,087.59] | 1,039.21 [1,021.34–1,067.43] | -0.7% | 176,580 → 162,823 (-7.8%) | 0.040 → 0.360 |
| `replace_each` | 1,966.89 [1,879.22–2,048.76] | 1,947.23 [1,930.56–2,019.81] | -1.0% | 171,408 → 190,551 (+11.2%) | 2.210 → 0.260 |
| `trim_each` | 1,985.85 [1,869.33–2,673.08] | 1,700.06 [1,680.68–1,736.35] | -14.4% | 157,564 → 133,171 (-15.5%) | 1.340 → 0.770 |
| `number_float_each` | 3,295.60 [3,167.74–3,413.51] | 502.88 [490.74–514.19] | -84.7% | 142,723 → 105,736 (-25.9%) | 3.870 → 1.890 |
| `to_millis_picture` | 3,383.18 [3,326.14–3,511.84] | 3,406.52 [3,403.96–3,476.94] | +0.7% | 464,960 → 451,014 (-3.0%) | 4.840 → 4.800 |
| `from_millis_each` | 567.46 [543.04–578.21] | 556.84 [539.28–577.45] | -1.9% | 161,611 → 149,556 (-7.5%) | 1.480 → 1.600 |
| `format_number_each` | 7,227.74 [7,076.02–7,494.98] | 7,325.56 [7,007.36–7,686.48] | +1.4% | 1,367,430 → 1,353,664 (-1.0%) | 0.320 → 0.860 |
| `merge_objects` | 16.61 [16.06–17.70] | 16.43 [16.32–16.91] | -1.1% | 7,149 → 7,147 (0.0%) | 0.010 → 0.010 |
| `spread_each` | 747.31 [742.31–758.28] | 728.18 [725.81–743.29] | -2.6% | 287,602 → 283,558 (-1.4%) | 0.230 → 0.220 |
| `serialize_orders` | 911.70 [905.89–917.93] | 900.11 [881.98–925.82] | -1.3% | 307,536 → 307,537 (0.0%) | 0.060 → 0.060 |

## Reading the result

- The decimal `$number` workload has the largest measured gain: 3,295.60 → 502.88 µs/op (−84.7%). `$map` with a lambda improved 18.0%, comparator `$sort` 15.2%, `[0]` 31.1%, and `[-1]` 21.5% by median time.
- The filter's median **rose** from 100.52 to 115.96 µs/op (+15.4%) even though reductions fell 21.8% and process minor GCs fell from 1.550 to 1.249/op. This is a real regression for this input and host; the lower reduction count alone does not establish a speedup. The profile below identifies work in selection and flattening, but does not prove the cause of this timing change.
- `$sum`, `$match`, `$replace`, `$fromMillis`, `$formatNumber`, `$merge`, `$spread`, and serialization have small or overlapping time differences here. `$replace` increased reductions by 11.2% while its median time changed by −1.0%. Avoid inferring a time win from reductions alone for BIF-heavy functions.
- Minor GC counts come from `Process.info(self(), :garbage_collection)[:minor_gcs]`, never from VM-wide statistics. They depend on the worker heap size and allocation pattern; individual rows such as `reduce_recursive` and `group_object` should be treated as diagnostics, not allocation benchmarks.

## Time canaries in CI

`mix run scripts/time_canaries.exs` measures four BIF-heavy operations: decimal `$number`, ASCII `$trim`, regex replacement templates, and object serialization. For each operation it measures five alternating batches against a comparable native Elixir/Erlang operation in the same process. CI fails when the median candidate/control time ratio exceeds **2× its recorded baseline ratio** in [time_canaries_baseline.json](../scripts/time_canaries_baseline.json). This relative threshold is more portable than an absolute microsecond ceiling. The script also reports the candidate process's minor GCs/op. It is a coarse regression alarm, not a stable latency SLO.

## Profile of remaining evaluator cost

`mix profile.eprof` on the candidate showed 100,000 lambda invocations for 100 evaluations of `$map` on 1,000 orders. There were 100,000 signature binds, environment merges, and process-depth reads, along with 400,300 `eval/3` calls. In ten evaluations of the recursive `$reduce`, there were 56,000 closure invocations, 102,000 process-depth writes, and 434,060 `eval/3` calls. These counts explain why closure setup and AST dispatch remain the main costs; `eprof` tracing perturbs absolute timings.

For 100 evaluations of the 1,000-order filter, `eprof` recorded 195,100 field selections, 100,000 predicate checks, and 95,100 flattened selected values. The filter timing regression merits a separate allocation and cache-behavior investigation before changing its semantics again. The prior `$sum(orders.price)` profile identified path selection and flattening as more costly than the arithmetic aggregate itself.

## Reproduce

```bash
python3 scripts/compare_checkouts.py \
  --base b9d0016 --current ab3f6f8 --rounds 5 \
  --output docs/benchmark_comparison_results.json
mix run scripts/time_canaries.exs
MIX_ENV=prod mix run scripts/benchmark.exs
```

`compare_checkouts.py` creates and removes temporary detached worktrees, alternates the checkouts, checks identical result hashes, and writes every round plus the summary. `benchmark.exs` remains the broader compilation/evaluation/one-shot smoke benchmark for 10, 100, and 1,000 orders; it now reports process minor GCs/op. Historical benchmark milestones have moved to `CHANGELOG.md`.
