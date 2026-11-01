defmodule Jexata.Runtime.Signature do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value

  def bind(nil, parameters, values, _context) do
    missing = length(parameters) - length(values)

    cond do
      missing < 0 -> {:error, Error.new("T1006", "Invalid function arity")}
      missing == 0 -> {:ok, values}
      true -> {:ok, values ++ List.duplicate(Value.undefined(), missing)}
    end
  end

  def bind({:prepared, descriptors}, parameters, values, context) do
    arity = length(parameters)

    values =
      if length(values) < arity do
        case Enum.find_index(descriptors, &(&1.modifier == ?-)) do
          nil -> values
          index -> List.insert_at(values, index, context)
        end
      else
        values
      end

    supplied = values
    values = Enum.take(values, arity)

    cond do
      length(values) < required_count(descriptors) ->
        {:error, Error.new("T1006", "Invalid function arity")}

      Enum.any?(Enum.drop(supplied, arity), fn value ->
        not Enum.any?(descriptors, &(&1.modifier == ?+ and matches?(&1.type, value)))
      end) ->
        {:error, Error.new("T0410", "Argument does not match function signature")}

      true ->
        bound =
          Enum.with_index(descriptors)
          |> Enum.map(fn {descriptor, index} ->
            {descriptor, Enum.at(values, index, Value.undefined())}
          end)

        validate(bound, [])
    end
  end

  def bind(:invalid, _parameters, _values, _context),
    do: {:error, Error.new("S0401", "Invalid function signature")}

  def bind(signature, parameters, values, context),
    do: bind(prepare(signature, length(parameters)), parameters, values, context)

  def prepare(nil, _arity), do: nil

  def prepare(signature, arity) when is_binary(signature) do
    with {:ok, descriptors} <- parse(signature),
         descriptors <- expand_repeating(descriptors, arity),
         true <- length(descriptors) == arity do
      {:prepared, descriptors}
    else
      _ -> :invalid
    end
  end

  def parse(signature) do
    params = top_level_parameters(signature)
    parse_descriptors(String.to_charlist(params), [])
  end

  defp top_level_parameters(signature),
    do: top_level_parameters(String.to_charlist(signature), 0, [])

  defp top_level_parameters([], _depth, acc), do: acc |> Enum.reverse() |> List.to_string()
  defp top_level_parameters([?: | _], 0, acc), do: acc |> Enum.reverse() |> List.to_string()

  defp top_level_parameters([?< | rest], depth, acc),
    do: top_level_parameters(rest, depth + 1, [?< | acc])

  defp top_level_parameters([?> | rest], depth, acc),
    do: top_level_parameters(rest, depth - 1, [?> | acc])

  defp top_level_parameters([character | rest], depth, acc),
    do: top_level_parameters(rest, depth, [character | acc])

  defp parse_descriptors([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_descriptors(characters, acc) do
    with {:ok, type, tail} <- parse_type(characters) do
      {modifier, tail} =
        case tail do
          [mark | rest] when mark in [?-, ??, ?+, ?*] -> {mark, rest}
          _ -> {nil, tail}
        end

      parse_descriptors(tail, [%{type: type, modifier: modifier} | acc])
    end
  end

  defp parse_type([type | rest]) when type in [?n, ?s, ?b, ?o, ?f, ?x],
    do: {:ok, type, if(type == ?f, do: consume_nested(rest), else: rest)}

  defp parse_type([?a, ?< | rest]) do
    {nested, tail} = take_nested(rest, [], 1)

    case parse_type(nested) do
      {:ok, inner, []} -> {:ok, {:array, inner}, tail}
      _ -> {:error, :invalid}
    end
  end

  defp parse_type([?a | rest]), do: {:ok, ?a, rest}

  defp parse_type([?( | rest]) do
    case Enum.split_while(rest, &(&1 != ?))) do
      {types, [?) | tail]} ->
        if ?< in types, do: {:error, :invalid_union}, else: {:ok, {:union, types}, tail}

      _ ->
        {:error, :invalid}
    end
  end

  defp parse_type(_), do: {:error, :invalid}

  defp consume_nested([?< | rest]), do: skip_nested(rest, 1)
  defp consume_nested(rest), do: rest
  defp skip_nested([], _), do: []
  defp skip_nested([?> | rest], 1), do: rest
  defp skip_nested([?< | rest], depth), do: skip_nested(rest, depth + 1)
  defp skip_nested([?> | rest], depth), do: skip_nested(rest, depth - 1)
  defp skip_nested([_ | rest], depth), do: skip_nested(rest, depth)

  defp take_nested([?> | rest], acc, 1), do: {Enum.reverse(acc), rest}
  defp take_nested([?< | rest], acc, depth), do: take_nested(rest, [?< | acc], depth + 1)
  defp take_nested([?> | rest], acc, depth), do: take_nested(rest, [?> | acc], depth - 1)
  defp take_nested([head | rest], acc, depth), do: take_nested(rest, [head | acc], depth)
  defp take_nested([], acc, _), do: {Enum.reverse(acc), []}

  defp expand_repeating(descriptors, count) do
    missing = count - length(descriptors)

    if missing > 0 do
      case Enum.find_index(descriptors, &(&1.modifier == ?+)) do
        nil ->
          descriptors

        index ->
          List.insert_at(descriptors, index, List.duplicate(Enum.at(descriptors, index), missing))
          |> List.flatten()
      end
    else
      descriptors
    end
  end

  defp required_count(descriptors),
    do: Enum.count(descriptors, &(&1.modifier not in [??, ?-, ?*]))

  defp validate([], acc), do: {:ok, Enum.reverse(acc)}

  defp validate([{descriptor, value} | rest], acc) do
    cond do
      Value.undefined?(value) and descriptor.modifier in [??, ?-, ?*] ->
        validate(rest, [value | acc])

      Value.undefined?(value) ->
        {:undefined}

      matches?(descriptor.type, value) or descriptor.modifier == ?? ->
        array? = descriptor.type == ?a or match?({:array, _}, descriptor.type)
        validate(rest, [if(array?, do: as_array(value), else: value) | acc])

      true ->
        code = if match?({:array, _}, descriptor.type), do: "T0412", else: "T0410"
        {:error, Error.new(code, "Argument does not match function signature")}
    end
  end

  defp matches?(?x, _), do: true
  defp matches?(?n, value), do: is_number(value)
  defp matches?(?s, value), do: is_binary(value)
  defp matches?(?b, value), do: is_boolean(value)
  defp matches?(?o, value), do: is_map(value) and not is_struct(value)
  defp matches?(?a, _), do: true

  defp matches?({:array, inner}, value),
    do: value |> as_array() |> Enum.all?(&matches?(inner, &1))

  defp matches?(?f, value),
    do: is_struct(value, Jexata.Runtime.Closure) or is_struct(value, Jexata.Runtime.Builtin)

  defp matches?({:union, types}, value), do: Enum.any?(types, &matches?(&1, value))

  defp as_array(value) when is_list(value), do: value
  defp as_array(value), do: [value]
end
