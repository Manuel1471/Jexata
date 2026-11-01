defmodule Jexata.FunctionsStringTest do
  use ExUnit.Case, async: true

  test "string functions handle Unicode and arrays" do
    assert Jexata.run("$length('hé')", %{}) == {:ok, 2}
    assert Jexata.run("$uppercase('abc')", %{}) == {:ok, "ABC"}
    assert Jexata.run("$substring('hello', 1, 3)", %{}) == {:ok, "ell"}
    assert Jexata.run("$contains('hello', 'ell')", %{}) == {:ok, true}
    assert Jexata.run("$join(['a','b'], '-')", %{}) == {:ok, "a-b"}
    assert Jexata.run("$string(null)", %{}) == {:ok, "null"}
  end
end
