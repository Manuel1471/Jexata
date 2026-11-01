defmodule Jexata.Functions.Numeric do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value

  @aggregates ["$sum", "$count", "$max", "$min", "$average"]
  @unary ["$abs", "$floor", "$ceil"]
  @supported @aggregates ++ @unary ++ ["$round"]

  def supported?(name), do: name in @supported

  def call(name, [input])
      when name in @aggregates and name != "$count" and is_struct(input, Value.Undefined),
      do: {:ok, Value.undefined()}

  def call(name, [input]) when name in @aggregates do
    values = Value.items(input)

    cond do
      name == "$count" -> {:ok, length(values)}
      Enum.all?(values, &is_number/1) -> aggregate(name, values)
      true -> {:error, Error.new("T0412", "#{name} requires numbers")}
    end
  end

  def call(name, [value]) when name in @unary do
    if is_number(value) do
      result =
        case name do
          "$abs" -> abs(value)
          "$floor" -> Float.floor(value / 1)
          "$ceil" -> Float.ceil(value / 1)
        end

      {:ok, if(name == "$abs", do: result, else: trunc(result))}
    else
      type_error(name)
    end
  end

  def call("$round", [value]), do: call("$round", [value, 0])

  def call("$round", [value, precision])
      when is_number(value) and is_integer(precision) and precision in -15..15 do
    scale = :math.pow(10, precision)
    scaled = value * scale
    low = Float.floor(scaled)
    fraction = scaled - low

    nearest =
      cond do
        fraction < 0.5 -> low
        fraction > 0.5 -> low + 1
        rem(trunc(low), 2) == 0 -> low
        true -> low + 1
      end

    result = nearest / scale
    {:ok, if(precision <= 0 and result == trunc(result), do: trunc(result), else: result)}
  end

  def call(name, _), do: type_error(name)

  defp aggregate("$sum", values), do: {:ok, Enum.sum(values)}
  defp aggregate("$max", []), do: {:ok, Value.undefined()}
  defp aggregate("$max", values), do: {:ok, Enum.max(values)}
  defp aggregate("$min", []), do: {:ok, Value.undefined()}
  defp aggregate("$min", values), do: {:ok, Enum.min(values)}
  defp aggregate("$average", []), do: {:ok, Value.undefined()}
  defp aggregate("$average", values), do: {:ok, Enum.sum(values) / length(values)}

  defp type_error(name), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}
end
