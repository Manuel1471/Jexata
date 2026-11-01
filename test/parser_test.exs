defmodule Jexata.ParserTest do
  use ExUnit.Case, async: true
  alias Jexata.Parser

  test "parses precedence and nested expressions" do
    assert {:ok, {:binary, "+", {:literal, 1}, {:binary, "*", {:literal, 2}, {:literal, 3}}}} =
             Parser.parse("1 + 2 * 3")

    assert {:ok, {:binary, "*", {:block, [{:binary, "+", _, _}]}, _}} =
             Parser.parse("(1 + 2) * 3")
  end

  test "parses paths, predicates, calls, constructors and blocks" do
    assert {:ok, {:call, {:variable, "$sum"}, [{:path, _, _}]}} =
             Parser.parse("$sum(orders.price)")

    assert {:ok, {:filter, {:name, "items"}, {:binary, ">", _, _}}} =
             Parser.parse("items[price > 2]")

    assert {:ok, {:object, [{_, {:array, [_, _]}}]}} = Parser.parse("{'a': [1,2]}")
    assert {:ok, {:block, [_, _]}} = Parser.parse("($x := 2; $x + 1)")
  end

  test "rejects incomplete expressions" do
    assert {:error, %Jexata.Error{code: "S0202"}} = Parser.parse("a +")
    assert {:error, %Jexata.Error{code: "S0202"}} = Parser.parse("[1,")
    assert {:error, %Jexata.Error{code: "S0202"}} = Parser.parse("(1")
  end

  test "reports invalid grouped steps and numeric path segments" do
    assert {:error, %Jexata.Error{code: "S0213"}} = Parser.parse("$.7")
    assert {:error, %Jexata.Error{code: "S0201"}} = Parser.parse("$.7a")
    assert {:error, %Jexata.Error{code: "S0210"}} = Parser.parse("[1]{'n':$}{'n':$}")
    assert {:error, %Jexata.Error{code: "S0209"}} = Parser.parse("[1]{'n':$}[true]")
    assert {:error, %Jexata.Error{code: "S0207"}} = Parser.parse("1=")
  end
end
