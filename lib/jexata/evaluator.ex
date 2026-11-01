defmodule Jexata.Evaluator do
  @moduledoc false
  alias Jexata.{Error, Functions, Semantics}
  alias Jexata.Runtime.{Closure, Value}

  @spec evaluate(Jexata.AST.t(), term()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(ast, data), do: eval(ast, data, %{root: data, environment: %{}})

  defp eval({:literal, value}, _, _), do: {:ok, value}
  defp eval({:name, name}, data, _), do: {:ok, Semantics.select(data, name)}
  defp eval({:variable, "$"}, data, _), do: {:ok, data}
  defp eval({:variable, "$$"}, _, %{root: root}), do: {:ok, root}

  defp eval({:variable, name}, _, %{environment: environment}) do
    case Map.fetch(environment, name) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, Error.new("T1005", "Undefined variable #{name}")}
    end
  end

  defp eval(:wildcard, data, _root) when is_map(data), do: {:ok, Value.sequence(Map.values(data))}
  defp eval(:wildcard, data, _root), do: {:ok, Value.sequence(Value.items(data))}
  defp eval(:descendants, data, _context), do: {:ok, Value.sequence(descendants(data))}

  defp eval({:path, left, right}, data, root) do
    with {:ok, source} <- eval(left, data, root) do
      source
      |> Value.items()
      |> eval_each(right, root)
    end
  end

  defp eval({:group, left, pairs}, data, context) do
    with {:ok, source} <- eval(left, data, context) do
      Enum.reduce_while(pairs, {:ok, %{}}, fn {key_ast, value_ast}, {:ok, result} ->
        case group_items(Value.items(source), key_ast, context) do
          {:ok, groups} ->
            Enum.reduce_while(groups, {:ok, result}, fn {key, items}, {:ok, acc} ->
              case eval(value_ast, Enum.reverse(items), context) do
                {:ok, value} ->
                  {:cont,
                   {:ok, if(Value.undefined?(value), do: acc, else: Map.put(acc, key, value))}}

                error ->
                  {:halt, error}
              end
            end)
            |> case do
              {:ok, value} -> {:cont, {:ok, value}}
              error -> {:halt, error}
            end

          error ->
            {:halt, error}
        end
      end)
    end
  end

  defp eval({:sort, left, terms}, data, context) do
    with {:ok, source} <- eval(left, data, context) do
      source
      |> Value.items()
      |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
        case eval_sort_keys(terms, item, context) do
          {:ok, keys} -> {:cont, {:ok, [{item, keys} | acc]}}
          error -> {:halt, error}
        end
      end)
      |> case do
        {:ok, decorated} ->
          sorted =
            decorated
            |> Enum.reverse()
            |> Enum.sort(fn {_, a}, {_, b} -> compare_sort_keys(a, b) end)

          {:ok, Value.sequence(Enum.map(sorted, &elem(&1, 0)))}

        error ->
          error
      end
    end
  end

  defp eval({:filter, left, predicate}, data, root) do
    with {:ok, source} <- eval(left, data, root) do
      source
      |> Value.items()
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
        case eval(predicate, item, root) do
          {:ok, result} ->
            keep = if is_number(result), do: result == index, else: Semantics.boolean(result)
            {:cont, {:ok, if(keep, do: [item | acc], else: acc)}}

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, values} -> {:ok, Value.sequence(Enum.reverse(values))}
        error -> error
      end
    end
  end

  defp eval({:array, expressions}, data, root) do
    with {:ok, values} <- eval_list(expressions, data, root) do
      {:ok,
       Enum.flat_map(values, fn
         %Value.Sequence{items: items} -> items
         value -> if Value.undefined?(value), do: [], else: [value]
       end)}
    end
  end

  defp eval({:object, pairs}, data, root) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn {key_ast, value_ast}, {:ok, acc} ->
      with {:ok, key} <- eval(key_ast, data, root),
           {:ok, value} <- eval(value_ast, data, root),
           true <- is_binary(key) do
        {:cont, {:ok, if(Value.undefined?(value), do: acc, else: Map.put(acc, key, value))}}
      else
        false -> {:halt, {:error, Error.new("T1003", "Object key must be a string")}}
        error -> {:halt, error}
      end
    end)
  end

  defp eval({:negate, ast}, data, root) do
    with {:ok, value} <- eval(ast, data, root) do
      if is_number(value), do: {:ok, -value}, else: type_error("Unary minus requires a number")
    end
  end

  defp eval({:binary, "?:", left, right}, data, context) do
    with {:ok, value} <- eval(left, data, context) do
      if Semantics.boolean(value), do: {:ok, value}, else: eval(right, data, context)
    end
  end

  defp eval({:binary, "??", left, right}, data, context) do
    with {:ok, value} <- eval(left, data, context) do
      if Value.undefined?(value), do: eval(right, data, context), else: {:ok, value}
    end
  end

  defp eval({:binary, "and", left, right}, data, root) do
    with {:ok, value} <- eval(left, data, root) do
      if Semantics.boolean(value), do: eval_boolean(right, data, root), else: {:ok, false}
    end
  end

  defp eval({:binary, "or", left, right}, data, root) do
    with {:ok, value} <- eval(left, data, root) do
      if Semantics.boolean(value), do: {:ok, true}, else: eval_boolean(right, data, root)
    end
  end

  defp eval({:binary, ":=", {:variable, name}, right}, data, context)
       when name not in ["$", "$$"], do: eval(right, data, context)

  defp eval({:binary, ":=", _, _}, _, _),
    do: {:error, Error.new("S0212", "Binding target must be a variable")}

  defp eval({:lambda, parameters, body}, _, context) do
    {:ok,
     %Closure{
       parameters: parameters,
       body: body,
       environment: context.environment,
       root: context.root
     }}
  end

  defp eval({:binary, op, left, right}, data, root) do
    with {:ok, a} <- eval(left, data, root),
         {:ok, b} <- eval(right, data, root) do
      binary(op, a, b)
    end
  end

  defp eval({:conditional, test, yes, no}, data, root) do
    with {:ok, value} <- eval(test, data, root) do
      eval(if(Semantics.boolean(value), do: yes, else: no), data, root)
    end
  end

  defp eval({:call, {:variable, name}, args}, data, context)
       when name in ["$map", "$filter", "$reduce"] do
    with {:ok, values} <- eval_list(args, data, context), do: higher_order(name, values, data)
  end

  defp eval({:call, {:variable, name}, args}, data, context) do
    with {:ok, values} <- eval_list(args, data, context) do
      case Map.fetch(context.environment, name) do
        {:ok, closure} -> invoke(closure, values, data)
        :error -> Functions.call(name, values, data)
      end
    end
  end

  defp eval({:call, target, args}, data, context) do
    with {:ok, function} <- eval(target, data, context),
         {:ok, values} <- eval_list(args, data, context) do
      invoke(function, values, data)
    end
  end

  defp eval({:block, nodes}, data, context) do
    Enum.reduce_while(nodes, {:ok, Value.undefined(), context}, fn
      {:binary, ":=", {:variable, name}, right}, {:ok, _, current} when name not in ["$", "$$"] ->
        case eval(right, data, current) do
          {:ok, value} -> {:cont, {:ok, value, put_in(current.environment[name], value)}}
          error -> {:halt, error}
        end

      node, {:ok, _, current} ->
        case eval(node, data, current) do
          {:ok, value} -> {:cont, {:ok, value, current}}
          error -> {:halt, error}
        end
    end)
    |> case do
      {:ok, value, _} -> {:ok, value}
      error -> error
    end
  end

  defp higher_order("$map", [input, %Closure{} = callback], data) do
    input
    |> Value.items()
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case invoke_callback(callback, [item, index, Value.items(input)], data) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Value.sequence(Enum.reverse(values))}
      error -> error
    end
  end

  defp higher_order("$filter", [input, %Closure{} = callback], data) do
    input
    |> Value.items()
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case invoke_callback(callback, [item, index, Value.items(input)], data) do
        {:ok, value} -> {:cont, {:ok, if(Semantics.boolean(value), do: [item | acc], else: acc)}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Value.sequence(Enum.reverse(values))}
      error -> error
    end
  end

  defp higher_order("$reduce", [input, %Closure{} = callback], data),
    do: reduce_items(Value.items(input), callback, Value.undefined(), data)

  defp higher_order("$reduce", [input, %Closure{} = callback, initial], data),
    do: reduce_items(Value.items(input), callback, initial, data)

  defp higher_order(name, _, _), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}

  defp reduce_items(items, callback, initial, data) do
    {first, rest} =
      if Value.undefined?(initial) do
        case items do
          [] -> {Value.undefined(), []}
          [head | tail] -> {head, tail}
        end
      else
        {initial, items}
      end

    rest
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, first}, fn {item, index}, {:ok, accumulator} ->
      case invoke_callback(callback, [accumulator, item, index, items], data) do
        {:ok, value} -> {:cont, {:ok, value}}
        error -> {:halt, error}
      end
    end)
  end

  defp invoke_callback(%Closure{parameters: parameters} = closure, args, data),
    do: invoke(closure, Enum.take(args, length(parameters)), data)

  defp invoke(%Closure{parameters: parameters, body: body} = closure, values, data)
       when length(parameters) == length(values) do
    bindings = Enum.zip(parameters, values) |> Map.new()
    context = %{root: closure.root, environment: Map.merge(closure.environment, bindings)}
    eval(body, data, context)
  end

  defp invoke(_, _, _),
    do: {:error, Error.new("T1006", "Value is not a callable function or arity is invalid")}

  defp eval_each(items, ast, root) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case eval(ast, item, root) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Value.sequence(Enum.reverse(values))}
      error -> error
    end
  end

  defp eval_list(nodes, data, root) do
    Enum.reduce_while(nodes, {:ok, []}, fn node, {:ok, acc} ->
      case eval(node, data, root) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  defp eval_boolean(ast, data, root) do
    with {:ok, value} <- eval(ast, data, root), do: {:ok, Semantics.boolean(value)}
  end

  defp binary(_, a, b) when is_struct(a, Value.Undefined) or is_struct(b, Value.Undefined),
    do: {:ok, Value.undefined()}

  defp binary(op, a, b) when op in ["+", "-", "*", "/", "%"] do
    if is_number(a) and is_number(b) do
      case {op, b} do
        {"/", zero} when zero == 0 -> {:error, Error.new("D1001", "Division by zero")}
        {"%", zero} when zero == 0 -> {:error, Error.new("D1001", "Division by zero")}
        {"+", _} -> {:ok, a + b}
        {"-", _} -> {:ok, a - b}
        {"*", _} -> {:ok, a * b}
        {"/", _} -> {:ok, a / b}
        {"%", _} when is_integer(a) and is_integer(b) -> {:ok, rem(a, b)}
        {"%", _} -> {:ok, :math.fmod(a, b)}
      end
    else
      type_error("Arithmetic operands must be numbers")
    end
  end

  defp binary(op, a, b) when op in ["=", "!=", "<", "<=", ">", ">=", "in"] do
    if op in ["=", "!=", "in"] or (is_number(a) and is_number(b)) or
         (is_binary(a) and is_binary(b)) do
      {:ok, Semantics.compare(op, a, b)}
    else
      type_error("Comparison operands must have compatible types")
    end
  end

  defp binary("&", a, b), do: {:ok, string(a) <> string(b)}

  defp binary("..", a, b) when is_integer(a) and is_integer(b) and b - a <= 100_000 do
    {:ok, if(a > b, do: [], else: Enum.to_list(a..b))}
  end

  defp binary("..", _, _), do: type_error("Range requires integers with at most 100000 values")
  defp binary(op, _, _), do: {:error, Error.new("T1007", "Unsupported operator #{op}")}

  defp string(nil), do: "null"
  defp string(true), do: "true"
  defp string(false), do: "false"
  defp string(value) when is_binary(value), do: value
  defp string(value) when is_number(value), do: to_string(value)

  defp string(value) do
    {:ok, result} = Jexata.Functions.String.call("$string", [value])
    result
  end

  defp group_items(items, key_ast, context) do
    Enum.reduce_while(items, {:ok, %{}}, fn item, {:ok, groups} ->
      case eval(key_ast, item, context) do
        {:ok, key} when is_binary(key) ->
          {:cont, {:ok, Map.update(groups, key, [item], &[item | &1])}}

        {:ok, _} ->
          {:halt, {:error, Error.new("T1003", "Group key must be a string")}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp eval_sort_keys(terms, item, context) do
    Enum.reduce_while(terms, {:ok, []}, fn {direction, ast}, {:ok, keys} ->
      case eval(ast, item, context) do
        {:ok, value} when is_number(value) or is_binary(value) ->
          {:cont, {:ok, [{direction, value} | keys]}}

        {:ok, _} ->
          {:halt, {:error, Error.new("T2008", "Sort key must be a number or string")}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, keys} -> {:ok, Enum.reverse(keys)}
      error -> error
    end
  end

  defp compare_sort_keys([], []), do: true

  defp compare_sort_keys([{direction, left} | rest_a], [{_, right} | rest_b]) do
    cond do
      left == right -> compare_sort_keys(rest_a, rest_b)
      direction == :asc -> left < right
      true -> left > right
    end
  end

  defp descendants(value) when is_list(value), do: Enum.flat_map(value, &descendants/1)

  defp descendants(value) when is_map(value) and not is_struct(value) do
    [value | Enum.flat_map(value, fn {_key, child} -> descendants(child) end)]
  end

  defp descendants(value), do: [value]

  defp type_error(message), do: {:error, Error.new("T2001", message)}
end
