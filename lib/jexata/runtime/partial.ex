defmodule Jexata.Runtime.Partial do
  @moduledoc false
  @enforce_keys [:function, :arguments]
  defstruct [:function, :arguments]

  defmodule Placeholder do
    @moduledoc false
    defstruct []
  end
end
