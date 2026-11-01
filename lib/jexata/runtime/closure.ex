defmodule Jexata.Runtime.Closure do
  @moduledoc false
  @enforce_keys [:parameters, :body, :environment, :root]
  defstruct [:parameters, :body, :environment, :root, :signature]
end
