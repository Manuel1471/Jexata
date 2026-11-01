defmodule Jexata.Optimizer do
  @moduledoc false

  # Fold scalar array constructors once per compiled expression. Nested array
  # constructors stay as nodes because their explicit array shape matters.
  def optimize(ast), do: optimize(ast, true)

  defp optimize({:array, entries}, fold?) do
    entries =
      Enum.map(entries, fn
        {:array, _} = nested -> optimize(nested, false)
        entry -> optimize(entry, true)
      end)

    if fold? and Enum.all?(entries, &scalar_literal?/1),
      do: {:literal, Enum.map(entries, &elem(&1, 1))},
      else: {:array, entries}
  end

  defp optimize(ast, _fold?) when is_tuple(ast),
    do: ast |> Tuple.to_list() |> Enum.map(&optimize(&1, true)) |> List.to_tuple()

  defp optimize(ast, _fold?) when is_list(ast), do: Enum.map(ast, &optimize(&1, true))
  defp optimize(ast, _fold?), do: ast

  defp scalar_literal?({:literal, value}),
    do: is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value)

  defp scalar_literal?(_), do: false
end
