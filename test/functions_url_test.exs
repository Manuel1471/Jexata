defmodule Jexata.FunctionsURLTest do
  use ExUnit.Case, async: true

  test "URL functions preserve URI separators and encode components" do
    assert Jexata.run("$encodeUrl('https://mozilla.org/?x=шеллы')", %{}) ==
             {:ok, "https://mozilla.org/?x=%D1%88%D0%B5%D0%BB%D0%BB%D1%8B"}

    assert Jexata.run("$encodeUrlComponent('?x=test')", %{}) == {:ok, "%3Fx%3Dtest"}
    assert Jexata.run("$decodeUrlComponent('%3Fx%3Dtest')", %{}) == {:ok, "?x=test"}
    assert Jexata.run("$decodeUrl(missing)", %{}) == {:ok, :undefined}
    assert {:error, %Jexata.Error{code: "D3140"}} = Jexata.run("$decodeUrl('%E0%A4%A')", %{})
  end
end
