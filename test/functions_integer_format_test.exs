defmodule Jexata.FunctionsIntegerFormatTest do
  use ExUnit.Case, async: true

  test "decimal pictures, ordinals, and Unicode digits round trip" do
    assert Jexata.run("$formatInteger(12345678, '#,##0')", %{}) == {:ok, "12,345,678"}
    assert Jexata.run("$formatInteger(123, '000;o')", %{}) == {:ok, "123rd"}
    assert Jexata.run("$parseInteger('1,234,567', '#,##0')", %{}) == {:ok, 1_234_567}
    assert Jexata.run("$parseInteger('١٢٣٤٠', '###١')", %{}) == {:ok, 12_340}
  end

  test "roman, alphabetic, and English words round trip" do
    for {number, picture, text} <- [
          {1984, "I", "MCMLXXXIV"},
          {300, "A", "KN"},
          {3731, "w;o", "three thousand, seven hundred and thirty-first"}
        ] do
      assert Jexata.run("$formatInteger(#{number}, '#{picture}')", %{}) == {:ok, text}
      assert Jexata.run("$parseInteger('#{text}', '#{picture}')", %{}) == {:ok, number}
    end
  end

  test "unsupported pictures and mixed digit families keep reference errors" do
    assert {:error, %Jexata.Error{code: "D3130"}} =
             Jexata.run("$formatInteger(12, 'α')", %{})

    assert {:error, %Jexata.Error{code: "D3131"}} =
             Jexata.run("$formatInteger(12, '##0０')", %{})
  end
end
