defmodule Jexata.Evaluator.Constructors do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value

  def array(expressions, data, context, evaluate),
    do: array_items(expressions, data, context, evaluate, [])

  def object(pairs, data, context, evaluate) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {key_ast, value_ast}, {:ok, acc} ->
      with {:ok, key} <- evaluate.(key_ast, data, context),
           {:ok, value} <- evaluate.(value_ast, data, context),
           true <- is_binary(key) do
        {:cont, {:ok, if(Value.undefined?(value), do: acc, else: Map.put(acc, key, value))}}
      else
        false -> {:halt, {:error, Error.new("T1003", "Object key must be a string")}}
        error -> {:halt, error}
      end
    end)
  end

  def ordered_value(ast, data, context, evaluate),
    do: ordered(ast, data, context, evaluate)

  defp ordered({:object, pairs}, data, context, evaluate) do
    Enum.reduce_while(pairs, {:ok, %{}, []}, fn {key_ast, value_ast}, {:ok, values, keys} ->
      with {:ok, key} <- evaluate.(key_ast, data, context),
           true <- is_binary(key),
           {:ok, value} <- ordered(value_ast, data, context, evaluate) do
        if Value.undefined?(value) do
          {:cont, {:ok, values, keys}}
        else
          keys = if Map.has_key?(values, key), do: keys, else: [key | keys]
          {:cont, {:ok, Map.put(values, key, value), keys}}
        end
      else
        false -> {:halt, {:error, Error.new("T1003", "Object key must be a string")}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values, keys} ->
        {:ok, {:ordered_object, Enum.map(Enum.reverse(keys), &{&1, values[&1]})}}

      error ->
        error
    end
  end

  defp ordered({:array, expressions}, data, context, evaluate) do
    Enum.reduce_while(expressions, {:ok, []}, fn expression, {:ok, values} ->
      case ordered(expression, data, context, evaluate) do
        {:ok, value} -> {:cont, {:ok, [value | values]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} ->
        {:ok,
         expressions
         |> Enum.zip(Enum.reverse(values))
         |> Enum.flat_map(fn
           {{:array, _}, value} -> [value]
           {_, %Value.Sequence{items: items}} -> items
           {_, value} when is_list(value) -> value
           {_, value} -> if Value.undefined?(value), do: [], else: [value]
         end)}

      error ->
        error
    end
  end

  defp ordered(ast, data, context, evaluate), do: evaluate.(ast, data, context)

  defp array_items([], _data, _context, _evaluate, acc), do: {:ok, Enum.reverse(acc)}

  defp array_items([expression | rest], data, context, evaluate, acc) do
    case evaluate.(expression, data, context) do
      {:ok, value} ->
        array_items(rest, data, context, evaluate, append_array_item(expression, value, acc))

      error ->
        error
    end
  end

  defp append_array_item({:array, _}, value, acc), do: [value | acc]
  defp append_array_item({:constant_array, _}, value, acc), do: [value | acc]
  defp append_array_item(_, %Value.Sequence{items: items}, acc), do: Enum.reverse(items, acc)
  defp append_array_item(_, value, acc) when is_list(value), do: Enum.reverse(value, acc)
  defp append_array_item(_, %Value.Undefined{}, acc), do: acc
  defp append_array_item(_, value, acc), do: [value | acc]
end
