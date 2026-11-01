defmodule Jexata.Runtime.Transform do
  @moduledoc false
  @enforce_keys [:pattern, :update, :delete, :environment]
  defstruct [:pattern, :update, :delete, :environment]
end
