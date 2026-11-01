# Architecture

`Jexata` is the public facade. `compile/2` checks source limits, tokenizes, parses, and returns an immutable `Jexata.Expression` containing an AST. `evaluate/2` walks that AST against the supplied Elixir value. There is no global process or cache.

`Jexata.Tokenizer` emits tokens with byte offsets. `Jexata.Parser` uses precedence climbing for operators and builds tuple AST nodes. `Jexata.Evaluator` evaluates nodes with a per-call context containing the root value and lexical bindings. `Jexata.Runtime.Closure` captures bindings for anonymous functions. `Jexata.Functions` dispatches selected built-ins to small groups.

`Jexata.Runtime.Value` distinguishes undefined from JSON null (`nil`), and sequences from explicit arrays. At the public boundary, undefined becomes `:undefined`, a sequence of multiple values becomes a list, and an explicit array remains a list. `Jexata.Semantics` owns boolean conversion, path selection, and basic comparison rules.

The implementation is pure Elixir and does not compile or evaluate user expressions as Elixir code. Compiled expressions are immutable and can be shared between BEAM processes. Evaluation currently has no general step or time budget.
