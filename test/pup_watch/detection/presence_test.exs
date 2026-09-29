defmodule PupWatch.Detection.PresenceTest do
  use ExUnit.Case, async: true

  alias PupWatch.Detection.Presence

  defp run(frames, s \\ Presence.new()) do
    Enum.map_reduce(frames, s, fn {ts, det}, s ->
      {s, ev} = Presence.step(s, ts, det)
      {ev, s}
    end)
  end

  defp dog(score), do: %{score: score}

  test "arrives when a dog is in 2 of the last 3 frames" do
    {events, s} = run([{0, dog(0.6)}, {333, nil}, {666, dog(0.8)}])
    assert events == [nil, nil, {:dog_arrived, dog(0.8)}]
    assert s.phase == :present
    assert s.peak == 0.8
  end

  test "a single-frame flicker does not arrive" do
    {events, s} = run([{0, dog(0.9)}, {333, nil}, {666, nil}, {999, dog(0.9)}, {1332, nil}])
    assert Enum.all?(events, &is_nil/1)
    assert s.phase == :idle
  end

  test "arrival needs the current frame to hold the dog" do
    {events, _} = run([{0, dog(0.9)}, {333, dog(0.9)}])
    assert List.last(events) == {:dog_arrived, dog(0.9)}

    {events, _} = run([{0, dog(0.9)}, {333, nil}, {666, nil}])
    assert Enum.all?(events, &is_nil/1)
  end

  test "leaves 10s after the last sighting, reporting the peak" do
    frames = [
      {0, dog(0.6)},
      {333, dog(0.7)},
      {5_000, dog(0.95)},
      {10_000, nil},
      {14_999, nil},
      {15_000, nil}
    ]

    {events, s} = run(frames)
    assert Enum.at(events, 4) == nil
    assert List.last(events) == {:dog_left, 0.95}
    assert s.phase == :idle
  end

  test "can arrive again after leaving" do
    {_, s} = run([{0, dog(0.6)}, {333, dog(0.6)}, {20_000, nil}])
    assert s.phase == :idle
    {events, _} = run([{21_000, dog(0.7)}, {21_333, dog(0.7)}], s)
    assert List.last(events) == {:dog_arrived, dog(0.7)}
  end

  test "reset leaves when present and is quiet when idle" do
    {_, s} = run([{0, dog(0.6)}, {333, dog(0.9)}])
    assert {%{phase: :idle}, {:dog_left, 0.9}} = Presence.reset(s)
    assert {%{phase: :idle}, nil} = Presence.reset(Presence.new())
  end
end
