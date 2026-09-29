defmodule PupWatch.Detection.Presence do
  @moduledoc """
  Turns per-frame detections into arrive/leave events. Pure: the caller passes
  monotonic timestamps, so it never reads the clock.
  """

  defstruct phase: :idle,
            recent: [],
            peak: 0.0,
            last_seen_ms: nil,
            arrive_hits: 2,
            arrive_window: 3,
            leave_after_ms: 10_000

  @type detection :: %{score: float()} | nil
  @type event :: {:dog_arrived, map()} | {:dog_left, float()} | nil

  def new(opts \\ []), do: struct(__MODULE__, opts)

  @spec step(%__MODULE__{}, integer(), detection) :: {%__MODULE__{}, event}
  def step(%{phase: :idle} = s, _ts, nil),
    do: {%{s | recent: Enum.take([nil | s.recent], s.arrive_window)}, nil}

  def step(%{phase: :idle} = s, ts, det) do
    recent = Enum.take([det | s.recent], s.arrive_window)

    if Enum.count(recent, & &1) >= s.arrive_hits do
      peak = recent |> Enum.reject(&is_nil/1) |> Enum.map(& &1.score) |> Enum.max()
      {%{s | phase: :present, recent: [], peak: peak, last_seen_ms: ts}, {:dog_arrived, det}}
    else
      {%{s | recent: recent}, nil}
    end
  end

  def step(%{phase: :present} = s, ts, nil) do
    if ts - s.last_seen_ms >= s.leave_after_ms,
      do: leave(s),
      else: {s, nil}
  end

  def step(%{phase: :present} = s, ts, det),
    do: {%{s | peak: max(s.peak, det.score), last_seen_ms: ts}, nil}

  @doc "Force a leave (e.g. the stream died)."
  def reset(%{phase: :present} = s), do: leave(s)
  def reset(s), do: {%{s | recent: []}, nil}

  defp leave(s),
    do: {%{s | phase: :idle, recent: [], peak: 0.0, last_seen_ms: nil}, {:dog_left, s.peak}}
end
