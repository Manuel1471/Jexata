# Isolate filter, predicate, and selection costs across Git revisions.
data = %{"orders" => Enum.map(1..1_000, fn number -> %{"price" => number} end)}

for {name, source} <- [
      {"full_filter", "orders[price > 50].price"},
      {"filter_only", "orders[price > 50]"},
      {"predicate_only", "orders.(price > 50)"},
      {"selection_only", "orders.price"}
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
      Enum.each(1..1_000, fn _ -> operation.() end)
      elapsed = System.monotonic_time(:nanosecond) - started
      {_, after_reductions} = Process.info(self(), :reductions)
      {_, after_gc} = Process.info(self(), :garbage_collection)

      %{
        case: name,
        mode: :evaluate,
        iterations: 1_000,
        us_per_op: elapsed / 1_000_000,
        reductions_per_op: (after_reductions - before_reductions) / 1_000,
        minor_gcs_per_op: (after_gc[:minor_gcs] - before_gc[:minor_gcs]) / 1_000,
        result_hash: :erlang.phash2(result)
      }
    end)
    |> Task.await(:infinity)

  IO.puts(:json.encode(row))
end
