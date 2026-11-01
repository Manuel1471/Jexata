defmodule Jexata.Optimizer do
  @moduledoc false
  alias Jexata.{Evaluator, Semantics}
  alias Jexata.Runtime.Signature

  # Scalar array constructors are immutable across evaluations. Nested array
  # constructors retain their node so the parent preserves explicit nesting.
  def optimize(ast), do: ast |> optimize_node(true) |> elem(0)

  defp optimize_node({:array, entries} = original, fold?) do
    {entries, changed?} = optimize_array_entries(entries)

    cond do
      fold? and match?([{:binary, "..", {:literal, _}, {:literal, _}}], entries) ->
        case fold_small_range(hd(entries)) do
          {:ok, values} -> {{:literal, values}, true}
          :no -> if(changed?, do: {{:array, entries}, true}, else: {original, false})
        end

      fold? and Enum.all?(entries, &scalar_literal?/1) ->
        {{:literal, Enum.map(entries, &elem(&1, 1))}, true}

      changed? ->
        {{:array, entries}, true}

      true ->
        {original, false}
    end
  end

  defp optimize_node({:path, left, right} = original, _fold?) do
    {left, left_changed?} = optimize_node(left, true)
    {right, right_changed?} = optimize_node(right, true)

    if (match?({:variable, "$"}, left) and match?({:object, _}, right)) or
         match?({:compiled_filter, _, _, _}, left) or match?({:filter, _, _}, left) do
      if left_changed? or right_changed?,
        do: {{:path, left, right}, true},
        else: {original, false}
    else
      left = path_name(left)
      right = right |> path_name() |> contextual_path_call()
      {{:compiled_path, left, right, indexed_path?(left)}, true}
    end
  end

  defp optimize_node({:filter, left, predicate}, _fold?) do
    {left, _} = optimize_node(left, true)
    {predicate, _} = optimize_node(predicate, true)
    {{:compiled_filter, left, predicate, boolean_predicate?(predicate)}, true}
  end

  defp optimize_node({:binary, op, left, right} = original, _fold?)
       when op in ["+", "-", "*", "/", "%", "&"] do
    {left, left_changed?} = optimize_node(left, true)
    {right, right_changed?} = optimize_node(right, true)
    node = if left_changed? or right_changed?, do: {:binary, op, left, right}, else: original

    if scalar_literal?(left) and scalar_literal?(right) do
      case Evaluator.evaluate(node, %{}) do
        {:ok, value} ->
          if scalar_value?(value),
            do: {{:literal, value}, true},
            else: {node, left_changed? or right_changed?}

        _ ->
          {node, left_changed? or right_changed?}
      end
    else
      {node, left_changed? or right_changed?}
    end
  end

  defp optimize_node({:conditional, test, yes, no} = original, _fold?) do
    {test, test_changed?} = optimize_node(test, true)
    {yes, yes_changed?} = optimize_node(yes, true)
    {no, no_changed?} = optimize_node(no, true)

    if scalar_literal?(test) do
      {if(Semantics.boolean(elem(test, 1)), do: yes, else: no), true}
    else
      changed? = test_changed? or yes_changed? or no_changed?
      if changed?, do: {{:conditional, test, yes, no}, true}, else: {original, false}
    end
  end

  defp optimize_node({:lambda, parameters, signature, body}, _fold?) do
    {body, _changed?} = optimize_node(body, true)
    references = body |> referenced_variables(MapSet.new()) |> MapSet.to_list()

    {{:compiled_lambda, parameters, Signature.prepare(signature, length(parameters)), body,
      references}, true}
  end

  defp optimize_node(ast, _fold?) when is_tuple(ast),
    do: optimize_tuple(ast, 0, tuple_size(ast), ast, false)

  defp optimize_node(ast, _fold?) when is_list(ast), do: optimize_list(ast)
  defp optimize_node(ast, _fold?), do: {ast, false}

  defp optimize_tuple(_original, index, index, current, changed?), do: {current, changed?}

  defp optimize_tuple(original, index, size, current, changed?) do
    {child, child_changed?} = optimize_node(elem(original, index), true)
    next = if child_changed?, do: put_elem(current, index, child), else: current
    optimize_tuple(original, index + 1, size, next, changed? or child_changed?)
  end

  defp optimize_list([]), do: {[], false}

  defp optimize_list([head | tail] = original) do
    {head, head_changed?} = optimize_node(head, true)
    {tail, tail_changed?} = optimize_list(tail)

    if head_changed? or tail_changed?,
      do: {[head | tail], true},
      else: {original, false}
  end

  defp optimize_array_entries([]), do: {[], false}

  defp optimize_array_entries([head | tail] = original) do
    fold? = not match?({:array, _}, head)
    {head, head_changed?} = optimize_node(head, fold?)
    {tail, tail_changed?} = optimize_array_entries(tail)

    if head_changed? or tail_changed?,
      do: {[head | tail], true},
      else: {original, false}
  end

  defp scalar_literal?({:literal, value}),
    do: scalar_value?(value)

  defp scalar_literal?(_), do: false

  defp scalar_value?(value),
    do: is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value)

  defp fold_small_range({:binary, "..", {:literal, start}, {:literal, finish}})
       when is_integer(start) and is_integer(finish) and finish - start < 256 do
    {:ok, if(start > finish, do: [], else: Enum.to_list(start..finish))}
  end

  defp fold_small_range(_), do: :no

  defp referenced_variables({:variable, name}, acc), do: MapSet.put(acc, name)

  defp referenced_variables({:compiled_lambda, _, _, _, references}, acc),
    do: Enum.reduce(references, acc, &MapSet.put(&2, &1))

  defp referenced_variables(ast, acc) when is_tuple(ast),
    do: ast |> Tuple.to_list() |> Enum.reduce(acc, &referenced_variables/2)

  defp referenced_variables(ast, acc) when is_list(ast),
    do: Enum.reduce(ast, acc, &referenced_variables/2)

  defp referenced_variables(_, acc), do: acc

  defp path_name({:literal, name}) when is_binary(name), do: {:name, name}
  defp path_name(other), do: other

  defp indexed_path?({:index_bind, _, _}), do: true
  defp indexed_path?({:compiled_path, _, _, indexed?}), do: indexed?
  defp indexed_path?({:path, left, _}), do: indexed_path?(left)
  defp indexed_path?({:sort, left, _}), do: indexed_path?(left)
  defp indexed_path?({:filter, left, _}), do: indexed_path?(left)
  defp indexed_path?({:compiled_filter, left, _, _}), do: indexed_path?(left)
  defp indexed_path?(_), do: false

  defp boolean_predicate?({:literal, value}) when is_boolean(value), do: true

  defp boolean_predicate?({:binary, op, _, _})
       when op in ["=", "!=", "<", "<=", ">", ">=", "in", "and", "or"],
       do: true

  defp boolean_predicate?(_), do: false

  defp contextual_path_call({:call, {:variable, name}, args} = call) do
    needs_context =
      (name in ["$substringBefore", "$substringAfter", "$contains", "$split", "$match", "$pad"] and
         length(args) == 1) or
        (name == "$substring" and length(args) == 1) or
        (name == "$replace" and length(args) == 2)

    if needs_context,
      do: {:call, {:variable, name}, [{:variable, "$"} | args]},
      else: call
  end

  defp contextual_path_call(other), do: other
end
