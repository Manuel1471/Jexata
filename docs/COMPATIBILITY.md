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

The deterministic [differential fuzzer](../scripts/differential_fuzz.py) generates bounded expressions from numeric, path, filter, lambda, array, object, conditional, and string-function forms over random JSON inputs. Seed `20261103` produced [1,000 matching results](differential_fuzz_results.json) against the same v2.2.0 reference checkout. The generator covers only its declared grammar; this check supplements the portable suite and does not extend its compatibility claim. Reproduce with `python3 scripts/differential_fuzz.py --count 1000 --seed 20261103`.

Supported areas include paths and predicates, sequence flattening, descendants, defaults, literals, arithmetic, comparisons, array and object constructors, grouping and sorting, blocks, lexical variables, lambdas, closures, function chaining and composition, partial application, immutable transforms, regex literals and core regex functions, higher-order functions, URL encoding, Base64, numeric and string formatting, and selected date/time functions. Many official groups pass completely, including `flattening`, `function-signatures`, `function-formatNumber`, `function-eval`, `function-sort`, `transforms`, and `function-applications`.


Large literal ranges in `$count` are counted analytically through ten million elements. Direct construction of a range is still limited to 100,000 generated values, which can differ from JSONata for expressions outside the portable suite. `$string` preserves the order of object literal keys, including nested literals, but input maps are unordered Elixir values and may stringify in a different key order.

Compilation limits cover source bytes, token count, and nesting. Evaluation has a configurable recursive function depth limit, a 100,000 tail-call iteration limit, a range size limit, and a one-million-codepoint `$pad` limit. `Jexata.evaluate_bounded/3` additionally runs an evaluation in a monitored BEAM process with configurable timeout, maximum process heap, a result-size estimate based on Erlang external-term size, and [Erlang regex match and recursion limits](https://www.erlang.org/docs/29/apps/stdlib/re.html). A separate watcher stops the worker when its caller exits. The copied input counts against the worker heap. It returns `J1005` for timeout, `J1006` for a heap kill, `J1007` for an oversized result, `J1008` for a regex match limit, and `J1009` for an unexpected worker failure. Unknown options return `J0007`. This is an execution boundary, not a complete security sandbox: there is no global step count. Version 1.0.0 is a useful native implementation; validate application-specific expressions before treating it as a full drop-in replacement for JSONata v2.2.0.
