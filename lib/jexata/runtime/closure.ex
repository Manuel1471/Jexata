defmodule Jexata.Runtime.Closure do
  @moduledoc false
  @enforce_keys [:parameters, :arity, :body, :environment, :root, :context_value]
  defstruct [
    :parameters,
    :arity,
    :body,
    :environment,
    :root,
    :context_value,
    :signature,
    references: [],
    leaf?: false
  ]
end
