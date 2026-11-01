defmodule Jexata.EvaluatorTest do
  use ExUnit.Case, async: true

  test "evaluates literals, paths and arithmetic" do
    assert Jexata.run("1 + 2 * 3", %{}) == {:ok, 7}
    assert Jexata.run("customer.name", %{"customer" => %{"name" => "Ada"}}) == {:ok, "Ada"}

    assert Jexata.run("orders.price", %{"orders" => [%{"price" => 2}, %{"price" => 3}]}) ==
             {:ok, [2, 3]}

    assert Jexata.run("\"customer\".\"name\"", %{"customer" => %{"name" => "Ada"}}) ==
             {:ok, "Ada"}
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

  test "ranges flatten into array constructors and validate endpoints" do
    assert Jexata.run("[0..3]", %{}) == {:ok, [0, 1, 2, 3]}
    assert Jexata.run("[5..2]", %{}) == {:ok, []}
    assert {:error, %Jexata.Error{code: "T2003"}} = Jexata.run("[1.1..5]", %{})
    assert Jexata.run("[1..10000000] ~> $count()", %{}) == {:ok, 10_000_000}
    assert {:error, %Jexata.Error{code: "D2014"}} = Jexata.run("[1..10000000]", %{})
  end

  test "flattens path sequences while preserving explicit nested arrays" do
    data = %{"a" => [1, 2], "items" => [%{"x" => [1, 2]}, %{"x" => [3, 4]}]}

    assert Jexata.run("[a]", data) == {:ok, [1, 2]}
    assert Jexata.run("[[a]]", data) == {:ok, [[1, 2]]}
    assert Jexata.run("items.x", data) == {:ok, [1, 2, 3, 4]}
    assert Jexata.run("items.x[0]", data) == {:ok, [1, 3]}
    assert Jexata.run("items.x[]", data) == {:ok, [1, 2, 3, 4]}
    assert Jexata.run("items[-1].x", data) == {:ok, [3, 4]}
  end

  test "supports filters, constructors and conditions" do
    data = %{"items" => [%{"price" => 1}, %{"price" => 3}]}
    assert Jexata.run("items[price > 2].price", data) == {:ok, 3}
    assert Jexata.run("items[0].price", data) == {:ok, 1}
    assert Jexata.run("{'yes': true ? 2 : 3}", %{}) == {:ok, %{"yes" => 2}}
    assert Jexata.run("false ? 2", %{}) == {:ok, :undefined}
    assert Jexata.run("true ? 2", %{}) == {:ok, 2}
  end

  test "reports type and arithmetic errors" do
    assert {:error, %Jexata.Error{code: "T2001"}} = Jexata.run("'a' + 2", %{})
    assert {:error, %Jexata.Error{code: "D1001"}} = Jexata.run("1 / 0", %{})
    assert {:error, %Jexata.Error{code: "D1001"}} = Jexata.run("1 % 0.0", %{})
    assert {:error, %Jexata.Error{code: "D1001"}} = Jexata.run("1/(10e300 * 10e100)", :undefined)
    assert Jexata.run("{'a': 1} & 'x'", %{}) == {:ok, "{\"a\":1}x"}
    assert {:error, %Jexata.Error{code: "T2002"}} = Jexata.run("1 + null", %{})
    assert {:error, %Jexata.Error{code: "D1002"}} = Jexata.run("-'x'", %{})
  end

  test "compiled expressions can be reused concurrently" do
    expression = Jexata.compile!("customer.name")

    tasks =
      for name <- ~w(Ada Bea Cal),
          do:
            Task.async(fn -> Jexata.evaluate!(expression, %{"customer" => %{"name" => name}}) end)

    assert Enum.map(tasks, &Task.await/1) == ~w(Ada Bea Cal)
  end

  test "chained bindings remain local to their parenthesized block" do
    assert Jexata.run("($a := $b := 5; $a + $b)", %{}) == {:ok, 10}
    assert Jexata.run("($x := 'outer'; ($x := missing); $x)", %{}) == {:ok, "outer"}

    assert Jexata.run("($x := 'outer'; ($x := missing; $x))", %{}) ==
             {:ok, :undefined}
  end
end
