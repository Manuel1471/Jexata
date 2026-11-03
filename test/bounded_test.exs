defmodule Jexata.BoundedTest do
  use ExUnit.Case, async: true

  test "isolated evaluation returns the same result and validates budgets" do
    expression = Jexata.compile!("$sum(orders.price)")
    data = %{"orders" => [%{"price" => 1}, %{"price" => 2}]}

    assert Jexata.evaluate_bounded(expression, data) == {:ok, 3}

    assert {:error, %Jexata.Error{code: "J0007"}} =
             Jexata.evaluate_bounded(expression, data, timeout_ms: 0)

    assert {:error, %Jexata.Error{code: "J1007"}} =
             Jexata.evaluate_bounded(expression, data, max_result_bytes: 1)
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
  end
end
