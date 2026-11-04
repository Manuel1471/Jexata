defmodule Jexata.Runtime.Bounded do
  @moduledoc false
  alias Jexata.Error
  alias Jexata.Runtime.LimitedRegex

  @defaults [
    timeout_ms: 1_000,
    max_heap_words: 1_000_000,
    max_result_bytes: 1_000_000,
    max_reductions: nil,
    regex_match_limit: 100_000,
    regex_recursion_limit: 10_000
  ]

  def evaluate(expression, data, options) when is_list(options) do
    with {:ok, limits} <- validate(options) do
      parent = self()
      tag = make_ref()
      bindings = Keyword.get(options, :bindings, %{})
      depth = Keyword.get(options, :max_function_depth, 1024)

      {watcher, monitor} =
        spawn_monitor(fn ->
          watch(parent, tag, expression, data, bindings, depth, limits)
        end)

      receive do
        {^tag, result} ->
          Process.demonitor(monitor, [:flush])
          result

        {:DOWN, ^monitor, :process, ^watcher, reason} ->
          internal_error("Evaluation watcher exited: #{inspect(reason)}")
      end
    end
  end

  def evaluate(_expression, _data, _options),
    do: {:error, Error.new("J0007", "Evaluation limits must be a keyword list")}

  defp watch(parent, tag, expression, data, bindings, depth, limits) do
    Process.flag(:trap_exit, true)
    parent_monitor = Process.monitor(parent)
    watcher = self()

    {worker, worker_monitor} =
      :erlang.spawn_opt(
        fn ->
          result = run_worker(expression, data, bindings, depth, limits)
          send(watcher, {tag, result})
        end,
        [
          :monitor,
          :link,
          {:max_heap_size, %{size: limits.max_heap_words, kill: true, error_logger: false}}
        ]
      )

    await_worker(
      parent,
      tag,
      parent_monitor,
      worker,
      worker_monitor,
      limits,
      System.monotonic_time(:millisecond) + limits.timeout_ms
    )
  end

  defp await_worker(parent, tag, parent_monitor, worker, worker_monitor, limits, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)
    interval = if limits.max_reductions, do: min(remaining, 5), else: remaining

    receive do
      {^tag, result} ->
        send(parent, {tag, result})

      {:DOWN, ^parent_monitor, :process, ^parent, _} ->
        Process.exit(worker, :kill)

      {:DOWN, ^worker_monitor, :process, ^worker, reason} ->
        send(parent, {tag, exit_error(reason)})
    after
      interval ->
        cond do
          remaining == 0 ->
            Process.exit(worker, :kill)
            send(parent, {tag, {:error, Error.new("J1005", "Evaluation timed out")}})

          over_reduction_budget?(worker, limits.max_reductions) ->
            Process.exit(worker, :kill)
            send(parent, {tag, reduction_error()})

          true ->
            await_worker(parent, tag, parent_monitor, worker, worker_monitor, limits, deadline)
        end
    end
  end

  defp over_reduction_budget?(_worker, nil), do: false

  defp over_reduction_budget?(worker, budget) do
    case Process.info(worker, :reductions) do
      {:reductions, count} -> count > budget
      nil -> false
    end
  end

  defp run_worker(expression, data, bindings, depth, limits) do
    try do
      LimitedRegex.install(limits.regex_match_limit, limits.regex_recursion_limit)

      Jexata.evaluate(expression, data, bindings, max_function_depth: depth)
      |> check_result(limits.max_result_bytes)
      |> check_reductions(limits.max_reductions)
    rescue
      error in Error -> {:error, error}
      error -> internal_error(Exception.message(error))
    catch
      kind, reason -> internal_error("#{kind}: #{inspect(reason)}")
    end
  end

  defp validate(options) do
    if Keyword.keyword?(options) do
      allowed = Keyword.keys(@defaults) ++ [:bindings, :max_function_depth]
      unknown = Enum.find(Keyword.keys(options), &(&1 not in allowed))

      cond do
        unknown != nil ->
          {:error, Error.new("J0007", "Unknown bounded evaluation option: #{unknown}")}

        true ->
          limits =
            Map.new(@defaults, fn {name, default} ->
              {name, Keyword.get(options, name, default)}
            end)

          if Enum.all?(limits, fn
               {:max_reductions, nil} -> true
               {_name, value} -> is_integer(value) and value > 0
             end) do
            {:ok, limits}
          else
            {:error, Error.new("J0007", "Evaluation limits must be positive integers")}
          end
      end
    else
      {:error, Error.new("J0007", "Evaluation limits must be a keyword list")}
    end
  end

  defp check_result({:ok, value} = result, max_result_bytes) do
    if :erlang.external_size(value) > max_result_bytes,
      do: {:error, Error.new("J1007", "Evaluation result exceeds size limit")},
      else: result
  end

  defp check_result(result, _max_result_bytes), do: result

  defp check_reductions(result, nil), do: result

  defp check_reductions(result, budget) do
    if over_reduction_budget?(self(), budget), do: reduction_error(), else: result
  end

  defp reduction_error,
    do: {:error, Error.new("J1010", "Evaluation exceeded its reduction budget")}

  defp exit_error(:killed),
    do: {:error, Error.new("J1006", "Evaluation process exceeded its heap")}

  defp exit_error(reason), do: internal_error("Evaluation process exited: #{inspect(reason)}")

  defp internal_error(message),
    do: {:error, Error.new("J1009", "Evaluation failed unexpectedly: " <> message)}
end
