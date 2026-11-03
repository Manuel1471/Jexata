# Changelog

## 1.0.0

- Added a native JSONata subset with reusable compiled expressions and structured errors.
- Added paths, sequences, operators, constructors, grouping and sorting, blocks, closures, chaining, composition, partial application, transforms, regex, and selected built-ins.
- Added compilation limits, ExUnit coverage, a reference compatibility runner, and a reproducible benchmark script.
- Added Hex package metadata, an MIT license, and CI with publication on `master` after passing checks.

The portable JSONata v2.2.0 suite reports 1,271 passing, 0 failing, 0 unsupported, and 0 skipped cases with the documented local runner. Comparator `$sort` now uses a stable merge sort, numeric operators and ASCII string operations have fast paths, `$pad` has a one-million-codepoint output limit, and CI checks reduction budgets for selected workloads. See `docs/COMPATIBILITY.md` for details and execution limits.

The compiler folds scalar and nested constant arrays, constant objects, safe arithmetic and concatenation, small ranges, and constant conditionals. It prepares path dispatch, filter predicate kind, closure references, and signed lambda descriptors. The evaluator updates independent transform paths in one pass, reuses unchanged output subtrees, scans hot filters and higher-order callbacks with direct recursion, and dispatches built-ins through a compiled registry. String functions use ASCII fast paths and iodata serialization. The benchmark records these hot paths, process heap snapshots, and garbage collection counts.
