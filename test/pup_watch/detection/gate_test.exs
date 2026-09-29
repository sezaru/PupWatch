defmodule PupWatch.Detection.GateTest do
  use ExUnit.Case, async: true

  alias PupWatch.Detection.Gate

  defp run(steps, g \\ Gate.new()) do
    Enum.map_reduce(steps, g, fn {ts, changed, present?}, g ->
      {run?, g} = Gate.decide(g, ts, changed, present?)
      {run?, g}
    end)
  end

  test "idle and still: only the first frame and the heartbeat run" do
    {runs, _} = run(for ts <- 0..12_000//1_000, do: {ts, 0.0, false})
    assert Enum.with_index(runs) |> Enum.filter(&elem(&1, 0)) |> Enum.map(&elem(&1, 1)) == [0, 10]
  end

  test "motion keeps it running for the hot window, then it idles" do
    {runs, _} =
      run([
        {0, 0.0, false},
        {1_000, 0.05, false},
        {3_000, 0.0, false},
        {5_900, 0.0, false},
        {6_100, 0.0, false}
      ])

    assert runs == [true, true, true, true, false]
  end

  test "tiny changes below the threshold don't count as motion" do
    {runs, _} = run([{0, 0.0, false}, {1_000, 0.005, false}, {2_000, 0.0, false}])
    assert runs == [true, false, false]
  end

  test "always runs while a dog is present" do
    {runs, _} =
      run([{0, 0.0, false}, {20_000, 0.0, true}, {20_300, 0.0, true}, {20_600, 0.0, true}])

    assert Enum.all?(runs)
  end
end
