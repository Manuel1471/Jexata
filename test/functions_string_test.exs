defmodule Jexata.FunctionsStringTest do
  use ExUnit.Case, async: true

  test "string functions handle Unicode and arrays" do
    assert Jexata.run("$length('hé')", %{}) == {:ok, 2}
    assert Jexata.run("$uppercase('abc')", %{}) == {:ok, "ABC"}
    assert Jexata.run("$substring('hello', 1, 3)", %{}) == {:ok, "ell"}
    assert Jexata.run("$contains('hello', 'ell')", %{}) == {:ok, true}
    assert Jexata.run("$join(['a','b'], '-')", %{}) == {:ok, "a-b"}
    assert Jexata.run("$string(null)", %{}) == {:ok, "null"}
    assert Jexata.run("$length(\"\\uD834\\uDD1E\")", %{}) == {:ok, 1}
  end

  test "substring delimiters, split limits and literal replacement" do
    assert Jexata.run("$substringBefore('abc', 'b')", %{}) == {:ok, "a"}
    assert Jexata.run("$substringAfter('abc', 'b')", %{}) == {:ok, "c"}
    assert Jexata.run("$substringBefore('abc', 'x')", %{}) == {:ok, "abc"}
    assert Jexata.run("$substringBefore('Hola', '')", %{}) == {:ok, ""}
    assert Jexata.run("$split('a,b,c', ',', 2)", %{}) == {:ok, ["a", "b"]}
    assert Jexata.run("$replace('aba', 'a', 'x', 1)", %{}) == {:ok, "xba"}
    assert Jexata.run("$contains('abc', missing)", %{}) == {:ok, :undefined}
    assert Jexata.run("$split('Hello', '')", %{}) == {:ok, ["H", "e", "l", "l", "o"]}
    assert Jexata.run("$join('hello')", %{}) == {:ok, "hello"}
  end

  test "pad repeats Unicode patterns on either side" do
    assert Jexata.run("$pad('foo', 8, '-+')", %{}) == {:ok, "foo-+-+-"}
    assert Jexata.run("$pad('𝄞💩', -7)", %{}) == {:ok, "     𝄞💩"}
    assert Jexata.run("$pad('foo', 5.7, '')", %{}) == {:ok, "foo  "}
    assert Jexata.run("$pad(missing, 3)", %{}) == {:ok, :undefined}
  end

  test "number to string follows JSONata significant digits and exponent thresholds" do
    assert Jexata.run("$string(22/7)", %{}) == {:ok, "3.14285714285714"}
    assert Jexata.run("$string(1e20)", %{}) == {:ok, "100000000000000000000"}
    assert Jexata.run("$string(1e21)", %{}) == {:ok, "1e+21"}
    assert Jexata.run("$string(1e-6)", %{}) == {:ok, "0.000001"}
    assert Jexata.run("$string(1e-7)", %{}) == {:ok, "1e-7"}
  end

  test "built-in functions are values and stringify to an empty string" do
    assert Jexata.run("$string($string)", %{}) == {:ok, ""}
    assert Jexata.run("$type($sum)", %{}) == {:ok, "function"}
  end

  test "base64 functions encode and decode UTF-8 bytes" do
    assert Jexata.run("$base64encode('hello:world')", %{}) == {:ok, "aGVsbG86d29ybGQ="}
    assert Jexata.run("$base64decode('aGVsbG86d29ybGQ=')", %{}) == {:ok, "hello:world"}
    assert Jexata.run("$base64encode()", %{}) == {:ok, :undefined}
  end
end
