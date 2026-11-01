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
| Pass | 1,239 |
| Fail | 13 |
| Unsupported | 10 |
| Skipped | 9 |
| Crash | 0 |

The runner counts a match when the result, undefined result, or expected error code agrees. `Unsupported` means the interpreter returned an unknown-function or parser-syntax error where the reference expected another result. `Skipped` includes cases with external bindings or fixtures rejected by OTP's JSON decoder (such as unpaired UTF-16 surrogates). `Fail` includes all other mismatches. This is **97.5% of all cases** and is not a full compatibility claim.

Supported areas include paths and predicates, sequence flattening, descendants, defaults, literals, arithmetic, comparisons, array and object constructors, grouping and sorting, blocks, lexical variables, lambdas, closures, function chaining and composition, partial application, immutable transforms, regex literals and core regex functions, higher-order functions, URL encoding, Base64, numeric and string formatting, and selected date/time functions. Many official groups pass completely, including `flattening`, `function-signatures`, `function-formatNumber`, `function-eval`, `function-sort`, `transforms`, and `function-applications`.

Remaining differences are concentrated in parser and error-code parity, object stringification order, sort index bindings, and a few syntax cases. Integer ranges are intentionally limited to 100,000 generated values, so two reference cases that request ten million values fail with `D2014`. One reference recursion test requests a depth limit of 302, while Jexata uses its own 1,024-call limit; that case therefore differs.

Compilation limits cover source bytes, token count, and nesting. Evaluation has a recursion depth limit, a 100,000 tail-call iteration limit, and a range size limit, but no general time, step, memory, output size, or regular expression budget. Do not evaluate arbitrary untrusted expressions without an external execution boundary. Version 1.0.0 is a useful native implementation with the documented gaps; it is not a full drop-in replacement for JSONata v2.2.0.
