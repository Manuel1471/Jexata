defmodule Jexata.FunctionsArrayTest do
  use ExUnit.Case, async: true

  test "array functions retain array shape" do
    assert Jexata.run("$append([1,2], 3)", %{}) == {:ok, [1, 2, 3]}
    assert Jexata.run("$reverse([1,2])", %{}) == {:ok, [2, 1]}
    assert Jexata.run("$distinct([1,2,1])", %{}) == {:ok, [1, 2]}
    assert Jexata.run("$sort([3,1,2])", %{}) == {:ok, [1, 2, 3]}
  end
end
