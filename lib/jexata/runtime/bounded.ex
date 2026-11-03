defmodule Jexata.Runtime.Bounded do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.LimitedRegex

  @defaults [
    timeout_ms: 1_000,
    max_heap_words: 1_000_000,
    max_result_bytes: 1_000_000,
    regex_match_limit: 100_000,
    regex_recursion_limit: 10_000
  ]

  def evaluate(expression, data, options) when is_list(options) do
    with {:ok, limits} <- validate(options) do
      parent = self()
      tag = make_ref()
      bindings = Keyword.get(options, :bindings, %{})
      depth = Keyword.get(options, :max_function_depth, 1024)

      {pid, monitor} =
        :erlang.spawn_opt(
          fn ->
            LimitedRegex.install(limits.regex_match_limit, limits.regex_recursion_limit)

            result =
              try do
                Jexata.evaluate(expression, data, bindings, max_function_depth: depth)
              rescue
                error in Error -> {:error, error}
              end

            checked =
              case result do
                {:ok, value} ->
                  if :erlang.external_size(value) > limits.max_result_bytes,
                    do: {:error, Error.new("J1007", "Evaluation result exceeds size limit")},
                    else: result

                _ ->
                  result
              end

            send(parent, {tag, checked})
          end,
          [
            :monitor,
            {:max_heap_size, %{size: limits.max_heap_words, kill: true, error_logger: false}}
          ]
        )

      receive do
        {^tag, result} ->
          Process.demonitor(monitor, [:flush])
          result

        {:DOWN, ^monitor, :process, ^pid, _reason} ->
          {:error, Error.new("J1006", "Evaluation process exceeded its heap or exited")}
      after
        limits.timeout_ms ->
          Process.exit(pid, :kill)

          receive do
            {:DOWN, ^monitor, :process, ^pid, _reason} -> :ok
          after
            1_000 -> :ok
          end

          receive do
            {^tag, _late_result} -> :ok
          after
            0 -> :ok
          end

          {:error, Error.new("J1005", "Evaluation timed out")}
      end
    end
  end

  def evaluate(_expression, _data, _options),
    do: {:error, Error.new("J0007", "Evaluation limits must be a keyword list")}

  defp validate(options) do
    if Keyword.keyword?(options) do
      limits =
        Map.new(@defaults, fn {name, default} -> {name, Keyword.get(options, name, default)} end)

      if Enum.all?(limits, fn {_name, value} -> is_integer(value) and value > 0 end) do
        {:ok, limits}
      else
        {:error, Error.new("J0007", "Evaluation limits must be positive integers")}
      end
    else
      {:error, Error.new("J0007", "Evaluation limits must be a keyword list")}
    end
  end
end
