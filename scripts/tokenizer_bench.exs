# Run with: MIX_ENV=prod mix run scripts/tokenizer_bench.exs /tmp/tokenizer_legacy.ex
[legacy_path] = System.argv()
Code.require_file(legacy_path)

legacy = Jexata.TokenizerLegacy
current = Jexata.Tokenizer

fixed = [
  "",
  " ",
  "\t\n\r\v\f",
  "\u00A0",
  "customer.name",
  "$sum(orders.price)",
  "orders[price > 50].price",
  "1",
  "0",
  "01",
  "1.2",
  "1e+",
  "1e-2",
  "1.",
  "a_b",
  "añb",
  "日本語",
  "a日本語",
  "$",
  "$$",
  "$foo",
  "$añb",
  "a.b",
  "a..b",
  "~> := != <= >= ** .. ?? ?: ",
  "/* comment */a",
  "/* unclosed",
  "'hello'",
  "'\\n'",
  "'\\y'",
  "'unterminated",
  "`name`",
  "`unterminated",
  "\"\\uD834\\uDD1E\"",
  "/hat/i",
  "/[a-z]+/",
  "/unterminated",
  "a / b",
  "[1..10]",
  "(x := 1; x)",
  "@ # ^",
  "é x"
]

fragments = [
  "a",
  "abc",
  "_x",
  "$x",
  "$$",
  ".",
  "..",
  "0",
  "01",
  "42",
  "1.2",
  "2e+",
  "e-3",
  " ",
  "\t",
  "\n",
  "\u00A0",
  "añb",
  "日本語",
  "💩",
  "+",
  "-",
  "~>",
  "[",
  "]",
  "(",
  ")",
  "{",
  "}",
  "'x'",
  "'\\y'",
  "\"x\"",
  "`x`",
  "/* c */",
  "/*",
  "/a+/i",
  "/",
  "?",
  ":",
  "&"
]

:rand.seed(:exsss, {11, 22, 33})

random_sources =
  for _ <- 1..50_000 do
    count = :rand.uniform(8)
    for _ <- 1..count, into: "", do: Enum.at(fragments, :rand.uniform(length(fragments)) - 1)
  end

mismatches =
  (fixed ++ random_sources)
  |> Enum.reduce([], fn source, acc ->
    old = legacy.tokenize(source)
    new = current.tokenize(source)
    if old == new, do: acc, else: [{source, old, new} | acc]
  end)
  |> Enum.take(5)

if mismatches != [] do
  Enum.each(Enum.reverse(mismatches), fn mismatch -> IO.inspect(mismatch, label: "Mismatch") end)
  System.halt(1)
end

IO.puts("Equivalence: OK (#{length(fixed)} fixed + 50,000 generated inputs)")

measure = fn tokenizer, source ->
  started = System.monotonic_time(:microsecond)

  checksum =
    Enum.reduce(1..1_000, 0, fn _, sum -> sum + :erlang.phash2(tokenizer.tokenize(source)) end)

  {System.monotonic_time(:microsecond) - started, checksum}
end

percentile = fn samples, fraction ->
  sorted = Enum.sort(samples)
  Enum.at(sorted, min(ceil(length(sorted) * fraction) - 1, length(sorted) - 1)) / 1_000
end

for source <- ["customer.name", "$sum(orders.price)", "orders[price > 50].price", "añb.日本語"] do
  legacy.tokenize(source)
  current.tokenize(source)

  pairs = for _ <- 1..25, do: {measure.(legacy, source), measure.(current, source)}
  old = Enum.map(pairs, fn {{time, _}, _} -> time end)
  new = Enum.map(pairs, fn {_, {time, _}} -> time end)
  old_median = percentile.(old, 0.5)
  new_median = percentile.(new, 0.5)

  IO.puts(
    "#{source}: old median #{Float.round(old_median, 3)} us/tokenize, " <>
      "new median #{Float.round(new_median, 3)} us/tokenize, " <>
      "old p95 #{Float.round(percentile.(old, 0.95), 3)}, " <>
      "new p95 #{Float.round(percentile.(new, 0.95), 3)}, " <>
      "speedup #{Float.round(old_median / new_median, 2)}x"
  )
end
