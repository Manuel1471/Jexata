defmodule Jexata.Functions.Object do
  @moduledoc false
  alias Jexata.{Error, Semantics}
  alias Jexata.Runtime.Value

  def supported?(name), do: name in ["$keys", "$lookup", "$merge", "$spread"]

  def call("$keys", [value]) do
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

  def call("$lookup", [value, key]) when is_binary(key), do: {:ok, Semantics.select(value, key)}

  def call("$merge", [value]) when is_struct(value, Value.Undefined), do: {:ok, value}

  def call("$merge", [value]) do
    items = Value.items(value)

    if Enum.all?(items, &plain_map?/1),
      do: {:ok, Enum.reduce(items, %{}, &Map.merge(&2, &1))},
      else: type_error("$merge")
  end

  def call("$spread", [value]) do
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

  def call(name, _), do: type_error(name)

  defp plain_map?(value), do: is_map(value) and not is_struct(value)

  defp type_error(name), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}
end
