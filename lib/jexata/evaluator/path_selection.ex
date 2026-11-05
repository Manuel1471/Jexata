defmodule Jexata.Evaluator.PathSelection do
  @moduledoc false
  alias Jexata.Semantics
  alias Jexata.Runtime.Value

  def descendants(value) when is_list(value), do: Enum.flat_map(value, &descendants/1)

  def descendants(value) when is_map(value) and not is_struct(value) do
    [value | Enum.flat_map(value, fn {_key, child} -> descendants(child) end)]
  end

  def descendants(value), do: [value]

  def evaluate(items, {:name, name}, _context, flatten_arrays?, keep_array?, _evaluate) do
    values = select_items(items, name, flatten_arrays?, [])
    {:ok, Value.sequence(Enum.reverse(values), keep_array?)}
  end

  def evaluate(items, {:variable, _} = ast, context, _flatten_arrays?, keep_array?, evaluate) do
    case evaluate_items(items, ast, context, [], true, evaluate) do
      {:ok, values} -> {:ok, Value.sequence(Enum.reverse(values), keep_array?)}
      error -> error
    end
  end

  def evaluate(items, ast, context, _flatten_arrays?, keep_array?, evaluate) do
    case evaluate_items(items, ast, context, [], false, evaluate) do
      {:ok, values} -> {:ok, Value.sequence(Enum.reverse(values), keep_array?)}
      error -> error
    end
  end

  defp select_items([], _name, _flatten?, values), do: values

  defp select_items([item | rest], name, flatten?, values) do
    selected = Semantics.select(item, name)
    next = if flatten?, do: Enum.reverse(Value.items(selected), values), else: [selected | values]
    select_items(rest, name, flatten?, next)
  end

  defp evaluate_items([], _ast, _context, values, _skip_empty?, _evaluate), do: {:ok, values}

  defp evaluate_items([item | rest], ast, context, values, skip_empty?, evaluate) do
    case evaluate.(ast, item, context) do
      {:ok, []} when skip_empty? ->
        evaluate_items(rest, ast, context, values, skip_empty?, evaluate)

      {:ok, value} ->
        evaluate_items(rest, ast, context, [value | values], skip_empty?, evaluate)

      error ->
        error
    end
  end
end
