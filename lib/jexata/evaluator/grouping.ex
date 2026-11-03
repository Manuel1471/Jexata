defmodule Jexata.Evaluator.Grouping do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value

  def run_plain([], _pairs, _context, _evaluate), do: {:ok, Value.undefined()}

  def run_plain(items, pairs, context, evaluate) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {key_ast, value_ast}, {:ok, result} ->
      groups =
        Enum.reduce_while(items, {:ok, %{}}, fn item, {:ok, groups} ->
          case evaluate.(key_ast, item, context) do
            {:ok, key} when is_binary(key) ->
              {:cont, {:ok, Map.update(groups, key, [item], &[item | &1])}}

            {:ok, _} ->
              {:halt, {:error, Error.new("T1003", "Group key must be a string")}}

            error ->
              {:halt, error}
          end
        end)

      case groups do
        {:ok, groups} -> merge_plain(groups, value_ast, result, context, evaluate)
        error -> {:halt, error}
      end
    end)
  end

  defp merge_plain(groups, value_ast, result, context, evaluate) do
    Enum.reduce_while(groups, {:ok, result}, fn {key, items}, {:ok, acc} ->
      case evaluate.(value_ast, Enum.reverse(items), context) do
        {:ok, value} ->
          cond do
            Value.undefined?(value) ->
              {:cont, {:ok, acc}}

            Map.has_key?(acc, key) ->
              {:halt, {:error, Error.new("D1009", "Duplicate object key")}}

            true ->
              {:cont, {:ok, Map.put(acc, key, value)}}
          end

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, value} -> {:cont, {:ok, value}}
      error -> {:halt, error}
    end
  end

  def run([], _pairs, _context, _evaluate), do: {:ok, Value.undefined()}

  def run(frames, pairs, context, evaluate) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {key_ast, value_ast}, {:ok, result} ->
      case group_frames(frames, key_ast, context, evaluate) do
        {:ok, groups} -> merge_groups(groups, value_ast, result, context, evaluate)
        error -> {:halt, error}
      end
    end)
  end

  defp group_frames(frames, key_ast, context, evaluate) do
    Enum.reduce_while(frames, {:ok, %{}}, fn {item, environment} = frame, {:ok, groups} ->
      case evaluate.(key_ast, item, %{context | environment: environment}) do
        {:ok, key} when is_binary(key) ->
          {:cont, {:ok, Map.update(groups, key, [frame], &[frame | &1])}}

        {:ok, _} ->
          {:halt, {:error, Error.new("T1003", "Group key must be a string")}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp merge_groups(groups, value_ast, result, context, evaluate) do
    Enum.reduce_while(groups, {:ok, result}, fn {key, reversed_frames}, {:ok, acc} ->
      frames = Enum.reverse(reversed_frames)
      items = Enum.map(frames, &elem(&1, 0))
      environment = merge_environments(frames, context.environment)

      case evaluate.(value_ast, items, %{context | environment: environment}) do
        {:ok, value} ->
          cond do
            Value.undefined?(value) ->
              {:cont, {:ok, acc}}

            Map.has_key?(acc, key) ->
              {:halt, {:error, Error.new("D1009", "Duplicate object key")}}

            true ->
              {:cont, {:ok, Map.put(acc, key, value)}}
          end

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, value} -> {:cont, {:ok, value}}
      error -> {:halt, error}
    end
  end

  defp merge_environments([{_, environment}], _default), do: environment

  defp merge_environments(frames, default) do
    keys =
      frames |> Enum.flat_map(fn {_, environment} -> Map.keys(environment) end) |> Enum.uniq()

    Enum.reduce(keys, default, fn key, acc ->
      values =
        Enum.map(frames, fn {_, environment} -> Map.get(environment, key, Value.undefined()) end)

      value = if Enum.uniq(values) == [hd(values)], do: hd(values), else: Value.sequence(values)
      Map.put(acc, key, value)
    end)
  end
end
