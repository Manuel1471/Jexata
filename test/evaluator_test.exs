defmodule Jexata.EvaluatorTest do
  use ExUnit.Case, async: true

  test "evaluates literals, paths and arithmetic" do
    assert Jexata.run("1 + 2 * 3", %{}) == {:ok, 7}
    assert Jexata.run("customer.name", %{"customer" => %{"name" => "Ada"}}) == {:ok, "Ada"}

    assert Jexata.run("orders.price", %{"orders" => [%{"price" => 2}, %{"price" => 3}]}) ==
             {:ok, [2, 3]}
  end

  test "preserves null, missing, arrays and sequence cardinality" do
    assert Jexata.run("missing", %{}) == {:ok, :undefined}
    assert Jexata.run("$", :undefined) == {:ok, :undefined}
    assert Jexata.run("1+2", :undefined) == {:ok, 3}
    assert Jexata.run("value", %{"value" => nil}) == {:ok, nil}
    assert Jexata.run("[missing, null, 1]", %{}) == {:ok, [nil, 1]}
    assert Jexata.run("values", %{"values" => [1]}) == {:ok, [1]}
    assert Jexata.run("items.x", %{"items" => [%{"x" => 1}]}) == {:ok, 1}
    assert Jexata.run("[items.x]", %{"items" => [%{"x" => 1}, %{"x" => 2}]}) == {:ok, [1, 2]}
  end

  test "supports filters, constructors and conditions" do
    data = %{"items" => [%{"price" => 1}, %{"price" => 3}]}
    assert Jexata.run("items[price > 2].price", data) == {:ok, 3}
    assert Jexata.run("items[0].price", data) == {:ok, 1}
    assert Jexata.run("{'yes': true ? 2 : 3}", %{}) == {:ok, %{"yes" => 2}}
  end

  test "reports type and arithmetic errors" do
    assert {:error, %Jexata.Error{code: "T2001"}} = Jexata.run("'a' + 2", %{})
    assert {:error, %Jexata.Error{code: "D1001"}} = Jexata.run("1 / 0", %{})
    assert {:error, %Jexata.Error{code: "D1001"}} = Jexata.run("1 % 0.0", %{})
    assert {:error, %Jexata.Error{code: "D1001"}} = Jexata.run("1/(10e300 * 10e100)", :undefined)
    assert Jexata.run("{'a': 1} & 'x'", %{}) == {:ok, "{\"a\":1}x"}
  end

  test "compiled expressions can be reused concurrently" do
    expression = Jexata.compile!("customer.name")

    tasks =
      for name <- ~w(Ada Bea Cal),
          do:
            Task.async(fn -> Jexata.evaluate!(expression, %{"customer" => %{"name" => name}}) end)

    assert Enum.map(tasks, &Task.await/1) == ~w(Ada Bea Cal)
  end
end
