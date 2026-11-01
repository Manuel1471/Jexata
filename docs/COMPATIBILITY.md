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
| Pass | 1,271 |
| Fail | 0 |
| Unsupported | 0 |
| Skipped | 0 |
| Crash | 0 |

The runner counts a match when the result, undefined result, or expected error code agrees. It handles external variable bindings and preserves lone UTF-16 surrogate escapes in expression fixtures when OTP cannot decode them directly. The suite's optional `depth` fixture counts reference evaluator nodes; the runner translates it to Jexata's recursive function call limit at approximately three nodes per call. This translation makes the recursion boundary test reproducible, but it is not a claim that both engines have identical depth accounting. All 1,271 portable cases pass with this runner; this is not a claim of complete JSONata compatibility beyond the suite.

Supported areas include paths and predicates, sequence flattening, descendants, defaults, literals, arithmetic, comparisons, array and object constructors, grouping and sorting, blocks, lexical variables, lambdas, closures, function chaining and composition, partial application, immutable transforms, regex literals and core regex functions, higher-order functions, URL encoding, Base64, numeric and string formatting, and selected date/time functions. Many official groups pass completely, including `flattening`, `function-signatures`, `function-formatNumber`, `function-eval`, `function-sort`, `transforms`, and `function-applications`.

Large literal ranges in `$count` are counted analytically through ten million elements. Direct construction of a range is still limited to 100,000 generated values, which can differ from JSONata for expressions outside the portable suite. `$string` preserves the order of object literal keys, including nested literals, but input maps are unordered Elixir values and may stringify in a different key order.

Compilation limits cover source bytes, token count, and nesting. Evaluation has a configurable recursive function depth limit, a 100,000 tail-call iteration limit, and a range size limit, but no general time, step, memory, output size, or regular expression budget. Do not evaluate arbitrary untrusted expressions without an external execution boundary. Version 1.0.0 is a useful native implementation; validate application-specific expressions before treating it as a full drop-in replacement for JSONata v2.2.0.
