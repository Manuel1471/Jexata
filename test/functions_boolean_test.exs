defmodule Jexata.FunctionsBooleanTest do
  use ExUnit.Case, async: true

  test "boolean functions distinguish undefined, null and empty objects" do
    assert Jexata.run("$exists(missing)", %{}) == {:ok, false}
    assert Jexata.run("$exists(null)", %{}) == {:ok, true}
    assert Jexata.run("$boolean({})", %{}) == {:ok, false}
    assert Jexata.run("$not(false)", %{}) == {:ok, true}
    assert Jexata.run("$boolean(function($x){$x})", %{}) == {:ok, false}
  end
end
