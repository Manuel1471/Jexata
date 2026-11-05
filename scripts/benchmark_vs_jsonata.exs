# Run with MIX_ENV=prod mix run scripts/benchmark_vs_jsonata.exs fixture.json.
[fixture_path] = System.argv()
%{"data" => data, "cases" => cases} = fixture_path |> File.read!() |> :json.decode()

for %{"name" => name, "source" => source, "mode" => mode, "iterations" => iterations} <- cases do
  row =
    Task.async(fn ->
      compiled = Jexata.compile!(source)

      operation =
        case mode do
          "compile" -> fn -> Jexata.compile!(source) end
          "evaluate" -> fn -> Jexata.evaluate!(compiled, data) end
        end

      result = if mode == "compile", do: 0, else: operation.()
      Enum.each(1..3, fn _ -> operation.() end)
      :erlang.garbage_collect(self())
      started = System.monotonic_time(:nanosecond)
      Enum.each(1..iterations, fn _ -> operation.() end)
      elapsed = System.monotonic_time(:nanosecond) - started

      %{
        case: name,
        mode: mode,
        iterations: iterations,
        ns_per_op: elapsed / iterations,
        result: if(result == :undefined, do: :null, else: result),
        undefined: result == :undefined
      }
    end)
    |> Task.await(:infinity)

  IO.puts(:json.encode(row))
end
