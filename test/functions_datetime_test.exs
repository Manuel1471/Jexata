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

  test "parses and formats date pictures, including names and timezone offsets" do
    assert Jexata.run("$toMillis('27th April 2008', '[D1o] [MNn] [Y0001]')", %{}) ==
             {:ok, 1_209_254_400_000}

    assert Jexata.run(
             "$toMillis('2020-09-09 08:00:00 +02:00', '[Y0001]-[M01]-[D01] [H01]:[m01]:[s01] [Z]')",
             %{}
           ) == {:ok, 1_599_631_200_000}

    assert Jexata.run(
             "$fromMillis(1522159380123, '[Y0001]-[M01]-[D01] [H01]:[m01]', '+0530')",
             %{}
           ) == {:ok, "2018-03-27 19:33"}
  end
end
