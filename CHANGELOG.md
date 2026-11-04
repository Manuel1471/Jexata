# Changelog

## 1.0.0

- Added a native JSONata subset with reusable compiled expressions and structured errors.
- Added paths, sequences, operators, constructors, grouping and sorting, blocks, closures, chaining, composition, partial application, transforms, regex, and selected built-ins.
- Added compilation limits, ExUnit coverage, a reference compatibility runner, and a reproducible benchmark script.
- Added Hex package metadata, an MIT license, and CI with publication on `master` after passing checks.
- Split constructors, path selection, and regex callbacks into focused modules; CI enforces 1,300 physical lines for the main evaluator and a 70% ExUnit coverage floor.
- Linked bounded evaluation workers to their watcher so an externally killed watcher also stops its worker.
- Added `$random` and `$clone` for ordinary JSON-shaped inputs and expanded differential fuzzing to 20,000 local cases plus two nightly random-seed batches.

The complete JSONata v2.2.0 reference fixture set reports 1,676 passing, three output-order differences, zero unsupported, and zero skipped cases. The earlier 1,271/1,271 result covered only `case*.json` files. The remaining differences are `$keys(%)` order on native Elixir input maps. Version 1.0.0 adds date/time picture parsing and formatting, integer-picture functions, `$now`, `$millis`, focus and index joins, and parent navigation. Comparator `$sort` uses a stable merge sort, numeric operators and ASCII string operations have fast paths, `$pad` has a one-million-codepoint output limit, and CI checks reduction budgets for selected workloads. See `docs/COMPATIBILITY.md` for details and execution limits.

The compiler folds scalar and nested constant arrays, constant objects, safe arithmetic and concatenation, small ranges, and constant conditionals. It prepares path dispatch, filter predicate kind, closure references, signed lambda descriptors, and non-invoking lambda bodies. The evaluator updates independent transform paths in one pass, reuses unchanged output subtrees, scans paths, hot filters, and higher-order callbacks with direct recursion, evaluates field-literal binary operands directly, and dispatches built-ins through a compiled registry, and scans placeholder arguments directly. String functions use ASCII fast paths and iodata serialization; `$number` validates decimal strings without regex. The benchmark records these hot paths, process heap snapshots, and garbage collection counts.

### Performance history

Earlier local runs measured `customer.name` compilation at 8.421 µs before the tokenizer changes and 0.989 µs later. The tokenizer equivalence script agreed on 42 directed and 50,000 generated inputs; median tokenization improved 7.30× for `customer.name`, 7.94× for `$sum(orders.price)`, and 7.21× for `orders[price > 50].price` against the legacy tokenizer. A long ASCII string literal fell from 40.528 to 1.723 µs per tokenization in a dedicated comparison.

Other historical comparisons measured `$zip` on two 1,000-item arrays at about 1,271 → 97 µs, canonical `$toMillis` at 1.782 → 0.538 µs, and comparator `$sort` on 1,000 items at 152,581 → 1,479 µs after stable merge sort replaced insertion sort. These timings came from separate local runs and should not be treated as paired release benchmarks. The current paired comparison and the filter regression bisect are in [docs/BENCHMARK.md](docs/BENCHMARK.md).
