defmodule Jexata.Functions.String do
  @moduledoc false
  alias Jexata.{Error, Semantics}
  alias Jexata.Runtime.Value
  alias Jexata.Runtime.LimitedRegex
  alias Jexata.Functions.String.Serialization

  @max_pad_codepoints 1_000_000

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
    "$match",
    "$base64encode",
    "$base64decode"
  ]
  def supported?(name), do: name in @supported

  def call("$string", [value]) when is_binary(value), do: {:ok, value}

  def call("$base64encode", []), do: {:ok, Value.undefined()}
  def call("$base64decode", []), do: {:ok, Value.undefined()}
  def call("$base64encode", [value]) when is_binary(value), do: {:ok, Base.encode64(value)}

  def call("$base64decode", [value]) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} when is_binary(decoded) -> {:ok, decoded}
      :error -> {:error, Error.new("D3140", "Invalid Base64 input")}
    end
  end

  def call("$string", [value]) when is_number(value), do: {:ok, Semantics.number_string(value)}
  def call("$string", [%Jexata.Runtime.Closure{}]), do: {:ok, ""}
  def call("$string", [%Jexata.Runtime.Builtin{}]), do: {:ok, ""}
  def call("$string", [%Jexata.Runtime.Partial{}]), do: {:ok, ""}
  def call("$string", [%Jexata.Runtime.Transform{}]), do: {:ok, ""}
  def call("$string", [%Jexata.Runtime.Composition{}]), do: {:ok, ""}

  def call("$string", [value, false]), do: call("$string", [value])
  def call("$string", [value, true]) when is_binary(value), do: {:ok, value}
  def call("$string", [value, true]) when is_number(value), do: call("$string", [value])
  def call("$string", [%Jexata.Runtime.Closure{}, true]), do: {:ok, ""}
  def call("$string", [%Jexata.Runtime.Builtin{}, true]), do: {:ok, ""}
  def call("$string", [%Jexata.Runtime.Partial{}, true]), do: {:ok, ""}
  def call("$string", [%Jexata.Runtime.Transform{}, true]), do: {:ok, ""}
  def call("$string", [%Jexata.Runtime.Composition{}, true]), do: {:ok, ""}

  def call("$string", [value, true]) do
    if Value.undefined?(value),
      do: {:ok, Value.undefined()},
      else: {:ok, Serialization.stringify(value, true)}
  end

  def call("$string", [value]) do
    if Value.undefined?(value) do
      {:ok, Value.undefined()}
    else
      {:ok, Serialization.stringify(value, false)}
    end
  end

  def call("$length", [value]) when is_binary(value) do
    {:ok, if(ascii?(value), do: byte_size(value), else: length(String.codepoints(value)))}
  end

  def call("$length", [value]) when is_struct(value, Value.Undefined), do: {:ok, value}
  def call("$length", []), do: {:error, Error.new("T0411", "$length requires a string")}

  def call(name, [value])
      when name in ["$uppercase", "$lowercase", "$trim"] and
             is_struct(value, Value.Undefined),
      do: {:ok, value}

  def call("$uppercase", [value]) when is_binary(value), do: {:ok, String.upcase(value)}
  def call("$lowercase", [value]) when is_binary(value), do: {:ok, String.downcase(value)}

  def call("$trim", [value]) when is_binary(value) do
    result =
      if ascii?(value) do
        value
        |> :binary.split([" ", "\t", "\n", "\r", "\v", "\f"], [:global])
        |> Enum.reject(&(&1 == ""))
        |> Enum.join(" ")
      else
        value |> String.trim() |> String.replace(~r/\s+/u, " ")
      end

    {:ok, result}
  end

  def call("$pad", [value, width]), do: call("$pad", [value, width, " "])

  def call("$pad", [value, _width, _pattern]) when is_struct(value, Value.Undefined),
    do: {:ok, Value.undefined()}

  def call("$pad", [value, width, pattern])
      when is_binary(value) and is_number(width) and is_binary(pattern) do
    target = trunc(abs(width))

    if target > @max_pad_codepoints do
      {:error, Error.new("J1004", "$pad output exceeds the configured limit")}
    else
      current = if ascii?(value), do: byte_size(value), else: length(String.codepoints(value))
      missing = max(target - current, 0)
      padding = if pattern == "", do: " ", else: pattern

      padded = pad_fragment(padding, missing)

      {:ok, if(width < 0, do: padded <> value, else: value <> padded)}
    end
  end

  def call("$contains", [value, token])
      when is_struct(value, Value.Undefined) or is_struct(token, Value.Undefined),
      do: {:ok, Value.undefined()}

  def call("$substringBefore", [value, ""]) when is_binary(value), do: {:ok, ""}

  def call("$substringBefore", [_value]),
    do: {:error, Error.new("T0411", "$substringBefore requires a separator")}

  def call("$substringBefore", [value, _token]) when is_struct(value, Value.Undefined),
    do: {:ok, Value.undefined()}

  def call("$substringBefore", [value, token]) when is_binary(value) and is_binary(token) do
    case :binary.match(value, token) do
      {index, _} -> {:ok, binary_part(value, 0, index)}
      :nomatch -> {:ok, value}
    end
  end

  def call("$substringAfter", [value, ""]) when is_binary(value), do: {:ok, value}

  def call("$substringAfter", [_value]),
    do: {:error, Error.new("T0411", "$substringAfter requires a separator")}

  def call("$substringAfter", [value, _token]) when is_struct(value, Value.Undefined),
    do: {:ok, Value.undefined()}

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

  def call("$replace", [_value, _token, _replacement, limit])
      when is_number(limit) and limit < 0,
      do: {:error, Error.new("D3011", "$replace limit must not be negative")}

  def call("$replace", [_value, "", _replacement]),
    do: {:error, Error.new("D3010", "$replace pattern must not be empty")}

  def call("$replace", [value, _token, _replacement])
      when is_struct(value, Value.Undefined),
      do: {:ok, value}

  def call("$replace", [value, _token, _replacement, _limit])
      when is_struct(value, Value.Undefined),
      do: {:ok, value}

  def call("$replace", [value, %Regex{} = pattern, replacement])
      when is_binary(value) and is_binary(replacement),
      do: regex_or_plain_replace(value, pattern, replacement, :all)

  def call("$replace", [value, %Regex{} = pattern, replacement, limit])
      when is_binary(value) and is_binary(replacement) and is_integer(limit) and limit >= 0,
      do: regex_or_plain_replace(value, pattern, replacement, limit)

  def call("$contains", [value, token]) when is_binary(value) and is_binary(token),
    do: {:ok, String.contains?(value, token)}

  def call("$contains", [value, %Regex{} = pattern]) when is_binary(value) do
    if plain_regex?(pattern),
      do: {:ok, :binary.match(value, pattern.source) != :nomatch},
      else: {:ok, LimitedRegex.match?(pattern, value)}
  end

  def call("$match", [value, pattern]), do: call("$match", [value, pattern, :all])

  def call("$match", [value, %Regex{} = pattern, limit])
      when is_binary(value) and (limit == :all or (is_integer(limit) and limit >= 0)) do
    matches = LimitedRegex.scan(pattern, value, return: :index)
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

  def call("$substring", [value, start]) when is_binary(value) and is_number(start),
    do: substring(value, floor(start), nil)

  def call("$substring", [value, _start]) when is_struct(value, Value.Undefined),
    do: {:ok, value}

  def call("$substring", [value, _start, _count]) when is_struct(value, Value.Undefined),
    do: {:ok, value}

  def call("$substring", [value, start, count])
      when is_binary(value) and is_number(start) and is_number(count),
      do: substring(value, floor(start), floor(count))

  def call("$split", [value, separator]) when is_binary(value) and is_binary(separator),
    do:
      {:ok,
       if(separator == "", do: String.codepoints(value), else: String.split(value, separator))}

  def call("$split", [value, _separator]) when is_struct(value, Value.Undefined),
    do: {:ok, Value.undefined()}

  def call("$split", [value, %Regex{} = pattern]) when is_binary(value),
    do: {:ok, split_regex_or_plain(value, pattern)}

  def call("$split", [value, separator, limit])
      when is_binary(value) and is_binary(separator) and is_number(limit) and limit >= 0,
      do:
        {:ok,
         value
         |> then(
           &if(separator == "", do: String.codepoints(&1), else: String.split(&1, separator))
         )
         |> Enum.take(trunc(limit))}

  def call("$split", [_value, _separator, limit]) when is_number(limit) and limit < 0,
    do: {:error, Error.new("D3020", "$split limit must not be negative")}

  def call("$split", [value, %Regex{} = pattern, limit])
      when is_binary(value) and is_integer(limit) and limit >= 0,
      do: {:ok, value |> split_regex_or_plain(pattern) |> Enum.take(limit)}

  def call("$join", [values]) when is_list(values), do: call("$join", [values, ""])
  def call("$join", [value]) when is_binary(value), do: {:ok, value}
  def call("$join", [value]) when is_struct(value, Value.Undefined), do: {:ok, value}

  def call("$join", [value, separator]) when is_binary(value) and is_binary(separator),
    do: {:ok, value}

  def call("$join", [value, _separator]) when is_struct(value, Value.Undefined),
    do: {:ok, Value.undefined()}

  def call("$join", [%Value.Sequence{items: values}, separator]),
    do: call("$join", [values, separator])

  def call("$join", [%Value.Sequence{items: values}]), do: call("$join", [values, ""])

  def call("$join", [values, separator])
      when is_list(values) and is_struct(separator, Value.Undefined),
      do: call("$join", [values, ""])

  def call("$join", [values, separator]) when is_list(values) and is_binary(separator) do
    if Enum.all?(values, &is_binary/1),
      do: {:ok, Enum.join(values, separator)},
      else: {:error, Error.new("T0412", "$join requires strings")}
  end

  def call("$join", [values, _separator]) when is_list(values),
    do: {:error, Error.new("T0410", "$join separator must be a string")}

  def call("$join", [_, _]), do: {:error, Error.new("T0412", "$join requires strings")}

  def call(name, _), do: type_error(name)

  defp regex_or_plain_replace(value, pattern, replacement, limit) do
    if plain_regex?(pattern) and :binary.match(replacement, "$") == :nomatch do
      if limit == :all,
        do: call("$replace", [value, pattern.source, replacement]),
        else: call("$replace", [value, pattern.source, replacement, limit])
    else
      regex_replace(value, pattern, replacement, limit)
    end
  end

  defp split_regex_or_plain(value, pattern) do
    if plain_regex?(pattern),
      do: :binary.split(value, pattern.source, [:global]),
      else: LimitedRegex.split(pattern, value)
  end

  defp plain_regex?(%Regex{source: source, opts: []}) when source != "",
    do: plain_regex_bytes?(source)

  defp plain_regex?(_), do: false

  defp plain_regex_bytes?(<<>>), do: true

  defp plain_regex_bytes?(<<byte, rest::binary>>)
       when byte in ?a..?z or byte in ?A..?Z or byte in ?0..?9 or byte in [32, ?_, ?-],
       do: plain_regex_bytes?(rest)

  defp plain_regex_bytes?(_), do: false

  defp substring(value, start, count) do
    if ascii?(value) do
      size = byte_size(value)
      index = if start < 0, do: max(size + start, 0), else: min(start, size)
      length = if is_nil(count), do: size - index, else: min(max(count, 0), size - index)
      {:ok, binary_part(value, index, length)}
    else
      chars = String.codepoints(value)
      index = if start < 0, do: max(length(chars) + start, 0), else: start
      suffix = Enum.drop(chars, index)
      selected = if is_nil(count), do: suffix, else: Enum.take(suffix, max(count, 0))
      {:ok, Enum.join(selected)}
    end
  end

  defp ascii?(<<>>), do: true
  defp ascii?(<<byte, rest::binary>>) when byte < 128, do: ascii?(rest)
  defp ascii?(_), do: false

  defp replace_regex(value, pattern, replacement, limit) do
    matches = LimitedRegex.scan(pattern, value, return: :index)
    matches = if limit == :all, do: matches, else: Enum.take(matches, limit)
    template = prepare_replacement(replacement)

    {parts, cursor} =
      Enum.map_reduce(matches, 0, fn [{start, size} | captures] = match, cursor ->
        untouched = binary_part(value, cursor, start - cursor)
        replacement = expand_replacement(template, value, match, captures)
        {[untouched, replacement], start + size}
      end)

    IO.iodata_to_binary([parts, binary_part(value, cursor, byte_size(value) - cursor)])
  end

  defp regex_replace(value, pattern, replacement, limit) do
    if LimitedRegex.match?(pattern, ""),
      do: {:error, Error.new("D1004", "Regex must not match an empty string")},
      else: {:ok, replace_regex(value, pattern, replacement, limit)}
  end

  defp prepare_replacement(template) do
    matches = Regex.scan(~r/\$\$|\$\d+/, template, return: :index)

    {parts, cursor} =
      Enum.map_reduce(matches, 0, fn [{start, size}], cursor ->
        literal = binary_part(template, cursor, start - cursor)
        token = binary_part(template, start, size)
        part = if token == "$$", do: :dollar, else: {:group, binary_part(token, 1, size - 1)}
        {[literal, part], start + size}
      end)

    [parts, binary_part(template, cursor, byte_size(template) - cursor)]
  end

  defp expand_replacement(template, value, full_match, captures) do
    groups = [hd(full_match) | captures]
    expand_replacement_parts(template, value, groups)
  end

  defp expand_replacement_parts(:dollar, _value, _groups), do: "$"

  defp expand_replacement_parts({:group, digits}, value, groups),
    do: replacement_group(digits, value, groups)

  defp expand_replacement_parts(parts, value, groups) when is_list(parts),
    do: Enum.map(parts, &expand_replacement_parts(&1, value, groups))

  defp expand_replacement_parts(literal, _value, _groups), do: literal

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

  def stringify_ordered(value, pretty), do: Serialization.stringify_ordered(value, pretty)

  defp pad_fragment(_pattern, 0), do: ""

  defp pad_fragment(pattern, count) do
    width = if ascii?(pattern), do: byte_size(pattern), else: length(String.codepoints(pattern))
    whole = div(count, width)
    extra = rem(count, width)

    if extra == 0 do
      String.duplicate(pattern, whole)
    else
      prefix = pattern |> String.codepoints() |> Enum.take(extra) |> Enum.join()
      String.duplicate(pattern, whole) <> prefix
    end
  end

  defp type_error(name), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}
end
