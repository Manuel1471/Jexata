defmodule Jexata.FunctionsErrorsTest do
  use ExUnit.Case, async: true

  test "$error returns a structured user error" do
    assert {:error, %Jexata.Error{code: "D3137", message: "bad input"}} =
             Jexata.run("$error('bad input')", %{})

    assert {:error, %Jexata.Error{code: "D3137"}} = Jexata.run("$error()", %{})
    assert {:error, %Jexata.Error{code: "T0410"}} = Jexata.run("$error(5)", %{})
  end

  test "$assert returns undefined on success and an error on failure" do
    assert Jexata.run("$assert(true)", %{}) == {:ok, :undefined}

    assert {:error, %Jexata.Error{code: "D3141", message: "too large"}} =
             Jexata.run("$assert(3 < 2, 'too large')", %{})

    assert {:error, %Jexata.Error{code: "T0410"}} = Jexata.run("$assert(5)", %{})
  end
end
