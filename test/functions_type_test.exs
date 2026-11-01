defmodule Jexata.FunctionsTypeTest do
  use ExUnit.Case, async: true

  test "$type reports JSONata value categories" do
    for {expression, expected} <- [
          {"$type(missing)", :undefined},
          {"$type(null)", "null"},
          {"$type(true)", "boolean"},
          {"$type(1.5)", "number"},
          {"$type('x')", "string"},
          {"$type([])", "array"},
          {"$type({})", "object"},
          {"$type(function($x){$x})", "function"}
        ] do
      assert Jexata.run(expression, %{}) == {:ok, expected}
    end
  end
end
