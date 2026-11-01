defmodule Jexata.OptimizerTest do
  use ExUnit.Case, async: true
  alias Jexata.{Evaluator, Optimizer, Parser}
  alias Jexata.Runtime.Value

  test "optimized and original ASTs agree on literals and contextual expressions" do
    cases = [
      {"[1, 'a', null]", %{}},
      {"[[1,2], [3]]", %{}},
      {"[1, [2,3]]", %{}},
      {"[missing, 2]", %{}},
      {"orders[price in [10,20,30]].price", %{"orders" => [%{"price" => 10}, %{"price" => 40}]}},
      {"$string({'b':2,'a':1})", %{}},
      {"[1..5]", %{}},
      {"1 + 2 * 3", %{}},
      {"'a' & 'b'", %{}},
      {"true ? [1,2] : [3]", %{}},
      {"$map([1,2,3], function($x)<n:n>{$x*2})", %{}},
      {"($f := function($n){$n=0 ? 1 : $n*$f($n-1)}; $f(5))", %{}}
    ]

    for {source, data} <- cases do
      {:ok, original} = Parser.parse(source)
      optimized = Optimizer.optimize(original)
      assert evaluate(original, data) == evaluate(optimized, data), source
    end
  end

  test "folds arithmetic, concatenation, small ranges and constant branches" do
    assert Jexata.compile!("1 + 2 * 3").ast == {:literal, 7}
    assert Jexata.compile!("'a' & 'b'").ast == {:literal, "ab"}
    assert Jexata.compile!("[1..5]").ast == {:literal, [1, 2, 3, 4, 5]}
    assert Jexata.compile!("true ? 2 : 3").ast == {:literal, 2}
    assert Jexata.compile!("1 / 0").ast != {:literal, 0}
  end

  defp evaluate(ast, data) do
    case Evaluator.evaluate(ast, data) do
      {:ok, value} -> {:ok, Value.public(value)}
      error -> error
    end
  end
end
