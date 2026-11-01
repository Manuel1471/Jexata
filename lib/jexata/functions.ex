defmodule Jexata.Functions do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Functions.{Array, Boolean, Numeric, Object, String}

  def call(name, args, context) do
    args =
      if args == [] and
           name in ["$count", "$abs", "$floor", "$ceil", "$round", "$boolean", "$not", "$exists"],
         do: [context],
         else: args

    cond do
      Numeric.supported?(name) -> Numeric.call(name, args)
      Boolean.supported?(name) -> Boolean.call(name, args)
      String.supported?(name) -> String.call(name, args)
      Array.supported?(name) -> Array.call(name, args)
      Object.supported?(name) -> Object.call(name, args)
      true -> {:error, Error.new("T1006", "Unknown function #{name}")}
    end
  end
end
