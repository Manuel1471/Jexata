defmodule Jexata.PartialApplicationTest do
  use ExUnit.Case, async: true

  test "partial application fills placeholders in order" do
    assert Jexata.run("($add:=function($x,$y){$x+$y}; $add(?,2)(3))", %{}) == {:ok, 5}

    assert Jexata.run("($first:=$substring(?,0,?); $first(?,5)('Hello World'))", %{}) ==
             {:ok, "Hello"}
  end

  test "partial application reports invalid targets" do
    assert {:error, %Jexata.Error{code: "T1007"}} =
             Jexata.run("substring(?,0,?)", %{})

    assert {:error, %Jexata.Error{code: "T1008"}} = Jexata.run("unknown(?)", %{})
  end
end
