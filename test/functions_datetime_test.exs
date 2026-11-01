defmodule Jexata.FunctionsDatetimeTest do
  use ExUnit.Case, async: true

  test "converts ISO timestamps and fixed date pictures to epoch milliseconds" do
    assert Jexata.run("$toMillis('1970-01-01T00:00:00.001Z')", %{}) == {:ok, 1}
    assert Jexata.run("$toMillis('2018')", %{}) == {:ok, 1_514_764_800_000}

    assert Jexata.run("$toMillis('20180205', '[Y0001][M01][D01]')", %{}) ==
             {:ok, 1_517_788_800_000}

    assert {:error, %Jexata.Error{code: "D3110"}} = Jexata.run("$toMillis('foo')", %{})
  end

  test "formats epoch milliseconds in UTC" do
    assert Jexata.run("$fromMillis(1)", %{}) == {:ok, "1970-01-01T00:00:00.001Z"}
    assert Jexata.run("$fromMillis(1509380732935)", %{}) == {:ok, "2017-10-30T16:25:32.935Z"}
    assert Jexata.run("$fromMillis(missing)", %{}) == {:ok, :undefined}
  end
end
