# Run from either checkout with MIX_ENV=prod mix run /absolute/path/to/benchmark_compare.exs.
# Each invocation is one comparison round; alternate checkout order between rounds.
orders =
  Enum.map(1..1_000, fn number ->
    %{
      "price" => number,
      "customer" => "customer#{rem(number, 10)}",
      "text" => "Order #{number} Foo",
      "padded" => "  Order #{number}   Foo  ",
      "decimal" => "#{number}.50",
      "date" => "20180205",
      "millis" => 1_509_380_732_935 + number
    }
  end)

data = %{
  "orders" => orders,
  "catalog" => Map.new(1..1_000, fn number -> {"item#{number}", %{"price" => number}} end),
  "a" => %{"one" => %{"b" => 1}, "two" => %{"b" => 2}},
  "customer" => %{"name" => "Ada"}
}

workloads = [
  {"compile_field", "customer.name", :compile, 10_000},
  {"filter", "orders[price > 50].price", :evaluate, 1_000},
  {"sum", "$sum(orders.price)", :evaluate, 1_000},
  {"map_lambda", "$map(orders,function($o){$o.price*2})", :evaluate, 300},
  {"reduce_recursive",
   "($f:=function($n){$n<=1?1:$n*$f($n-1)};$reduce(orders,function($a,$o){$a+$f($o.price%10)},0))",
   :evaluate, 30},
  {"sort_comparator", "$sort(orders,function($a,$b){$a.price>$b.price})", :evaluate, 30},
  {"group_object", "orders{customer:$sum(price)}", :evaluate, 100},
  {"descendants", "orders.**.price", :evaluate, 100},
  {"wildcard", "catalog.*.price", :evaluate, 100},
  {"index_zero", "orders[0].price", :evaluate, 1_000},
  {"index_negative", "orders[-1].price", :evaluate, 1_000},
  {"chain_sum", "orders.price ~> $sum()", :evaluate, 1_000},
  {"match_each", "$map(orders,function($o){$match($o.text,/Order/)})", :evaluate, 100},
  {"replace_each", "$map(orders,function($o){$replace($o.text,/Order/,'Item')})", :evaluate, 100},
  {"trim_each", "$map(orders,function($o){$trim($o.padded)})", :evaluate, 100},
  {"number_float_each", "$map(orders,function($o){$number($o.decimal)})", :evaluate, 100},
  {"to_millis_picture", "$map(orders,function($o){$toMillis($o.date,'[Y0001][M01][D01]')})",
   :evaluate, 50},
  {"from_millis_each", "$map(orders,function($o){$fromMillis($o.millis)})", :evaluate, 100},
  {"format_number_each", "$map(orders,function($o){$formatNumber($o.price,'#,###.00')})",
   :evaluate, 50},
  {"merge_objects", "$merge(orders)", :evaluate, 100},
  {"spread_each", "$map(orders,function($o){$spread($o)})", :evaluate, 100},
  {"serialize_orders", "$string(orders)", :evaluate, 100}
]

gc_count = fn ->
  {_, details} = Process.info(self(), :garbage_collection)
  Keyword.fetch!(details, :minor_gcs)
end

for {name, source, mode, iterations} <- workloads do
  row =
    Task.async(fn ->
      compiled = Jexata.compile!(source)

      operation =
        if mode == :compile,
          do: fn -> Jexata.compile!(source) end,
          else: fn -> Jexata.evaluate!(compiled, data) end

      result = operation.()
      Enum.each(1..3, fn _ -> operation.() end)
      :erlang.garbage_collect(self())
      {_, before_reductions} = Process.info(self(), :reductions)
      before_gc = gc_count.()
      before_time = System.monotonic_time(:microsecond)
      Enum.each(1..iterations, fn _ -> operation.() end)
      elapsed = System.monotonic_time(:microsecond) - before_time
      {_, after_reductions} = Process.info(self(), :reductions)
      after_gc = gc_count.()

      %{
        case: name,
        mode: mode,
        iterations: iterations,
        us_per_op: elapsed / iterations,
        reductions_per_op: (after_reductions - before_reductions) / iterations,
        minor_gcs_per_op: (after_gc - before_gc) / iterations,
        result_hash: :erlang.phash2(result)
      }
    end)
    |> Task.await(:infinity)

  IO.puts(:json.encode(row))
end
