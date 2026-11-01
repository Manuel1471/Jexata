defmodule Jexata.Functions.String do
  @moduledoc false
  alias Jexata.Error
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
    "$replace"
  ]
  def supported?(name), do: name in @supported

  def call("$string", [value]) when is_binary(value), do: {:ok, value}

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

  def call("$contains", [value, token]) when is_binary(value) and is_binary(token),
    do: {:ok, String.contains?(value, token)}

  def call("$substring", [value, start]) when is_binary(value) and is_integer(start),
    do: substring(value, start, nil)

  def call("$substring", [value, start, count])
      when is_binary(value) and is_integer(start) and is_integer(count),
      do: substring(value, start, count)

  def call("$split", [value, separator]) when is_binary(value) and is_binary(separator),
    do: {:ok, String.split(value, separator)}

  def call("$split", [value, separator, limit])
      when is_binary(value) and is_binary(separator) and is_integer(limit) and limit >= 0,
      do: {:ok, value |> String.split(separator) |> Enum.take(limit)}

  def call("$join", [values]) when is_list(values), do: call("$join", [values, ""])

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

  defp json_value(nil), do: :null
  defp json_value(list) when is_list(list), do: Enum.map(list, &json_value/1)

  defp json_value(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {key, json_value(value)} end)

  defp json_value(value), do: value

  defp type_error(name), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}
end
