# JSONata compatibility

Target: [JSONata v2.2.0](https://github.com/jsonata-js/jsonata/releases/tag/v2.2.0), commit `8ee4476f8a228bfc7a62979ae0a9c13a4043cd03`. The [language-neutral test suite](https://github.com/jsonata-js/jsonata/tree/v2.2.0/test/test-suite) is MIT licensed. The suite is not vendored; the runner reads a separately cloned reference checkout.

Run the full check with:

```bash
git clone --depth 1 --branch v2.2.0 https://github.com/jsonata-js/jsonata.git /tmp/jexata-reference-2.2.0
mix run scripts/compatibility.exs /tmp/jexata-reference-2.2.0/test/test-suite --details
```

Result on Elixir 1.20.2 / OTP 29:

| Category | Cases |
| --- | ---: |
| Total | 1,679 |
| Pass | 1,676 |
| Fail | 3 |
| Unsupported | 0 |
| Skipped | 0 |
| Crash | 0 |

The runner reads every JSON file in `groups/*/`. Its previous `case*.json` glob omitted 20 fixture files containing 408 additional cases. The old subset still gives 1,271/1,271 with `--case-files-only`, but it is not the full suite. The runner counts a match when the result, undefined result, or expected error code agrees. It classifies `T1006` and `S0202` mismatches as unsupported, and other mismatches as failures. It handles external variable bindings and preserves lone UTF-16 surrogate escapes in expression fixtures when OTP cannot decode them directly. The suite's optional `depth` fixture counts reference evaluator nodes; the runner translates it to Jexata's recursive function call limit at approximately three nodes per call. This translation makes the recursion boundary test reproducible, but it is not a claim that both engines have identical depth accounting.

The deterministic [differential fuzzer](../scripts/differential_fuzz.py) generates bounded expressions from numeric, path, filter, lambda, array, object, conditional, string, regex, date/time, and error-producing forms over random JSON inputs. Seed `20261103` produced [20,000 cases](differential_fuzz_results.json): one fixed known key-order difference and **zero unexpected mismatches**, including comparisons of error codes. The `$match`-inside-`$map` regression probe now matches. The generator covers only its declared grammar; this check supplements the suite and does not extend its compatibility claim. Reproduce with `python3 scripts/differential_fuzz.py --count 20000 --seed 20261103`. The nightly Linux job runs two additional 10,000-case batches with recorded random seeds.

Supported areas include paths and predicates, sequence flattening, descendants, defaults, literals, arithmetic, comparisons, array and object constructors, grouping and sorting, focus and index joins, parent navigation, blocks, lexical variables, lambdas, closures, function chaining and composition, partial application, immutable transforms, regex literals and core regex functions, higher-order functions, URL encoding, Base64, numeric and string formatting, integer pictures, and date/time pictures. The reference groups for `function-fromMillis`, `function-toMillis`, `function-formatInteger`, `function-parseInteger`, and `joins` now pass completely.

The three reference-fixture mismatches are in the `parent-operator` fixture: `$keys(%)` expects input-object keys in JSON source order, while the runner decodes the fixture to native Elixir maps, which do not retain that order. Parent traversal and the other cases in that group agree. Source order cannot be reconstructed from a native map. Version 1.0.0 accepts native maps and has no ordered-input API, so source key order remains a documented limit. A separate [64-expression differential benchmark](JSONATA_JS_COMPARISON.md) found this ordering difference through `*`; its `$match`-inside-`$map` case now matches the JS array shape. `$random` and `$clone` are implemented for their ordinary JSON-shaped inputs, although the reference fixtures do not exercise them. Jexata's `$clone` returns the immutable native value rather than copying its tree. A passing suite is therefore evidence for the tested expressions, not a claim of complete language or function coverage.


Large literal ranges in `$count` are counted analytically through ten million elements. Direct construction of a range is limited to 1,000,000 generated values, which can differ from JSONata. `$string` preserves the order of object literal keys, including nested literals, but input maps are unordered Elixir values and may stringify in a different key order.

Compilation limits cover source bytes, token count, and nesting. Evaluation has a configurable recursive function depth limit, a 100,000 tail-call iteration limit, a range size limit, and a one-million-codepoint `$pad` limit. `Jexata.evaluate_bounded/3` additionally runs an evaluation in a monitored BEAM process with configurable timeout, maximum process heap, a result-size estimate based on Erlang external-term size, and [Erlang regex match and recursion limits](https://www.erlang.org/docs/29/apps/stdlib/re.html). A separate watcher stops the worker when its caller exits; it also links to the worker so that an externally killed watcher cannot leave it running. The copied input counts against the worker heap. It returns `J1005` for timeout, `J1006` for a heap kill, `J1007` for an oversized result, `J1008` for a regex match limit, and `J1009` for an unexpected worker failure. Unknown options return `J0007`. This is an execution boundary, not a complete security sandbox: there is no global step count. Version 1.0.0 is a useful native implementation; validate application-specific expressions before treating it as a full drop-in replacement for JSONata v2.2.0.
