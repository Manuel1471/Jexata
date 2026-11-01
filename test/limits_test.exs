defmodule Jexata.LimitsTest do
  use ExUnit.Case, async: true

  test "rejects source, token and nesting limits before evaluation" do
    assert {:error, %Jexata.Error{code: "J1001"}} = Jexata.compile("1 + 2", max_source_bytes: 3)
    assert {:error, %Jexata.Error{code: "J1002"}} = Jexata.compile("1 + 2", max_tokens: 3)
    assert {:error, %Jexata.Error{code: "J1003"}} = Jexata.compile("((1))", max_nesting: 1)

    assert {:error, %Jexata.Error{code: "J1002"}} =
             Jexata.compile("((1))", max_nesting: 1, max_tokens: 3)
  end

  test "rejects invalid options and invalid UTF-8" do
    assert {:error, %Jexata.Error{code: "J0005"}} = Jexata.compile("1", max_tokens: 0)
    assert {:error, %Jexata.Error{code: "J0001"}} = Jexata.compile(<<255>>)
    assert {:error, %Jexata.Error{code: "S0201"}} = Jexata.compile(" \t\u00a0 ")
  end

  test "quoted delimiters do not consume or evade nesting depth" do
    assert {:ok, _} = Jexata.compile("['(', ')']", max_nesting: 1)
    assert {:ok, _} = Jexata.compile("[')']", max_nesting: 1)

    assert {:error, %Jexata.Error{code: "J1003"}} =
             Jexata.compile("[')', [1]]", max_nesting: 1)
  end
end
