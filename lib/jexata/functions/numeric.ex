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

    if name == "$count", do: {:ok, length(values)}, else: aggregate(name, values)
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
    case value do
      <<"0", prefix, digits::binary>> when prefix in [?x, ?X] ->
        radix_number(digits, 16)

      <<"0", prefix, digits::binary>> when prefix in [?o, ?O] ->
        radix_number(digits, 8)

      <<"0", prefix, digits::binary>> when prefix in [?b, ?B] ->
        radix_number(digits, 2)

      _ ->
        decimal_number(value)
    end
  end

  defp radix_number(digits, radix) do
    case Integer.parse(digits, radix) do
      {number, ""} when digits != "" and binary_part(digits, 0, 1) not in ["+", "-"] ->
        {:ok, number}

      _ ->
        invalid_number()
    end
  end

  defp decimal_number(value) do
    case decimal_kind(value) do
      :float ->
        case Float.parse(value) do
          {number, ""} -> {:ok, number}
          _ -> invalid_number()
        end

      :integer ->
        {:ok, String.to_integer(value)}

      :invalid ->
        invalid_number()
    end
  end

  defp decimal_kind(<<"-", rest::binary>>), do: decimal_integral(rest)
  defp decimal_kind(value), do: decimal_integral(value)

  defp decimal_integral(value) do
    case decimal_digits(value, 0) do
      {0, _} -> :invalid
      {_, rest} -> decimal_fraction(rest)
    end
  end

  defp decimal_fraction(<<".", rest::binary>>) do
    case decimal_digits(rest, 0) do
      {0, _} -> :invalid
      {_, tail} -> decimal_exponent(tail, true)
    end
  end

  defp decimal_fraction(rest), do: decimal_exponent(rest, false)

  defp decimal_exponent(<<marker, rest::binary>>, _float?) when marker in [?e, ?E] do
    rest =
      case rest do
        <<sign, tail::binary>> when sign in [?+, ?-] -> tail
        other -> other
      end

    case decimal_digits(rest, 0) do
      {0, _} -> :invalid
      {_, ""} -> :float
      _ -> :invalid
    end
  end

  defp decimal_exponent("", true), do: :float
  defp decimal_exponent("", false), do: :integer
  defp decimal_exponent(_, _), do: :invalid

  defp decimal_digits(<<digit, rest::binary>>, count) when digit in ?0..?9,
    do: decimal_digits(rest, count + 1)

  defp decimal_digits(rest, count), do: {count, rest}

  defp aggregate("$sum" = name, values), do: sum(values, 0, name)
  defp aggregate("$average" = name, values), do: average(values, 0, 0, name)
  defp aggregate("$max" = name, values), do: extremum(values, nil, :max, name)
  defp aggregate("$min" = name, values), do: extremum(values, nil, :min, name)

  defp sum([], total, _name), do: {:ok, total}
  defp sum([value | rest], total, name) when is_number(value), do: sum(rest, total + value, name)
  defp sum(_, _, name), do: aggregate_type_error(name)

  defp average([], _total, 0, _name), do: {:ok, Value.undefined()}
  defp average([], total, count, _name), do: {:ok, total / count}

  defp average([value | rest], total, count, name) when is_number(value),
    do: average(rest, total + value, count + 1, name)

  defp average(_, _, _, name), do: aggregate_type_error(name)

  defp extremum([], nil, _direction, _name), do: {:ok, Value.undefined()}
  defp extremum([], current, _direction, _name), do: {:ok, current}

  defp extremum([value | rest], nil, direction, name) when is_number(value),
    do: extremum(rest, value, direction, name)

  defp extremum([value | rest], current, :max, name) when is_number(value),
    do: extremum(rest, max(value, current), :max, name)

  defp extremum([value | rest], current, :min, name) when is_number(value),
    do: extremum(rest, min(value, current), :min, name)

  defp extremum(_, _, _, name), do: aggregate_type_error(name)

  defp aggregate_type_error(name), do: {:error, Error.new("T0412", "#{name} requires numbers")}

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
