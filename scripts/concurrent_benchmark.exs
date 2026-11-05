# Run with MIX_ENV=prod mix run scripts/concurrent_benchmark.exs.
# This is a diagnostic benchmark, not a CI latency gate.
data = %{"orders" => Enum.map(1..1_000, fn number -> %{"price" => number} end)}
expression = Jexata.compile!("orders[price > 50].price")
iterations_per_worker = 1_000

percentile = fn sorted, fraction ->
  index = max(ceil(length(sorted) * fraction) - 1, 0)
  Enum.at(sorted, index)
end

for workers <- [1, 4, 10] do
  rounds =
    for round <- 1..3 do
      marker = make_ref()
      parent = self()

      tasks =
        for _ <- 1..workers do
          Task.async(fn ->
            Enum.each(1..10, fn _ -> Jexata.evaluate!(expression, data) end)
            send(parent, {:ready, self(), marker})

            receive do
              {:go, ^marker} -> :ok
            end

            for _ <- 1..iterations_per_worker do
              started = System.monotonic_time(:nanosecond)
              result = Jexata.evaluate!(expression, data)
              {System.monotonic_time(:nanosecond) - started, :erlang.phash2(result)}
            end
          end)
        end

      Enum.each(tasks, fn task ->
        receive do
          {:ready, pid, ^marker} when pid == task.pid -> :ok
        end
      end)

      started = System.monotonic_time(:nanosecond)
      Enum.each(tasks, fn task -> send(task.pid, {:go, marker}) end)
      samples = Enum.flat_map(tasks, &Task.await(&1, 60_000))
      elapsed = System.monotonic_time(:nanosecond) - started
      hashes = samples |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

      if length(hashes) != 1, do: raise("Concurrent evaluations returned different results")

      latencies = samples |> Enum.map(&elem(&1, 0)) |> Enum.sort()

      %{
        round: round,
        workers: workers,
        operations: length(samples),
        throughput_per_second: length(samples) * 1_000_000_000 / elapsed,
        p50_us: percentile.(latencies, 0.50) / 1_000,
        p99_us: percentile.(latencies, 0.99) / 1_000
      }
    end

  IO.puts(
    :json.encode(%{
      workers: workers,
      iterations_per_worker: iterations_per_worker,
      rounds: rounds,
      throughput_median:
        rounds |> Enum.map(& &1.throughput_per_second) |> Enum.sort() |> Enum.at(1),
      p99_us_median: rounds |> Enum.map(& &1.p99_us) |> Enum.sort() |> Enum.at(1)
    })
  )
end
