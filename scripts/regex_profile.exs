# Compare plain-regex built-ins across commits with compare_checkouts.py.
data = %{
  "orders" => Enum.map(1..1_000, fn number -> %{"text" => "Order #{number} Foo"} end)
}

for {name, source} <- [
      {"replace_plain_regex", "$map(orders,function($o){$replace($o.text,/Order/,'Item')})"},
      {"contains_plain_regex", "$map(orders,function($o){$contains($o.text,/Order/)})"},
      {"split_plain_regex", "$map(orders,function($o){$split($o.text,/Order/)})"}
    ] do
  row =
    Task.async(fn ->
      compiled = Jexata.compile!(source)
      operation = fn -> Jexata.evaluate!(compiled, data) end
      result = operation.()
      Enum.each(1..3, fn _ -> operation.() end)
      :erlang.garbage_collect(self())
      {_, before_reductions} = Process.info(self(), :reductions)
      {_, before_gc} = Process.info(self(), :garbage_collection)
      started = System.monotonic_time(:nanosecond)
      Enum.each(1..100, fn _ -> operation.() end)
      elapsed = System.monotonic_time(:nanosecond) - started
      {_, after_reductions} = Process.info(self(), :reductions)
      {_, after_gc} = Process.info(self(), :garbage_collection)

      %{
        case: name,
        mode: :evaluate,
        iterations: 100,
        us_per_op: elapsed / 100_000,
        reductions_per_op: (after_reductions - before_reductions) / 100,
        minor_gcs_per_op: (after_gc[:minor_gcs] - before_gc[:minor_gcs]) / 100,
        result_hash: :erlang.phash2(result)
      }
    end)
    |> Task.await(:infinity)

  IO.puts(:json.encode(row))
end
