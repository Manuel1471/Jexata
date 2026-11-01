defmodule Jexata.Functions.Array do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value

  def supported?(name), do: name in ["$append", "$reverse", "$sort", "$distinct", "$zip"]
  def call("$append", [left, right]), do: {:ok, Value.items(left) ++ Value.items(right)}
  def call("$reverse", [value]), do: {:ok, Enum.reverse(Value.items(value))}
  def call("$distinct", [value]), do: {:ok, Enum.uniq(Value.items(value))}

  def call("$zip", args) when args != [] do
    lists = Enum.map(args, &Value.items/1)
    count = lists |> Enum.map(&length/1) |> Enum.min()

    {:ok,
     if(count == 0,
       do: [],
       else: for(index <- 0..(count - 1), do: Enum.map(lists, &Enum.at(&1, index)))
     )}
  end

  def call("$sort", [value]) do
    items = Value.items(value)

    cond do
      Enum.all?(items, &is_number/1) -> {:ok, Enum.sort(items)}
      Enum.all?(items, &is_binary/1) -> {:ok, Enum.sort(items)}
      true -> {:error, Error.new("T2007", "$sort requires all numbers or all strings")}
    end
  end

  def call(name, _), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}
end
