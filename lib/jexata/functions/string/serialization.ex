defmodule Jexata.Functions.String.Serialization do
  @moduledoc false
  alias Jexata.Runtime.Value

  def stringify(value, false),
    do: value |> Value.public() |> json_value() |> :json.encode() |> IO.iodata_to_binary()

  def stringify(value, true),
    do: value |> Value.public() |> json_value() |> pretty_json(0) |> IO.iodata_to_binary()

  def stringify_ordered(value, pretty),
    do: value |> ordered_json(pretty, 0) |> IO.iodata_to_binary()

  defp ordered_json({:ordered_object, pairs}, false, level) do
    entries =
      Enum.map(pairs, fn {key, value} ->
        [encode_json(key), ":", ordered_json(value, false, level + 1)]
      end)

    ["{", Enum.intersperse(entries, ","), "}"]
  end

  defp ordered_json({:ordered_object, pairs}, true, level) do
    entries =
      Enum.map(pairs, fn {key, value} ->
        [
          String.duplicate("  ", level + 1),
          encode_json(key),
          ": ",
          ordered_json(value, true, level + 1)
        ]
      end)

    if entries == [],
      do: "{}",
      else: ["{\n", Enum.intersperse(entries, ",\n"), "\n", String.duplicate("  ", level), "}"]
  end

  defp ordered_json(values, pretty, level) when is_list(values) do
    entries = Enum.map(values, &ordered_json(&1, pretty, level + 1))

    if pretty do
      if entries == [],
        do: "[]",
        else: [
          "[\n",
          Enum.intersperse(Enum.map(entries, &[String.duplicate("  ", level + 1), &1]), ",\n"),
          "\n",
          String.duplicate("  ", level),
          "]"
        ]
    else
      ["[", Enum.intersperse(entries, ","), "]"]
    end
  end

  defp ordered_json(value, pretty, level) do
    value = value |> Value.public() |> json_value()
    if pretty, do: pretty_json(value, level), else: encode_json(value)
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
        [String.duplicate("  ", level + 1), encode_json(key), ": ", pretty_json(item, level + 1)]
      end)

    if entries == [],
      do: "{}",
      else: ["{\n", Enum.intersperse(entries, ",\n"), "\n", String.duplicate("  ", level), "}"]
  end

  defp pretty_json(value, level) when is_list(value) do
    entries =
      Enum.map(value, fn item ->
        [String.duplicate("  ", level + 1), pretty_json(item, level + 1)]
      end)

    if entries == [],
      do: "[]",
      else: ["[\n", Enum.intersperse(entries, ",\n"), "\n", String.duplicate("  ", level), "]"]
  end

  defp pretty_json(value, _level), do: encode_json(value)
  defp encode_json(value), do: value |> :json.encode() |> IO.iodata_to_binary()
end
