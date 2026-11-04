# Changelog

## 1.0.0

Jexata compiles and evaluates JSONata expressions over native Elixir data. The public API supports reusable compiled expressions, external bindings, structured errors, and bounded evaluation with time, process-heap, result-size, and regex limits.

The language implementation includes paths, predicates, constructors, grouping and sorting, variables, lambdas, higher-order functions, partial application, transforms, regex, numeric and string functions, and date/time and integer pictures. It has no production dependency on JavaScript or a database.

The complete JSONata.js v2.2.0 fixture suite gives **1,676 passes out of 1,679**. The three remaining failures involve the source order of keys in input objects, which native Elixir maps do not retain. The [compatibility report](docs/COMPATIBILITY.md) records this limit and the test method. The [64-expression comparison](docs/JSONATA_JS_COMPARISON.md) records matching results and timing ranges against the reference implementation.

CI checks two Elixir/OTP combinations, static analysis, format, compilation warnings, tests and coverage, the reference fixture baseline, performance guards, package contents, and the 1,300-line source-file limit. Publication to Hex is configured for a passing push to `master` when the version is new.
