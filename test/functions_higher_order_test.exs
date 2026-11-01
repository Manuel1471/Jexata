defmodule Jexata.FunctionsHigherOrderTest do
  use ExUnit.Case, async: true

  test "blocks and closures capture lexical bindings" do
    assert Jexata.run("($x := 2; $x + 1)", %{}) == {:ok, 3}
    assert Jexata.run("(function($x){$x + 1})(2)", %{}) == {:ok, 3}
    assert Jexata.run("($x := 10; $f := function($y){$x + $y}; $f(5))", %{}) == {:ok, 15}
    assert Jexata.run("$x", %{}) == {:ok, :undefined}

    assert Jexata.run("value.($f := function(){$.name}; $f())", %{"value" => %{"name" => "Ada"}}) ==
             {:ok, "Ada"}
  end

  test "map filter and reduce invoke anonymous functions" do
    assert Jexata.run("$map([1,2], function($x){$x+1})", %{}) == {:ok, [2, 3]}

    assert Jexata.run("$map([10,20], function($x,$i,$all){$x+$i+$count($all)})", %{}) ==
             {:ok, [12, 23]}

    assert Jexata.run("$map([10,20], function(){7})", %{}) == {:ok, [7, 7]}
    assert Jexata.run("$map([1], function($x){$x+1})", %{}) == {:ok, 2}
    assert Jexata.run("$filter([1,2,3], function($x){$x>1})", %{}) == {:ok, [2, 3]}
    assert Jexata.run("$filter([10,20], function($x,$i){$i=1})", %{}) == {:ok, 20}
    assert Jexata.run("$reduce([1,2,3], function($a,$b){$a+$b}, 0)", %{}) == {:ok, 6}
    assert Jexata.run("$reduce([1,2,3], function($a,$b,$i){$i})", %{}) == {:ok, 2}
    assert Jexata.run("$reduce([1,2,3], $append)", %{}) == {:ok, [1, 2, 3]}

    assert {:error, %Jexata.Error{code: "D3050"}} =
             Jexata.run("$reduce([1], function($x){$x})", %{})
  end

  test "recursive closures can refer to themselves and later peer functions" do
    assert Jexata.run("($f:=function($n){$n=0 ? 1 : $n*$f($n-1)}; $f(5))", %{}) ==
             {:ok, 120}

    assert Jexata.run(
             "($even:=function($n){$n=0 ? true : $odd($n-1)}; $odd:=function($n){$n=0 ? false : $even($n-1)}; $odd(5))",
             %{}
           ) == {:ok, true}

    assert Jexata.run("($odd := function($n){$n = 0 ? false : $odd($n - 1)}; $odd(6555))", %{}) ==
             {:ok, false}
  end

  test "chain array preservation applies after the function call" do
    assert Jexata.run("([1] ~> $map(function($x){$x * $x})[])", %{}) == {:ok, [1]}
  end

  test "custom matchers return match objects" do
    assert Jexata.run(
             "$match('aba', function($s){{'match':'a', 'start':0, 'groups':[]}})",
             %{}
           ) == {:ok, %{"match" => "a", "index" => 0, "groups" => []}}

    assert {:error, %Jexata.Error{code: "T1010"}} = Jexata.run("$split('abc', $uppercase)", %{})
  end

  test "function composition applies functions from left to right" do
    assert Jexata.run("($uppertrim := $trim ~> $uppercase; $uppertrim('  hello  '))", %{}) ==
             {:ok, "HELLO"}

    assert Jexata.run(
             "($square := function($x){$x*$x}; $sum_of_squares := $map(?, $square) ~> $sum; [1..3] ~> $sum_of_squares())",
             %{}
           ) == {:ok, 14}
  end
end
