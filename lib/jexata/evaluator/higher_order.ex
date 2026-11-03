defmodule Jexata.Evaluator.HigherOrder do
  @moduledoc false
  alias Jexata.{Error, Functions, Semantics}
  alias Jexata.Runtime.{Builtin, Closure, Composition, Partial, Value}

  def call(name, args, data, invoke_fun),
    do: higher_order(name, args, %{data: data, invoke: invoke_fun})

  def invoke_callback(callback, args, data, invoke_fun),
    do: invoke_callback(callback, args, %{data: data, invoke: invoke_fun})

  defp invoke(function, args, context),
    do: context.invoke.(function, args, context.data)

  defp higher_order("$map", [input, callback], context) do
    items = Value.items(input)
    map_items(items, callback, context, items, 0, [])
  end

  defp higher_order("$filter", [input, callback], context) do
    items = Value.items(input)
    filter_items(items, callback, context, items, 0, [])
  end

  defp higher_order("$reduce", [input, callback], context),
    do: reduce_items(Value.items(input), callback, Value.undefined(), context)

  defp higher_order("$reduce", [input, callback, initial], context),
    do: reduce_items(Value.items(input), callback, initial, context)

  defp higher_order("$sort", [input], context), do: Functions.call("$sort", [input], context.data)

  defp higher_order("$sort", [input, callback], context) do
    if Value.undefined?(input) do
      {:ok, input}
    else
      input
      |> Value.items()
      |> merge_sort(callback, context)
      |> case do
        {:ok, sorted} -> {:ok, Value.sequence(sorted)}
        error -> error
      end
    end
  end

  defp higher_order("$single", [input], context),
    do: higher_order("$single", [input, nil], context)

  defp higher_order("$single", [input, callback], context) do
    if Value.undefined?(input) do
      {:ok, Value.undefined()}
    else
      input
      |> Value.items()
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, found} ->
        result =
          if is_nil(callback),
            do: {:ok, true},
            else: invoke_callback(callback, [item, index, Value.items(input)], context)

        case result do
          {:ok, value} ->
            {:cont, {:ok, if(Semantics.boolean(value), do: [item | found], else: found)}}

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, [item]} -> {:ok, item}
        {:ok, []} -> {:error, Error.new("D3139", "$single found no matching item")}
        {:ok, _} -> {:error, Error.new("D3138", "$single found multiple matching items")}
        error -> error
      end
    end
  end

  defp higher_order("$each", [object, callback], context)
       when is_map(object) and not is_struct(object) do
    object
    |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, results} ->
      case invoke_callback(callback, [value, key, object], context) do
        {:ok, result} -> {:cont, {:ok, [result | results]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Value.sequence(Enum.reverse(results))}
      error -> error
    end
  end

  defp higher_order("$sift", [object, callback], context)
       when is_map(object) and not is_struct(object) do
    Enum.reduce_while(object, {:ok, %{}}, fn {key, value}, {:ok, result} ->
      case invoke_callback(callback, [value, key, object], context) do
        {:ok, keep} ->
          {:cont,
           {:ok, if(Semantics.boolean(keep), do: Map.put(result, key, value), else: result)}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, result} when map_size(result) == 0 -> {:ok, Value.undefined()}
      other -> other
    end
  end

  defp higher_order("$sift", [objects, callback], context) when is_list(objects) do
    Enum.reduce_while(objects, {:ok, []}, fn object, {:ok, results} ->
      case higher_order("$sift", [object, callback], context) do
        {:ok, result} -> {:cont, {:ok, [result | results]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Value.sequence(Enum.reverse(results))}
      error -> error
    end
  end

  defp higher_order("$sift", [%Value.Sequence{items: objects}, callback], context),
    do: higher_order("$sift", [objects, callback], context)

  defp higher_order("$sift", [_other, _callback], _data), do: {:ok, Value.undefined()}

  defp higher_order(name, _, _), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}

  defp map_items([], _callback, _data, _items, _index, acc),
    do: {:ok, Value.sequence(Enum.reverse(acc))}

  defp map_items([item | rest], callback, context, items, index, acc) do
    case invoke_indexed_callback(callback, item, index, items, context) do
      {:ok, value} -> map_items(rest, callback, context, items, index + 1, [value | acc])
      error -> error
    end
  end

  defp filter_items([], _callback, _data, _items, _index, acc),
    do: {:ok, Value.sequence(Enum.reverse(acc))}

  defp filter_items([item | rest], callback, context, items, index, acc) do
    case invoke_indexed_callback(callback, item, index, items, context) do
      {:ok, value} ->
        next = if Semantics.boolean(value), do: [item | acc], else: acc
        filter_items(rest, callback, context, items, index + 1, next)

      error ->
        error
    end
  end

  defp invoke_indexed_callback(%Closure{arity: 0} = closure, _item, _index, _items, context),
    do: invoke(closure, [], context)

  defp invoke_indexed_callback(%Closure{arity: 1} = closure, item, _index, _items, context),
    do: invoke(closure, [item], context)

  defp invoke_indexed_callback(%Closure{arity: 2} = closure, item, index, _items, context),
    do: invoke(closure, [item, index], context)

  defp invoke_indexed_callback(%Closure{arity: 3} = closure, item, index, items, context),
    do: invoke(closure, [item, index, items], context)

  defp invoke_indexed_callback(callback, item, index, items, context),
    do: invoke_callback(callback, [item, index, items], context)

  defp reduce_items(items, callback, initial, context) do
    if is_struct(callback, Closure) and length(callback.parameters) < 2 do
      {:error, Error.new("D3050", "$reduce callback requires at least two parameters")}
    else
      do_reduce_items(items, callback, initial, context)
    end
  end

  defp do_reduce_items(items, callback, initial, context) do
    index_offset = if Value.undefined?(initial), do: 1, else: 0

    {first, rest} =
      if Value.undefined?(initial) do
        case items do
          [] -> {Value.undefined(), []}
          [head | tail] -> {head, tail}
        end
      else
        {initial, items}
      end

    reduce_items(rest, callback, first, index_offset, items, context)
  end

  defp reduce_items([], _callback, accumulator, _index, _items, _data),
    do: {:ok, accumulator}

  defp reduce_items([item | rest], callback, accumulator, index, items, context) do
    case invoke_reduce_callback(callback, accumulator, item, index, items, context) do
      {:ok, value} -> reduce_items(rest, callback, value, index + 1, items, context)
      error -> error
    end
  end

  defp invoke_reduce_callback(%Closure{arity: 0} = callback, _, _, _, _, context),
    do: invoke(callback, [], context)

  defp invoke_reduce_callback(%Closure{arity: 1} = callback, accumulator, _, _, _, context),
    do: invoke(callback, [accumulator], context)

  defp invoke_reduce_callback(%Closure{arity: 2} = callback, accumulator, item, _, _, context),
    do: invoke(callback, [accumulator, item], context)

  defp invoke_reduce_callback(
         %Closure{arity: 3} = callback,
         accumulator,
         item,
         index,
         _,
         context
       ),
       do: invoke(callback, [accumulator, item, index], context)

  defp invoke_reduce_callback(callback, accumulator, item, index, items, context),
    do: invoke_callback(callback, [accumulator, item, index, items], context)

  defp invoke_callback(%Closure{arity: 0} = closure, _args, context),
    do: invoke(closure, [], context)

  defp invoke_callback(%Closure{arity: 1} = closure, [a | _], context),
    do: invoke(closure, [a], context)

  defp invoke_callback(%Closure{arity: 2} = closure, [a, b | _], context),
    do: invoke(closure, [a, b], context)

  defp invoke_callback(%Closure{arity: 3} = closure, [a, b, c | _], context),
    do: invoke(closure, [a, b, c], context)

  defp invoke_callback(%Closure{arity: arity} = closure, args, context),
    do: invoke(closure, Enum.take(args, arity), context)

  defp invoke_callback(%Builtin{name: "$append"} = builtin, [left, right | _], context),
    do: invoke(builtin, [left, right], context)

  defp invoke_callback(%Builtin{} = builtin, [value | _], context),
    do: invoke(builtin, [value], context)

  defp invoke_callback(%Partial{} = partial, [value | _], context),
    do: invoke(partial, [value], context)

  defp invoke_callback(%Composition{} = composition, [value | _], context),
    do: invoke(composition, [value], context)

  defp invoke_callback(_, _, _),
    do: {:error, Error.new("T1006", "Comparator or callback is not a function")}

  defp merge_sort([], _callback, _data), do: {:ok, []}
  defp merge_sort([_] = items, _callback, _data), do: {:ok, items}

  defp merge_sort(items, callback, context) do
    {left, right} = Enum.split(items, div(length(items), 2))

    with {:ok, left} <- merge_sort(left, callback, context),
         {:ok, right} <- merge_sort(right, callback, context),
         do: merge_sorted(left, right, callback, context, [])
  end

  defp merge_sorted([], right, _callback, _data, acc),
    do: {:ok, Enum.reverse(acc, right)}

  defp merge_sorted(left, [], _callback, _data, acc),
    do: {:ok, Enum.reverse(acc, left)}

  defp merge_sorted([a | left] = first, [b | right] = second, callback, context, acc) do
    case invoke_callback(callback, [a, b], context) do
      {:ok, result} ->
        if Semantics.boolean(result),
          do: merge_sorted(first, right, callback, context, [b | acc]),
          else: merge_sorted(left, second, callback, context, [a | acc])

      error ->
        error
    end
  end
end
