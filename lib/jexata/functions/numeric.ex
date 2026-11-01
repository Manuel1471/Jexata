defmodule Jexata.Functions.Numeric do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value

  @aggregates ["$sum", "$count", "$max", "$min", "$average"]
  @unary ["$abs", "$floor", "$ceil"]
  @supported @aggregates ++ @unary ++ ["$round", "$number", "$sqrt", "$power", "$formatBase"]

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

  def call(name, [value]) when name in @unary and is_struct(value, Value.Undefined),
    do: {:ok, value}

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

  def call("$number", [value]) when is_number(value), do: {:ok, value}
  def call("$number", [true]), do: {:ok, 1}
  def call("$number", [false]), do: {:ok, 0}

  def call("$number", [value]) when is_binary(value) do
    parsed = Integer.parse(value)

    if match?({_, ""}, parsed) and not String.starts_with?(value, "+") do
      {:ok, elem(parsed, 0)}
    else
      number_from_string(value)
    end
  end

  def call("$number", [value]) when is_struct(value, Value.Undefined),
    do: {:ok, Value.undefined()}

  def call("$sqrt", [value]) when is_number(value) and value >= 0, do: {:ok, :math.sqrt(value)}

  def call("$sqrt", [value]) when is_struct(value, Value.Undefined), do: {:ok, value}

  def call("$sqrt", [value]) when is_number(value),
    do: {:error, Error.new("D3060", "Square root of a negative number")}

  def call("$power", [base, exponent]) when is_number(base) and is_number(exponent) do
    try do
      {:ok, :math.pow(base, exponent)}
    rescue
      ArithmeticError -> {:error, Error.new("D3061", "Numeric result is not finite")}
    end
  end

  def call("$power", [base, _exponent]) when is_struct(base, Value.Undefined),
    do: {:ok, base}

  def call("$formatBase", [value]), do: call("$formatBase", [value, 10])

  def call("$formatBase", [value, _base]) when is_struct(value, Value.Undefined),
    do: {:ok, value}

  def call("$formatBase", [value, base])
      when is_number(value) and is_number(base) do
    integer = round_decimal(value, 0)
    radix = round_decimal(base, 0)

    if radix in 2..36,
      do: {:ok, Integer.to_string(integer, radix) |> String.downcase()},
      else: {:error, Error.new("D3100", "Invalid numeric base")}
  end

  def call("$round", [value]), do: call("$round", [value, 0])

  def call("$round", [value, _precision]) when is_struct(value, Value.Undefined),
    do: {:ok, value}

  def call("$round", [value, precision])
      when is_number(value) and is_integer(precision) and precision in -100..100,
      do: {:ok, round_decimal(value, precision)}

  def call(name, _), do: type_error(name)

  defp number_from_string(value) do
    cond do
      Regex.match?(~r/\A0[xX][0-9a-fA-F]+\z/, value) ->
        {:ok, value |> String.slice(2..-1//1) |> String.to_integer(16)}

      Regex.match?(~r/\A0[oO][0-7]+\z/, value) ->
        {:ok, value |> String.slice(2..-1//1) |> String.to_integer(8)}

      Regex.match?(~r/\A0[bB][01]+\z/, value) ->
        {:ok, value |> String.slice(2..-1//1) |> String.to_integer(2)}

      Regex.match?(~r/\A-?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\z/, value) ->
        if String.contains?(value, [".", "e", "E"]) do
          case Float.parse(value) do
            {number, ""} -> {:ok, number}
            _ -> invalid_number()
          end
        else
          {:ok, String.to_integer(value)}
        end

      true ->
        invalid_number()
    end
  end

  defp aggregate("$sum", values), do: {:ok, Enum.sum(values)}
  defp aggregate("$max", []), do: {:ok, Value.undefined()}
  defp aggregate("$max", values), do: {:ok, Enum.max(values)}
  defp aggregate("$min", []), do: {:ok, Value.undefined()}
  defp aggregate("$min", values), do: {:ok, Enum.min(values)}
  defp aggregate("$average", []), do: {:ok, Value.undefined()}
  defp aggregate("$average", values), do: {:ok, Enum.sum(values) / length(values)}

  defp type_error(name), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}
  defp invalid_number, do: {:error, Error.new("D3030", "Cannot cast string to number")}

  defp round_decimal(value, precision) when is_integer(value) and precision >= 0, do: value

  defp round_decimal(value, precision) do
    text =
      if is_integer(value),
        do: Integer.to_string(value),
        else: :erlang.float_to_binary(value, [:short])

    sign = if String.starts_with?(text, "-"), do: -1, else: 1
    text = String.trim_leading(text, "-")
    [mantissa | exponent] = String.split(text, ~r/[eE]/)
    [whole | fraction] = String.split(mantissa, ".")
    fractional = Enum.at(fraction, 0, "")
    coefficient = String.to_integer(whole <> fractional)

    scale =
      if(exponent == [], do: 0, else: String.to_integer(hd(exponent))) - String.length(fractional) +
        precision

    rounded =
      if scale >= 0 do
        coefficient * Integer.pow(10, scale)
      else
        divisor = Integer.pow(10, -scale)
        quotient = div(coefficient, divisor)
        remainder = rem(coefficient, divisor)

        if remainder * 2 > divisor or (remainder * 2 == divisor and rem(quotient, 2) == 1),
          do: quotient + 1,
          else: quotient
      end

    result = sign * rounded

    if precision > 0,
      do: result / Integer.pow(10, precision),
      else: result * Integer.pow(10, -precision)
  end
end
