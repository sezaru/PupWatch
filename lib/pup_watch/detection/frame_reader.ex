defmodule PupWatch.Detection.FrameReader do
  @moduledoc """
  Decodes a stream with an ffmpeg Port into fixed-size raw BGR frames and sends
  each to `sink` as `{:frame, binary, {w, h}, mono_ms}`. Restarts ffmpeg with
  backoff and tells the sink `:stream_down` / `:stream_up`.
  """
  use GenServer
  require Logger

  @max_backoff 30_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)

  @impl true
  def init(opts) do
    {w, h} = Keyword.fetch!(opts, :size)

    state = %{
      source: Keyword.fetch!(opts, :source),
      loop?: Keyword.get(opts, :loop, false),
      fps: Keyword.get(opts, :fps, 3),
      w: w,
      h: h,
      frame_bytes: w * h * 3,
      sink: Keyword.fetch!(opts, :sink),
      port: nil,
      buf: <<>>,
      up?: false,
      backoff: 1_000
    }

    Process.flag(:trap_exit, true)
    {:ok, state, {:continue, :open}}
  end

  @impl true
  def handle_continue(:open, s), do: {:noreply, open(s)}

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = s),
    do: {:noreply, cut(%{s | buf: s.buf <> data})}

  def handle_info({port, {:exit_status, code}}, %{port: port} = s) do
    Logger.warning("frame reader: ffmpeg exited #{code}, retrying in #{s.backoff}ms")
    if s.up?, do: send(s.sink, :stream_down)
    Process.send_after(self(), :reopen, s.backoff)
    {:noreply, %{s | port: nil, buf: <<>>, up?: false, backoff: min(s.backoff * 2, @max_backoff)}}
  end

  def handle_info(:reopen, s), do: {:noreply, open(s)}
  def handle_info({:EXIT, _, _}, s), do: {:noreply, s}
  def handle_info(_, s), do: {:noreply, s}

  @impl true
  def terminate(_, %{port: port}) when is_port(port) do
    with {:os_pid, pid} <- Port.info(port, :os_pid), do: System.cmd("kill", ["#{pid}"])
    :ok
  end

  def terminate(_, _), do: :ok

  defp open(s) do
    port =
      Port.open({:spawn_executable, System.find_executable("ffmpeg")}, [
        :binary,
        :exit_status,
        args: args(s)
      ])

    %{s | port: port}
  end

  defp args(s) do
    input =
      cond do
        String.starts_with?(s.source, "rtsp") -> ["-rtsp_transport", "tcp", "-i", s.source]
        s.loop? -> ["-re", "-stream_loop", "-1", "-i", s.source]
        true -> ["-re", "-i", s.source]
      end

    ["-nostdin", "-hide_banner", "-loglevel", "error"] ++
      input ++
      [
        "-an",
        "-vf",
        "fps=#{s.fps},scale=#{s.w}:#{s.h}",
        "-f",
        "rawvideo",
        "-pix_fmt",
        "bgr24",
        "-"
      ]
  end

  defp cut(%{buf: buf, frame_bytes: n} = s) when byte_size(buf) >= n do
    <<frame::binary-size(n), rest::binary>> = buf
    unless s.up?, do: send(s.sink, :stream_up)
    send(s.sink, {:frame, frame, {s.w, s.h}, System.monotonic_time(:millisecond)})
    cut(%{s | buf: rest, up?: true, backoff: 1_000})
  end

  defp cut(s), do: s
end
