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

  test "transform updates independent nested array paths in one result" do
    input = %{
      "items" => [
        %{"products" => [%{"price" => 1}, %{"price" => 2}]},
        %{"products" => [%{"price" => 3}]}
      ]
    }

    assert Jexata.run("$ ~> |items.products|{'double': price * 2}|", input) ==
             {:ok,
              %{
                "items" => [
                  %{
                    "products" => [%{"price" => 1, "double" => 2}, %{"price" => 2, "double" => 4}]
                  },
                  %{"products" => [%{"price" => 3, "double" => 6}]}
                ]
              }}
  end

  test "transform keeps sequential behavior for overlapping paths" do
    input = %{"child" => %{"value" => 1}}

    assert Jexata.run("$ ~> |**|{'touched': true}|", input) ==
             {:ok, %{"child" => %{"value" => 1, "touched" => true}, "touched" => true}}
  end
end
