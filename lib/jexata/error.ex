defmodule Jexata.Error do
  @moduledoc "A structured compilation or evaluation error."
  defexception [:code, :message, :position]

  @type t :: %__MODULE__{code: String.t(), message: String.t(), position: non_neg_integer() | nil}

  @spec new(String.t(), String.t(), non_neg_integer() | nil) :: t()
  def new(code, message, position \\ nil),
    do: %__MODULE__{code: code, message: message, position: position}
end
