defmodule Jexata.FunctionsObjectTest do
  use ExUnit.Case, async: true

  test "object functions work on maps and arrays of maps" do
    assert Jexata.run("$lookup(obj, 'a')", %{"obj" => %{"a" => 2}}) == {:ok, 2}
    assert Jexata.run("$merge([{'a': 1}, {'b': 2}])", %{}) == {:ok, %{"a" => 1, "b" => 2}}
    assert Jexata.run("$keys({'a': 1})", %{}) == {:ok, "a"}
    assert Jexata.run("$spread(function($x){$x})", %{}) == {:ok, :function}
  end
end
