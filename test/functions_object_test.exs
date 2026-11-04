defmodule Jexata.FunctionsObjectTest do
  use ExUnit.Case, async: true

  test "object functions work on maps and arrays of maps" do
    assert Jexata.run("$lookup(obj, 'a')", %{"obj" => %{"a" => 2}}) == {:ok, 2}
    assert Jexata.run("$merge([{'a': 1}, {'b': 2}])", %{}) == {:ok, %{"a" => 1, "b" => 2}}
    assert Jexata.run("$keys({'a': 1})", %{}) == {:ok, "a"}
    assert Jexata.run("$spread(function($x){$x})", %{}) == {:ok, :function}
  end

  test "clone returns JSON-shaped immutable data and validates its input" do
    data = %{"nested" => %{"items" => [1, %{"x" => true}]}}
    assert Jexata.run("$clone(nested)", data) == {:ok, data["nested"]}
    assert Jexata.run("$clone()", data["nested"]) == {:ok, data["nested"]}
    assert Jexata.run("$clone([1,2])", %{}) == {:ok, [1, 2]}
    assert Jexata.run("$clone(missing)", %{}) == {:ok, :undefined}
    assert {:error, %Jexata.Error{code: "T0410"}} = Jexata.run("$clone(1)", %{})
  end
end
