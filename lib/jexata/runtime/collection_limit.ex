defmodule Jexata.Runtime.CollectionLimit do
  @moduledoc false
  alias Jexata.AST
  alias Jexata.Error
  alias Jexata.Runtime.Value.Sequence

  @key {__MODULE__, :max_items}

  def install(nil), do: :ok
  def install(limit), do: Process.put(@key, limit)

  def check([] = value), do: value
  def check([_] = value), do: value

  def check(value) do
    if limit = Process.get(@key), do: check_size(value, limit)
    value
  end

  def check_result({:ok, value} = result) do
    if limit = Process.get(@key), do: check_tree(value, limit)
    result
  end

  def check_result(result), do: result

  def check_input(value) do
    if limit = Process.get(@key), do: check_tree(value, limit)
    :ok
  end

  def check_ast(ast) do
    if limit = Process.get(@key), do: check_ast_node(ast, limit)
    :ok
  end

  defp check_ast_node({:constant_array, value}, limit), do: check_tree(value, limit)
  defp check_ast_node({:literal, value}, limit), do: check_tree(value, limit)
  defp check_ast_node(ast, limit), do: Enum.each(AST.children(ast), &check_ast_node(&1, limit))

  defp check_tree(%Sequence{items: items}, limit), do: check_tree(items, limit)

  defp check_tree(list, limit) when is_list(list) do
    check_size(list, limit)
    Enum.each(list, &check_tree(&1, limit))
  end

  defp check_tree(map, limit) when is_map(map) and not is_struct(map) do
    check_size(map, limit)
    Enum.each(map, fn {_key, value} -> check_tree(value, limit) end)
  end

  defp check_tree(_, _), do: :ok

  defp check_size(%Sequence{items: items}, limit), do: check_size(items, limit)

  defp check_size(list, limit) when is_list(list) do
    if length(list) > limit, do: exceeded()
  end

  defp check_size(map, limit) when is_map(map) and not is_struct(map) do
    if map_size(map) > limit, do: exceeded()
  end

  defp check_size(_, _), do: :ok

  defp exceeded, do: raise(Error.new("J1011", "Collection exceeds item limit"))
end
