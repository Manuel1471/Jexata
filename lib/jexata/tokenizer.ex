defmodule Jexata.Tokenizer do
  @moduledoc false
  alias Jexata.{Error, Token}

  @number ~r/\A(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/
  @name ~r/\A[\p{L}_][\p{L}\p{N}_]*/u
  @operators ["~>", ":=", "!=", "<=", ">=", "**", "..", "??", "?:"]
  @single [
    ".",
    "[",
    "]",
    "{",
    "}",
    "(",
    ")",
    ",",
    ":",
    ";",
    "?",
    "+",
    "-",
    "*",
    "/",
    "%",
    "=",
    "<",
    ">",
    "&",
    "|",
    "^",
    "#",
    "@"
  ]

  @spec tokenize(String.t()) :: {:ok, [Token.t()]} | {:error, Error.t()}
  def tokenize(source) when is_binary(source), do: scan(source, 0, [])

  defp scan(<<>>, position, acc), do: {:ok, Enum.reverse([token(:eof, nil, position) | acc])}

  defp scan(source, position, acc) do
    cond do
      String.match?(source, ~r/\A\s/u) ->
        [space] = Regex.run(~r/\A\s/u, source)
        consume(source, space, position, acc)

      String.starts_with?(source, "/*") ->
        case :binary.match(source, "*/") do
          {offset, 2} -> consume(source, binary_part(source, 0, offset + 2), position, acc)
          :nomatch -> {:error, Error.new("S0106", "Unterminated comment", position)}
        end

      String.starts_with?(source, ["\"", "'", "`"]) ->
        <<quote::utf8, rest::binary>> = source

        with {:ok, value, tail} <- quoted(rest, quote, position + 1, []) do
          type = if quote == ?`, do: :name, else: :string

          scan(tail, position + byte_size(source) - byte_size(tail), [
            token(type, value, position) | acc
          ])
        end

      true ->
        scan_token(source, position, acc)
    end
  end

  defp scan_token(source, position, acc) do
    multi = Enum.find(@operators, &String.starts_with?(source, &1))

    cond do
      multi ->
        emit(source, multi, :op, multi, position, acc)

      String.starts_with?(source, "$$") ->
        emit(source, "$$", :variable, "$$", position, acc)

      String.starts_with?(source, "$") ->
        scan_variable(source, position, acc)

      String.starts_with?(source, "/") and regex_position?(acc) ->
        scan_regex(source, position, acc)

      Regex.match?(@number, source) ->
        [lexeme] = Regex.run(@number, source)

        if String.contains?(lexeme, [".", "e", "E"]) do
          case Float.parse(lexeme) do
            {value, ""} -> emit(source, lexeme, :number, value, position, acc)
            _ -> {:error, Error.new("S0102", "Invalid numeric literal", position)}
          end
        else
          emit(source, lexeme, :number, String.to_integer(lexeme), position, acc)
        end

      Regex.match?(@name, source) ->
        [name] = Regex.run(@name, source)

        {type, value} =
          case name do
            "true" -> {:literal, true}
            "false" -> {:literal, false}
            "null" -> {:literal, nil}
            "and" -> {:op, "and"}
            "or" -> {:op, "or"}
            "in" -> {:op, "in"}
            _ -> {:name, name}
          end

        emit(source, name, type, value, position, acc)

      true ->
        <<character::utf8, _::binary>> = source
        symbol = <<character::utf8>>

        if symbol in @single do
          emit(source, symbol, :op, symbol, position, acc)
        else
          {:error, Error.new("S0101", "Unexpected character #{inspect(symbol)}", position)}
        end
    end
  end

  defp scan_variable(source, position, acc) do
    rest = binary_part(source, 1, byte_size(source) - 1)

    name =
      case Regex.run(@name, rest) do
        [value] -> value
        _ -> ""
      end

    lexeme = "$" <> name
    emit(source, lexeme, :variable, lexeme, position, acc)
  end

  defp regex_position?([]), do: true

  defp regex_position?([%Token{value: value} | _]),
    do:
      value in [
        "(",
        "[",
        "{",
        ",",
        ":",
        ";",
        "?",
        "=",
        "+",
        "-",
        "*",
        "/",
        "%",
        "&",
        "|",
        "~>",
        ":="
      ]

  defp scan_regex(<<?/, rest::binary>>, position, acc) do
    case regex_body(rest, [], false) do
      {:ok, body, tail} ->
        flags = Regex.run(~r/\A[a-z]*/, tail) |> hd()
        remaining = binary_part(tail, byte_size(flags), byte_size(tail) - byte_size(flags))
        consumed = byte_size(rest) - byte_size(remaining) + 1
        scan(remaining, position + consumed, [token(:regex, {body, flags}, position) | acc])

      :error ->
        {:error, Error.new("S0104", "Unterminated regular expression", position)}
    end
  end

  defp regex_body(<<>>, _, _), do: :error

  defp regex_body(<<?\\, character, tail::binary>>, acc, in_class),
    do: regex_body(tail, [<<?\\, character>> | acc], in_class)

  defp regex_body(<<?[, tail::binary>>, acc, false),
    do: regex_body(tail, ["[" | acc], true)

  defp regex_body(<<?], tail::binary>>, acc, true),
    do: regex_body(tail, ["]" | acc], false)

  defp regex_body(<<?/, tail::binary>>, acc, false),
    do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary(), tail}

  defp regex_body(<<character, tail::binary>>, acc, in_class),
    do: regex_body(tail, [<<character>> | acc], in_class)

  defp emit(source, lexeme, type, value, position, acc) do
    tail = binary_part(source, byte_size(lexeme), byte_size(source) - byte_size(lexeme))
    scan(tail, position + byte_size(lexeme), [token(type, value, position) | acc])
  end

  defp consume(source, lexeme, position, acc) do
    tail = binary_part(source, byte_size(lexeme), byte_size(source) - byte_size(lexeme))
    scan(tail, position + byte_size(lexeme), acc)
  end

  defp token(type, value, position), do: %Token{type: type, value: value, position: position}

  defp quoted(<<>>, quote, position, _acc),
    do:
      {:error,
       Error.new(if(quote == ?`, do: "S0105", else: "S0101"), "Unterminated string", position)}

  defp quoted(<<quote::utf8, tail::binary>>, quote, _position, acc),
    do: {:ok, IO.iodata_to_binary(Enum.reverse(acc)), tail}

  defp quoted(<<?\\, escape::utf8, tail::binary>>, quote, position, acc) do
    case escape do
      ?u ->
        unicode_escape(tail, quote, position, acc)

      _ ->
        value =
          Map.get(
            %{
              ?n => "\n",
              ?r => "\r",
              ?t => "\t",
              ?b => "\b",
              ?f => "\f",
              ?/ => "/",
              ?\\ => "\\",
              ?\" => "\"",
              ?' => "'",
              ?` => "`"
            },
            escape
          )

        if value,
          do: quoted(tail, quote, position + 2, [value | acc]),
          else: {:error, Error.new("S0103", "Invalid escape", position)}
    end
  end

  defp quoted(<<character::utf8, tail::binary>>, quote, position, acc),
    do:
      quoted(tail, quote, position + byte_size(<<character::utf8>>), [<<character::utf8>> | acc])

  defp unicode_escape(<<digits::binary-size(4), tail::binary>>, quote, position, acc) do
    case Integer.parse(digits, 16) do
      {high, ""} when high in 0xD800..0xDBFF ->
        case tail do
          <<?\\, ?u, low_digits::binary-size(4), rest::binary>> ->
            case Integer.parse(low_digits, 16) do
              {low, ""} when low in 0xDC00..0xDFFF ->
                codepoint = 0x10000 + (high - 0xD800) * 0x400 + low - 0xDC00
                quoted(rest, quote, position + 12, [<<codepoint::utf8>> | acc])

              _ ->
                {:error, Error.new("S0104", "Invalid Unicode surrogate pair", position)}
            end

          _ ->
            {:error, Error.new("S0104", "Invalid Unicode surrogate pair", position)}
        end

      {codepoint, ""} when codepoint not in 0xD800..0xDFFF and codepoint <= 0x10FFFF ->
        quoted(tail, quote, position + 6, [<<codepoint::utf8>> | acc])

      _ ->
        {:error, Error.new("S0104", "Invalid Unicode escape", position)}
    end
  end

  defp unicode_escape(_, _, position, _),
    do: {:error, Error.new("S0104", "Invalid Unicode escape", position)}
end
