# Run with: MIX_ENV=prod mix run scripts/benchmark.exs
# Times are per operation; repeat on the same host for comparisons.
sizes = [small: 10, medium: 100, large: 1_000]

expressions = [
  {:field, "customer.name", 10_000},
  {:nested, "customer.address.city", 10_000},
  {:arithmetic, "price * quantity + tax", 10_000},
  {:filter, "orders[price > 50].price", 10_000},
  {:aggregate, "$sum(orders.price)", 10_000},
  {:map_lambda, "$map(orders, function($o){$o.price * 2})", 1_000},
  {:map_string, "$map(orders, function($o){$uppercase($string($o.price))})", 1_000},
  {:reduce_lambda, "$reduce(orders, function($acc,$o){$acc+$o.price}, 0)", 1_000},
  {:reduce_recursive,
   "($f := function($n){$n <= 1 ? 1 : $n * $f($n - 1)}; $reduce(orders, function($acc,$o){$acc + $f($o.price % 10)}, 0))",
   100},
  {:sort_comparator, "$sort(orders, function($a,$b){$a.price > $b.price})", 100}
]

IO.puts(
  "Elixir #{System.version()}, OTP #{:erlang.system_info(:otp_release)}, schedulers #{System.schedulers_online()}"
)

IO.puts("size,items,expression,mode,iterations,microseconds_per_op,reductions_per_op")

for {size, count} <- sizes do
  data = %{
    "customer" => %{"name" => "Ada", "address" => %{"city" => "Monterrey"}},
    "price" => 10,
    "quantity" => 2,
    "tax" => 3,
    "orders" => Enum.map(1..count, fn number -> %{"price" => number} end)
  }

  for {name, source, iterations} <- expressions do
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
        "#{size},#{count},#{name},#{mode},#{iterations},#{Float.round(microseconds / iterations, 3)},#{Float.round((after_reductions - before_reductions) / iterations, 3)}"
      )
    end
  end
end
