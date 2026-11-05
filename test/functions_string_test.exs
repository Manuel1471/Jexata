defmodule Jexata.FunctionsStringTest do
  use ExUnit.Case, async: true

  test "string functions handle Unicode and arrays" do
    assert Jexata.run("$length('hé')", %{}) == {:ok, 2}
    assert Jexata.run("$uppercase('abc')", %{}) == {:ok, "ABC"}
    assert Jexata.run("$trim('  a\\t b\\n c  ')", %{}) == {:ok, "a b c"}
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

  test "plain regex fast paths preserve replacement, split and contains semantics" do
    assert Jexata.run("$replace('OrderOrder', /Order/, 'X')", %{}) == {:ok, "XX"}
    assert Jexata.run("$replace('OrderOrder', /Order/, 'X', 1)", %{}) == {:ok, "XOrder"}
    assert Jexata.run("$split('OrderOrder', /Order/)", %{}) == {:ok, ["", "", ""]}
    assert Jexata.run("$contains('new Order', /Order/)", %{}) == {:ok, true}
    assert Jexata.run("$replace('Order', /Order/, '$1')", %{}) == {:ok, ""}
    assert Jexata.run("$replace('a.b', /\\./, '-')", %{}) == {:ok, "a-b"}
    assert Jexata.run("$contains('ORDER', /Order/i)", %{}) == {:ok, true}
  end

  test "capture templates preserve dollars, multi-digit references and literal text" do
    pattern = ~r/(Order) ([0-9]+)/

    for {template, expected} <- [
          {"$2 $1", "123 Order"},
          {"$$-$1", "$-Order"},
          {"$10", "Order0"},
          {"$9", ""},
          {"$x and $", "$x and $"}
        ] do
      assert Jexata.Functions.String.call("$replace", ["Order 123", pattern, template]) ==
               {:ok, expected}
    end
  end

  test "$match keeps its array boundary inside $map" do
    match = %{"match" => "Order", "index" => 0, "groups" => []}
    data = %{"orders" => [%{"text" => "Order 1"}, %{"text" => "Order 2"}]}

    assert Jexata.run("$match('Order 1',/Order/)", %{}) == {:ok, match}

    assert Jexata.run("$map(orders,function($o){$match($o.text,/Order/)})", data) ==
             {:ok, [[match], [match]]}
  end

  test "pad repeats Unicode patterns on either side" do
    assert Jexata.run("$pad('foo', 8, '-+')", %{}) == {:ok, "foo-+-+-"}
    assert Jexata.run("$pad('x', 6, 'é𝄞')", %{}) == {:ok, "xé𝄞é𝄞é"}
    assert Jexata.run("$pad('𝄞💩', -7)", %{}) == {:ok, "     𝄞💩"}
    assert Jexata.run("$pad('foo', 5.7, '')", %{}) == {:ok, "foo  "}
    assert Jexata.run("$pad(missing, 3)", %{}) == {:ok, :undefined}
    assert {:error, %Jexata.Error{code: "J1004"}} = Jexata.run("$pad('x', 1000000000)", %{})
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

  test "object literals stringify in source order, including nested objects" do
    assert Jexata.run(~S|$string({'b': 2, 'a': {'z': 1, 'y': 0}})|, %{}) ==
             {:ok, ~s({"b":2,"a":{"z":1,"y":0}})}

    assert Jexata.run(~S|$string({'b': 2, 'a': 1}, true)|, %{}) ==
             {:ok, "{\n  \"b\": 2,\n  \"a\": 1\n}"}

    assert match?({:error, %Jexata.Error{code: "D3001"}}, Jexata.run("$string(1/0)", %{}))
    assert Jexata.run("($f := $string(?); $f(2))", %{}) == {:ok, "2"}
  end

  test "base64 functions encode and decode UTF-8 bytes" do
    assert Jexata.run("$base64encode('hello:world')", %{}) == {:ok, "aGVsbG86d29ybGQ="}
    assert Jexata.run("$base64decode('aGVsbG86d29ybGQ=')", %{}) == {:ok, "hello:world"}
    assert Jexata.run("$base64encode()", %{}) == {:ok, :undefined}
  end

  test "undefined string arguments propagate and concatenation treats them as empty" do
    assert Jexata.run("$uppercase(missing)", %{}) == {:ok, :undefined}
    assert Jexata.run("$substring(missing, 1)", %{}) == {:ok, :undefined}
    assert Jexata.run("'x' & missing", %{}) == {:ok, "x"}
    assert Jexata.run("missing & 'x'", %{}) == {:ok, "x"}
    assert Jexata.run("name.$uppercase()", %{"name" => "Ada"}) == {:ok, "ADA"}

    assert Jexata.run("name.$uppercase().$substringBefore(' ')", %{"name" => "Ada Bell"}) ==
             {:ok, "ADA"}

    assert Jexata.run("$substring('Hello World', 5.5, 5)", %{}) == {:ok, " Worl"}
  end
end
