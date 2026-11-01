defmodule Jexata.Runtime.Closure do
  @moduledoc false
  @enforce_keys [:parameters, :body, :environment, :root, :context_value]
  defstruct [:parameters, :body, :environment, :root, :context_value, :signature]
end
