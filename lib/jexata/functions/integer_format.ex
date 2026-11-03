defmodule Jexata.Functions.IntegerFormat do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.Value

  @few ~w(zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen)
  @ordinals ~w(zeroth first second third fourth fifth sixth seventh eighth ninth tenth eleventh twelfth thirteenth fourteenth fifteenth sixteenth seventeenth eighteenth nineteenth)
  @decades ~w(twenty thirty forty fifty sixty seventy eighty ninety)
  @magnitudes [
    {1_000_000_000_000, "trillion"},
    {1_000_000_000, "billion"},
    {1_000_000, "million"},
    {1_000, "thousand"}
  ]
  @roman [
    {1000, "m"},
    {900, "cm"},
    {500, "d"},
    {400, "cd"},
    {100, "c"},
    {90, "xc"},
    {50, "l"},
    {40, "xl"},
    {10, "x"},
    {9, "ix"},
    {5, "v"},
    {4, "iv"},
    {1, "i"}
  ]
  @digit_starts [0x30, 0x660, 0x6F0, 0xFF10]

  def call(_, [value, _picture]) when is_struct(value, Value.Undefined),
    do: {:ok, Value.undefined()}

  def call("$formatInteger", [value, picture]) when is_number(value) and is_binary(picture) do
    with {:ok, format} <- analyse(picture) do
      number = integer_value(value)
      sign = if number < 0, do: "-", else: ""
      {:ok, sign <> format_integer(abs(number), format)}
    end
  end

  def call("$parseInteger", [value, picture]) when is_binary(value) and is_binary(picture) do
    with {:ok, format} <- analyse(picture), do: parse_integer(value, format)
  end

  def call(name, _), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}

  defp integer_value(value) when is_integer(value), do: value
  defp integer_value(value) when abs(value) < 1.0e15, do: floor(value)

  defp integer_value(value) do
    value
    |> Float.to_string()
    |> decimal_string_integer()
  end

  defp analyse(picture) do
    [primary | modifiers] = String.split(picture, ";")
    ordinal? = modifiers != [] and String.starts_with?(List.last(modifiers), "o")

    case primary do
      "A" -> {:ok, {:letters, :upper}}
      "a" -> {:ok, {:letters, :lower}}
      "I" -> {:ok, {:roman, :upper}}
      "i" -> {:ok, {:roman, :lower}}
      "W" -> {:ok, {:words, :upper, ordinal?}}
      "Ww" -> {:ok, {:words, :title, ordinal?}}
      "w" -> {:ok, {:words, :lower, ordinal?}}
      _ -> analyse_decimal(primary, ordinal?)
    end
  end

  defp analyse_decimal(primary, ordinal?) do
    {zero, mandatory, _optional, separators, _position, mixed?} =
      primary
      |> String.to_charlist()
      |> Enum.reverse()
      |> Enum.reduce({nil, 0, 0, [], 0, false}, fn char,
                                                   {zero, mandatory, optional, separators, pos,
                                                    mixed?} ->
        case digit_start(char) do
          nil when char == ?# ->
            {zero, mandatory, optional + 1, separators, pos + 1, mixed?}

          nil ->
            {zero, mandatory, optional, [{pos, <<char::utf8>>} | separators], pos, mixed?}

          start ->
            {zero || start, mandatory + 1, optional, separators, pos + 1,
             mixed? or (zero != nil and zero != start)}
        end
      end)

    cond do
      mixed? -> {:error, Error.new("D3131", "Mixed digit families in integer picture")}
      mandatory == 0 -> {:error, Error.new("D3130", "Unsupported integer picture")}
      true -> {:ok, {:decimal, zero, mandatory, Enum.reverse(separators), ordinal?}}
    end
  end

  defp digit_start(char), do: Enum.find(@digit_starts, &(char in &1..(&1 + 9)))

  defp format_integer(value, {:letters, casing}) do
    base = if casing == :upper, do: ?A, else: ?a
    letters(value, base, []) |> IO.iodata_to_binary()
  end

  defp format_integer(value, {:roman, casing}) do
    result = roman(value, @roman, []) |> IO.iodata_to_binary()
    if casing == :upper, do: String.upcase(result), else: result
  end

  defp format_integer(value, {:words, casing, ordinal?}) do
    result = words(value, false, ordinal?)

    case casing do
      :upper ->
        String.upcase(result)

      :lower ->
        result

      :title ->
        String.split(result, ~r/(\s+|-)/, include_captures: true)
        |> Enum.map_join(fn word -> if word == "and", do: word, else: String.capitalize(word) end)
    end
  end

  defp format_integer(value, {:decimal, zero, mandatory, separators, ordinal?}) do
    digits = value |> Integer.to_string() |> String.pad_leading(mandatory, "0")
    positions = grouping_positions(separators, byte_size(digits))

    grouped =
      Enum.reduce(positions, digits, fn {position, character}, acc ->
        offset = byte_size(acc) - position

        if offset > 0,
          do:
            binary_part(acc, 0, offset) <>
              character <> binary_part(acc, offset, byte_size(acc) - offset),
          else: acc
      end)

    localized =
      if zero == ?0 do
        grouped
      else
        for <<char::utf8 <- grouped>>, into: "" do
          if char in ?0..?9, do: <<zero + char - ?0::utf8>>, else: <<char::utf8>>
        end
      end

    if ordinal?, do: localized <> ordinal_suffix(value), else: localized
  end

  defp grouping_positions([], _length), do: []

  defp grouping_positions(separators, length) do
    positions = Enum.map(separators, &elem(&1, 0))
    chars = Enum.map(separators, &elem(&1, 1))
    interval = Enum.reduce(positions, &Integer.gcd/2)

    regular? =
      length(Enum.uniq(chars)) == 1 and interval > 0 and
        Enum.sort(positions) == Enum.map(1..length(positions), &(&1 * interval))

    if regular? do
      for position <- interval..(length - 1)//interval, do: {position, hd(chars)}
    else
      separators
    end
    |> Enum.sort_by(&elem(&1, 0), :desc)
  end

  defp ordinal_suffix(value) when rem(value, 100) in 11..13, do: "th"
  defp ordinal_suffix(value), do: %{1 => "st", 2 => "nd", 3 => "rd"}[rem(value, 10)] || "th"

  defp letters(0, _, acc), do: acc

  defp letters(value, base, acc),
    do: letters(div(value - 1, 26), base, [<<base + rem(value - 1, 26)>> | acc])

  defp roman(0, _, acc), do: Enum.reverse(acc)

  defp roman(value, [{size, numeral} | _rest] = all, acc) when value >= size,
    do: roman(value - size, all, [numeral | acc])

  defp roman(value, [_ | rest], acc), do: roman(value, rest, acc)

  defp words(value, previous?, ordinal?) when value < 20 do
    prefix = if previous?, do: " and ", else: ""
    prefix <> Enum.at(if(ordinal?, do: @ordinals, else: @few), value)
  end

  defp words(value, previous?, ordinal?) when value < 100 do
    tens = Enum.at(@decades, div(value, 10) - 2)
    remainder = rem(value, 10)
    prefix = if previous?, do: " and ", else: ""

    cond do
      remainder > 0 -> prefix <> tens <> "-" <> words(remainder, false, ordinal?)
      ordinal? -> prefix <> String.slice(tens, 0..-2//1) <> "ieth"
      true -> prefix <> tens
    end
  end

  defp words(value, previous?, ordinal?) when value < 1_000 do
    prefix = if previous?, do: ", ", else: ""
    base = Enum.at(@few, div(value, 100)) <> " hundred"
    remainder = rem(value, 100)

    cond do
      remainder > 0 -> prefix <> base <> words(remainder, true, ordinal?)
      ordinal? -> prefix <> base <> "th"
      true -> prefix <> base
    end
  end

  defp words(value, previous?, ordinal?) do
    {factor, magnitude} = Enum.find(@magnitudes, fn {factor, _} -> value >= factor end)
    prefix = if previous?, do: ", ", else: ""
    base = words(div(value, factor), false, false) <> " " <> magnitude
    remainder = rem(value, factor)

    cond do
      remainder > 0 -> prefix <> base <> words(remainder, true, ordinal?)
      ordinal? -> prefix <> base <> "th"
      true -> prefix <> base
    end
  end

  defp parse_integer(value, {:letters, casing}) do
    base = if casing == :upper, do: ?A, else: ?a

    number =
      Enum.reduce(String.to_charlist(value), 0, fn char, acc -> acc * 26 + char - base + 1 end)

    {:ok, number}
  end

  defp parse_integer(value, {:roman, _}) do
    {number, _} =
      value
      |> String.upcase()
      |> String.to_charlist()
      |> Enum.reverse()
      |> Enum.reduce({0, 1}, fn char, {sum, max_seen} ->
        digit = %{?M => 1000, ?D => 500, ?C => 100, ?L => 50, ?X => 10, ?V => 5, ?I => 1}[char]
        if digit < max_seen, do: {sum - digit, max_seen}, else: {sum + digit, digit}
      end)

    {:ok, number}
  end

  defp parse_integer(value, {:words, _, _}) do
    lookup = word_values()

    segments =
      value
      |> String.downcase()
      |> String.split(~r/,\s|\sand\s|[\s-]+/, trim: true)
      |> Enum.reduce([0], fn word, [top | rest] ->
        number = Map.fetch!(lookup, word)

        if number < 100 do
          if top >= 1_000, do: [number, top | rest], else: [top + number | rest]
        else
          [top * number | rest]
        end
      end)

    number = Enum.sum(segments)
    {:ok, if(abs(number) > 9_007_199_254_740_991, do: number * 1.0, else: number)}
  end

  defp parse_integer(value, {:decimal, zero, _mandatory, separators, ordinal?}) do
    digits =
      if ordinal?, do: String.slice(value, 0, max(String.length(value) - 2, 0)), else: value

    digits =
      Enum.reduce(separators, digits, fn {_, separator}, acc ->
        String.replace(acc, separator, "")
      end)

    normalized =
      for <<char::utf8 <- digits>>, into: "" do
        if char in zero..(zero + 9), do: <<char - zero + ?0>>, else: <<char::utf8>>
      end

    case Integer.parse(normalized) do
      {number, ""} -> {:ok, number}
      _ -> {:error, Error.new("D3130", "Invalid integer text")}
    end
  end

  defp word_values do
    singles = Map.new(Enum.with_index(@few), fn {word, index} -> {word, index} end)
    ordinals = Map.new(Enum.with_index(@ordinals), fn {word, index} -> {word, index} end)
    tens = Map.new(Enum.with_index(@decades), fn {word, index} -> {word, (index + 2) * 10} end)

    tens_ord =
      Map.new(@decades |> Enum.with_index(), fn {word, index} ->
        {String.slice(word, 0..-2//1) <> "ieth", (index + 2) * 10}
      end)

    magnitudes = Map.new(@magnitudes, fn {value, word} -> {word, value} end)
    magnitude_ord = Map.new(@magnitudes, fn {value, word} -> {word <> "th", value} end)

    Map.merge(singles, ordinals)
    |> Map.merge(tens)
    |> Map.merge(tens_ord)
    |> Map.merge(magnitudes)
    |> Map.merge(magnitude_ord)
    |> Map.merge(%{"hundred" => 100, "hundredth" => 100})
  end

  defp decimal_string_integer(string) do
    case String.split(string, "e") do
      [mantissa, exponent] ->
        {digits, fractional} =
          case String.split(mantissa, ".") do
            [whole, fraction] -> {whole <> fraction, byte_size(fraction)}
            [whole] -> {whole, 0}
          end

        shift = String.to_integer(exponent) - fractional
        String.to_integer(digits <> String.duplicate("0", max(shift, 0)))

      [_] ->
        String.to_integer(hd(String.split(string, ".")))
    end
  end
end
