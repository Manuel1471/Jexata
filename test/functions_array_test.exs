defmodule Jexata.FunctionsArrayTest do
  use ExUnit.Case, async: true

  test "array functions retain array shape" do
    assert Jexata.run("$append([1,2], 3)", %{}) == {:ok, [1, 2, 3]}
    assert Jexata.run("$reverse([1,2])", %{}) == {:ok, [2, 1]}
    assert Jexata.run("$distinct([1,2,1])", %{}) == {:ok, [1, 2]}
    assert Jexata.run("$sort([3,1,2])", %{}) == {:ok, [1, 2, 3]}
  end

  test "zip truncates to the shortest input" do
    assert Jexata.run("$zip([1,2,3], [4,5])", %{}) == {:ok, [[1, 4], [2, 5]]}
    assert Jexata.run("$zip(1,2,3)", %{}) == {:ok, [[1, 2, 3]]}
    assert Jexata.run("$zip([1,2], missing)", %{}) == {:ok, []}
  end

  test "shuffle preserves the array members" do
    assert Jexata.run("$shuffle(missing)", %{}) == {:ok, :undefined}
    assert Jexata.run("$sort($shuffle([1,2,3]))", %{}) == {:ok, [1, 2, 3]}
  end
end
