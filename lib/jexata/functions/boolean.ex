defmodule Jexata.Functions.Boolean do
  @moduledoc false
  alias Jexata.{Error, Semantics}
  alias Jexata.Runtime.Value

  def supported?(name), do: name in ["$boolean", "$not", "$exists"]
  def call("$boolean", [value]), do: {:ok, Semantics.boolean(value)}
  def call("$not", [value]), do: {:ok, not Semantics.boolean(value)}
  def call("$exists", [value]), do: {:ok, not Value.undefined?(value)}
  def call(name, _), do: {:error, Error.new("T0410", "Invalid arguments for #{name}")}
end
