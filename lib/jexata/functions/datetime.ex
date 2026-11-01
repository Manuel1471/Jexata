defmodule Jexata.Functions.Datetime do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value

  def supported?(name), do: name in ["$toMillis", "$fromMillis"]

  def call("$toMillis", [value]) when is_struct(value, Value.Undefined),
    do: {:ok, Value.undefined()}

  def call("$toMillis", [value]) when is_binary(value), do: parse_iso(value)

  def call("$toMillis", [value, picture]) when is_binary(value) and is_binary(picture),
    do: parse_picture(value, picture)

  def call("$fromMillis", [value]) when is_struct(value, Value.Undefined),
    do: {:ok, Value.undefined()}

  def call("$fromMillis", [value]) when is_number(value) do
    case DateTime.from_unix(trunc(value), :millisecond) do
      {:ok, date} ->
        {:ok, DateTime.to_iso8601(date)}

      {:error, _} ->
        {:error, Error.new("D3111", "Milliseconds outside supported range")}
    end
  end

  def call(name, _), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}

  defp parse_iso(value) do
    normalized =
      cond do
        Regex.match?(~r/\A\d{4}\z/, value) -> value <> "-01-01T00:00:00Z"
        Regex.match?(~r/\A\d{4}-\d{2}-\d{2}\z/, value) -> value <> "T00:00:00Z"
        true -> value
      end

    case DateTime.from_iso8601(normalized) do
      {:ok, date, _offset} -> {:ok, DateTime.to_unix(date, :millisecond)}
      {:error, _} -> {:error, Error.new("D3110", "Invalid ISO 8601 timestamp")}
    end
  end

  defp parse_picture(value, picture) do
    tokens = Regex.scan(~r/\[([^\]]+)\]/, picture, capture: :all_but_first) |> List.flatten()

    if Enum.join(Enum.map(tokens, &"[#{&1}]")) == picture and
         Enum.all?(
           tokens,
           &(&1 in ["Y0001", "Y,*-4", "Y0000", "M01", "M00", "D01", "D00", "H00", "m00", "s00"])
         ) do
      widths =
        Enum.map(tokens, fn token -> if String.starts_with?(token, "Y"), do: 4, else: 2 end)

      if String.length(value) == Enum.sum(widths) and Regex.match?(~r/\A\d+\z/, value) do
        {fields, ""} =
          Enum.zip(tokens, widths)
          |> Enum.map_reduce(value, fn {token, width}, rest ->
            {part, remaining} = String.split_at(rest, width)
            {{String.first(token), String.to_integer(part)}, remaining}
          end)

        parts = Map.new(fields)

        with {:ok, date} <- Date.new(parts["Y"], parts["M"] || 1, parts["D"] || 1),
             {:ok, time} <- Time.new(parts["H"] || 0, parts["m"] || 0, parts["s"] || 0),
             {:ok, datetime} <- DateTime.new(date, time, "Etc/UTC") do
          {:ok, DateTime.to_unix(datetime, :millisecond)}
        else
          _ -> {:error, Error.new("D3110", "Invalid formatted timestamp")}
        end
      else
        {:error, Error.new("D3110", "Invalid formatted timestamp")}
      end
    else
      {:error, Error.new("D3130", "Unsupported date picture")}
    end
  end
end
