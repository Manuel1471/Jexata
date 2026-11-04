defmodule Jexata.Runtime.Value do
  @moduledoc false
  defmodule Undefined do
    @moduledoc false
    defstruct []
  end

  defmodule Sequence do
    @moduledoc false
    defstruct items: [], keep_array: false
  end

  alias __MODULE__.{Sequence, Undefined}
  alias Jexata.Runtime.CollectionLimit

  def undefined, do: %Undefined{}
  def undefined?(%Undefined{}), do: true
  def undefined?(_), do: false

  def sequence(values, keep_array \\ false) do
    items = sequence_items(values, [])

    case {items, keep_array} do
      {[], true} -> %Sequence{items: [], keep_array: true}
      {[one], true} -> %Sequence{items: [one], keep_array: true}
      {items, true} -> %Sequence{items: CollectionLimit.check(items), keep_array: true}
      {[], false} -> undefined()
      {[one], false} -> one
      {many, false} -> %Sequence{items: CollectionLimit.check(many)}
    end
  end

  # Call only when each item has already passed through sequence normalization.
  def sequence_from_items(items) do
    case items do
      [] -> undefined()
      [one] -> one
      many -> %Sequence{items: CollectionLimit.check(many)}
    end
  end

  defp sequence_items([], acc), do: Enum.reverse(acc)
  defp sequence_items([%Undefined{} | rest], acc), do: sequence_items(rest, acc)

  defp sequence_items([%Sequence{items: nested} | rest], acc),
    do: sequence_items(rest, Enum.reverse(nested, acc))

  defp sequence_items([item | rest], acc), do: sequence_items(rest, [item | acc])

  def items(%Undefined{}), do: []
  def items(%Sequence{items: items}), do: items
  def items(list) when is_list(list), do: list
  def items(value), do: [value]

  def public(%Jexata.Runtime.Closure{}), do: :function
  def public(%Jexata.Runtime.Builtin{}), do: :function
  def public(%Jexata.Runtime.Partial{}), do: :function
  def public(%Jexata.Runtime.Transform{}), do: :function
  def public(%Jexata.Runtime.Composition{}), do: :function
  def public(%Undefined{}), do: :undefined
  def public(%Sequence{items: items}), do: public(items)
  def public(list) when is_list(list), do: elem(public_list(list), 0)

  def public(map) when is_map(map) do
    Enum.reduce(map, map, fn {key, value}, result ->
      converted = public(value)
      if converted === value, do: result, else: Map.put(result, key, converted)
    end)
  end

  def public(value), do: value

  def public_root(%Sequence{items: [], keep_array: false}), do: :undefined
  def public_root(%Sequence{items: [item], keep_array: false}), do: public(item)
  def public_root(value), do: public(value)

  defp public_list([]), do: {[], false}

  defp public_list([head | tail] = original) do
    converted = public(head)
    {converted_tail, tail_changed?} = public_list(tail)

    if converted === head and not tail_changed?,
      do: {original, false},
      else: {[converted | converted_tail], true}
  end
end
