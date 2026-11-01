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
  def boolean(%Jexata.Runtime.Closure{}), do: false
  def boolean(%Jexata.Runtime.Builtin{}), do: false
  def boolean(%Jexata.Runtime.Partial{}), do: false
  def boolean(%Jexata.Runtime.Transform{}), do: false
  def boolean(%Jexata.Runtime.Composition{}), do: false
  def boolean(map) when is_map(map), do: map_size(map) > 0
  def boolean([]), do: false
  def boolean(list) when is_list(list), do: Enum.any?(list, &boolean/1)
  def boolean(_), do: true

  def select(value, name) when is_map(value) and not is_struct(value) do
    case Map.fetch(value, name) do
      {:ok, selected} -> selected
      :error -> Value.undefined()
    end
  end

  def select(value, name) when is_list(value), do: select_list(value, name, [])

  def select(%Sequence{items: values}, name), do: select(values, name)
  def select(_, _), do: Value.undefined()

  defp select_list([], _name, acc), do: acc |> Enum.reverse() |> Value.sequence_from_items()

  defp select_list([item | rest], name, acc),
    do: select_list(rest, name, Enum.reverse(Value.items(select(item, name)), acc))

  def compare("=", left, right), do: left == right
  def compare("!=", left, right), do: left != right
  def compare("in", left, right), do: Enum.any?(Value.items(right), &(&1 == left))
  def compare("<", left, right), do: left < right
  def compare("<=", left, right), do: left <= right
  def compare(">", left, right), do: left > right
  def compare(">=", left, right), do: left >= right

  def number_string(value) when is_integer(value), do: Integer.to_string(value)

  def number_string(value) when is_float(value) do
    [mantissa, exponent] = value |> :erlang.float_to_binary(scientific: 14) |> String.split("e")
    exponent = String.to_integer(exponent)
    sign = if String.starts_with?(mantissa, "-"), do: "-", else: ""

    digits =
      mantissa |> String.trim_leading("-") |> String.replace(".", "") |> String.trim_trailing("0")

    digits = if digits == "", do: "0", else: digits

    cond do
      digits == "0" ->
        "0"

      exponent in 0..20 ->
        decimal_string(sign, digits, exponent + 1)

      exponent in -6..-1 ->
        sign <> "0." <> String.duplicate("0", -exponent - 1) <> digits

      true ->
        head = String.first(digits)
        tail = String.slice(digits, 1..-1//1)
        fractional = if tail == "", do: "", else: "." <> tail
        exponent_text = if exponent > 0, do: "+#{exponent}", else: Integer.to_string(exponent)
        sign <> head <> fractional <> "e" <> exponent_text
    end
  end

  defp decimal_string(sign, digits, point) do
    if point >= String.length(digits) do
      sign <> digits <> String.duplicate("0", point - String.length(digits))
    else
      {whole, fractional} = String.split_at(digits, point)
      sign <> whole <> "." <> fractional
    end
  end
end
