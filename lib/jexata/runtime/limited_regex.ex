defmodule Jexata.Runtime.LimitedRegex do
  @moduledoc false
  alias Jexata.Error

  @key {__MODULE__, :limits}

  def install(match_limit, recursion_limit), do: Process.put(@key, {match_limit, recursion_limit})

  def run(pattern, value, options \\ []) do
    case limits() do
      nil ->
        Regex.run(pattern, value, options)

      bounds ->
        case :re.run(value, pattern.re_pattern, [
               :report_errors,
               {:capture, :all, :index} | bounds
             ]) do
          :nomatch -> nil
          {:match, captures} -> captures
          {:error, reason} -> limit_error!(reason)
        end
    end
  end

  def scan(pattern, value, options \\ []) do
    case limits() do
      nil ->
        Regex.scan(pattern, value, options)

      bounds ->
        case :re.run(value, pattern.re_pattern, [
               :global,
               :report_errors,
               {:capture, :all, :index} | bounds
             ]) do
          :nomatch -> []
          {:match, captures} -> captures
          {:error, reason} -> limit_error!(reason)
        end
    end
  end

  def match?(pattern, value) do
    case limits() do
      nil ->
        Regex.match?(pattern, value)

      bounds ->
        case :re.run(value, pattern.re_pattern, [:report_errors, {:capture, :none} | bounds]) do
          :nomatch -> false
          :match -> true
          {:error, reason} -> limit_error!(reason)
        end
    end
  end

  def split(pattern, value) do
    case limits() do
      nil ->
        Regex.split(pattern, value)

      bounds ->
        case :re.run(value, pattern.re_pattern, [
               :global,
               :report_errors,
               {:capture, :none} | bounds
             ]) do
          {:error, reason} ->
            limit_error!(reason)

          _ ->
            value
            |> :re.split(pattern.re_pattern, [{:return, :binary}, :group | bounds])
            |> Enum.map(&hd/1)
        end
    end
  end

  defp limits() do
    case Process.get(@key) do
      nil ->
        nil

      {match_limit, recursion_limit} ->
        [{:match_limit, match_limit}, {:match_limit_recursion, recursion_limit}]
    end
  end

  defp limit_error!(reason),
    do: raise(Error.new("J1008", "Regular expression limit exceeded: #{reason}"))
end
