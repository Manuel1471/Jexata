defmodule Jexata.Parser do
  @moduledoc false
  alias Jexata.{Error, Token, Tokenizer}
  alias Jexata.Runtime.Limits

  @precedence %{
    ":=" => 10,
    "?:" => 20,
    "??" => 20,
    "~>" => 50,
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
         {:ok, tokens} <- tokenize_with_prior_syntax_error(source),
         :ok <- Limits.tokens(tokens, limits),
         {:ok, ast, rest} <- expression(tokens, 0) do
      case rest do
        [%Token{type: :eof}] ->
          {:ok, ast}

        [%Token{value: ";", position: position} | _] ->
          {:error, Error.new("S0201", "Unexpected trailing semicolon", position)}

        [token | _] ->
          {:error, syntax("Unexpected token", token)}
      end
    end
  end

  defp tokenize_with_prior_syntax_error(source) do
    case Tokenizer.tokenize(source) do
      {:error, %Error{code: "S0101"} = lexical_error} ->
        source
        |> last_quote_offset()
        |> case do
          nil ->
            {:error, lexical_error}

          offset ->
            prefix = binary_part(source, 0, offset)

            case parse(prefix) do
              {:error, %Error{code: "S0202", position: position} = syntax_error}
              when position < offset ->
                {:error, syntax_error}

              _ ->
                {:error, lexical_error}
            end
        end

      result ->
        result
    end
  end

  defp last_quote_offset(source) do
    ["\"", "'", "`"]
    |> Enum.flat_map(&:binary.matches(source, &1))
    |> Enum.map(&elem(&1, 0))
    |> Enum.max(fn -> nil end)
  end

  defp expression(tokens, min_bp) do
    with {:ok, left, rest} <- prefix(tokens) do
      infix(left, rest, min_bp)
    end
  end

  defp prefix([%Token{type: type, value: value} | rest])
       when type in [:literal, :number, :string],
       do: {:ok, {:literal, value}, rest}

  defp prefix([%Token{type: :regex, value: {pattern, flags}, position: position} | rest]) do
    if String.match?(flags, ~r/\A[im]*\z/) do
      case Regex.compile(pattern, flags) do
        {:ok, regex} -> {:ok, {:literal, regex}, rest}
        {:error, _} -> {:error, Error.new("S0301", "Invalid regular expression", position)}
      end
    else
      {:error, Error.new("S0301", "Invalid regular expression flags", position)}
    end
  end

  defp prefix([%Token{type: :name, value: name}, %Token{value: "("} | rest])
       when name in ["function", "λ"],
       do: lambda_parameters([], rest)

  defp prefix([%Token{type: :name, value: name} | rest]), do: {:ok, {:name, name}, rest}
  defp prefix([%Token{type: :variable, value: name} | rest]), do: {:ok, {:variable, name}, rest}

  defp prefix([%Token{value: "-"} | rest]) do
    with {:ok, value, tail} <- expression(rest, 90), do: {:ok, {:negate, value}, tail}
  end

  defp prefix([%Token{value: "?"} | rest]), do: {:ok, :placeholder, rest}

  defp prefix([%Token{value: "|"} | rest]) do
    with {:ok, pattern, tail} <- expression(rest, 0),
         {:ok, tail} <- expect(tail, "|"),
         {:ok, update, tail} <- expression(tail, 0),
         {:ok, delete, tail} <- transform_delete(tail),
         {:ok, tail} <- expect(tail, "|") do
      {:ok, {:transform, pattern, update, delete}, tail}
    end
  end

  defp prefix([%Token{value: "*"} | rest]), do: {:ok, :wildcard, rest}
  defp prefix([%Token{value: "**"} | rest]), do: {:ok, :descendants, rest}

  defp prefix([%Token{value: "%"}, %Token{value: "%"}, %Token{type: :eof}]),
    do: {:error, Error.new("S0207", "Missing right operand")}

  defp prefix([%Token{value: "%"} | rest]), do: {:ok, :parent, rest}
  defp prefix([%Token{value: "["} | rest]), do: collection(rest, "]", :array)
  defp prefix([%Token{value: "{"} | rest]), do: collection(rest, "}", :object)

  defp prefix([%Token{value: "("}, %Token{value: ")"} | rest]),
    do: {:ok, {:literal, Jexata.Runtime.Value.undefined()}, rest}

  defp prefix([%Token{value: "("} | rest]) do
    with {:ok, first, tail} <- expression(rest, 0) do
      block([first], tail)
    end
  end

  defp prefix([%Token{type: :op, position: position} | _]),
    do: {:error, Error.new("S0211", "Unexpected operator", position)}

  defp prefix([token | _]), do: {:error, syntax("Expected an expression", token)}
  defp prefix([]), do: {:error, Error.new("S0201", "Expected an expression")}

  defp infix(left, [%Token{value: "."} | rest], min_bp) when min_bp < 100 do
    with {:ok, right, tail} <- path_prefix(rest),
         {:ok, right, tail} <- path_postfix(right, tail),
         do: infix({:path, left, right}, tail, min_bp)
  end

  defp infix(left, [%Token{value: "#"}, %Token{type: :variable, value: name} | rest], min_bp)
       when min_bp < 100 and name not in ["$", "$$"],
       do: infix({:index_bind, left, name}, rest, min_bp)

  defp infix(_left, [%Token{value: "#"} | _], min_bp) when min_bp < 100,
    do: {:error, Error.new("S0214", "Index binding requires a variable")}

  defp infix(left, [%Token{value: "@"}, %Token{type: :variable, value: name} | rest], min_bp)
       when min_bp < 100 and name not in ["$", "$$"] do
    cond do
      focus_after_filter?(left) ->
        {:error, Error.new("S0215", "Focus binding after predicate")}

      match?({:sort, _, _}, left) ->
        {:error, Error.new("S0216", "Focus binding after sort")}

      true ->
        infix({:focus_bind, left, name}, rest, min_bp)
    end
  end

  defp infix(_left, [%Token{value: "@"} | _], min_bp) when min_bp < 100,
    do: {:error, Error.new("S0214", "Focus binding requires a variable")}

  defp infix(left, [%Token{value: "("} | rest], min_bp) when min_bp < 100 do
    with {:ok, args, tail} <- arguments(rest), do: infix({:call, left, args}, tail, min_bp)
  end

  defp infix({:group, _, _}, [%Token{value: "{"} = token | _], min_bp)
       when min_bp < 100,
       do: {:error, Error.new("S0210", "Grouping cannot be applied twice", token.position)}

  defp infix(left, [%Token{value: "{"} | rest], min_bp) when min_bp < 100 do
    with {:ok, {:object, pairs}, tail} <- collection(rest, "}", :object),
         do: infix({:group, left, pairs}, tail, min_bp)
  end

  defp infix(left, [%Token{value: "^"}, %Token{value: "("} | rest], min_bp) when min_bp < 100 do
    with {:ok, terms, tail} <- sort_terms([], rest), do: infix({:sort, left, terms}, tail, min_bp)
  end

  defp infix(left, [%Token{value: "["}, %Token{value: "]"} | rest], min_bp) when min_bp < 100,
    do: infix({:keep_array, left}, rest, min_bp)

  defp infix({:group, _, _}, [%Token{value: "["} = token | _], min_bp)
       when min_bp < 100,
       do:
         {:error, Error.new("S0209", "Predicate cannot follow a grouped object", token.position)}

  defp infix(left, [%Token{value: "["} | rest], min_bp) when min_bp < 100 do
    with {:ok, predicate, tail} <- expression(rest, 0),
         {:ok, tail} <- expect(tail, "]") do
      infix({:filter, left, predicate}, tail, min_bp)
    end
  end

  defp infix(left, [%Token{value: "?"} | rest], min_bp) when min_bp < 20 do
    with {:ok, consequent, tail} <- expression(rest, 0),
         {:ok, alternate, tail} <- optional_alternate(tail) do
      infix({:conditional, left, consequent, alternate}, tail, min_bp)
    end
  end

  defp infix(_left, [%Token{value: "=", position: position}, %Token{type: :eof}], min_bp)
       when min_bp < 50,
       do: {:error, Error.new("S0207", "Missing right operand", position)}

  defp infix(left, [%Token{type: type, value: op} | rest] = tokens, min_bp)
       when type in [:op, :name] do
    case Map.get(@precedence, op) do
      nil ->
        {:ok, left, tokens}

      bp when bp <= min_bp ->
        {:ok, left, tokens}

      bp ->
        right_bp = if op == ":=", do: bp - 1, else: bp

        with {:ok, right, tail} <- expression(rest, right_bp) do
          infix({:binary, op, left, right}, tail, min_bp)
        end
    end
  end

  defp infix(left, tokens, _), do: {:ok, left, tokens}

  defp focus_after_filter?({:filter, _, _}), do: true
  defp focus_after_filter?({:path, _, right}), do: focus_after_filter?(right)
  defp focus_after_filter?(_), do: false

  defp path_prefix([%Token{type: :string, value: name} | rest]), do: {:ok, {:name, name}, rest}

  defp path_prefix([%Token{type: :number, position: position}, %Token{type: :name} | _]),
    do: {:error, Error.new("S0201", "Expected a field name", position)}

  defp path_prefix([%Token{type: :number, position: position} | _]),
    do: {:error, Error.new("S0213", "Numeric path step is invalid", position)}

  defp path_prefix(tokens), do: prefix(tokens)

  defp transform_delete([%Token{value: ","} | rest]), do: expression(rest, 0)
  defp transform_delete(rest), do: {:ok, nil, rest}

  defp optional_alternate([%Token{value: ":"} | rest]), do: expression(rest, 19)
  defp optional_alternate(tail), do: {:ok, {:literal, Jexata.Runtime.Value.undefined()}, tail}

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
    with {:ok, signature, rest} <- lambda_signature(rest),
         {:ok, tail} <- expect(rest, "{"),
         {:ok, body, tail} <- expression(tail, 0),
         {:ok, tail} <- expect(tail, "}") do
      {:ok, {:lambda, Enum.reverse(parameters), signature, body}, tail}
    end
  end

  defp lambda_parameters(parameters, [%Token{type: :variable, value: name} | rest])
       when name not in ["$", "$$"] do
    case rest do
      [%Token{value: ","} | tail] -> lambda_parameters([name | parameters], tail)
      _ -> lambda_parameters_finish([name | parameters], rest)
    end
  end

  defp lambda_parameters(_, [token | _]),
    do: {:error, Error.new("S0208", "Function parameter must be a variable", token.position)}

  defp lambda_parameters_finish(parameters, tokens) do
    with {:ok, tail} <- expect(tokens, ")"),
         do: lambda_parameters(parameters, [%Token{type: :op, value: ")", position: 0} | tail])
  end

  defp lambda_signature([%Token{value: "<"} | rest]), do: signature_tokens(rest, [], 0)
  defp lambda_signature(rest), do: {:ok, nil, rest}

  defp signature_tokens([%Token{value: ">"} | rest], tokens, 0) do
    signature = tokens |> Enum.reverse() |> Enum.join()

    case Jexata.Runtime.Signature.parse(signature) do
      {:ok, _} -> {:ok, signature, rest}
      {:error, :invalid_union} -> {:error, Error.new("S0402", "Invalid union type in signature")}
      _ -> {:error, Error.new("S0401", "Invalid function signature")}
    end
  end

  defp signature_tokens([%Token{value: "<"} | rest], tokens, depth),
    do: signature_tokens(rest, ["<" | tokens], depth + 1)

  defp signature_tokens([%Token{value: ">"} | rest], tokens, depth),
    do: signature_tokens(rest, [">" | tokens], depth - 1)

  defp signature_tokens([%Token{value: value} | rest], tokens, depth) when is_binary(value),
    do: signature_tokens(rest, [value | tokens], depth)

  defp signature_tokens([token | _], _, _),
    do: {:error, Error.new("S0401", "Invalid function signature", token.position)}

  defp signature_tokens([], _, _), do: {:error, Error.new("S0401", "Unclosed function signature")}

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

  defp block(items, [%Token{value: ";"}, %Token{value: ")"} | rest]),
    do: block(items, [%Token{type: :op, value: ")", position: 0} | rest])

  defp block(items, [%Token{value: ";"} | rest]) do
    with {:ok, value, tail} <- expression(rest, 0), do: block([value | items], tail)
  end

  defp block(items, tokens) do
    with {:ok, tail} <- expect(tokens, ")") do
      nodes = Enum.reverse(items)
      {:ok, {:block, nodes}, tail}
    end
  end

  defp expect([%Token{value: value} | rest], value), do: {:ok, rest}

  defp expect([%Token{type: :eof, position: position} | _], value),
    do: {:error, Error.new("S0203", "Expected #{inspect(value)}", position)}

  defp expect([token | _], value), do: {:error, syntax("Expected #{inspect(value)}", token)}
  defp expect([], value), do: {:error, Error.new("S0201", "Expected #{inspect(value)}")}

  defp syntax(message, token), do: Error.new("S0202", message, token.position)
end
