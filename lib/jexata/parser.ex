defmodule Jexata.Parser do
  @moduledoc false
  alias Jexata.{Error, Token, Tokenizer}
  alias Jexata.Runtime.Limits

  @precedence %{
    ":=" => 10,
    "?:" => 20,
    "??" => 20,
    "~>" => 25,
    "or" => 30,
    "and" => 40,
    "=" => 50,
    "!=" => 50,
    "<" => 50,
    "<=" => 50,
    ">" => 50,
    ">=" => 50,
    "in" => 50,
    "&" => 60,
    ".." => 65,
    "+" => 70,
    "-" => 70,
    "*" => 80,
    "/" => 80,
    "%" => 80
  }

  @spec parse(String.t()) :: {:ok, Jexata.AST.t()} | {:error, Error.t()}
  def parse(source, options \\ []) do
    with {:ok, limits} <- Limits.validate(options),
         :ok <- Limits.source(source, limits),
         {:ok, tokens} <- Tokenizer.tokenize(source),
         :ok <- Limits.tokens(tokens, limits),
         {:ok, ast, rest} <- expression(tokens, 0) do
      case rest do
        [%Token{type: :eof}] -> {:ok, ast}
        [token | _] -> {:error, syntax("Unexpected token", token)}
      end
    end
  end

  defp expression(tokens, min_bp) do
    with {:ok, left, rest} <- prefix(tokens) do
      infix(left, rest, min_bp)
    end
  end

  defp prefix([%Token{type: type, value: value} | rest])
       when type in [:literal, :number, :string],
       do: {:ok, {:literal, value}, rest}

  defp prefix([%Token{type: :name, value: "function"}, %Token{value: "("} | rest]),
    do: lambda_parameters([], rest)

  defp prefix([%Token{type: :name, value: name} | rest]), do: {:ok, {:name, name}, rest}
  defp prefix([%Token{type: :variable, value: name} | rest]), do: {:ok, {:variable, name}, rest}

  defp prefix([%Token{value: "-"} | rest]) do
    with {:ok, value, tail} <- expression(rest, 90), do: {:ok, {:negate, value}, tail}
  end

  defp prefix([%Token{value: "*"} | rest]), do: {:ok, :wildcard, rest}
  defp prefix([%Token{value: "**"} | rest]), do: {:ok, :descendants, rest}
  defp prefix([%Token{value: "["} | rest]), do: collection(rest, "]", :array)
  defp prefix([%Token{value: "{"} | rest]), do: collection(rest, "}", :object)

  defp prefix([%Token{value: "("} | rest]) do
    with {:ok, first, tail} <- expression(rest, 0) do
      block([first], tail)
    end
  end

  defp prefix([token | _]), do: {:error, syntax("Expected an expression", token)}
  defp prefix([]), do: {:error, Error.new("S0201", "Expected an expression")}

  defp infix(left, [%Token{value: "."} | rest], min_bp) when min_bp < 100 do
    with {:ok, right, tail} <- prefix(rest),
         {:ok, right, tail} <- path_postfix(right, tail),
         do: infix({:path, left, right}, tail, min_bp)
  end

  defp infix(left, [%Token{value: "("} | rest], min_bp) when min_bp < 100 do
    with {:ok, args, tail} <- arguments(rest), do: infix({:call, left, args}, tail, min_bp)
  end

  defp infix(left, [%Token{value: "{"} | rest], min_bp) when min_bp < 100 do
    with {:ok, {:object, pairs}, tail} <- collection(rest, "}", :object),
         do: infix({:group, left, pairs}, tail, min_bp)
  end

  defp infix(left, [%Token{value: "^"}, %Token{value: "("} | rest], min_bp) when min_bp < 100 do
    with {:ok, terms, tail} <- sort_terms([], rest), do: infix({:sort, left, terms}, tail, min_bp)
  end

  defp infix(left, [%Token{value: "["}, %Token{value: "]"} | rest], min_bp) when min_bp < 100,
    do: infix({:keep_array, left}, rest, min_bp)

  defp infix(left, [%Token{value: "["} | rest], min_bp) when min_bp < 100 do
    with {:ok, predicate, tail} <- expression(rest, 0),
         {:ok, tail} <- expect(tail, "]") do
      infix({:filter, left, predicate}, tail, min_bp)
    end
  end

  defp infix(left, [%Token{value: "?"} | rest], min_bp) when min_bp < 20 do
    with {:ok, consequent, tail} <- expression(rest, 0),
         {:ok, tail} <- expect(tail, ":"),
         {:ok, alternate, tail} <- expression(tail, 19) do
      infix({:conditional, left, consequent, alternate}, tail, min_bp)
    end
  end

  defp infix(left, [%Token{type: :op, value: op} | rest] = tokens, min_bp) do
    case Map.get(@precedence, op) do
      nil ->
        {:ok, left, tokens}

      bp when bp <= min_bp ->
        {:ok, left, tokens}

      bp ->
        with {:ok, right, tail} <- expression(rest, bp) do
          infix({:binary, op, left, right}, tail, min_bp)
        end
    end
  end

  defp infix(left, tokens, _), do: {:ok, left, tokens}

  defp path_postfix(left, [%Token{value: "("} | rest]) do
    with {:ok, args, tail} <- arguments(rest), do: path_postfix({:call, left, args}, tail)
  end

  defp path_postfix(left, [%Token{value: "["}, %Token{value: "]"} | rest]),
    do: path_postfix({:keep_array, left}, rest)

  defp path_postfix(left, [%Token{value: "["} | rest]) do
    with {:ok, predicate, tail} <- expression(rest, 0),
         {:ok, tail} <- expect(tail, "]"),
         do: path_postfix({:filter, left, predicate}, tail)
  end

  defp path_postfix(left, tail), do: {:ok, left, tail}

  defp sort_terms(terms, tokens) do
    {direction, rest} =
      case tokens do
        [%Token{value: ">"} | tail] -> {:desc, tail}
        [%Token{value: "<"} | tail] -> {:asc, tail}
        _ -> {:asc, tokens}
      end

    with {:ok, ast, tail} <- expression(rest, 0) do
      case tail do
        [%Token{value: ","} | more] ->
          sort_terms([{direction, ast} | terms], more)

        _ ->
          with {:ok, more} <- expect(tail, ")"),
               do: {:ok, Enum.reverse([{direction, ast} | terms]), more}
      end
    end
  end

  defp collection([%Token{value: closing} | rest], closing, :array), do: {:ok, {:array, []}, rest}

  defp collection([%Token{value: closing} | rest], closing, :object),
    do: {:ok, {:object, []}, rest}

  defp collection(tokens, "]", :array) do
    with {:ok, first, tail} <- expression(tokens, 0), do: array_items([first], tail)
  end

  defp collection(tokens, "}", :object) do
    with {:ok, key, tail} <- expression(tokens, 0),
         {:ok, tail} <- expect(tail, ":"),
         {:ok, value, tail} <- expression(tail, 0) do
      object_items([{key, value}], tail)
    end
  end

  defp array_items(items, [%Token{value: ","} | rest]) do
    with {:ok, value, tail} <- expression(rest, 0), do: array_items([value | items], tail)
  end

  defp array_items(items, tokens) do
    with {:ok, tail} <- expect(tokens, "]"), do: {:ok, {:array, Enum.reverse(items)}, tail}
  end

  defp object_items(items, [%Token{value: ","} | rest]) do
    with {:ok, key, tail} <- expression(rest, 0),
         {:ok, tail} <- expect(tail, ":"),
         {:ok, value, tail} <- expression(tail, 0) do
      object_items([{key, value} | items], tail)
    end
  end

  defp object_items(items, tokens) do
    with {:ok, tail} <- expect(tokens, "}"), do: {:ok, {:object, Enum.reverse(items)}, tail}
  end

  defp lambda_parameters(parameters, [%Token{value: ")"} | rest]) do
    with {:ok, tail} <- expect(rest, "{"),
         {:ok, body, tail} <- expression(tail, 0),
         {:ok, tail} <- expect(tail, "}") do
      {:ok, {:lambda, Enum.reverse(parameters), body}, tail}
    end
  end

  defp lambda_parameters(parameters, [%Token{type: :variable, value: name} | rest])
       when name not in ["$", "$$"] do
    case rest do
      [%Token{value: ","} | tail] -> lambda_parameters([name | parameters], tail)
      _ -> lambda_parameters_finish([name | parameters], rest)
    end
  end

  defp lambda_parameters(_, [token | _]), do: {:error, syntax("Expected a parameter", token)}

  defp lambda_parameters_finish(parameters, tokens) do
    with {:ok, tail} <- expect(tokens, ")"),
         do: lambda_parameters(parameters, [%Token{type: :op, value: ")", position: 0} | tail])
  end

  defp arguments([%Token{value: ")"} | rest]), do: {:ok, [], rest}

  defp arguments(tokens) do
    with {:ok, first, tail} <- expression(tokens, 0), do: argument_items([first], tail)
  end

  defp argument_items(items, [%Token{value: ","} | rest]) do
    with {:ok, value, tail} <- expression(rest, 0), do: argument_items([value | items], tail)
  end

  defp argument_items(items, tokens) do
    with {:ok, tail} <- expect(tokens, ")"), do: {:ok, Enum.reverse(items), tail}
  end

  defp block(items, [%Token{value: ";"} | rest]) do
    with {:ok, value, tail} <- expression(rest, 0), do: block([value | items], tail)
  end

  defp block(items, tokens) do
    with {:ok, tail} <- expect(tokens, ")") do
      nodes = Enum.reverse(items)
      {:ok, if(length(nodes) == 1, do: hd(nodes), else: {:block, nodes}), tail}
    end
  end

  defp expect([%Token{value: value} | rest], value), do: {:ok, rest}
  defp expect([token | _], value), do: {:error, syntax("Expected #{inspect(value)}", token)}
  defp expect([], value), do: {:error, Error.new("S0201", "Expected #{inspect(value)}")}

  defp syntax(message, token), do: Error.new("S0202", message, token.position)
end
