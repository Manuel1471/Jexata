defmodule Jexata.Functions do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Functions.{Boolean, Numeric}

  def call(name, args, context) do
    args =
      if args == [] and
           name in ["$count", "$abs", "$floor", "$ceil", "$round", "$boolean", "$not", "$exists"],
         do: [context],
         else: args

    cond do
      Numeric.supported?(name) -> Numeric.call(name, args)
      Boolean.supported?(name) -> Boolean.call(name, args)
      true -> {:error, Error.new("T1006", "Unknown function #{name}")}
    end
  end
end
