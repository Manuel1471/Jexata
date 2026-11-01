defmodule Jexata.TransformTest do
  use ExUnit.Case, async: true

  test "transform updates selected objects without modifying the input" do
    input = %{"items" => [%{"price" => 2, "old" => true}, %{"price" => 3, "old" => true}]}

    assert Jexata.run("$ ~> |items|{'total': price * 2}, 'old'|", input) ==
             {:ok, %{"items" => [%{"price" => 2, "total" => 4}, %{"price" => 3, "total" => 6}]}}

    assert input == %{"items" => [%{"price" => 2, "old" => true}, %{"price" => 3, "old" => true}]}
  end

  test "transform validates update and delete expressions" do
    assert {:error, %Jexata.Error{code: "T2011"}} =
             Jexata.run("$ ~> |$|5|", %{})

    assert {:error, %Jexata.Error{code: "T2012"}} =
             Jexata.run("$ ~> |$|{},5|", %{})
  end
end
