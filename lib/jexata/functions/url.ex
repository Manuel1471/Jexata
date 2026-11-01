defmodule Jexata.Functions.URL do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value

  @names ["$encodeUrl", "$encodeUrlComponent", "$decodeUrl", "$decodeUrlComponent"]
  @reserved ~c";/?:@&=+$,#"

  def supported?(name), do: name in @names

  def call(name, [value]) when is_struct(value, Value.Undefined) and name in @names,
    do: {:ok, Value.undefined()}

  def call("$encodeUrl", [value]) when is_binary(value) do
    if String.valid?(value),
      do: {:ok, URI.encode(value, &uri_character?/1)},
      else: {:error, Error.new("D3140", "Invalid Unicode string")}
  end

  def call("$encodeUrlComponent", [value]) when is_binary(value) do
    if String.valid?(value),
      do: {:ok, URI.encode(value, &component_character?/1)},
      else: {:error, Error.new("D3140", "Invalid Unicode string")}
  end

  def call(name, [value])
      when name in ["$decodeUrl", "$decodeUrlComponent"] and is_binary(value) do
    decoded = URI.decode(value)

    if valid_percent_encoding?(value) and String.valid?(decoded) do
      {:ok, decoded}
    else
      {:error, Error.new("D3140", "Malformed URL passed to #{name}(): #{inspect(value)}")}
    end
  end

  def call(name, _), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}

  defp component_character?(character),
    do: URI.char_unreserved?(character) or character in ~c"!'()*"

  defp uri_character?(character),
    do: component_character?(character) or character in @reserved

  defp valid_percent_encoding?(value), do: valid_percent_encoding?(value, true)
  defp valid_percent_encoding?(<<>>, valid), do: valid

  defp valid_percent_encoding?(<<?%, a, b, rest::binary>>, valid) do
    valid_percent_encoding?(rest, valid and hex?(a) and hex?(b))
  end

  defp valid_percent_encoding?(<<?%, _::binary>>, _valid), do: false

  defp valid_percent_encoding?(<<_, rest::binary>>, valid),
    do: valid_percent_encoding?(rest, valid)

  defp hex?(character),
    do: character in ?0..?9 or character in ?a..?f or character in ?A..?F
end
