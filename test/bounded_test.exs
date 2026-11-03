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
end
