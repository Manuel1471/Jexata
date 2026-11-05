defmodule Jexata.RegexTest do
  use ExUnit.Case, async: true

  test "regex literals work with contains split and replacement" do
    assert Jexata.run("$contains('Hat', /hat/i)", %{}) == {:ok, true}
    assert Jexata.run("$split('ababbxabbcc', /b+/, 2)", %{}) == {:ok, ["a", "a"]}

    assert Jexata.run("$replace('ababbxabbcc', /b+/, 'yy', 2)", %{}) ==
             {:ok, "ayyayyxabbcc"}

    assert Jexata.run("$replace('John Smith', /(\\w+)\\s(\\w+)/, '$2, $1')", %{}) ==
             {:ok, "Smith, John"}

    assert Jexata.run("$replace('ab ab', /(a)(b)/, '$2-$1-$$')", %{}) ==
             {:ok, "b-a-$ b-a-$"}

    assert Jexata.run("8 / 2", %{}) == {:ok, 4.0}

    assert Jexata.run("$contains($.\"Product Name\", /hat/i)", %{"Product Name" => "Hat"}) ==
             {:ok, true}

    assert Jexata.run("$match('John Smith', /(\\w+)\\s(\\w+)/).groups", %{}) ==
             {:ok, ["John", "Smith"]}

    assert Jexata.run("$map(['Ada'], $match(?, /A/)).match", %{}) == {:ok, "A"}
  end
end
