defmodule Jexata.OptimizerTest do
  use ExUnit.Case, async: true
  alias Jexata.{AST, Evaluator, Optimizer, Parser}
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
      {"items^(>price).price", %{"items" => [%{"price" => 1}, %{"price" => 3}]}},
      {"items{kind:$sum(price)}", %{"items" => [%{"kind" => "a", "price" => 2}]}},
      {"($x:=2; $x+3)", %{}},
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

  test "AST traversal leaves literal payloads and metadata untouched" do
    payload = {:binary, "+", {:literal, 1}, {:literal, 2}}
    assert Optimizer.optimize({:literal, payload}) == {:literal, payload}
    assert AST.children({:literal, payload}) == []

    sort = {:sort, {:name, "items"}, [{:desc, payload}]}
    assert {:sort, {:name, "items"}, [{:desc, {:literal, 3}}]} = Optimizer.optimize(sort)
    assert AST.children(sort) == [{:name, "items"}, payload]

    {:ok, closure} = Evaluator.evaluate({:lambda, [], nil, {:literal, {:variable, "$x"}}}, %{})
    assert closure.references == []
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

  test "indirect invocation forms still enforce the recursive depth limit" do
    cases = [
      {"parameter call", "($g:=function(){1};$f:=function($h){1+$h()};$f($g))", %{}},
      {"pipeline", "($g:=function($x){$x+1};$f:=function(){1+(1~>$g())};$f())", %{}},
      {"map callback", "($f:=function(){$map([1,2],function($x){$x+1})};$f())", %{}},
      {"reduce callback", "($f:=function(){$reduce([1,2],function($a,$x){$a+$x},0)};$f())", %{}},
      {"partial function", "($g:=function($x){$x+1};$p:=$g(?);$f:=function(){1+$p(1)};$f())",
       %{}},
      {"transform", "($g:=function($x){$x+1};$f:=function(){$ ~> |$|{'b':$g(a)}|};$f())",
       %{"a" => 1}},
      {"Y-style self parameter", "($f:=function($self,$n){$n=0?0:1+$self($self,$n-1)};$f($f,2))",
       %{}},
      {"self parameter call", "($f:=function($self){1+$self($self)};$f($f))", %{}}
    ]

    for {name, source, data} <- cases do
      expression = Jexata.compile!(source)

      assert {:error, %Jexata.Error{code: "U1001"}} =
               Jexata.evaluate(expression, data, %{}, max_function_depth: 1),
             name
    end
  end

  defp evaluate(ast, data) do
    case Evaluator.evaluate(ast, data) do
      {:ok, value} -> {:ok, Value.public(value)}
      error -> error
    end
  end
end
