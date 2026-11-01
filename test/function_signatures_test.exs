defmodule Jexata.FunctionSignaturesTest do
  use ExUnit.Case, async: true

  test "signatures validate types and insert path context" do
    assert Jexata.run("function($x,$y)<n-n:n>{$x+$y}(2, 6)", %{}) == {:ok, 8}

    assert Jexata.run("[1..3].function($x,$y)<n-n:n>{$x+$y}(6)", %{}) ==
             {:ok, [7, 8, 9]}

    assert {:error, %Jexata.Error{code: "T0410"}} =
             Jexata.run("function($x)<n:n>{$x}('a')", %{})

    assert {:error, %Jexata.Error{code: "T0412"}} =
             Jexata.run("function($x)<a<n>:a>{$x}(['a'])", %{})
  end

  test "invalid signature syntax reports a structured compile error" do
    assert {:error, %Jexata.Error{code: "S0401"}} =
             Jexata.compile("function($x)<n<n>>{$x}")
  end
end
