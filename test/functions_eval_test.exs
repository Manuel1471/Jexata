defmodule Jexata.FunctionsEvalTest do
  use ExUnit.Case, async: true

  test "$eval parses and evaluates source against current or supplied context" do
    assert Jexata.run("$eval('[1,2,3]')", %{}) == {:ok, [1, 2, 3]}

    assert Jexata.run("$eval('Price * Quantity')", %{"Price" => 4, "Quantity" => 3}) ==
             {:ok, 12}

    assert Jexata.run("$eval('Price * Quantity', item)", %{
             "item" => %{"Price" => 4, "Quantity" => 3}
           }) == {:ok, 12}

    assert Jexata.run("$eval(missing)", %{}) == {:ok, :undefined}
  end

  test "$eval wraps parse and runtime errors" do
    assert {:error, %Jexata.Error{code: "D3120"}} = Jexata.run("$eval('#')", %{})
    assert {:error, %Jexata.Error{code: "D3121"}} = Jexata.run("$eval('string(2)')", %{})
  end
end
