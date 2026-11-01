defmodule Jexata.FunctionsHigherOrderTest do
  use ExUnit.Case, async: true

  test "blocks and closures capture lexical bindings" do
    assert Jexata.run("($x := 2; $x + 1)", %{}) == {:ok, 3}
    assert Jexata.run("(function($x){$x + 1})(2)", %{}) == {:ok, 3}
    assert Jexata.run("($x := 10; $f := function($y){$x + $y}; $f(5))", %{}) == {:ok, 15}
    assert Jexata.run("$x", %{}) == {:ok, :undefined}
  end

  test "map filter and reduce invoke anonymous functions" do
    assert Jexata.run("$map([1,2], function($x){$x+1})", %{}) == {:ok, [2, 3]}
    assert Jexata.run("$map([1], function($x){$x+1})", %{}) == {:ok, 2}
    assert Jexata.run("$filter([1,2,3], function($x){$x>1})", %{}) == {:ok, [2, 3]}
    assert Jexata.run("$reduce([1,2,3], function($a,$b){$a+$b}, 0)", %{}) == {:ok, 6}
  end
end
