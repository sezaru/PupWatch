defmodule PupWatch.Pipeline do
  @moduledoc "Camera → detector → recorder. Off in tests, which start pieces directly."
  use Supervisor

  alias PupWatch.Detection.{Detector, FrameReader}

  def start_link(_), do: Supervisor.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    if Application.get_env(:pup_watch, :pipeline, true) do
      cam = Application.fetch_env!(:pup_watch, :camera)
      PupWatch.Storage.ensure_dirs!()

      children = [
        {Detector, []},
        {FrameReader,
         source: cam[:detect_source],
         size: cam[:detect_size],
         fps: cam[:detect_fps],
         sink: Detector},
        {PupWatch.Recorder, source: cam[:record_source]},
        PupWatch.Retention
      ]

      Supervisor.init(children, strategy: :one_for_one)
    else
      :ignore
    end
  end
end
