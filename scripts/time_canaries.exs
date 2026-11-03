# Run with: mix run scripts/time_canaries.exs
# Recalibrate deliberately with: mix run scripts/time_canaries.exs --write-baseline
baseline_path = Path.join(__DIR__, "time_canaries_baseline.json")
write_baseline? = "--write-baseline" in System.argv()

replacement_input = String.duplicate("ab", 50)
trim_input = String.duplicate("  hello   world\t", 20)
serialize_input = Map.new(1..100, fn n -> {"key#{n}", n} end)
replacement_pattern = ~r/(a)(b)/

canaries = [
  {"number_decimal", 100_000, fn -> Jexata.Functions.Numeric.call("$number", ["12.50"]) end,
   fn -> Float.parse("12.50") end},
  {"trim_ascii", 10_000, fn -> Jexata.Functions.String.call("$trim", [trim_input]) end,
   fn ->
     trim_input
     |> :binary.split([" ", "\t", "\n", "\r", "\v", "\f"], [:global])
     |> Enum.reject(&(&1 == ""))
     |> Enum.join(" ")
   end},
  {"replace_template", 2_000,
   fn ->
     Jexata.Functions.String.call("$replace", [replacement_input, replacement_pattern, "$2-$1-$$"])
   end, fn -> Regex.replace(replacement_pattern, replacement_input, "\\2-\\1-$") end},
  {"serialize_object", 2_000,
   fn -> Jexata.Functions.String.call("$string", [serialize_input]) end,
   fn -> serialize_input |> :json.encode() |> IO.iodata_to_binary() end}
]

gc_count = fn ->
  {_, details} = Process.info(self(), :garbage_collection)
  Keyword.fetch!(details, :minor_gcs)
end

measure = fn operation, iterations ->
  operation.()
  :erlang.garbage_collect(self())
  before_gc = gc_count.()
  {microseconds, _} = :timer.tc(fn -> Enum.each(1..iterations, fn _ -> operation.() end) end)
  after_gc = gc_count.()
  {microseconds / iterations, (after_gc - before_gc) / iterations}
end

measurements =
  Map.new(canaries, fn {name, iterations, candidate, control} ->
    rounds =
      for round <- 1..5 do
        if rem(round, 2) == 1 do
          {candidate_us, minor_gcs} = measure.(candidate, iterations)
          {control_us, _} = measure.(control, iterations)
          {candidate_us / control_us, candidate_us, minor_gcs}
        else
          {control_us, _} = measure.(control, iterations)
          {candidate_us, minor_gcs} = measure.(candidate, iterations)
          {candidate_us / control_us, candidate_us, minor_gcs}
        end
      end

    {name,
     %{
       "ratio" => rounds |> Enum.map(&elem(&1, 0)) |> Enum.sort() |> Enum.at(2),
       "us_per_op" => rounds |> Enum.map(&elem(&1, 1)) |> Enum.sort() |> Enum.at(2),
       "minor_gcs_per_op" => rounds |> Enum.map(&elem(&1, 2)) |> Enum.sort() |> Enum.at(2)
     }}
  end)

if write_baseline? do
  File.write!(baseline_path, [IO.iodata_to_binary(:json.encode(measurements)), "\n"])
end

baselines = baseline_path |> File.read!() |> :json.decode()

failures =
  Enum.reduce(measurements, [], fn {name, result}, failures ->
    ratio = result["ratio"]
    limit = baselines[name]["ratio"] * 2.0

    IO.puts(
      "#{name}: #{Float.round(result["us_per_op"], 3)} µs/op, " <>
        "#{Float.round(result["minor_gcs_per_op"], 4)} minor GCs/op, " <>
        "relative time #{Float.round(ratio, 3)} (limit #{Float.round(limit, 3)})"
    )

    if ratio > limit, do: [name | failures], else: failures
  end)

if failures != [] do
  IO.puts(:stderr, "Time canary budget exceeded: #{Enum.join(Enum.reverse(failures), ", ")}")
  System.halt(1)
end
