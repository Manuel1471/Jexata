defmodule Jexata.Expression do
  @moduledoc "Immutable compiled expression. Its fields are internal implementation details."
  @enforce_keys [:source]
  defstruct [:source, :ast]

  @opaque t :: %__MODULE__{source: String.t(), ast: term()}
end
