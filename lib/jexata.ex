defmodule Jexata do
  @moduledoc """
  Compile JSONata expressions and evaluate them against native Elixir values.

  See `README.md` and `docs/COMPATIBILITY.md` for supported syntax and known gaps.
  """

  alias Jexata.{Error, Evaluator, Expression, Parser}
  alias Jexata.Runtime.Limits

  @type json ::
          nil | boolean() | number() | String.t() | [json()] | %{optional(String.t()) => json()}

  @type input :: json() | :undefined
  @type result :: json() | :undefined | :function

  @doc "Compiles a JSONata source string into an immutable expression.

  `max_source_bytes`, `max_tokens`, and `max_nesting` may be set as positive integers.
  "
  @spec compile(String.t()) :: {:ok, Expression.t()} | {:error, Error.t()}
  @spec compile(String.t(), keyword()) :: {:ok, Expression.t()} | {:error, Error.t()}
  def compile(source, options \\ [])

  def compile(source, options) when is_binary(source) do
    with {:ok, limits} <- Limits.validate(options),
         true <- String.valid?(source),
         :ok <- Limits.source(source, limits) do
      if String.trim(source) == "" do
        {:error, Error.new("S0201", "Expression is empty", 0)}
      else
        with {:ok, ast} <- Parser.parse(source, limits),
             do: {:ok, %Expression{source: source, ast: ast}}
      end
    else
      false -> {:error, Error.new("J0001", "Expression must be valid UTF-8")}
      error -> error
    end
  end

  def compile(_, _), do: {:error, Error.new("J0001", "Expression must be a string")}

  @doc "Evaluates a compiled expression against JSON-like Elixir data."
  @spec evaluate(Expression.t(), input()) :: {:ok, result()} | {:error, Error.t()}
  def evaluate(expression, data), do: evaluate(expression, data, %{})

  @doc "Evaluates a compiled expression with external variable bindings.

  Binding keys are variable names without the leading `$`, and values are JSON-like Elixir data.
  "
  @spec evaluate(Expression.t(), input(), map()) :: {:ok, result()} | {:error, Error.t()}
  def evaluate(%Expression{ast: nil}, _data, _bindings),
    do: {:error, Error.new("J0003", "Expected a compiled expression")}

  def evaluate(%Expression{ast: ast}, data, bindings) when is_map(bindings) do
    if Enum.all?(bindings, fn {name, _} ->
         is_binary(name) and name != "" and not String.starts_with?(name, "$")
       end) do
      environment = Map.new(bindings, fn {name, value} -> {"$" <> name, value} end)

      with {:ok, value} <- Evaluator.evaluate(ast, data, environment),
           do: {:ok, Jexata.Runtime.Value.public(value)}
    else
      {:error, Error.new("J0005", "Bindings must use names without a leading $")}
    end
  end

  def evaluate(_, _, _), do: {:error, Error.new("J0003", "Expected a compiled expression")}

  @doc "Evaluates with a positive `:max_function_depth` limit for recursive calls."
  @spec evaluate(Expression.t(), input(), map(), keyword()) ::
          {:ok, result()} | {:error, Error.t()}
  def evaluate(%Expression{ast: ast}, data, bindings, options)
      when is_map(bindings) and is_list(options) do
    max_depth = Keyword.get(options, :max_function_depth, 1024)

    cond do
      not (is_integer(max_depth) and max_depth > 0) ->
        {:error, Error.new("J0006", "max_function_depth must be a positive integer")}

      not Enum.all?(bindings, fn {name, _} ->
        is_binary(name) and name != "" and not String.starts_with?(name, "$")
      end) ->
        {:error, Error.new("J0005", "Bindings must use names without a leading $")}

      true ->
        environment = Map.new(bindings, fn {name, value} -> {"$" <> name, value} end)

        with {:ok, value} <- Evaluator.evaluate(ast, data, environment, max_depth),
             do: {:ok, Jexata.Runtime.Value.public(value)}
    end
  end

  def evaluate(_, _, _, _), do: {:error, Error.new("J0003", "Expected a compiled expression")}

  @doc "Compiles and evaluates a JSONata expression in one call."
  @spec run(String.t(), input()) :: {:ok, result()} | {:error, Error.t()}
  def run(source, data) do
    with {:ok, expression} <- compile(source), do: evaluate(expression, data)
  end

  @doc "Compiles and evaluates an expression with external variable bindings."
  @spec run(String.t(), input(), map()) :: {:ok, result()} | {:error, Error.t()}
  def run(source, data, bindings) do
    with {:ok, expression} <- compile(source), do: evaluate(expression, data, bindings)
  end

  @doc "Compiles and evaluates with external bindings and evaluation options."
  @spec run(String.t(), input(), map(), keyword()) :: {:ok, result()} | {:error, Error.t()}
  def run(source, data, bindings, options) do
    with {:ok, expression} <- compile(source), do: evaluate(expression, data, bindings, options)
  end

  @doc "Like `compile/1`, but raises on errors."
  @spec compile!(String.t()) :: Expression.t()
  def compile!(source), do: unwrap!(compile(source))

  @doc "Like `evaluate/2`, but raises on errors."
  @spec evaluate!(Expression.t(), input()) :: result()
  def evaluate!(expression, data), do: unwrap!(evaluate(expression, data))

  @doc "Like `run/2`, but raises on errors."
  @spec run!(String.t(), input()) :: result()
  def run!(source, data), do: unwrap!(run(source, data))

  defp unwrap!({:ok, value}), do: value
  defp unwrap!({:error, error}), do: raise(error)
end
