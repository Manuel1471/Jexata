defmodule Jexata.FunctionsNumericTest do
  use ExUnit.Case, async: true

  test "aggregates selected values and arrays" do
    data = %{"orders" => [%{"price" => 100}, %{"price" => 250}]}
    assert Jexata.run("$sum(orders.price)", data) == {:ok, 350}
    assert Jexata.run("$count(orders)", data) == {:ok, 2}
    assert Jexata.run("$max([3, 8, 2])", data) == {:ok, 8}
    assert Jexata.run("$min([3, 8, 2])", data) == {:ok, 2}
    assert Jexata.run("$average([2, 4])", data) == {:ok, 3.0}
    assert Jexata.run("$sum([])", data) == {:ok, 0}
    assert Jexata.run("$sum(missing)", data) == {:ok, :undefined}
    assert Jexata.run("$max([])", data) == {:ok, :undefined}
  end

  test "numeric helpers validate types" do
    assert Jexata.run("$abs(-5)", %{}) == {:ok, 5}
    assert Jexata.run("$floor(2.9)", %{}) == {:ok, 2}
    assert Jexata.run("$ceil(2.1)", %{}) == {:ok, 3}
    assert Jexata.run("$round(2.5)", %{}) == {:ok, 2}
    assert Jexata.run("$round(3.5)", %{}) == {:ok, 4}
    assert {:error, %Jexata.Error{code: "T0412"}} = Jexata.run("$sum([1, 'x'])", %{})
  end
end
