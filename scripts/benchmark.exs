# Run with: MIX_ENV=prod mix run scripts/benchmark.exs
# Times are per operation; repeat on the same host for comparisons.
iterations = 10_000
sizes = [small: 10, medium: 100, large: 1_000]

expressions = [
  field: "customer.name",
  nested: "customer.address.city",
  arithmetic: "price * quantity + tax",
  filter: "orders[price > 50].price",
  aggregate: "$sum(orders.price)"
]

IO.puts(
  "Elixir #{System.version()}, OTP #{:erlang.system_info(:otp_release)}, schedulers #{System.schedulers_online()}"
)

IO.puts("Iterations per measurement: #{iterations}")
IO.puts("size,items,expression,mode,microseconds_per_op,reductions_per_op")

for {size, count} <- sizes do
  data = %{
    "customer" => %{"name" => "Ada", "address" => %{"city" => "Monterrey"}},
    "price" => 10,
    "quantity" => 2,
    "tax" => 3,
    "orders" => Enum.map(1..count, fn number -> %{"price" => number} end)
  }

  for {name, source} <- expressions do
    compiled = Jexata.compile!(source)

    for {mode, operation} <- [
          compile: fn -> Jexata.compile!(source) end,
          evaluate: fn -> Jexata.evaluate!(compiled, data) end,
          run: fn -> Jexata.run!(source, data) end
        ] do
      operation.()
      {_, before_reductions} = Process.info(self(), :reductions)
      {microseconds, _} = :timer.tc(fn -> for _ <- 1..iterations, do: operation.() end)
      {_, after_reductions} = Process.info(self(), :reductions)

      IO.puts(
        "#{size},#{count},#{name},#{mode},#{Float.round(microseconds / iterations, 3)},#{Float.round((after_reductions - before_reductions) / iterations, 3)}"
      )
    end
  end
end
