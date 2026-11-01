defmodule Jexata.Runtime.Limits do
  @moduledoc false
  alias Jexata.Error

  @defaults [max_source_bytes: 100_000, max_tokens: 10_000, max_nesting: 128]
  @keys Keyword.keys(@defaults)

  def validate(options) when is_list(options) do
    if Keyword.keyword?(options) and
         Enum.all?(options, fn {key, value} ->
           key in @keys and is_integer(value) and value > 0
         end) do
      {:ok, Keyword.merge(@defaults, options)}
    else
      {:error, Error.new("J0005", "Invalid compilation limits")}
    end
  end

  def validate(_), do: {:error, Error.new("J0005", "Invalid compilation limits")}

  def source(source, options) do
    if byte_size(source) <= options[:max_source_bytes],
      do: :ok,
      else: {:error, Error.new("J1001", "Expression exceeds source size limit")}
  end

  def tokens(tokens, options) do
    if length(tokens) <= options[:max_tokens],
      do: nesting(tokens, options[:max_nesting], 0),
      else: {:error, Error.new("J1002", "Expression exceeds token limit")}
  end

  defp nesting([], _, _), do: :ok

  defp nesting([%{value: value, position: position} | rest], max, depth) do
    next =
      cond do
        value in ["(", "[", "{"] -> depth + 1
        value in [")", "]", "}"] -> depth - 1
        true -> depth
      end

    if next > max do
      {:error, Error.new("J1003", "Expression exceeds nesting limit", position)}
    else
      nesting(rest, max, next)
    end
  end
end
