# Jexata

Jexata is a native Elixir implementation of the JSONata query language. It is under development and is **not yet compatible with the complete JSONata language**.

The public API is `Jexata.compile/1`, `Jexata.evaluate/2`, and `Jexata.run/2`, with raising variants. A compiled expression is immutable and intended for reuse. Current evaluation support is described as it is implemented.

JSONata operates on decoded JSON-like Elixir values; it does not replace a JSON decoder such as Jason. Source expressions are treated as data and are never evaluated as Elixir code.

Target reference: JSONata 2.2.0 documentation and [reference implementation](https://github.com/jsonata-js/jsonata). Compatibility testing and a production release are pending.
