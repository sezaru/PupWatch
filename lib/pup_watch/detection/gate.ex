defmodule PupWatch.Detection.Gate do
  @moduledoc """
  Decides per frame whether to run YOLOX. Pure: timestamps are passed in.

  Always while a dog is present (a sleeping dog doesn't move), for `hot_ms` after
  any motion (so a dog that walks in and stops still gets its 2-of-3 frames), and
  every `heartbeat_ms` regardless, in case motion fell between frames.
  """

  defstruct last_motion_ms: nil,
            last_run_ms: nil,
            threshold: 0.01,
            hot_ms: 5_000,
            heartbeat_ms: 10_000

  def new(opts \\ []), do: struct(__MODULE__, opts)

  @spec decide(%__MODULE__{}, integer(), float(), boolean()) :: {boolean(), %__MODULE__{}}
  def decide(g, ts, changed, present?) do
    g = if changed >= g.threshold, do: %{g | last_motion_ms: ts}, else: g

    run? =
      present? or
        (g.last_motion_ms != nil and ts - g.last_motion_ms < g.hot_ms) or
        g.last_run_ms == nil or
        ts - g.last_run_ms >= g.heartbeat_ms

    {run?, if(run?, do: %{g | last_run_ms: ts}, else: g)}
  end
end
