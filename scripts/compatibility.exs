# Run with: mix run scripts/compatibility.exs /path/to/jsonata/test/test-suite
# --case-files-only reproduces the earlier 1,271-case subset.
# Reference: jsonata-js/jsonata v2.2.0 (8ee4476f8a228bfc7a62979ae0a9c13a4043cd03)
[suite | _] = System.argv()

group_filter =
  System.argv()
  |> Enum.find_value(fn arg ->
    if String.starts_with?(arg, "--group="), do: String.replace_prefix(arg, "--group=", "")
  end)

files =
  Path.wildcard(Path.join([suite, "groups", "*", "*.json"]))
  |> Enum.sort()
  |> Enum.filter(fn file ->
    (is_nil(group_filter) or Path.basename(Path.dirname(file)) == group_filter) and
      ("--case-files-only" not in System.argv() or String.starts_with?(Path.basename(file), "case"))
  end)

normalize = fn recursive, value ->
  case value do
    :null -> nil
    list when is_list(list) -> Enum.map(list, &recursive.(recursive, &1))
    map when is_map(map) -> Map.new(map, fn {key, item} -> {key, recursive.(recursive, item)} end)
    other -> other
  end
end

read_json = fn path ->
  source = File.read!(path)

  try do
    source |> :json.decode() |> then(&normalize.(normalize, &1))
  rescue
    _ ->
      # OTP rejects lone UTF-16 surrogates. Keep their escape text inside the
      # JSONata source so the tokenizer can model the invalid string value.
      sanitized =
        Regex.replace(
          ~r/\\uD[89AB][0-9A-F]{2}(?!\\uD[C-F][0-9A-F]{2})|\\uD[C-F][0-9A-F]{2}/i,
          source,
          fn escape -> "\\" <> escape end
        )

      try do
        sanitized |> :json.decode() |> then(&normalize.(normalize, &1))
      rescue
        _ -> :unreadable
      end
  end
end

cases =
  Enum.flat_map(files, fn file ->
    case read_json.(file) do
      list when is_list(list) -> Enum.map(list, &{file, &1})
      value -> [{file, value}]
    end
  end)

result =
  Enum.reduce(cases, %{pass: 0, fail: 0, unsupported: 0, skipped: 0, crashes: 0}, fn {file,
                                                                                      case_data},
                                                                                     counts ->
    status =
      if case_data == :unreadable do
        :skipped
      else
        group = Path.dirname(file)

        expression =
          case Map.fetch(case_data, "expr") do
            {:ok, text} ->
              text

            :error ->
              case Map.fetch(case_data, "expr-file") do
                {:ok, filename} -> File.read!(Path.join(group, filename))
                :error -> nil
              end
          end

        data =
          cond do
            Map.has_key?(case_data, "data") -> case_data["data"]
            case_data["dataset"] == nil -> :undefined
            true -> read_json.(Path.join([suite, "datasets", case_data["dataset"] <> ".json"]))
          end

        if not is_binary(expression) or data == :unreadable do
          :skipped
        else
          try do
            options =
              case case_data["depth"] do
                depth when is_integer(depth) and depth > 0 ->
                  # The reference counts evaluator nodes; recursive closure calls
                  # in this interpreter span approximately three such nodes.
                  [max_function_depth: max(div(depth, 3), 1)]

                _ ->
                  []
              end

            actual = Jexata.run(expression, data, case_data["bindings"] || %{}, options)
            expected_code = case_data["code"] || get_in(case_data, ["error", "code"])

            cond do
              Map.has_key?(case_data, "result") and actual == {:ok, case_data["result"]} ->
                :pass

              case_data["unordered"] == true and
                match?({:ok, values} when is_list(values), actual) and
                is_list(case_data["result"]) and
                  Enum.sort(elem(actual, 1)) == Enum.sort(case_data["result"]) ->
                :pass

              case_data["undefinedResult"] == true and actual == {:ok, :undefined} ->
                :pass

              expected_code && match?({:error, %{code: _}}, actual) &&
                  elem(actual, 1).code == expected_code ->
                :pass

              match?({:error, %{code: "T1006"}}, actual) ->
                :unsupported

              match?({:error, %{code: "S0202"}}, actual) ->
                :unsupported

              true ->
                if "--mismatches" in System.argv(),
                  do:
                    IO.inspect({expression, actual, case_data["result"], expected_code},
                      label: "ACTUAL"
                    )

                :fail
            end
          rescue
            _ -> :crashes
          end
        end
      end

    if status in [:fail, :unsupported] and "--mismatches" in System.argv() do
      IO.inspect({file, case_data["expr"], case_data["result"], case_data["code"], status},
        label: "CASE"
      )
    end

    if "--details" in System.argv() do
      group_name = file |> Path.dirname() |> Path.basename()
      groups = Process.get(:compat_groups, %{})

      group_counts =
        Map.get(groups, group_name, %{pass: 0, fail: 0, unsupported: 0, skipped: 0, crashes: 0})

      Process.put(
        :compat_groups,
        Map.put(groups, group_name, Map.update!(group_counts, status, &(&1 + 1)))
      )
    end

    Map.update!(counts, status, &(&1 + 1))
  end)

IO.puts("Reference: JSONata v2.2.0 (8ee4476f8a228bfc7a62979ae0a9c13a4043cd03)")
IO.puts("Total: #{length(cases)}")

Enum.each([:pass, :fail, :unsupported, :skipped, :crashes], fn key ->
  IO.puts("#{key}: #{result[key]}")
end)

if "--assert-baseline" in System.argv() and group_filter == nil and
     "--case-files-only" not in System.argv() do
  baseline = %{total: 1679, pass: 1319, fail: 204, unsupported: 156}

  if length(cases) != baseline.total or result.pass < baseline.pass or
       result.fail > baseline.fail or result.unsupported > baseline.unsupported or
       result.skipped != 0 or result.crashes != 0 do
    IO.puts(:stderr, "Full reference compatibility baseline regressed")
    System.halt(1)
  end
end

if "--details" in System.argv() do
  Process.get(:compat_groups, %{})
  |> Enum.sort_by(fn {_name, counts} -> -(counts.fail + counts.unsupported) end)
  |> Enum.each(fn {name, counts} -> IO.puts("#{name}: #{inspect(counts)}") end)
end
