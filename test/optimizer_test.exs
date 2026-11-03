defmodule Jexata.OptimizerTest do
  use ExUnit.Case, async: true
  alias Jexata.{Evaluator, Optimizer, Parser}
  alias Jexata.Runtime.Value

  test "optimized and original ASTs agree on literals and contextual expressions" do
    cases = [
      {"[1, 'a', null]", %{}},
      {"[[1,2], [3]]", %{}},
      {"[[1,2], missing]", %{}},
      {"[[1..5], [6,7]]", %{}},
      {"[1, [2,3]]", %{}},
      {"[missing, 2]", %{}},
      {"orders[price in [10,20,30]].price", %{"orders" => [%{"price" => 10}, %{"price" => 40}]}},
      {"name.$substringBefore(' ')", %{"name" => "Ada Bell"}},
      {"'customer'.'name'", %{"customer" => %{"name" => "Ada"}}},
      {"orders#$i.price", %{"orders" => [%{"price" => 2}, %{"price" => 3}]}},
      {"$ ~> |items|{'double': price * 2}|", %{"items" => [%{"price" => 2}]}},
      {"$string({'b':2,'a':1})", %{}},
      {"{'a':1,'nested':{'b':[2,3]}}", %{}},
      {"{'test':()}", %{}},
      {"items{'x':$sum(price)}", %{"items" => [%{"price" => 2}]}},
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
    assert Jexata.compile!("[[1,2],[3]]").ast == {:literal, [[1, 2], [3]]}
    assert Jexata.compile!("true ? 2 : 3").ast == {:literal, 2}
    assert Jexata.compile!("{'a':1,'b':2}").ast == {:literal, %{"a" => 1, "b" => 2}}
    assert Jexata.compile!("1 / 0").ast != {:literal, 0}
  end

  test "prepares filter predicate kind while preserving positional filters" do
    assert {:compiled_filter, _, _, true} = Jexata.compile!("orders[price > 50]").ast
    assert {:compiled_filter, _, _, false} = Jexata.compile!("orders[-1]").ast

    assert Jexata.run("orders[-1].price", %{"orders" => [%{"price" => 1}, %{"price" => 2}]}) ==
             {:ok, 2}
  end

  test "marks only non-invoking lambda bodies for depth fast path" do
    {:ok, leaf} = Jexata.compile!("function($x){$x + 1}").ast |> Evaluator.evaluate(%{})
    assert leaf.leaf?

    {:ok, calling} = Jexata.compile!("function($x){$abs($x)}").ast |> Evaluator.evaluate(%{})
    refute calling.leaf?

    expression =
      Jexata.compile!("($g := function($x){$x+1}; $f := function($x){1+$g($x)}; $f(1))")

    assert {:error, %Jexata.Error{code: "U1001"}} =
             Jexata.evaluate(expression, %{}, %{}, max_function_depth: 1)

    assert Jexata.evaluate(expression, %{}, %{}, max_function_depth: 2) == {:ok, 3}
  end

  defp evaluate(ast, data) do
    case Evaluator.evaluate(ast, data) do
      {:ok, value} -> {:ok, Value.public(value)}
      error -> error
    end
  end
end
