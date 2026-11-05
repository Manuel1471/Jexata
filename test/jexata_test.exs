defmodule JexataTest do
  use ExUnit.Case, async: true

  test "compilation returns an immutable expression" do
    assert {:ok, %Jexata.Expression{source: "a"}} = Jexata.compile("a")
  end

  test "external bindings are isolated per evaluation" do
    expression = Jexata.compile!("$price.foo.bar")

    assert Jexata.evaluate(expression, %{}, %{"price" => %{"foo" => %{"bar" => 45}}}) ==
             {:ok, 45}

    assert Jexata.evaluate(expression, %{}) == {:ok, :undefined}
    assert Jexata.run("[1,2,3].$v", :undefined, %{"v" => []}) == {:ok, :undefined}
  end

  test "invalid inputs return structured errors" do
    assert {:error, %Jexata.Error{code: "J0001"}} = Jexata.compile(123)
    assert {:error, %Jexata.Error{code: "S0201", position: 0}} = Jexata.compile(" ")
    assert_raise Jexata.Error, fn -> Jexata.compile!("") end
  end
end
