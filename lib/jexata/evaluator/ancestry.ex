defmodule Jexata.Evaluator.Ancestry do
  @moduledoc false
  alias Jexata.AST

  @key {__MODULE__, :parents}
  def key, do: @key
  def contains_parent?(:parent), do: true
  def contains_parent?(ast), do: Enum.any?(AST.children(ast), &contains_parent?/1)

  def parent(environment), do: environment |> Map.get(@key, []) |> List.first()

  def pop(environment) do
    case Map.get(environment, @key, []) do
      [parent | rest] -> {:ok, parent, Map.put(environment, @key, rest)}
      [] -> :error
    end
  end

  def push(environment, parent), do: Map.update(environment, @key, [parent], &[parent | &1])

  def focus(environment, parent) do
    case Map.get(environment, @key, []) do
      [^parent | _] -> environment
      _ -> push(environment, parent)
    end
  end
end
