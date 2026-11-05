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
    scan_tokens(tokens, options[:max_tokens], options[:max_nesting], 0, 0, nil)
  end

  defp scan_tokens([], _, _, _, _, nil), do: :ok
  defp scan_tokens([], _, _, _, _, error), do: {:error, error}

  defp scan_tokens([_ | _], max_tokens, _, count, _, _) when count >= max_tokens,
    do: {:error, Error.new("J1002", "Expression exceeds token limit")}

  defp scan_tokens(
         [%{type: type, value: value, position: position} | rest],
         max_tokens,
         max_nesting,
         count,
         depth,
         error
       ) do
    next =
      cond do
        type == :op and value in ["(", "[", "{"] -> depth + 1
        type == :op and value in [")", "]", "}"] -> depth - 1
        true -> depth
      end

    error =
      if next > max_nesting and error == nil,
        do: Error.new("J1003", "Expression exceeds nesting limit", position),
        else: error

    scan_tokens(rest, max_tokens, max_nesting, count + 1, next, error)
  end
end
