defmodule Jexata.Functions do
  @moduledoc false
  alias Jexata.{Error, Functions.Numeric}

  def call(name, args) do
    if Numeric.supported?(name) do
      Numeric.call(name, args)
    else
      {:error, Error.new("T1006", "Unknown function #{name}")}
    end
  end
end
