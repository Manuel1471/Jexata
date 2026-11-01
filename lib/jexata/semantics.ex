defmodule Jexata.Semantics do
  @moduledoc false
  alias Jexata.Runtime.Value
  alias Jexata.Runtime.Value.{Sequence, Undefined}

  def boolean(%Undefined{}), do: false
  def boolean(nil), do: false
  def boolean(false), do: false
  def boolean(0), do: false
  def boolean(value) when is_float(value) and value == 0.0, do: false
  def boolean(""), do: false
  def boolean(%Sequence{items: items}), do: Enum.any?(items, &boolean/1)
  def boolean(map) when is_map(map), do: map_size(map) > 0
  def boolean([]), do: false
  def boolean(list) when is_list(list), do: Enum.any?(list, &boolean/1)
  def boolean(_), do: true

  def select(value, name) do
    value
    |> Value.items()
    |> Enum.map(fn
      map when is_map(map) -> Map.get(map, name, Value.undefined())
      _ -> Value.undefined()
    end)
    |> Value.sequence()
  end

  def compare("=", left, right), do: left == right
  def compare("!=", left, right), do: left != right
  def compare("in", left, right), do: Enum.any?(Value.items(right), &(&1 == left))
  def compare("<", left, right), do: left < right
  def compare("<=", left, right), do: left <= right
  def compare(">", left, right), do: left > right
  def compare(">=", left, right), do: left >= right
end
