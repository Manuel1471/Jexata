defmodule Jexata.Functions.Object do
  @moduledoc false
  alias Jexata.{Error, Semantics}
  alias Jexata.Runtime.Value
  alias Jexata.Runtime.CollectionLimit

  def call(name, args), do: CollectionLimit.check_result(call_impl(name, args))

  def supported?(name), do: name in ["$keys", "$lookup", "$merge", "$spread", "$clone"]

  defp call_impl("$clone", [value]) when is_map(value) and not is_struct(value), do: {:ok, value}
  defp call_impl("$clone", [value]) when is_list(value), do: {:ok, value}

  defp call_impl("$clone", [value]) when is_struct(value, Value.Undefined),
    do: {:ok, value}

  defp call_impl("$keys", [value]) do
    keys =
      value
      |> Value.items()
      |> Enum.flat_map(fn
        map when is_map(map) and not is_struct(map) -> Map.keys(map)
        _ -> []
      end)
      |> Enum.uniq()

    {:ok, Value.sequence(keys)}
  end

  defp call_impl("$lookup", [value, key]) when is_binary(key),
    do: {:ok, Semantics.select(value, key)}

  defp call_impl("$merge", [value]) when is_struct(value, Value.Undefined), do: {:ok, value}

  defp call_impl("$merge", [value]) do
    items = Value.items(value)

    if Enum.all?(items, &plain_map?/1),
      do: {:ok, Enum.reduce(items, %{}, &Map.merge(&2, &1))},
      else: type_error("$merge")
  end

  defp call_impl("$spread", [value]) do
    if Value.undefined?(value) or is_struct(value, Jexata.Runtime.Closure) or
         is_struct(value, Jexata.Runtime.Builtin) or
         (not is_map(value) and not is_list(value)) do
      {:ok, value}
    else
      items = Value.items(value)

      if Enum.all?(items, &plain_map?/1) do
        {:ok,
         Enum.flat_map(items, fn map -> Enum.map(map, fn {key, entry} -> %{key => entry} end) end)}
      else
        type_error("$spread")
      end
    end
  end

  defp call_impl(name, _), do: type_error(name)

  defp plain_map?(value), do: is_map(value) and not is_struct(value)

  defp type_error(name), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}
end
