# Evaluate generated cases with: MIX_ENV=prod mix run scripts/differential_eval.exs cases.json
[path] = System.argv()
cases = path |> File.read!() |> :json.decode()

for %{"name" => name, "source" => source, "data" => data} <- cases do
  result =
    try do
      case Jexata.run(source, data) do
        {:ok, :undefined} -> %{kind: "undefined"}
        {:ok, value} -> %{kind: "value", value: value}
        {:error, error} -> %{kind: "error", code: error.code}
      end
    rescue
      error -> %{kind: "crash", message: Exception.message(error)}
    end

  IO.puts(:json.encode(%{name: name, result: result}))
end
