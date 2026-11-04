defmodule Jexata.BoundedTest do
  use ExUnit.Case, async: true

  test "isolated evaluation returns the same result and validates budgets" do
    expression = Jexata.compile!("$sum(orders.price)")
    data = %{"orders" => [%{"price" => 1}, %{"price" => 2}]}

    assert Jexata.evaluate_bounded(expression, data) == {:ok, 3}

    assert {:error, %Jexata.Error{code: "J0007"}} =
             Jexata.evaluate_bounded(expression, data, timeout_ms: 0)

    assert {:error, %Jexata.Error{code: "J0007"}} =
             Jexata.evaluate_bounded(expression, data, timeout: 1)

    assert {:error, %Jexata.Error{code: "J0007"}} =
             Jexata.evaluate_bounded(expression, data, max_reductions: 0)

    assert Jexata.evaluate_bounded(expression, data, max_reductions: 1_000_000) == {:ok, 3}

    assert {:error, %Jexata.Error{code: "J1007"}} =
             Jexata.evaluate_bounded(expression, data, max_result_bytes: 1)
  end

  test "a reduction budget limits completed and ongoing evaluations" do
    expression = Jexata.compile!("$map(orders,function($x){$x*2})")
    data = %{"orders" => Enum.to_list(1..10_000)}

    assert {:error, %Jexata.Error{code: "J1010"}} =
             Jexata.evaluate_bounded(expression, data,
               max_reductions: 10_000,
               max_heap_words: 10_000_000,
               timeout_ms: 5_000
             )
  end

  test "internal worker exceptions have their own error code" do
    expression = %Jexata.Expression{source: "invalid", ast: {:unknown_node}}

    assert {:error, %Jexata.Error{code: "J1009"}} =
             Jexata.evaluate_bounded(expression, %{})
  end

  test "the worker stops when its caller dies" do
    parent = self()

    caller =
      spawn(fn ->
        receive do
          :start ->
            expression = Jexata.compile!("($f:=function($n){$f($n+1)};$f(0))")
            send(parent, :caller_started)
            Jexata.evaluate_bounded(expression, %{}, timeout_ms: 30_000)
        end
      end)

    :erlang.trace(caller, true, [:procs, :set_on_spawn])
    send(caller, :start)
    assert_receive :caller_started, 1_000
    assert_receive {:trace, ^caller, :spawn, watcher, _}, 1_000
    assert_receive {:trace, ^watcher, :spawn, worker, _}, 1_000
    assert Process.alive?(worker)
    worker_monitor = Process.monitor(worker)
    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :killed}, 1_000
  end

  test "the worker stops when its watcher is killed" do
    parent = self()

    caller =
      spawn(fn ->
        receive do
          :start ->
            expression = Jexata.compile!("($f:=function($n){$f($n+1)};$f(0))")
            send(parent, :caller_started)

            send(
              parent,
              {:bounded_result, Jexata.evaluate_bounded(expression, %{}, timeout_ms: 30_000)}
            )
        end
      end)

    :erlang.trace(caller, true, [:procs, :set_on_spawn])
    send(caller, :start)
    assert_receive :caller_started, 1_000
    assert_receive {:trace, ^caller, :spawn, watcher, _}, 1_000
    assert_receive {:trace, ^watcher, :spawn, worker, _}, 1_000
    worker_monitor = Process.monitor(worker)

    Process.exit(watcher, :kill)

    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :killed}, 1_000
    assert_receive {:bounded_result, {:error, %Jexata.Error{code: "J1009"}}}, 1_000
  end

  test "time and heap limits stop expensive expressions" do
    expression = Jexata.compile!("$map(orders,function($x){$x*2})")
    data = %{"orders" => Enum.to_list(1..100_000)}

    assert {:error, %Jexata.Error{code: "J1005"}} =
             Jexata.evaluate_bounded(expression, data,
               timeout_ms: 1,
               max_heap_words: 10_000_000
             )

    assert {:error, %Jexata.Error{code: "J1006"}} =
             Jexata.evaluate_bounded(expression, data, timeout_ms: 1_000, max_heap_words: 1_000)
  end

  test "bounded regex calls report backtracking limits" do
    contains = Jexata.compile!("$contains(s,/a+/)")
    split = Jexata.compile!("$split(s,/a+/)")
    data = %{"s" => String.duplicate("a", 100)}

    assert Jexata.evaluate_bounded(contains, data) == {:ok, true}

    assert {:error, %Jexata.Error{code: "J1008"}} =
             Jexata.evaluate_bounded(contains, data,
               regex_match_limit: 1,
               regex_recursion_limit: 1
             )

    assert {:error, %Jexata.Error{code: "J1008"}} =
             Jexata.evaluate_bounded(split, data,
               regex_match_limit: 1,
               regex_recursion_limit: 1
             )

    for source <- ["$split(s,/(b)/)", "$match(s,/(b)/)", "$replace(s,/(b)/,'X')"] do
      expression = Jexata.compile!(source)
      input = %{"s" => "ab"}
      assert Jexata.evaluate_bounded(expression, input) == Jexata.evaluate(expression, input)
    end

    pathological = Jexata.compile!("$contains(s,/(a+)+$/)")
    hostile = %{"s" => String.duplicate("a", 200) <> "!"}

    assert {:error, %Jexata.Error{code: "J1008"}} =
             Jexata.evaluate_bounded(pathological, hostile,
               regex_match_limit: 1_000,
               regex_recursion_limit: 1_000
             )
  end

  test "large generated collections and padding stay bounded" do
    range = Jexata.compile!("[1..100000].[1..100000]")
    pad = Jexata.compile!("$pad('x', 1000000000)")

    assert {:error, %Jexata.Error{code: code}} =
             Jexata.evaluate_bounded(range, %{}, timeout_ms: 100, max_heap_words: 100_000)

    assert code in ["J1005", "J1006", "J1007"]
    assert {:error, _} = Jexata.evaluate_bounded(pad, %{})
  end
end
