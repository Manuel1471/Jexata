defmodule Jexata.Functions do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Functions.{Array, Boolean, Numeric, Object, String}
  alias Jexata.Runtime.Value

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
             "$exists"
           ],
         do: [context],
         else: args

    cond do
      name == "$type" -> type_of(args)
      Numeric.supported?(name) -> Numeric.call(name, args)
      Boolean.supported?(name) -> Boolean.call(name, args)
      String.supported?(name) -> String.call(name, args)
      Array.supported?(name) -> Array.call(name, args)
      Object.supported?(name) -> Object.call(name, args)
      true -> {:error, Error.new("T1006", "Unknown function #{name}")}
    end
  end

  defp type_of([value]) do
    result =
      cond do
        Value.undefined?(value) -> Value.undefined()
        is_nil(value) -> "null"
        is_boolean(value) -> "boolean"
        is_number(value) -> "number"
        is_binary(value) -> "string"
        is_list(value) or is_struct(value, Value.Sequence) -> "array"
        is_struct(value, Jexata.Runtime.Closure) -> "function"
        is_map(value) -> "object"
      end

    {:ok, result}
  end

  defp type_of(_), do: {:error, Error.new("T0410", "Invalid arguments for $type")}
end
