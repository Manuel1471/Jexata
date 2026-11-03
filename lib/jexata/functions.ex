defmodule Jexata.Functions do
  @moduledoc false
  alias Jexata.Error

  alias Jexata.Functions.{
    Array,
    Boolean,
    Datetime,
    IntegerFormat,
    NumberFormat,
    Numeric,
    Object,
    String,
    URL
  }

  alias Jexata.Runtime.Value

  @numeric ~w($sum $count $max $min $average $abs $floor $ceil $round $number $sqrt $power $formatBase)
  @boolean ~w($boolean $not $exists)
  @string ~w($string $length $uppercase $lowercase $trim $substring $contains $split $join $substringBefore $substringAfter $replace $pad $match $base64encode $base64decode)
  @array ~w($append $reverse $sort $distinct $zip $shuffle)
  @object ~w($keys $lookup $merge $spread)
  @url ~w($encodeUrl $encodeUrlComponent $decodeUrl $decodeUrlComponent)
  @datetime ~w($toMillis $fromMillis $now $millis)
  @integer_format ~w($formatInteger $parseInteger)
  @builtin_modules [
    {Numeric, @numeric},
    {Boolean, @boolean},
    {String, @string},
    {Array, @array},
    {Object, @object},
    {URL, @url},
    {Datetime, @datetime},
    {IntegerFormat, @integer_format}
  ]
  @module_by_name for {module, names} <- @builtin_modules,
                      name <- names,
                      into: %{},
                      do: {name, module}
  @special_names ~w($type $error $assert $map $filter $reduce $single $each $sift $eval $formatNumber)

  def supported?(name) do
    name in @special_names or Map.has_key?(@module_by_name, name)
  end

  def call(name, args, context) do
    args =
      if args == [] and
           name in [
             "$count",
             "$abs",
             "$floor",
             "$ceil",
             "$round",
             "$number",
             "$sqrt",
             "$boolean",
             "$not",
             "$uppercase",
             "$lowercase",
             "$trim",
             "$string",
             "$fromMillis"
           ],
         do: [context],
         else: args

    cond do
      name == "$error" -> error_function(args)
      name == "$assert" -> assert_function(args)
      name == "$formatNumber" -> NumberFormat.call(args)
      name == "$type" -> type_of(args)
      true -> dispatch_builtin(name, args)
    end
  end

  defp dispatch_builtin(name, args) do
    case Map.fetch(@module_by_name, name) do
      {:ok, module} -> module.call(name, args)
      :error -> {:error, Error.new("T1006", "Unknown function #{name}")}
    end
  end

  defp type_of([value]) do
    result =
      cond do
        Value.undefined?(value) ->
          Value.undefined()

        is_nil(value) ->
          "null"

        is_boolean(value) ->
          "boolean"

        is_number(value) ->
          "number"

        is_binary(value) ->
          "string"

        is_list(value) or is_struct(value, Value.Sequence) ->
          "array"

        is_struct(value, Jexata.Runtime.Closure) or is_struct(value, Jexata.Runtime.Builtin) or
          is_struct(value, Jexata.Runtime.Partial) or is_struct(value, Jexata.Runtime.Transform) or
            is_struct(value, Jexata.Runtime.Composition) ->
          "function"

        is_map(value) ->
          "object"
      end

    {:ok, result}
  end

  defp type_of(_), do: {:error, Error.new("T0410", "Invalid arguments for $type")}

  defp error_function([]), do: {:error, Error.new("D3137", "$error() function evaluated")}

  defp error_function([value]) when is_binary(value),
    do: {:error, Error.new("D3137", value)}

  defp error_function([value]) when is_struct(value, Value.Undefined),
    do: error_function([])

  defp error_function(_), do: {:error, Error.new("T0410", "Invalid arguments for $error")}

  defp assert_function([true]), do: {:ok, Value.undefined()}
  defp assert_function([false]), do: {:error, Error.new("D3141", "$assert() statement failed")}

  defp assert_function([true, message]) when is_binary(message),
    do: {:ok, Value.undefined()}

  defp assert_function([false, message]) when is_binary(message),
    do: {:error, Error.new("D3141", message)}

  defp assert_function(_), do: {:error, Error.new("T0410", "Invalid arguments for $assert")}
end
