defmodule Jexata.Functions.String do
  @moduledoc false
  alias Jexata.{Error, Semantics}
  alias Jexata.Runtime.Value

  @supported [
    "$string",
    "$length",
    "$uppercase",
    "$lowercase",
    "$trim",
    "$substring",
    "$contains",
    "$split",
    "$join",
    "$substringBefore",
    "$substringAfter",
    "$replace",
    "$pad",
    "$match"
  ]
  def supported?(name), do: name in @supported

  def call("$string", [value]) when is_binary(value), do: {:ok, value}
  def call("$string", [value]) when is_number(value), do: {:ok, Semantics.number_string(value)}
  def call("$string", [%Jexata.Runtime.Closure{}]), do: {:ok, ""}
  def call("$string", [%Jexata.Runtime.Builtin{}]), do: {:ok, ""}

  def call("$string", [value, false]), do: call("$string", [value])
  def call("$string", [value, true]) when is_binary(value), do: {:ok, value}
  def call("$string", [value, true]) when is_number(value), do: call("$string", [value])
  def call("$string", [%Jexata.Runtime.Closure{}, true]), do: {:ok, ""}
  def call("$string", [%Jexata.Runtime.Builtin{}, true]), do: {:ok, ""}

  def call("$string", [value, true]) do
    if Value.undefined?(value),
      do: {:ok, Value.undefined()},
      else: {:ok, value |> Value.public() |> json_value() |> pretty_json(0)}
  end

  def call("$string", [value]) do
    if Value.undefined?(value) do
      {:ok, Value.undefined()}
    else
      {:ok, value |> Value.public() |> json_value() |> :json.encode() |> IO.iodata_to_binary()}
    end
  end

  def call("$length", [value]) when is_binary(value), do: {:ok, length(String.codepoints(value))}
  def call("$uppercase", [value]) when is_binary(value), do: {:ok, String.upcase(value)}
  def call("$lowercase", [value]) when is_binary(value), do: {:ok, String.downcase(value)}

  def call("$trim", [value]) when is_binary(value),
    do: {:ok, value |> String.trim() |> String.replace(~r/\s+/u, " ")}

  def call("$pad", [value, width]), do: call("$pad", [value, width, " "])

  def call("$pad", [value, _width, _pattern]) when is_struct(value, Value.Undefined),
    do: {:ok, Value.undefined()}

  def call("$pad", [value, width, pattern])
      when is_binary(value) and is_number(width) and is_binary(pattern) do
    missing = max(trunc(abs(width)) - length(String.codepoints(value)), 0)
    padding = if pattern == "", do: " ", else: pattern
    padded = padding |> String.codepoints() |> Stream.cycle() |> Enum.take(missing) |> Enum.join()
    {:ok, if(width < 0, do: padded <> value, else: value <> padded)}
  end

  def call("$contains", [value, token])
      when is_struct(value, Value.Undefined) or is_struct(token, Value.Undefined),
      do: {:ok, Value.undefined()}

  def call("$substringBefore", [value, ""]) when is_binary(value), do: {:ok, ""}

  def call("$substringBefore", [value, token]) when is_binary(value) and is_binary(token) do
    case :binary.match(value, token) do
      {index, _} -> {:ok, binary_part(value, 0, index)}
      :nomatch -> {:ok, value}
    end
  end

  def call("$substringAfter", [value, ""]) when is_binary(value), do: {:ok, value}

  def call("$substringAfter", [value, token]) when is_binary(value) and is_binary(token) do
    case :binary.match(value, token) do
      {index, length} ->
        {:ok, binary_part(value, index + length, byte_size(value) - index - length)}

      :nomatch ->
        {:ok, value}
    end
  end

  def call("$replace", [value, token, replacement])
      when is_binary(value) and is_binary(token) and is_binary(replacement) and token != "",
      do: {:ok, String.replace(value, token, replacement)}

  def call("$replace", [value, token, replacement, limit])
      when is_binary(value) and is_binary(token) and is_binary(replacement) and is_integer(limit) and
             limit >= 0 and token != "" do
    {:ok,
     if(limit == 0,
       do: value,
       else: value |> String.split(token, parts: limit + 1) |> Enum.join(replacement)
     )}
  end

  def call("$replace", [value, %Regex{} = pattern, replacement])
      when is_binary(value) and is_binary(replacement),
      do: regex_replace(value, pattern, replacement, :all)

  def call("$replace", [value, %Regex{} = pattern, replacement, limit])
      when is_binary(value) and is_binary(replacement) and is_integer(limit) and limit >= 0,
      do: regex_replace(value, pattern, replacement, limit)

  def call("$contains", [value, token]) when is_binary(value) and is_binary(token),
    do: {:ok, String.contains?(value, token)}

  def call("$contains", [value, %Regex{} = pattern]) when is_binary(value),
    do: {:ok, Regex.match?(pattern, value)}

  def call("$match", [value, pattern]), do: call("$match", [value, pattern, :all])

  def call("$match", [value, %Regex{} = pattern, limit])
      when is_binary(value) and (limit == :all or (is_integer(limit) and limit >= 0)) do
    matches = Regex.scan(pattern, value, return: :index)
    matches = if limit == :all, do: matches, else: Enum.take(matches, limit)

    results =
      Enum.map(matches, fn [{index, length} | captures] ->
        groups =
          Enum.map(captures, fn
            {-1, _} -> ""
            {start, size} -> binary_part(value, start, size)
          end)

        %{"match" => binary_part(value, index, length), "index" => index, "groups" => groups}
      end)

    {:ok, Value.sequence(results)}
  end

  def call("$substring", [value, start]) when is_binary(value) and is_integer(start),
    do: substring(value, start, nil)

  def call("$substring", [value, start, count])
      when is_binary(value) and is_integer(start) and is_integer(count),
      do: substring(value, start, count)

  def call("$split", [value, separator]) when is_binary(value) and is_binary(separator),
    do: {:ok, String.split(value, separator)}

  def call("$split", [value, %Regex{} = pattern]) when is_binary(value),
    do: {:ok, Regex.split(pattern, value)}

  def call("$split", [value, separator, limit])
      when is_binary(value) and is_binary(separator) and is_integer(limit) and limit >= 0,
      do: {:ok, value |> String.split(separator) |> Enum.take(limit)}

  def call("$split", [value, %Regex{} = pattern, limit])
      when is_binary(value) and is_integer(limit) and limit >= 0,
      do: {:ok, pattern |> Regex.split(value) |> Enum.take(limit)}

  def call("$join", [values]) when is_list(values), do: call("$join", [values, ""])

  def call("$join", [values, separator])
      when is_list(values) and is_struct(separator, Value.Undefined),
      do: call("$join", [values, ""])

  def call("$join", [values, separator]) when is_list(values) and is_binary(separator) do
    if Enum.all?(values, &is_binary/1),
      do: {:ok, Enum.join(values, separator)},
      else: type_error("$join")
  end

  def call(name, _), do: type_error(name)

  defp substring(value, start, count) do
    chars = String.codepoints(value)
    index = if start < 0, do: max(length(chars) + start, 0), else: start
    suffix = Enum.drop(chars, index)
    selected = if is_nil(count), do: suffix, else: Enum.take(suffix, max(count, 0))
    {:ok, Enum.join(selected)}
  end

  defp replace_regex(value, pattern, replacement, limit) do
    matches = Regex.scan(pattern, value, return: :index)
    matches = if limit == :all, do: matches, else: Enum.take(matches, limit)

    {parts, cursor} =
      Enum.map_reduce(matches, 0, fn [{start, size} | captures] = match, cursor ->
        untouched = binary_part(value, cursor, start - cursor)
        replacement = expand_replacement(replacement, value, match, captures)
        {[untouched, replacement], start + size}
      end)

    IO.iodata_to_binary([parts, binary_part(value, cursor, byte_size(value) - cursor)])
  end

  defp regex_replace(value, pattern, replacement, limit) do
    if Regex.match?(pattern, ""),
      do: {:error, Error.new("D1004", "Regex must not match an empty string")},
      else: {:ok, replace_regex(value, pattern, replacement, limit)}
  end

  defp expand_replacement(template, value, full_match, captures) do
    Regex.replace(~r/\$\$|\$\d+/, template, fn token ->
      cond do
        token == "$$" ->
          "$"

        true ->
          digits = String.slice(token, 1..-1//1)
          replacement_group(digits, value, [hd(full_match) | captures])
      end
    end)
  end

  defp replacement_group(digits, value, groups) do
    candidates =
      for width <- String.length(digits)..1//-1,
          index = digits |> String.slice(0, width) |> String.to_integer(),
          index < length(groups),
          do: {index, String.slice(digits, width..-1//1)}

    case candidates do
      [{index, remainder} | _] ->
        {start, size} = Enum.at(groups, index)
        if(start < 0, do: "", else: binary_part(value, start, size)) <> remainder

      [] ->
        String.slice(digits, 1..-1//1)
    end
  end

  defp json_value(nil), do: :null
  defp json_value(:function), do: ""
  defp json_value(list) when is_list(list), do: Enum.map(list, &json_value/1)

  defp json_value(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, json_value(value)} end)

  defp json_value(value), do: value

  defp pretty_json(value, level) when is_map(value) do
    entries =
      Enum.map(value, fn {key, item} ->
        String.duplicate("  ", level + 1) <>
          encode_json(key) <> ": " <> pretty_json(item, level + 1)
      end)

    if entries == [],
      do: "{}",
      else: "{\n" <> Enum.join(entries, ",\n") <> "\n" <> String.duplicate("  ", level) <> "}"
  end

  defp pretty_json(value, level) when is_list(value) do
    entries =
      Enum.map(value, fn item ->
        String.duplicate("  ", level + 1) <> pretty_json(item, level + 1)
      end)

    if entries == [],
      do: "[]",
      else: "[\n" <> Enum.join(entries, ",\n") <> "\n" <> String.duplicate("  ", level) <> "]"
  end

  defp pretty_json(value, _level), do: encode_json(value)
  defp encode_json(value), do: value |> :json.encode() |> IO.iodata_to_binary()

  defp type_error(name), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}
end
