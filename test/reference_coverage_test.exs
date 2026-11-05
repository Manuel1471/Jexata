defmodule Jexata.ReferenceCoverageTest do
  use ExUnit.Case, async: false

  @suite System.get_env("JEXATA_REFERENCE_SUITE")

  if @suite do
    test "the complete JSONata v2.2.0 suite exercises the public API" do
      assert File.dir?(@suite), "reference fixture directory is missing: #{@suite}"
      previous_args = System.argv()

      try do
        System.argv([@suite])

        ExUnit.CaptureIO.capture_io(fn ->
          {counts, _bindings} =
            Code.eval_file(Path.expand("../scripts/compatibility.exs", __DIR__))

          send(self(), {:reference_counts, counts})
        end)

        assert_receive {:reference_counts, counts}
        assert counts == %{pass: 1676, fail: 3, unsupported: 0, skipped: 0, crashes: 0}
      after
        System.argv(previous_args)
      end
    end
  else
    @tag skip: "set JEXATA_REFERENCE_SUITE to include the official fixtures in coverage"
    test "reference fixtures are available for coverage" do
      :ok
    end
  end
end
