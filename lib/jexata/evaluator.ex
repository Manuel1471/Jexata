defmodule Jexata.Evaluator do
  @moduledoc false
  alias Jexata.{Error, Functions, Semantics}
  alias Jexata.Runtime.Value

  @spec evaluate(Jexata.AST.t(), term()) :: {:ok, term()} | {:error, Error.t()}
  def evaluate(ast, data), do: eval(ast, data, data)

  defp eval({:literal, value}, _, _), do: {:ok, value}
  defp eval({:name, name}, data, _), do: {:ok, Semantics.select(data, name)}
  defp eval({:variable, "$"}, data, _), do: {:ok, data}
  defp eval({:variable, "$$"}, _, root), do: {:ok, root}

  defp eval({:variable, name}, _, _),
    do: {:error, Error.new("T1005", "Undefined variable #{name}")}

  defp eval(:wildcard, data, _root) when is_map(data), do: {:ok, Value.sequence(Map.values(data))}
  defp eval(:wildcard, data, _root), do: {:ok, Value.sequence(Value.items(data))}

  defp eval({:path, left, right}, data, root) do
    with {:ok, source} <- eval(left, data, root) do
      source
      |> Value.items()
      |> eval_each(right, root)
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

  defp eval({:binary, ":=", _, _}, _, _),
    do: {:error, Error.new("T1007", "Bindings are not implemented yet")}

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

  defp eval({:call, {:variable, name}, args}, data, root) do
    with {:ok, values} <- eval_list(args, data, root), do: Functions.call(name, values, data)
  end

  defp eval({:call, _, _}, _, _),
    do: {:error, Error.new("T1006", "Only named built-in functions can be called")}

  defp eval({:block, _}, _, _), do: {:error, Error.new("T1007", "Blocks are not implemented yet")}

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
        {"/", 0} -> {:error, Error.new("D1001", "Division by zero")}
        {"%", 0} -> {:error, Error.new("D1001", "Division by zero")}
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
  defp string(_), do: "[object Object]"

  defp type_error(message), do: {:error, Error.new("T2001", message)}
end
