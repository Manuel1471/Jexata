defmodule Jexata.Evaluator.Transforms do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.{Transform, Value}

  def apply(%Transform{} = transform, input, eval_fun, predicate_fun) do
    context = %{
      root: input,
      environment: transform.environment,
      eval_ast: eval_fun,
      predicate: predicate_fun
    }

    references =
      transform.pattern
      |> selected_paths([{[], input}], context)
      |> Enum.flat_map(&expand_reference/1)
      |> Enum.filter(fn {_path, value} -> is_map(value) and not is_struct(value) end)
      |> Enum.uniq_by(&elem(&1, 0))

    if disjoint_references?(references) do
      apply_disjoint_transform(transform, input, context, references)
    else
      apply_sequential_transform(transform, input, context, references)
    end
  end

  defp disjoint_references?([]), do: true

  defp disjoint_references?([{path, _} | rest]),
    do: Enum.all?(rest, fn {candidate, _} -> length(candidate) == length(path) end)

  defp apply_disjoint_transform(_transform, input, _context, []), do: {:ok, input}

  defp apply_disjoint_transform(transform, input, context, references) do
    Enum.reduce_while(references, {:ok, %{}}, fn {path, selected}, {:ok, trie} ->
      case transformed_value(transform, selected, context) do
        {:ok, changed} -> {:cont, {:ok, insert_update(trie, path, changed)}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, trie} -> {:ok, apply_updates(input, trie)}
      error -> error
    end
  end

  defp apply_sequential_transform(transform, input, context, references) do
    Enum.reduce_while(references, {:ok, input}, fn {path, _}, {:ok, document} ->
      selected = get_path(document, path)

      case transformed_value(transform, selected, context) do
        {:ok, changed} -> {:cont, {:ok, put_path(document, path, changed)}}
        error -> {:halt, error}
      end
    end)
  end

  defp transformed_value(transform, selected, context) do
    with {:ok, update} <- context.eval_ast.(transform.update, selected, context),
         {:ok, update} <- transform_update(update),
         {:ok, delete} <- transform_delete(transform.delete, selected, context),
         do: {:ok, selected |> Map.merge(update) |> Map.drop(delete)}
  end

  defp insert_update(_trie, [], changed), do: {:replace, changed}

  defp insert_update(trie, [key | rest], changed) do
    child = Map.get(trie, key, %{})
    Map.put(trie, key, insert_update(child, rest, changed))
  end

  defp apply_updates(_input, {:replace, changed}), do: changed

  defp apply_updates(input, trie) when is_map(input),
    do:
      Enum.reduce(trie, input, fn {key, child}, acc ->
        Map.update!(acc, key, &apply_updates(&1, child))
      end)

  defp apply_updates(input, trie) when is_list(input),
    do: apply_updates_list(input, trie, 0, [])

  defp apply_updates_list([], _trie, _index, acc), do: Enum.reverse(acc)

  defp apply_updates_list([value | rest], trie, index, acc) do
    updated =
      case Map.fetch(trie, index) do
        {:ok, child} -> apply_updates(value, child)
        :error -> value
      end

    apply_updates_list(rest, trie, index + 1, [updated | acc])
  end

  defp transform_update(update) when is_map(update) and not is_struct(update), do: {:ok, update}
  defp transform_update(update) when is_struct(update, Value.Undefined), do: {:ok, %{}}
  defp transform_update(_), do: {:error, Error.new("T2011", "Transform update must be an object")}

  defp transform_delete(nil, _selected, _context), do: {:ok, []}

  defp transform_delete(ast, selected, context) do
    case context.eval_ast.(ast, selected, context) do
      {:ok, value} when is_binary(value) ->
        {:ok, [value]}

      {:ok, values} when is_list(values) ->
        if Enum.all?(values, &is_binary/1),
          do: {:ok, values},
          else: {:error, Error.new("T2012", "Transform delete must contain strings")}

      {:ok, value} when is_struct(value, Value.Undefined) ->
        {:ok, []}

      {:ok, _} ->
        {:error, Error.new("T2012", "Transform delete must contain strings")}

      error ->
        error
    end
  end

  defp selected_paths({:variable, "$"}, refs, _context), do: refs

  defp selected_paths({:block, [ast]}, refs, context),
    do: selected_paths(ast, refs, context)

  defp selected_paths({:path, left, right}, refs, context),
    do: selected_paths(right, selected_paths(left, refs, context), context)

  defp selected_paths({:compiled_path, left, right, _}, refs, context),
    do: selected_paths(right, selected_paths(left, refs, context), context)

  defp selected_paths({:name, name}, refs, _context) do
    refs
    |> Enum.flat_map(&expand_reference/1)
    |> Enum.flat_map(fn
      {path, map} when is_map(map) and not is_struct(map) ->
        if Map.has_key?(map, name), do: [{path ++ [name], Map.get(map, name)}], else: []

      _ ->
        []
    end)
  end

  defp selected_paths({:filter, left, predicate}, refs, context) do
    candidates = left |> selected_paths(refs, context) |> Enum.flat_map(&expand_reference/1)
    count = length(candidates)

    candidates
    |> Enum.with_index()
    |> Enum.filter(fn {{_path, value}, index} ->
      case context.eval_ast.(predicate, value, context) do
        {:ok, result} -> context.predicate.(result, index, count)
        _ -> false
      end
    end)
    |> Enum.map(&elem(&1, 0))
  end

  defp selected_paths({:compiled_filter, left, predicate, _boolean?}, refs, context),
    do: selected_paths({:filter, left, predicate}, refs, context)

  defp selected_paths(:wildcard, refs, _context) do
    refs
    |> Enum.flat_map(&expand_reference/1)
    |> Enum.flat_map(fn
      {path, map} when is_map(map) and not is_struct(map) ->
        Enum.map(map, fn {key, value} -> {path ++ [key], value} end)

      _ ->
        []
    end)
  end

  defp selected_paths(:descendants, refs, _context),
    do: refs ++ Enum.flat_map(refs, &descendant_references/1)

  defp selected_paths(_, _refs, _context), do: []

  defp descendant_references({path, map}) when is_map(map) and not is_struct(map) do
    Enum.flat_map(map, fn {key, value} ->
      reference = {path ++ [key], value}
      [reference | descendant_references(reference)]
    end)
  end

  defp descendant_references({path, values}) when is_list(values) do
    values
    |> Enum.with_index()
    |> Enum.flat_map(fn {value, index} ->
      reference = {path ++ [index], value}
      [reference | descendant_references(reference)]
    end)
  end

  defp descendant_references(_), do: []

  defp expand_reference({path, values}) when is_list(values),
    do: Enum.with_index(values) |> Enum.map(fn {value, index} -> {path ++ [index], value} end)

  defp expand_reference(reference), do: [reference]

  defp get_path(value, []), do: value
  defp get_path(map, [key | tail]) when is_map(map), do: get_path(Map.fetch!(map, key), tail)
  defp get_path(list, [index | tail]) when is_list(list), do: get_path(Enum.at(list, index), tail)

  defp put_path(_old, [], value), do: value

  defp put_path(map, [key | tail], value) when is_map(map),
    do: Map.update!(map, key, &put_path(&1, tail, value))

  defp put_path(list, [index | tail], value) when is_list(list),
    do: List.update_at(list, index, &put_path(&1, tail, value))
end
