defmodule Jexata.AdvancedOperatorsTest do
  use ExUnit.Case, async: true

  test "default and coalescing distinguish false from undefined" do
    assert Jexata.run("missing ?: 9", %{}) == {:ok, 9}
    assert Jexata.run("0 ?: 9", %{}) == {:ok, 9}
    assert Jexata.run("0 ?? 9", %{}) == {:ok, 0}
    assert Jexata.run("missing ?? 9", %{}) == {:ok, 9}
  end

  test "descendant navigation finds nested property values" do
    data = %{"a" => %{"b" => 1}}
    assert Jexata.run("a.**.b", data) == {:ok, 1}
    assert Jexata.run("a.**", data) == {:ok, [%{"b" => 1}, 1]}
  end

  test "order-by sorts by evaluated keys" do
    data = %{"items" => [%{"price" => 3}, %{"price" => 1}, %{"price" => 2}]}
    assert Jexata.run("items^(price).price", data) == {:ok, [1, 2, 3]}
    assert Jexata.run("items^(>price).price", data) == {:ok, [3, 2, 1]}
  end

  test "grouping evaluates values over each group" do
    data = %{
      "items" => [
        %{"kind" => "a", "price" => 1},
        %{"kind" => "a", "price" => 2},
        %{"kind" => "b", "price" => 4}
      ]
    }

    assert Jexata.run("items{kind:$sum(price)}", data) == {:ok, %{"a" => 3, "b" => 4}}
    assert Jexata.run("items{kind:price}", data) == {:ok, %{"a" => [1, 2], "b" => 4}}
  end

  test "function chaining passes the left value as the first argument" do
    assert Jexata.run("'  hi  ' ~> $trim() ~> $uppercase()", %{}) == {:ok, "HI"}
    assert Jexata.run("3 ~> function($x){$x * 2}", %{}) == {:ok, 6}
  end
end
