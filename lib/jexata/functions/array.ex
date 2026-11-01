defmodule Jexata.Functions.Array do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value

  def supported?(name), do: name in ["$append", "$reverse", "$sort", "$distinct"]
  def call("$append", [left, right]), do: {:ok, Value.items(left) ++ Value.items(right)}
  def call("$reverse", [value]), do: {:ok, Enum.reverse(Value.items(value))}
  def call("$distinct", [value]), do: {:ok, Enum.uniq(Value.items(value))}

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
