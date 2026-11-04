defmodule Jexata.FunctionsNumberFormatTest do
  use ExUnit.Case, async: true

  test "formats decimal, grouped, percent and exponent pictures" do
    assert Jexata.run("$formatNumber(12345.6, '#,###.00')", %{}) == {:ok, "12,345.60"}
    assert Jexata.run("$formatNumber(0.14, '01%')", %{}) == {:ok, "14%"}
    assert Jexata.run("$formatNumber(1234.5678, '00.000e0')", %{}) == {:ok, "12.346e2"}
    assert Jexata.run("$formatNumber(2, '000.000')", %{}) == {:ok, "002.000"}
    assert Jexata.run("$formatNumber(0, '#,###.00')", %{}) == {:ok, ".00"}
    assert Jexata.run("$formatNumber(0.4, '#.##')", %{}) == {:ok, ".4"}
    assert Jexata.run("$formatNumber(0, '#.##')", %{}) == {:ok, ".0"}
    assert Jexata.run("$formatNumber(missing, '#0.00')", %{}) == {:ok, :undefined}
  end

  test "integer grouping fast path handles boundaries and signs" do
    for {value, expected} <- [
          {0, "0"},
          {9, "9"},
          {999, "999"},
          {1_000, "1,000"},
          {12_345_678, "12,345,678"},
          {-1, "-1"},
          {-1_000_000, "-1,000,000"}
        ] do
      assert Jexata.Functions.NumberFormat.call([value, "#,##0"]) == {:ok, expected}
    end
  end

  test "rejects malformed pictures with JSONata codes" do
    assert {:error, %Jexata.Error{code: "D3080"}} =
             Jexata.run("$formatNumber(20, '#;#;#')", %{})

    assert {:error, %Jexata.Error{code: "D3081"}} =
             Jexata.run("$formatNumber(20, '#.0.0')", %{})
  end
end
