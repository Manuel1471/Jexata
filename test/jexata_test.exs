defmodule JexataTest do
  use ExUnit.Case, async: true

  test "compilation returns an immutable expression" do
    assert {:ok, %Jexata.Expression{source: "a"}} = Jexata.compile("a")
  end

  test "invalid inputs return structured errors" do
    assert {:error, %Jexata.Error{code: "J0001"}} = Jexata.compile(123)
    assert {:error, %Jexata.Error{code: "S0201", position: 0}} = Jexata.compile(" ")
    assert_raise Jexata.Error, fn -> Jexata.compile!("") end
  end
end
