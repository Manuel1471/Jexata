defmodule Jexata.AST do
  @moduledoc false
  @type t ::
          {:literal, term()}
          | {:constant_array, [term()]}
          | {:name, String.t()}
          | {:variable, String.t()}
          | {:binary, String.t(), t(), t()}
          | {:conditional, t(), t(), t()}
          | {:path, t(), t()}
          | {:compiled_path, t(), t(), boolean()}
          | {:filter, t(), t()}
          | {:compiled_filter, t(), t(), boolean()}
          | {:index_bind, t(), String.t()}
          | {:focus_bind, t(), String.t()}
          | {:keep_array, t()}
          | {:negate, t()}
          | {:lambda, [String.t()], String.t() | nil, t()}
          | {:compiled_lambda, [String.t()], term(), t(), [String.t()], boolean()}
          | {:call, t(), [t()]}
          | {:array, [t()]}
          | {:object, [{t(), t()}]}
          | {:group, t(), [{t(), t()}]}
          | {:sort, t(), [{:asc | :desc, t()}]}
          | {:block, [t()]}
          | {:transform, t(), t(), t() | nil}
          | :placeholder
          | :wildcard
          | :descendants
          | :parent
          | {:parent_mode, t()}

  # Keep AST traversal separate from tuple-valued literal data and node metadata.
  def children({:binary, _, left, right}), do: [left, right]
  def children({:parent_mode, ast}), do: [ast]
  def children({:conditional, test, yes, no}), do: [test, yes, no]
  def children({:transform, pattern, update, delete}), do: [pattern, update, delete]
  def children({:path, left, right}), do: [left, right]
  def children({:compiled_path, left, right, _}), do: [left, right]
  def children({:filter, left, predicate}), do: [left, predicate]
  def children({:compiled_filter, left, predicate, _}), do: [left, predicate]
  def children({:index_bind, left, _}), do: [left]
  def children({:focus_bind, left, _}), do: [left]
  def children({:keep_array, child}), do: [child]
  def children({:negate, child}), do: [child]
  def children({:lambda, _, _, body}), do: [body]
  def children({:compiled_lambda, _, _, body, _, _}), do: [body]
  def children({:call, target, args}), do: [target | args]
  def children({:array, entries}), do: entries
  def children({:object, pairs}), do: Enum.flat_map(pairs, fn {key, value} -> [key, value] end)
  def children({:group, left, pairs}), do: [left | children({:object, pairs})]
  def children({:sort, left, terms}), do: [left | Enum.map(terms, &elem(&1, 1))]
  def children({:block, nodes}), do: nodes
  def children({key, value}) when is_tuple(key), do: [key, value]
  def children(_), do: []

  # The callback returns {new_child, changed?}; unchanged nodes retain identity.
  def map_children({:binary, op, left, right} = node, fun),
    do: map_fixed(node, [left, right], fun, fn [a, b] -> {:binary, op, a, b} end)

  def map_children({:conditional, test, yes, no} = node, fun),
    do: map_fixed(node, [test, yes, no], fun, fn [a, b, c] -> {:conditional, a, b, c} end)

  def map_children({:transform, pattern, update, delete} = node, fun),
    do:
      map_fixed(node, [pattern, update, delete], fun, fn [a, b, c] ->
        {:transform, a, b, c}
      end)

  def map_children({:call, target, args} = node, fun),
    do:
      map_fixed(node, [target | args], fun, fn [new_target | new_args] ->
        {:call, new_target, new_args}
      end)

  def map_children({:group, left, pairs} = node, fun),
    do:
      map_fixed(node, [left | pairs], fun, fn [new_left | new_pairs] ->
        {:group, new_left, new_pairs}
      end)

  def map_children({:sort, left, terms} = node, fun),
    do:
      map_fixed(node, [left | terms], fun, fn [new_left | new_terms] ->
        {:sort, new_left, new_terms}
      end)

  def map_children({:block, nodes} = node, fun),
    do: map_fixed(node, nodes, fun, fn updated -> {:block, updated} end)

  def map_children({:index_bind, left, name} = node, fun),
    do: map_fixed(node, [left], fun, fn [updated] -> {:index_bind, updated, name} end)

  def map_children({:focus_bind, left, name} = node, fun),
    do: map_fixed(node, [left], fun, fn [updated] -> {:focus_bind, updated, name} end)

  def map_children({:keep_array, child} = node, fun),
    do: map_fixed(node, [child], fun, fn [updated] -> {:keep_array, updated} end)

  def map_children({:negate, child} = node, fun),
    do: map_fixed(node, [child], fun, fn [updated] -> {:negate, updated} end)

  def map_children({direction, expression} = term, fun) when direction in [:asc, :desc],
    do: map_fixed(term, [expression], fun, fn [updated] -> {direction, updated} end)

  def map_children({key, value} = pair, fun) when is_tuple(key),
    do:
      map_fixed(pair, [key, value], fun, fn [new_key, new_value] ->
        {new_key, new_value}
      end)

  def map_children(node, _fun), do: {node, false}

  defp map_fixed(original, children, fun, rebuild) do
    {updated, changed?} = map_list(children, fun)
    if changed?, do: {rebuild.(updated), true}, else: {original, false}
  end

  defp map_list([], _fun), do: {[], false}

  defp map_list([head | tail] = original, fun) do
    {updated_head, head_changed?} = fun.(head)
    {updated_tail, tail_changed?} = map_list(tail, fun)

    if head_changed? or tail_changed?,
      do: {[updated_head | updated_tail], true},
      else: {original, false}
  end
end
