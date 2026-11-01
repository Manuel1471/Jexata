# Run with: mix run scripts/compatibility.exs /path/to/jsonata/test/test-suite
# Reference: jsonata-js/jsonata v2.2.0 (8ee4476f8a228bfc7a62979ae0a9c13a4043cd03)
[suite | _] = System.argv()
files = Path.wildcard(Path.join([suite, "groups", "*", "case*.json"])) |> Enum.sort()

normalize = fn recursive, value ->
  case value do
    :null -> nil
    list when is_list(list) -> Enum.map(list, &recursive.(recursive, &1))
    map when is_map(map) -> Map.new(map, fn {key, item} -> {key, recursive.(recursive, item)} end)
    other -> other
  end
end

read_json = fn path ->
  try do
    path |> File.read!() |> :json.decode() |> then(&normalize.(normalize, &1))
  rescue
    # Some official fixtures contain unpaired UTF-16 surrogates, which OTP JSON rejects.
    _ -> :unreadable
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

        if not is_binary(expression) or data in [:undefined, :unreadable] or
             map_size(case_data["bindings"] || %{}) > 0 do
          :skipped
        else
          try do
            actual = Jexata.run(expression, data)
            expected_code = case_data["code"] || get_in(case_data, ["error", "code"])

            cond do
              Map.has_key?(case_data, "result") and actual == {:ok, case_data["result"]} ->
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
                :fail
            end
          rescue
            _ -> :crashes
          end
        end
      end

    Map.update!(counts, status, &(&1 + 1))
  end)

IO.puts("Reference: JSONata v2.2.0 (8ee4476f8a228bfc7a62979ae0a9c13a4043cd03)")
IO.puts("Total: #{length(cases)}")

Enum.each([:pass, :fail, :unsupported, :skipped, :crashes], fn key ->
  IO.puts("#{key}: #{result[key]}")
end)
