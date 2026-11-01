defmodule Jexata.FunctionsStringTest do
  use ExUnit.Case, async: true

  test "string functions handle Unicode and arrays" do
    assert Jexata.run("$length('hé')", %{}) == {:ok, 2}
    assert Jexata.run("$uppercase('abc')", %{}) == {:ok, "ABC"}
    assert Jexata.run("$substring('hello', 1, 3)", %{}) == {:ok, "ell"}
    assert Jexata.run("$contains('hello', 'ell')", %{}) == {:ok, true}
    assert Jexata.run("$join(['a','b'], '-')", %{}) == {:ok, "a-b"}
    assert Jexata.run("$string(null)", %{}) == {:ok, "null"}
  end

  test "substring delimiters, split limits and literal replacement" do
    assert Jexata.run("$substringBefore('abc', 'b')", %{}) == {:ok, "a"}
    assert Jexata.run("$substringAfter('abc', 'b')", %{}) == {:ok, "c"}
    assert Jexata.run("$substringBefore('abc', 'x')", %{}) == {:ok, "abc"}
    assert Jexata.run("$substringBefore('Hola', '')", %{}) == {:ok, ""}
    assert Jexata.run("$split('a,b,c', ',', 2)", %{}) == {:ok, ["a", "b"]}
    assert Jexata.run("$replace('aba', 'a', 'x', 1)", %{}) == {:ok, "xba"}
    assert Jexata.run("$contains('abc', missing)", %{}) == {:ok, :undefined}
  end

  test "pad repeats Unicode patterns on either side" do
    assert Jexata.run("$pad('foo', 8, '-+')", %{}) == {:ok, "foo-+-+-"}
    assert Jexata.run("$pad('𝄞💩', -7)", %{}) == {:ok, "     𝄞💩"}
    assert Jexata.run("$pad('foo', 5.7, '')", %{}) == {:ok, "foo  "}
    assert Jexata.run("$pad(missing, 3)", %{}) == {:ok, :undefined}
  end
end
