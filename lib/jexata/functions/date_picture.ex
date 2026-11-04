defmodule Jexata.Functions.DatePicture do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Functions.IntegerFormat
  alias Jexata.Runtime.Value

  @months ~w(january february march april may june july august september october november december)
  @weekdays ~w(monday tuesday wednesday thursday friday saturday sunday)

  def parse(value, picture) when is_binary(value) and is_binary(picture) do
    with {:ok, tokens} <- tokenize(picture, []),
         {:ok, captures} <- capture_parts(value, tokens),
         {:ok, fields} <- parse_parts(captures, %{}),
         {:ok, millis} <- fields_to_millis(fields) do
      {:ok, millis}
    end
  end

  defp capture_parts(value, tokens) do
    if Enum.all?(tokens, &match?({:text, _}, &1)),
      do: {:ok, nil},
      else: do_capture_parts(value, tokens)
  end

  defp do_capture_parts(value, tokens) do
    {source, markers, _} =
      Enum.reduce(tokens, {"", [], 0}, fn
        {:text, literal}, {source, markers, count} ->
          {source <> Regex.escape(literal), markers, count}

        {:marker, marker}, {source, markers, count} ->
          {source <> "(?<field#{count}>.*?)", [{"field#{count}", marker} | markers], count + 1}
      end)

    case Regex.compile("\\A" <> source <> "\\z", "s") do
      {:ok, regex} ->
        case Regex.named_captures(regex, value) do
          nil ->
            {:ok, nil}

          captures ->
            {:ok,
             Enum.map(Enum.reverse(markers), fn {name, marker} -> {marker, captures[name]} end)}
        end

      _ ->
        {:error, Error.new("D3130", "Invalid date picture")}
    end
  end

  defp parse_parts(nil, _), do: {:ok, nil}

  defp parse_parts(parts, fields) do
    Enum.reduce_while(parts, {:ok, fields}, fn {marker, text}, {:ok, fields} ->
      case parse_part(marker, text) do
        {:ok, :invalid, nil} ->
          {:halt, {:ok, nil}}

        {:ok, :fraction, number} ->
          {:cont,
           {:ok,
            fields |> Map.put(:fraction, number) |> Map.put(:fraction_width, byte_size(text))}}

        {:ok, key, number} ->
          {:cont, {:ok, Map.put(fields, key, number)}}

        {:ok, :ignore} ->
          {:cont, {:ok, fields}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp parse_part(<<component::utf8, picture::binary>>, text) do
    cond do
      component == ?Y and String.starts_with?(picture, "N") ->
        {:error, Error.new("D3133", "Name presentation unavailable for date component")}

      component in [?C, ?E, ?F] ->
        {:ok, :ignore}

      component == ?P ->
        {:ok, :meridiem, String.downcase(text)}

      component in [?Z, ?z] ->
        parse_zone(text)

      component == ?M and String.starts_with?(picture, "N") ->
        parse_name(text, @months, :month)

      component == ?x and String.starts_with?(picture, "N") ->
        parse_name(text, @months, :week_month)

      component in [?Y, ?X, ?M, ?D, ?H, ?h, ?m, ?s, ?f, ?d, ?W, ?w, ?x] ->
        parse_number(component, picture, text)

      true ->
        {:error, Error.new("D3132", "Unknown date picture component")}
    end
  end

  defp parse_name(text, names, key) do
    if text == "", do: {:ok, nil, nil}, else: do_parse_name(text, names, key)
  end

  defp do_parse_name(text, names, key) do
    prefix = String.downcase(text)

    case Enum.find_index(names, &String.starts_with?(&1, prefix)) do
      nil -> {:ok, nil, nil}
      index -> {:ok, key, index + 1}
    end
  end

  defp parse_number(component, picture, text) do
    key =
      %{
        ?Y => :year,
        ?X => :week_year,
        ?M => :month,
        ?D => :day,
        ?H => :hour,
        ?h => :hour12,
        ?m => :minute,
        ?s => :second,
        ?f => :fraction,
        ?d => :yearday,
        ?W => :week,
        ?w => :week_month_number,
        ?x => :week_month
      }[component]

    format = picture |> String.split(",", parts: 2) |> hd()
    format = if format == "", do: "1", else: format
    format = String.trim_leading(format, "#")

    format =
      if String.ends_with?(format, "o"),
        do: String.replace_suffix(format, "o", ";o"),
        else: format

    result =
      if component == ?f do
        case Integer.parse(text) do
          {number, ""} -> {:ok, number}
          _ -> :error
        end
      else
        IntegerFormat.call("$parseInteger", [text, format])
      end

    case result do
      {:ok, number} -> {:ok, key, number}
      _ -> if(text == "", do: {:ok, nil, nil}, else: {:ok, :invalid, nil})
    end
  end

  defp parse_zone(text) do
    normalized = String.replace_prefix(text, "GMT", "")

    case Regex.run(~r/\A([+-])(\d{1,2})(?::?(\d{2}))?\z/, normalized) do
      [_, sign, hour, minutes] ->
        offset = String.to_integer(hour) * 60 + String.to_integer(minutes)
        {:ok, :offset, if(sign == "-", do: -offset, else: offset)}

      [_, sign, hour] ->
        offset = String.to_integer(hour) * 60
        {:ok, :offset, if(sign == "-", do: -offset, else: offset)}

      _ when normalized == "Z" ->
        {:ok, :offset, 0}

      _ ->
        {:ok, nil, nil}
    end
  end

  defp fields_to_millis(nil), do: {:ok, Value.undefined()}

  defp fields_to_millis(fields) do
    incomplete? =
      (Map.has_key?(fields, :day) and not Map.has_key?(fields, :month)) or
        ((Map.has_key?(fields, :day) or Map.has_key?(fields, :month)) and
           not Map.has_key?(fields, :year)) or Map.has_key?(fields, :week_year)

    if incomplete?,
      do: {:error, Error.new("D3136", "Insufficient date components")},
      else: build_millis(fields)
  end

  defp build_millis(fields) do
    now = DateTime.utc_now()
    year = Map.get(fields, :year, now.year)

    time_only? =
      not Enum.any?([:year, :month, :day, :yearday, :week_year], &Map.has_key?(fields, &1))

    date =
      cond do
        Map.has_key?(fields, :yearday) ->
          with {:ok, first} <- Date.new(year, 1, 1),
               date <- Date.add(first, fields.yearday - 1),
               true <- date.year == year,
               do: {:ok, date},
               else: (_ -> :error)

        Map.has_key?(fields, :week_year) and Map.has_key?(fields, :week) ->
          with {:ok, first} <- Date.new(fields.week_year, 1, 4) do
            monday = Date.add(first, 1 - Date.day_of_week(first))
            {:ok, Date.add(monday, (fields.week - 1) * 7 + Map.get(fields, :weekday, 1) - 1)}
          end

        true ->
          Date.new(
            year,
            Map.get(fields, :month, if(time_only?, do: now.month, else: 1)),
            Map.get(fields, :day, if(time_only?, do: now.day, else: 1))
          )
      end

    hour = Map.get(fields, :hour, Map.get(fields, :hour12, 0))
    hour = if Map.get(fields, :meridiem) == "pm" and hour < 12, do: hour + 12, else: hour
    hour = if Map.get(fields, :meridiem) == "am" and hour == 12, do: 0, else: hour
    fraction = Map.get(fields, :fraction, 0)
    fraction_width = Map.get(fields, :fraction_width, 1)

    millis =
      fraction
      |> Integer.to_string()
      |> String.pad_leading(fraction_width, "0")
      |> String.pad_trailing(3, "0")
      |> String.slice(0, 3)
      |> String.to_integer()

    with {:ok, date} <- date,
         {:ok, time} <-
           Time.new(hour, Map.get(fields, :minute, 0), Map.get(fields, :second, 0), millis * 1000),
         {:ok, datetime} <- DateTime.new(date, time, "Etc/UTC") do
      {:ok, DateTime.to_unix(datetime, :millisecond) - Map.get(fields, :offset, 0) * 60_000}
    else
      _ -> {:ok, Value.undefined()}
    end
  end

  def format(millis, picture, timezone \\ "0000") when is_number(millis) and is_binary(picture) do
    with {:ok, offset} <- timezone_offset(timezone),
         {:ok, datetime} <- DateTime.from_unix(trunc(millis), :millisecond),
         {:ok, tokens} <- tokenize(picture, []) do
      local = DateTime.add(datetime, offset * 60, :second)
      date = DateTime.to_date(local)
      time = DateTime.to_time(local)
      context = %{date: date, time: time, offset: offset}

      Enum.reduce_while(tokens, {:ok, []}, fn
        {:text, text}, {:ok, acc} ->
          {:cont, {:ok, [text | acc]}}

        {:marker, marker}, {:ok, acc} ->
          case render(marker, context) do
            {:ok, value} -> {:cont, {:ok, [value | acc]}}
            error -> {:halt, error}
          end
      end)
      |> case do
        {:ok, parts} -> {:ok, parts |> Enum.reverse() |> IO.iodata_to_binary()}
        error -> error
      end
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.new("D3111", "Milliseconds outside supported range")}
    end
  end

  defp tokenize(<<>>, acc), do: {:ok, Enum.reverse(acc)}
  defp tokenize("[[" <> rest, acc), do: tokenize(rest, [{:text, "["} | acc])
  defp tokenize("]]" <> rest, acc), do: tokenize(rest, [{:text, "]"} | acc])

  defp tokenize("[" <> rest, acc) do
    case :binary.match(rest, "]") do
      {index, 1} ->
        marker = binary_part(rest, 0, index) |> String.replace(~r/\s+/, "")
        remaining = binary_part(rest, index + 1, byte_size(rest) - index - 1)
        tokenize(remaining, [{:marker, marker} | acc])

      :nomatch ->
        {:error, Error.new("D3135", "Unclosed date picture marker")}
    end
  end

  defp tokenize(<<char::utf8, rest::binary>>, acc),
    do: tokenize(rest, [{:text, <<char::utf8>>} | acc])

  defp render(<<component::utf8, picture::binary>>, context) do
    cond do
      component in [?Z, ?z] ->
        render_timezone(component, picture, context.offset)

      component in [?C, ?E] ->
        {:ok, "ISO"}

      component == ?P ->
        render_name(picture, if(context.time.hour < 12, do: "am", else: "pm"))

      component == ?M and String.starts_with?(picture, "N") ->
        render_name(picture, Enum.at(@months, context.date.month - 1))

      component == ?F and (picture == "" or String.starts_with?(picture, "N")) ->
        render_name(picture, Enum.at(@weekdays, Date.day_of_week(context.date) - 1))

      component == ?x and String.starts_with?(picture, "N") ->
        week_month = Date.add(context.date, 4 - Date.day_of_week(context.date)).month
        render_name(picture, Enum.at(@months, week_month - 1))

      String.starts_with?(picture, "N") ->
        {:error, Error.new("D3133", "Name presentation unavailable for date component")}

      true ->
        render_number(component, picture, context)
    end
  end

  defp render(<<>>, _), do: {:error, Error.new("D3132", "Empty date picture marker")}

  defp render_name(picture, name) do
    [presentation | widths] = String.split(picture, ",", parts: 2)

    value =
      case presentation do
        "N" -> String.upcase(name)
        "Nn" -> String.capitalize(name)
        _ -> name
      end

    width =
      case widths do
        [part] ->
          case Regex.run(~r/-(\d+)$/, part) do
            [_, digits] -> String.to_integer(digits)
            _ -> nil
          end

        _ ->
          nil
      end

    {:ok, if(width, do: String.slice(value, 0, width), else: value)}
  end

  defp render_number(component, picture, context) do
    date = context.date
    time = context.time
    {week_year, week} = :calendar.iso_week_number({date.year, date.month, date.day})
    week_thursday = Date.add(date, 4 - Date.day_of_week(date))

    value =
      case component do
        ?Y -> date.year
        ?X -> week_year
        ?M -> date.month
        ?D -> date.day
        ?H -> time.hour
        ?h -> if(rem(time.hour, 12) == 0, do: 12, else: rem(time.hour, 12))
        ?m -> time.minute
        ?s -> time.second
        ?f -> div(elem(time.microsecond, 0), 1000)
        ?F -> Date.day_of_week(date)
        ?W -> week
        ?w -> div(week_thursday.day - 1, 7) + 1
        ?d -> Date.diff(date, Date.new!(date.year, 1, 1)) + 1
        _ -> nil
      end

    if value == nil do
      {:error, Error.new("D3132", "Unknown date picture component")}
    else
      numeric_picture(component, value, picture)
    end
  end

  defp numeric_picture(component, value, picture) do
    {raw_format, width} = split_width(picture)
    format = raw_format
    format = if format == "", do: default_format(component), else: format
    format = if format == "0" and component not in [?F], do: "1", else: format

    format =
      if String.starts_with?(format, "#"), do: String.trim_leading(format, "#"), else: format

    format = if format == "", do: "1", else: format

    format =
      if String.ends_with?(format, "o"),
        do: String.replace_suffix(format, "o", ";o"),
        else: format

    {value, format} =
      case width do
        width_text when is_binary(width_text) ->
          max_width =
            case Regex.run(~r/-(\d+)$/, width_text) do
              [_, digits] -> String.to_integer(digits)
              _ -> nil
            end

          min_width =
            case Regex.run(~r/^(\d+)/, width_text) do
              [_, digits] -> String.to_integer(digits)
              _ -> 0
            end

          max_width =
            if max_width == nil and component == ?Y and raw_format == "" and min_width > 0,
              do: min_width,
              else: max_width

          value = if max_width, do: rem(value, Integer.pow(10, max_width)), else: value

          format =
            if max_width || byte_size(format) < min_width,
              do: String.duplicate("0", max(min_width, min(byte_size(format), max_width || 99))),
              else: format

          {value, format}

        _ ->
          {value, format}
      end

    IntegerFormat.call("$formatInteger", [value, format])
  end

  defp split_width(picture) do
    parts = String.split(picture, ",")
    suffix = List.last(parts)

    if length(parts) > 1 and Regex.match?(~r/\A(?:\*|\d+(?:-\d+)?)\z/, suffix) do
      {parts |> Enum.drop(-1) |> Enum.join(","), suffix}
    else
      {picture, nil}
    end
  end

  defp default_format(component) when component in [?m, ?s], do: "01"
  defp default_format(?f), do: "001"
  defp default_format(_), do: "1"

  defp render_timezone(component, picture, offset) do
    if String.replace(picture, ~r/[t:01]/, "") != "" or String.contains?(picture, "010101") do
      {:error, Error.new("D3134", "Invalid timezone picture")}
    else
      sign = if offset < 0, do: "-", else: "+"
      hours = div(abs(offset), 60)
      minutes = rem(abs(offset), 60)
      trailing_z? = String.ends_with?(picture, "t")

      colon? =
        String.contains?(picture, ":") or picture == "" or (picture == "0" and minutes != 0)

      short? = picture == "0"

      hour_text =
        if short?,
          do: Integer.to_string(hours),
          else: String.pad_leading(Integer.to_string(hours), 2, "0")

      minute_text =
        if short? and minutes == 0,
          do: "",
          else:
            if(colon?, do: ":", else: "") <>
              String.pad_leading(Integer.to_string(minutes), 2, "0")

      cond do
        offset == 0 and trailing_z? ->
          {:ok, "Z"}

        true ->
          {:ok, if(component == ?z, do: "GMT", else: "") <> sign <> hour_text <> minute_text}
      end
    end
  end

  defp timezone_offset("0000"), do: {:ok, 0}

  defp timezone_offset(<<sign, h1, h2, m1, m2>>) when sign in [?+, ?-] do
    with {hours, ""} <- Integer.parse(<<h1, h2>>),
         {minutes, ""} <- Integer.parse(<<m1, m2>>),
         true <- hours <= 23 and minutes <= 59 do
      {:ok, if(sign == ?-, do: -1, else: 1) * (hours * 60 + minutes)}
    else
      _ -> {:error, Error.new("D3134", "Invalid timezone offset")}
    end
  end

  defp timezone_offset(_), do: {:error, Error.new("D3134", "Invalid timezone offset")}
end
