defmodule Jexata.FunctionsHigherOrderMoreTest do
  use ExUnit.Case, async: true

  test "$single selects exactly one item" do
    assert Jexata.run("$single([0])", %{}) == {:ok, 0}
    assert Jexata.run("$single([0,1,2], function($x){$x=1})", %{}) == {:ok, 1}
    assert {:error, %Jexata.Error{code: "D3138"}} = Jexata.run("$single([1,2])", %{})
    assert {:error, %Jexata.Error{code: "D3139"}} = Jexata.run("$single([])", %{})
  end

  test "$each maps object entries and $sift selects entries" do
    assert Jexata.run("$each({'a':'hi','b':'bye'}, $uppercase)", %{}) ==
             {:ok, ["HI", "BYE"]}

    assert Jexata.run("$sift({'a':1,'b':0}, $boolean)", %{}) == {:ok, %{"a" => 1}}
  end
end
