defmodule Jexata.Functions.NumberFormat do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value

  def call([value, _picture]) when is_struct(value, Value.Undefined),
    do: {:ok, Value.undefined()}

  def call([value, picture]), do: call([value, picture, %{}])

  def call([value, picture, options])
      when is_number(value) and is_binary(picture) and is_map(options) do
    separator = Map.get(options, "pattern-separator", ";")
    pictures = String.split(picture, separator)

    cond do
      length(pictures) > 2 ->
        {:error, Error.new("D3080", "Too many number subpictures")}

      true ->
        with :ok <- validate(pictures, options) do
          selected = if value < 0, do: Enum.at(pictures, 1, hd(pictures)), else: hd(pictures)

          minus =
            if value < 0 and length(pictures) == 1,
              do: Map.get(options, "minus-sign", "-"),
              else: ""

          {:ok, minus <> format(abs(value), selected, options)}
        end
    end
  end

  def call(_), do: {:error, Error.new("T0410", "Invalid arguments for $formatNumber")}

  defp validate(pictures, options) do
    Enum.reduce_while(pictures, :ok, fn picture, _ ->
      case validate_picture(picture, options) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_picture(picture, options) do
    decimal = Map.get(options, "decimal-separator", ".")
    group = Map.get(options, "grouping-separator", ",")
    percent = Map.get(options, "percent", "%")
    permille = Map.get(options, "per-mille", "‰")
    exponent = Map.get(options, "exponent-separator", "e")
    {_prefix, active, _suffix} = picture_parts(picture, options)
    [mantissa | exponent_parts] = String.split(active, exponent)
    [integer | fraction] = String.split(mantissa, decimal)
    fractional = Enum.at(fraction, 0, "")
    zero = Map.get(options, "zero-digit", "0")
    zero_chars = zero_digits(zero)
    digit = Map.get(options, "digit", "#")
    required = Enum.any?(String.graphemes(mantissa), &(&1 in zero_chars))
    optional = String.contains?(mantissa, digit)

    code =
      cond do
        not required and not optional ->
          if(exponent_parts == [], do: "D3086", else: "D3085")

        occurrences(picture, decimal) > 1 ->
          "D3081"

        occurrences(picture, percent) > 1 ->
          "D3082"

        occurrences(picture, permille) > 1 ->
          "D3083"

        String.contains?(picture, percent) and String.contains?(picture, permille) ->
          "D3084"

        String.contains?(active, "+") ->
          "D3086"

        String.ends_with?(integer, group) and fraction != [] ->
          "D3087"

        String.starts_with?(fractional, group) ->
          "D3087"

        String.ends_with?(integer, group) ->
          "D3088"

        String.contains?(integer, group <> group) ->
          "D3089"

        required_before_optional?(integer, zero_chars, digit) ->
          "D3090"

        required_after_optional?(fractional, zero_chars, digit) ->
          "D3091"

        exponent_parts != [] and
            (String.contains?(picture, percent) or String.contains?(picture, permille)) ->
          "D3092"

        exponent_parts != [] and
            (Enum.at(exponent_parts, 0) == "" or
               not Enum.all?(String.graphemes(hd(exponent_parts)), &(&1 in zero_chars))) ->
          "D3093"

        true ->
          nil
      end

    if code, do: {:error, Error.new(code, "Invalid number picture")}, else: :ok
  end

  defp format(value, picture, options) do
    {prefix, active, suffix} = picture_parts(picture, options)
    decimal = Map.get(options, "decimal-separator", ".")
    group = Map.get(options, "grouping-separator", ",")
    exponent_sep = Map.get(options, "exponent-separator", "e")
    zero_chars = zero_digits(Map.get(options, "zero-digit", "0"))
    digit = Map.get(options, "digit", "#")
    [mantissa | exponent_picture] = String.split(active, exponent_sep)
    [integer_picture | fraction_picture] = String.split(mantissa, decimal)
    fractional_picture = Enum.at(fraction_picture, 0, "")
    min_integer = count_chars(integer_picture, zero_chars)
    min_fraction = count_chars(fractional_picture, zero_chars)
    max_fraction = min_fraction + occurrences(fractional_picture, digit)

    min_fraction =
      if exponent_picture != [] and min_integer == 0 and max_fraction == 0,
        do: 1,
        else: min_fraction

    max_fraction = max(max_fraction, min_fraction)

    scale =
      cond do
        String.contains?(picture, Map.get(options, "percent", "%")) -> 100
        String.contains?(picture, Map.get(options, "per-mille", "‰")) -> 1000
        true -> 1
      end

    value = value * scale

    {value, exponent_value} =
      if exponent_picture == [] or value == 0 or min_integer == 0 do
        {value, 0}
      else
        target = max(min_integer, 1)
        exponent_value = floor(:math.log10(value)) - target + 1
        {value / :math.pow(10, exponent_value), exponent_value}
      end

    max_fraction = min(max_fraction, 15)
    rounded = Float.round(value * 1.0, max_fraction)
    fixed = :erlang.float_to_binary(rounded, decimals: max_fraction)
    [whole | fraction] = String.split(fixed, ".")
    whole = String.pad_leading(whole, max(min_integer, 1), "0")

    whole =
      if integer_picture == "" and exponent_picture != [] and whole == "0", do: "", else: whole

    fractional =
      Enum.at(fraction, 0, "")
      |> String.trim_trailing("0")
      |> String.pad_trailing(min_fraction, "0")

    whole = group_integer(whole, integer_picture, group)
    fractional = group_fraction(fractional, fractional_picture, group)
    point = if fraction_picture != [] and fractional != "", do: decimal, else: ""

    exponent_text =
      if exponent_picture == [] do
        ""
      else
        width = count_chars(hd(exponent_picture), zero_chars)
        sign = if exponent_value < 0, do: Map.get(options, "minus-sign", "-"), else: ""

        exponent_sep <>
          sign <> String.pad_leading(Integer.to_string(abs(exponent_value)), width, "0")
      end

    number = whole <> point <> fractional <> exponent_text
    prefix <> local_digits(number, zero_chars) <> suffix
  end

  defp picture_parts(picture, options) do
    zero_chars = zero_digits(Map.get(options, "zero-digit", "0"))
    digit = Map.get(options, "digit", "#")
    group = Map.get(options, "grouping-separator", ",")
    decimal = Map.get(options, "decimal-separator", ".")
    active? = fn char -> char in zero_chars or char in [digit, group, decimal] end
    chars = String.graphemes(picture)
    first = Enum.find_index(chars, active?)
    last = chars |> Enum.reverse() |> Enum.find_index(active?)

    if is_nil(first) do
      {picture, "", ""}
    else
      finish = length(chars) - last

      {Enum.take(chars, first) |> Enum.join(),
       chars |> Enum.slice(first, finish - first) |> Enum.join(),
       Enum.drop(chars, finish) |> Enum.join()}
    end
  end

  defp group_integer(value, picture, separator) do
    parts = String.split(picture, separator)

    if length(parts) < 2 do
      value
    else
      positions =
        parts
        |> tl()
        |> Enum.reverse()
        |> Enum.scan(0, fn part, acc -> acc + String.length(part) end)

      interval = hd(positions)

      regular? =
        Enum.with_index(positions, 1) |> Enum.all?(fn {pos, index} -> pos == interval * index end)

      positions =
        if regular?,
          do: Enum.to_list(interval..(String.length(value) - 1)//interval),
          else: positions

      Enum.reduce(positions, value, fn pos, acc ->
        if pos > 0 and pos < String.length(value) do
          {left, right} = String.split_at(acc, String.length(value) - pos)
          left <> separator <> right
        else
          acc
        end
      end)
    end
  end

  defp group_fraction(value, picture, separator) do
    parts = String.split(picture, separator)

    positions =
      parts |> Enum.drop(-1) |> Enum.scan(0, fn part, acc -> acc + String.length(part) end)

    Enum.reduce(Enum.reverse(positions), value, fn pos, acc ->
      if pos > 0 and pos < String.length(value) do
        {left, right} = String.split_at(acc, pos)
        left <> separator <> right
      else
        acc
      end
    end)
  end

  defp zero_digits(zero) do
    [point] = String.to_charlist(zero)
    for offset <- 0..9, do: <<point + offset::utf8>>
  end

  defp local_digits(value, zero_chars) do
    value
    |> String.graphemes()
    |> Enum.map(fn char ->
      if char in ~w(0 1 2 3 4 5 6 7 8 9),
        do: Enum.at(zero_chars, String.to_integer(char)),
        else: char
    end)
    |> Enum.join()
  end

  defp occurrences(text, token), do: length(String.split(text, token)) - 1
  defp count_chars(text, chars), do: Enum.count(String.graphemes(text), &(&1 in chars))

  defp required_before_optional?(text, zero_chars, digit) do
    case String.split(text, digit, parts: 2) do
      [_] -> false
      [before, _] -> Enum.any?(String.graphemes(before), &(&1 in zero_chars))
    end
  end

  defp required_after_optional?(text, zero_chars, digit) do
    case String.split(text, digit) do
      [_] ->
        false

      parts ->
        parts
        |> tl()
        |> Enum.any?(fn part -> Enum.any?(String.graphemes(part), &(&1 in zero_chars)) end)
    end
  end
end
