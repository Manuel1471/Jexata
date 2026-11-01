# Run with: mix run scripts/reductions_guard.exs
# Baselines were recorded on Elixir 1.20.2 / OTP 29; a 50% margin allows
# runtime and host variation while catching large algorithmic regressions.
baseline_path = Path.join(__DIR__, "reductions_baseline.json")
baselines = baseline_path |> File.read!() |> :json.decode()
data = %{"orders" => Enum.map(1..1_000, &%{"price" => &1})}
iterations = 20
max_ratio = 1.5

failures =
  Enum.reduce(baselines, [], fn {name, %{"source" => source, "baseline" => baseline} = config},
                                failures ->
    expression = Jexata.compile!(source)
    input = if config["input"] == "root_array", do: data["orders"], else: data
    operation = fn -> Jexata.evaluate!(expression, input) end
    operation.()
    {_, before_reductions} = Process.info(self(), :reductions)
    Enum.each(1..iterations, fn _ -> operation.() end)
    {_, after_reductions} = Process.info(self(), :reductions)
    measured = (after_reductions - before_reductions) / iterations
    limit = baseline * max_ratio

    IO.puts(
      "#{name}: #{round(measured)} reductions/op; baseline #{baseline}; limit #{round(limit)}"
    )

    if measured > limit, do: [name | failures], else: failures
  end)

if failures != [] do
  IO.puts(:stderr, "Reduction budget exceeded: #{Enum.join(Enum.reverse(failures), ", ")}")
  System.halt(1)
end
