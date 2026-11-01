defmodule Jexata.FunctionsNumberFormatTest do
  use ExUnit.Case, async: true

  test "formats decimal, grouped, percent and exponent pictures" do
    assert Jexata.run("$formatNumber(12345.6, '#,###.00')", %{}) == {:ok, "12,345.60"}
    assert Jexata.run("$formatNumber(0.14, '01%')", %{}) == {:ok, "14%"}
    assert Jexata.run("$formatNumber(1234.5678, '00.000e0')", %{}) == {:ok, "12.346e2"}
    assert Jexata.run("$formatNumber(2, '000.000')", %{}) == {:ok, "002.000"}
    assert Jexata.run("$formatNumber(missing, '#0.00')", %{}) == {:ok, :undefined}
  end

  test "rejects malformed pictures with JSONata codes" do
    assert {:error, %Jexata.Error{code: "D3080"}} =
             Jexata.run("$formatNumber(20, '#;#;#')", %{})

    assert {:error, %Jexata.Error{code: "D3081"}} =
             Jexata.run("$formatNumber(20, '#.0.0')", %{})
  end
end
