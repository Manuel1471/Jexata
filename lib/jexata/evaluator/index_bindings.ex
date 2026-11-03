defmodule Jexata.Evaluator.IndexBindings do
  @moduledoc false
  alias Jexata.Runtime.Value
  alias Jexata.Evaluator.Ancestry
  alias Jexata.Semantics

  def indexed_path?({:index_bind, _, _}), do: true
  def indexed_path?({:focus_bind, _, _}), do: true
  def indexed_path?({:keep_array, left}), do: indexed_path?(left)
  def indexed_path?({:compiled_path, _, _, indexed?}), do: indexed?
  def indexed_path?({:path, left, _}), do: indexed_path?(left)
  def indexed_path?({:sort, left, _}), do: indexed_path?(left)
  def indexed_path?({:filter, left, _}), do: indexed_path?(left)
  def indexed_path?({:compiled_filter, left, _, _}), do: indexed_path?(left)
  def indexed_path?(_), do: false

  def keep_array?({:keep_array, _}), do: true
  def keep_array?({:compiled_filter, left, _, _}), do: keep_array?(left)
  def keep_array?({:filter, left, _}), do: keep_array?(left)
  def keep_array?({:sort, left, _}), do: keep_array?(left)
  def keep_array?({:compiled_path, left, _, _}), do: keep_array?(left)
  def keep_array?(_), do: false

  def expand(mode, previous, step, name, index_name, data, context, evaluate_previous, evaluate) do
    parents =
      if previous == nil,
        do: {:ok, [{data, context.environment}]},
        else: evaluate_previous.(previous, data, context)

    with {:ok, parents} <- parents do
      Enum.reduce_while(parents, {:ok, []}, fn {parent, environment}, {:ok, acc} ->
        case evaluate.(step, parent, %{context | environment: environment}) do
          {:ok, value} ->
            frames =
              value
              |> Value.items()
              |> Enum.with_index()
              |> Enum.map(fn {item, index} ->
                frame_value = if mode == :focus, do: parent, else: item

                environment =
                  if mode == :focus and Map.get(context, :parent_mode, false),
                    do: Ancestry.focus(environment, parent),
                    else: environment

                env =
                  if mode == :focus,
                    do: Map.put(environment, name, item),
                    else: Map.put(environment, name, index)

                env = if index_name, do: Map.put(env, index_name, index), else: env
                {frame_value, env}
              end)

            {:cont, {:ok, [frames | acc]}}

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, lists} -> {:ok, lists |> Enum.reverse() |> List.flatten()}
        error -> error
      end
    end
  end

  def bind_frames(frames, name), do: frames |> bind_frames(name, 0, []) |> Enum.reverse()

  defp bind_frames([], _name, _index, acc), do: acc

  defp bind_frames([{value, environment} | rest], name, index, acc) do
    {next_index, next_acc} = bind_items(Value.items(value), environment, name, index, acc)
    bind_frames(rest, name, next_index, next_acc)
  end

  defp bind_items([], _environment, _name, index, acc), do: {index, acc}

  defp bind_items([item | rest], environment, name, index, acc) do
    bind_items(rest, environment, name, index + 1, [
      {item, Map.put(environment, name, index)} | acc
    ])
  end

  def filter(left, predicate, boolean?, data, context, evaluate_indexed, evaluate) do
    with {:ok, frames} <- evaluate_indexed.(left, data, context) do
      count = if boolean?, do: 0, else: length(frames)

      frames
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {{item, environment} = frame, index}, {:ok, acc} ->
        case evaluate.(predicate, item, %{context | environment: environment}) do
          {:ok, result} ->
            next = if predicate_matches?(result, index, count), do: [frame | acc], else: acc
            {:cont, {:ok, next}}

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, selected} -> {:ok, Enum.reverse(selected)}
        error -> error
      end
    end
  end

  def path(
        left,
        {:name, name},
        data,
        %{parent_mode: false} = context,
        evaluate_indexed,
        _evaluate
      ) do
    with {:ok, frames} <- evaluate_indexed.(left, data, context) do
      {:ok, select_names(frames, name, [])}
    end
  end

  def path(left, right, data, context, evaluate_indexed, evaluate) do
    with {:ok, frames} <- evaluate_indexed.(left, data, context) do
      Enum.reduce_while(frames, {:ok, []}, fn {item, environment}, {:ok, acc} ->
        next_result =
          if Map.get(context, :parent_mode, false) do
            evaluate_indexed.(right, item, %{context | environment: environment})
          else
            case evaluate.(right, item, %{context | environment: environment}) do
              {:ok, value} -> {:ok, Enum.map(Value.items(value), &{&1, environment})}
              error -> error
            end
          end

        case next_result do
          {:ok, next} -> {:cont, {:ok, [next | acc]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, values} -> {:ok, values |> Enum.reverse() |> List.flatten()}
        error -> error
      end
    end
  end

  defp select_names([], _name, acc), do: Enum.reverse(acc)

  defp select_names([{item, environment} | rest], name, acc) do
    selected = Semantics.select(item, name)
    select_names(rest, name, append_selected(selected, environment, acc))
  end

  defp append_selected(%Value.Undefined{}, _environment, acc), do: acc

  defp append_selected(%Value.Sequence{items: items}, environment, acc),
    do: Enum.reduce(items, acc, fn item, acc -> [{item, environment} | acc] end)

  defp append_selected(items, environment, acc) when is_list(items),
    do: Enum.reduce(items, acc, fn item, acc -> [{item, environment} | acc] end)

  defp append_selected(item, environment, acc), do: [{item, environment} | acc]

  def predicate_matches?(value, index, count) when is_number(value) do
    target = floor(value)
    index == if(target < 0, do: count + target, else: target)
  end

  def predicate_matches?(values, index, count) when is_list(values) and values != [] do
    if Enum.all?(values, &is_number/1),
      do: Enum.any?(values, &predicate_matches?(&1, index, count)),
      else: Semantics.boolean(values)
  end

  def predicate_matches?(value, _index, _count), do: Semantics.boolean(value)
end
