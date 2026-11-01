defmodule Jexata.Functions.Array do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value

  def supported?(name),
    do: name in ["$append", "$reverse", "$sort", "$distinct", "$zip", "$shuffle"]

  def call("$append", [left, right]) when is_struct(left, Value.Undefined), do: {:ok, right}
  def call("$append", [left, right]) when is_struct(right, Value.Undefined), do: {:ok, left}
  def call("$append", [left, right]), do: {:ok, Value.items(left) ++ Value.items(right)}
  def call("$reverse", [value]) when is_struct(value, Value.Undefined), do: {:ok, value}
  def call("$reverse", [value]), do: {:ok, Enum.reverse(Value.items(value))}
  def call("$distinct", [value]), do: {:ok, Enum.uniq(Value.items(value))}
  def call("$shuffle", [value]) when is_struct(value, Value.Undefined), do: {:ok, value}
  def call("$shuffle", [value]), do: {:ok, value |> Value.items() |> Enum.shuffle()}

  def call("$zip", args) when args != [] do
    lists = Enum.map(args, &Value.items/1)
    {:ok, lists |> Enum.zip() |> Enum.map(&Tuple.to_list/1)}
  end

  def call("$sort", [value]) when is_struct(value, Value.Undefined), do: {:ok, value}

  def call("$sort", [value]) do
    items = Value.items(value)

    cond do
      Enum.all?(items, &is_number/1) -> {:ok, Enum.sort(items)}
      Enum.all?(items, &is_binary/1) -> {:ok, Enum.sort(items)}
      true -> {:error, Error.new("D3070", "$sort requires all numbers or all strings")}
    end
  end

  def call(name, _), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}
end
