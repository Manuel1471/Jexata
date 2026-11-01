defmodule Jexata.Token do
  @moduledoc false
  @enforce_keys [:type, :value, :position]
  defstruct [:type, :value, :position]

  @type t :: %__MODULE__{type: atom(), value: term(), position: non_neg_integer()}
end
