defmodule Jexata do
  @moduledoc """
  Compile JSONata expressions and evaluate them against native Elixir values.

  The implementation is under development. See `README.md` for supported syntax.
  """

  alias Jexata.{Error, Expression}

  @type json ::
          nil | boolean() | number() | String.t() | [json()] | %{optional(String.t()) => json()}

  @doc "Compiles a JSONata source string into an immutable expression."
  @spec compile(String.t()) :: {:ok, Expression.t()} | {:error, Error.t()}
  def compile(source) when is_binary(source) do
    if String.trim(source) == "" do
      {:error, Error.new("S0201", "Expression is empty", 0)}
    else
      {:ok, %Expression{source: source}}
    end
  end

  def compile(_), do: {:error, Error.new("J0001", "Expression must be a string")}

  @doc "Evaluates a compiled expression against JSON-like Elixir data."
  @spec evaluate(Expression.t(), json()) :: {:ok, json()} | {:error, Error.t()}
  def evaluate(%Expression{}, _data),
    do: {:error, Error.new("J0002", "Expression evaluation is not implemented yet")}

  def evaluate(_, _), do: {:error, Error.new("J0003", "Expected a compiled expression")}

  @doc "Compiles and evaluates a JSONata expression in one call."
  @spec run(String.t(), json()) :: {:ok, json()} | {:error, Error.t()}
  def run(source, data) do
    with {:ok, expression} <- compile(source), do: evaluate(expression, data)
  end

  @doc "Like `compile/1`, but raises on errors."
  @spec compile!(String.t()) :: Expression.t()
  def compile!(source), do: unwrap!(compile(source))

  @doc "Like `evaluate/2`, but raises on errors."
  @spec evaluate!(Expression.t(), json()) :: json()
  def evaluate!(expression, data), do: unwrap!(evaluate(expression, data))

  @doc "Like `run/2`, but raises on errors."
  @spec run!(String.t(), json()) :: json()
  def run!(source, data), do: unwrap!(run(source, data))

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, error}), do: raise(error)
end
