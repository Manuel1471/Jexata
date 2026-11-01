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

  test "numeric conversion and powers follow JSONata's basic rules" do
    assert Jexata.run("$number('12.5')", %{}) == {:ok, 12.5}
    assert Jexata.run("$number('0x12')", %{}) == {:ok, 18}
    assert Jexata.run("$number(missing)", %{}) == {:ok, :undefined}
    assert Jexata.run("$sqrt(4)", %{}) == {:ok, 2.0}
    assert Jexata.run("$power(2, 3)", %{}) == {:ok, 8.0}
    assert Jexata.run("$formatBase(10, 2)", %{}) == {:ok, "1010"}
    assert {:error, %Jexata.Error{code: "D3060"}} = Jexata.run("$sqrt(-1)", %{})
    assert Jexata.run("$number('0123')", %{}) == {:ok, 123}
    assert {:error, %Jexata.Error{code: "D3030"}} = Jexata.run("$number('abc')", %{})
  end
end
