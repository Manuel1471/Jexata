defmodule Jexata.TokenizerTest do
  use ExUnit.Case, async: true
  alias Jexata.Tokenizer

  test "recognizes literals, names, variables and operators with byte offsets" do
    assert {:ok, tokens} = Tokenizer.tokenize("$sum(é.price) >= 2.5")

    assert Enum.map(tokens, &{&1.type, &1.value, &1.position}) == [
             {:variable, "$sum", 0},
             {:op, "(", 4},
             {:name, "é", 5},
             {:op, ".", 7},
             {:name, "price", 8},
             {:op, ")", 13},
             {:op, ">=", 15},
             {:number, 2.5, 18},
             {:eof, nil, 21}
           ]
  end

  test "decodes quoted field names and strings, and skips comments" do
    assert {:ok, tokens} = Tokenizer.tokenize("/* x */ `full name` & '\\u00E9\\n'")
    assert Enum.map(tokens, & &1.value) == ["full name", "&", "é\n", nil]
  end

  test "rejects malformed lexical input" do
    assert {:error, %Jexata.Error{code: "S0101", position: 0}} = Tokenizer.tokenize("!")
    assert {:error, %Jexata.Error{code: "S0103"}} = Tokenizer.tokenize("'oops")
    assert {:error, %Jexata.Error{code: "S0104"}} = Tokenizer.tokenize("'\\x'")
    assert {:error, %Jexata.Error{code: "S0106"}} = Tokenizer.tokenize("/* oops")
    assert {:error, %Jexata.Error{code: "S0102"}} = Tokenizer.tokenize("1e999999")
  end
end
