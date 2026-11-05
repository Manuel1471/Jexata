defmodule Jexata.NavigationBindingsTest do
  use ExUnit.Case, async: true

  test "parent navigation keeps the ancestor for equal scalar values in separate branches" do
    data = %{
      "orders" => [
        %{"id" => "o1", "products" => [%{"price" => 5}, %{"price" => 7}]},
        %{"id" => "o2", "products" => [%{"price" => 5}]}
      ]
    }

    assert Jexata.run("orders.products.{ 'order': %.id, 'price': price }", data) ==
             {:ok,
              [
                %{"order" => "o1", "price" => 5},
                %{"order" => "o1", "price" => 7},
                %{"order" => "o2", "price" => 5}
              ]}

    assert Jexata.run("orders.products.price[%.%.id='o2']", data) == {:ok, 5}
  end

  test "focus binding joins sibling collections and index binding resets per parent" do
    data = %{
      "left" => [%{"k" => 1}, %{"k" => 2}],
      "right" => [%{"k" => 2, "v" => "B"}, %{"k" => 1, "v" => "A"}]
    }

    assert Jexata.run("left@$l.right@$r[$l.k=$r.k].{'v':$r.v}", data) ==
             {:ok, [%{"v" => "A"}, %{"v" => "B"}]}

    assert Jexata.run("right#$i[$i=1].v", data) == {:ok, "A"}
  end

  test "invalid focus and parent expressions return reference error codes" do
    assert {:error, %Jexata.Error{code: "S0215"}} =
             Jexata.compile("orders[0]@$o.id")

    assert {:error, %Jexata.Error{code: "S0217"}} = Jexata.run("%", %{})
    assert {:error, %Jexata.Error{code: "T1006"}} = Jexata.run("%()", %{})
  end
end
