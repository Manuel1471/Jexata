defmodule Jexata.Evaluator.RegexCallbacks do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.{Closure, LimitedRegex, Value}

  def match(matcher, value, bind, invoke) do
    matcher = bind.(matcher, %{"$match" => matcher})

    with {:ok, first} <- invoke.(matcher, [value], value),
         do: match_results(first, [], 0, invoke)
  end

  defp match_results(_result, _acc, count, _invoke) when count >= 100_000,
    do: {:error, Error.new("U1001", "Matcher iteration limit exceeded")}

  defp match_results(result, acc, count, invoke) do
    cond do
      Value.undefined?(result) ->
        {:ok, Value.sequence(Enum.reverse(acc))}

      is_map(result) and is_binary(result["match"]) and is_number(result["start"]) and
          is_list(result["groups"]) ->
        entry = %{
          "match" => result["match"],
          "index" => result["start"],
          "groups" => result["groups"]
        }

        case result["next"] do
          %Closure{} = next ->
            with {:ok, subsequent} <- invoke.(next, [], next.context_value),
                 do: match_results(subsequent, [entry | acc], count + 1, invoke)

          _ ->
            {:ok, Value.sequence(Enum.reverse([entry | acc]))}
        end

      true ->
        {:error, Error.new("T1010", "Matcher did not return a match object")}
    end
  end

  def replace(value, pattern, callback, limit, data, invoke_callback) do
    if LimitedRegex.match?(pattern, "") do
      {:error, Error.new("D1004", "Regex must not match an empty string")}
    else
      matches = LimitedRegex.scan(pattern, value, return: :index)
      matches = if limit == :all, do: matches, else: Enum.take(matches, limit)

      Enum.reduce_while(matches, {:ok, [], 0}, fn [{start, size} | captures],
                                                  {:ok, acc, cursor} ->
        groups =
          Enum.map(captures, fn
            {-1, _} -> ""
            {index, length} -> binary_part(value, index, length)
          end)

        match = %{
          "match" => binary_part(value, start, size),
          "index" => start,
          "groups" => groups
        }

        case invoke_callback.(callback, [match], data) do
          {:ok, replacement} when is_binary(replacement) ->
            prefix = binary_part(value, cursor, start - cursor)
            {:cont, {:ok, [acc, prefix, replacement], start + size}}

          {:ok, _} ->
            {:halt, {:error, Error.new("D3012", "Replacement function must return a string")}}

          error ->
            {:halt, error}
        end
      end)
      |> case do
        {:ok, parts, cursor} ->
          {:ok,
           IO.iodata_to_binary([parts, binary_part(value, cursor, byte_size(value) - cursor)])}

        error ->
          error
      end
    end
  end
end
