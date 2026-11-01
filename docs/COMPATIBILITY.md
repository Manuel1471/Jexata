# JSONata compatibility

Target: [JSONata v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0), commit `8ee4476f8a228bfc7a62979ae0a9c13a4043cd03`. The [language-neutral test suite](https://github.com/jsonata-js/jsonata/tree/v2.2.0/test/test-suite) is MIT licensed. The suite is not vendored; the runner reads a separately cloned reference checkout.

Run the check with:

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
mix run scripts/compatibility.exs /tmp/jexata-reference-2.2.0/test/test-suite
```

Result on Elixir 1.20.2 / OTP 29:

| Category | Cases |
| --- | ---: |
| Total | 1,271 |
| Pass | 655 |
| Fail | 281 |
| Unsupported | 326 |
| Skipped | 9 |
| Crash | 0 |

The runner counts a match when the result, undefined result, or expected error code agrees. `Unsupported` currently means the interpreter returned an unknown-function or parser-syntax error where the reference expected another result. `Skipped` includes cases with external bindings or fixtures rejected by OTP's JSON decoder (such as unpaired UTF-16 surrogates). `Fail` includes all other mismatches. These categories are coarse; the result is a baseline, not a compliance claim.

Current supported areas include basic paths and predicates, descendants, defaults, literals, arithmetic, comparisons, array and object constructors, basic grouping and sorting, blocks, lexical variables, lambdas, chaining of values into functions, a small higher-order subset, and selected built-ins. Major remaining areas include complete grouping and sorting behavior, regex literals and functions, transforms, function chaining/composition, date/time functions, the full built-in library, complete error-code parity, and edge cases in sequence and numeric semantics.

Compilation limits cover source bytes, token count, and nesting. Evaluation does not yet have a general resource budget. Stable 1.0 compatibility has not been achieved.
