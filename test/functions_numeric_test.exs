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

  test "random returns a unit interval value and rejects arguments" do
    for _ <- 1..100 do
      assert {:ok, value} = Jexata.run("$random()", %{})
      assert is_float(value) and value >= 0 and value < 1
    end

    assert {:error, %Jexata.Error{code: "T0410"}} = Jexata.run("$random(1)", %{})
  end

  test "numeric conversion and powers follow JSONata's basic rules" do
    assert Jexata.run("$number('12.5')", %{}) == {:ok, 12.5}
    assert Jexata.run("$number('0x12')", %{}) == {:ok, 18}
    assert Jexata.run("$number('12.50')", %{}) == {:ok, 12.5}
    assert Jexata.run("$number('1.25e+2')", %{}) == {:ok, 125.0}
    assert {:error, %Jexata.Error{code: "D3030"}} = Jexata.run("$number('0x+12')", %{})
    assert Jexata.run("$number(missing)", %{}) == {:ok, :undefined}
    assert Jexata.run("$sqrt(4)", %{}) == {:ok, 2.0}
    assert Jexata.run("$power(2, 3)", %{}) == {:ok, 8.0}
    assert Jexata.run("$formatBase(10, 2)", %{}) == {:ok, "1010"}
    assert {:error, %Jexata.Error{code: "D3060"}} = Jexata.run("$sqrt(-1)", %{})
    assert Jexata.run("$number('0123')", %{}) == {:ok, 123}
    assert Jexata.run("$number('-007')", %{}) == {:ok, -7}
    assert {:error, %Jexata.Error{code: "D3030"}} = Jexata.run("$number('abc')", %{})
  end

  test "decimal parser agrees with the previous lexical rule" do
    :rand.seed(:exsplus, {11, 22, 33})
    characters = ~c"0123456789.eE+-q"
    legacy = ~r/\A-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\z/

    for _ <- 1..5_000 do
      size = :rand.uniform(11) - 1
      value = for _ <- List.duplicate(nil, size), into: "", do: <<Enum.random(characters)>>
      valid? = match?({:ok, _}, Jexata.Functions.Numeric.call("$number", [value]))

      legacy_valid? =
        Regex.match?(legacy, value) and
          (not String.contains?(value, [".", "e", "E"]) or
             match?({_, ""}, Float.parse(value)))

      assert valid? == legacy_valid?, value
    end
  end
end
