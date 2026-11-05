defmodule Jexata.Functions.Array do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value
  alias Jexata.Runtime.CollectionLimit

  def call(name, args), do: CollectionLimit.check_result(call_impl(name, args))

  def supported?(name),
    do: name in ["$append", "$reverse", "$sort", "$distinct", "$zip", "$shuffle"]

  defp call_impl("$append", [left, right]) when is_struct(left, Value.Undefined), do: {:ok, right}
  defp call_impl("$append", [left, right]) when is_struct(right, Value.Undefined), do: {:ok, left}
  defp call_impl("$append", [left, right]), do: {:ok, Value.items(left) ++ Value.items(right)}
  defp call_impl("$reverse", [value]) when is_struct(value, Value.Undefined), do: {:ok, value}
  defp call_impl("$reverse", [value]), do: {:ok, Enum.reverse(Value.items(value))}
  defp call_impl("$distinct", [value]) when is_struct(value, Value.Undefined), do: {:ok, value}

  defp call_impl("$distinct", [%Value.Sequence{} = value]),
    do: {:ok, Enum.uniq(Value.items(value))}

  defp call_impl("$distinct", [value]) when not is_list(value), do: {:ok, value}
  defp call_impl("$distinct", [value]), do: {:ok, Enum.uniq(Value.items(value))}
  defp call_impl("$shuffle", [value]) when is_struct(value, Value.Undefined), do: {:ok, value}
  defp call_impl("$shuffle", [value]), do: {:ok, value |> Value.items() |> Enum.shuffle()}

  defp call_impl("$zip", args) when args != [] do
    lists = Enum.map(args, &Value.items/1)
    {:ok, lists |> Enum.zip() |> Enum.map(&Tuple.to_list/1)}
  end

  defp call_impl("$sort", [value]) when is_struct(value, Value.Undefined), do: {:ok, value}

  defp call_impl("$sort", [value]) do
    items = Value.items(value)

    cond do
      Enum.all?(items, &is_number/1) -> {:ok, Enum.sort(items)}
      Enum.all?(items, &is_binary/1) -> {:ok, Enum.sort(items)}
      true -> {:error, Error.new("D3070", "$sort requires all numbers or all strings")}
    end
  end

  defp call_impl(name, _), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}
end
