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

  def undefined, do: %Undefined{}
  def undefined?(%Undefined{}), do: true
  def undefined?(_), do: false

  def sequence(values, keep_array \\ false) do
    items =
      Enum.flat_map(values, fn
        %Undefined{} -> []
        %Sequence{items: nested} -> nested
        item -> [item]
      end)

    case {items, keep_array} do
      {items, true} -> %Sequence{items: items, keep_array: true}
      {[], false} -> undefined()
      {[one], false} -> one
      {many, false} -> %Sequence{items: many}
    end
  end

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
  def public(%Sequence{items: items}), do: Enum.map(items, &public/1)
  def public(list) when is_list(list), do: Enum.map(list, &public/1)
  def public(map) when is_map(map), do: Map.new(map, fn {key, value} -> {key, public(value)} end)
  def public(value), do: value
end
