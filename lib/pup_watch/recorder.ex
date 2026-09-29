defmodule PupWatch.Recorder do
  @moduledoc """
  One mp4 per dog visit: listens to the detector and runs `ffmpeg -c:v copy`
  from the HD stream while the dog is around, capped at `:max_ms` per clip.
  """
  use GenServer
  require Logger

  alias PupWatch.{Monitor, Storage}
  alias PupWatch.Detection.Detector

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    for rec <- Monitor.recordings_in_progress!() do
      Logger.warning("recorder: marking interrupted recording #{rec.id} as failed")
      Monitor.fail_recording!(rec)
    end

    Phoenix.PubSub.subscribe(PupWatch.PubSub, Keyword.get(opts, :topic, Detector.topic()))

    {:ok,
     %{
       source: Keyword.fetch!(opts, :source),
       max_ms: Keyword.get(opts, :max_ms, 5 * 60_000),
       current: nil
     }}
  end

  @impl true
  def handle_info({:dog_arrived, info}, %{current: nil} = s), do: {:noreply, start_clip(s, info)}
  def handle_info({:dog_left, peak}, %{current: %{}} = s), do: {:noreply, stop_clip(s, peak)}

  def handle_info({:roll, id}, %{current: %{rec: %{id: id}} = cur} = s) do
    s = stop_clip(s, cur.peak)
    {:noreply, start_clip(s, %{score: cur.peak, thumbnail: cur.thumbnail})}
  end

  # The stream ended under us. A clean exit still wrote a playable mp4; keep it.
  def handle_info({port, {:exit_status, code}}, %{current: %{port: port} = cur} = s) do
    Logger.warning("recorder: ffmpeg exited #{code} mid-clip #{cur.rec.id}")
    close(cur, cur.peak, code == 0)
    {:noreply, %{s | current: nil}}
  end

  def handle_info(_, s), do: {:noreply, s}

  @impl true
  def terminate(_, %{current: %{} = cur} = s) do
    stop_clip(s, cur.peak)
    :ok
  catch
    _, _ -> :ok
  end

  def terminate(_, _), do: :ok

  defp start_clip(s, %{score: score, thumbnail: jpeg}) do
    rec = Monitor.start_recording!(%{started_at: DateTime.utc_now(), peak_confidence: score})
    File.write!(Storage.path(rec.thumbnail_path), jpeg)

    port =
      Port.open({:spawn_executable, System.find_executable("ffmpeg")}, [
        :binary,
        :exit_status,
        args: args(s.source, Storage.path(rec.clip_path))
      ])

    Process.send_after(self(), {:roll, rec.id}, s.max_ms)
    %{s | current: %{rec: rec, port: port, peak: score, thumbnail: jpeg}}
  end

  defp stop_clip(%{current: cur} = s, peak) do
    Port.command(cur.port, "q")

    clean? =
      receive do
        {port, {:exit_status, code}} when port == cur.port -> code == 0
      after
        15_000 ->
          with {:os_pid, pid} <- Port.info(cur.port, :os_pid), do: System.cmd("kill", ["#{pid}"])
          false
      end

    close(cur, peak, clean?)
    %{s | current: nil}
  end

  defp close(cur, peak, clean?) do
    clip = Storage.path(cur.rec.clip_path)

    if clean? and match?({:ok, %{size: size}} when size > 0, File.stat(clip)),
      do: Monitor.finish_recording!(cur.rec, %{peak_confidence: max(peak, cur.peak)}),
      else: fail(cur.rec)
  end

  defp fail(rec) do
    clip = Storage.path(rec.clip_path)
    if match?({:ok, %{size: 0}}, File.stat(clip)), do: File.rm(clip)
    Monitor.fail_recording!(rec)
  end

  # C200 audio is G.711 A-law, which mp4 can't carry — re-encode just the audio.
  defp args(source, out) do
    input =
      if String.starts_with?(source, "rtsp"),
        do: ["-rtsp_transport", "tcp", "-i", source],
        else: ["-re", "-i", source]

    ["-hide_banner", "-loglevel", "error"] ++
      input ++
      ["-map", "0:v", "-map", "0:a?", "-c:v", "copy", "-c:a", "aac", "-b:a", "32k"] ++
      ["-movflags", "+faststart", "-y", out]
  end
end
