defmodule PupWatch.Detection.Detector do
  @moduledoc """
  Runs YOLOX on frames from the FrameReader, gated by cheap motion detection, and
  publishes on PubSub "detector": `{:dog_arrived, %{score, thumbnail}}`,
  `{:dog_left, peak}`, `{:status, status}` and `{:detection, box | nil}` with the
  box as `[x, y, w, h]` fractions of the frame.
  """
  use GenServer
  require Logger

  alias PupWatch.Detection.{Gate, Motion, Presence, Yolox}

  @topic "detector"

  def topic, do: @topic

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)

  def status(server \\ __MODULE__) do
    GenServer.call(server, :status)
  catch
    :exit, _ -> %{state: :offline, since: nil}
  end

  @impl true
  def init(opts) do
    presence_opts = Keyword.get(opts, :presence, [])
    # OpenCV's default pool (one thread per core) mostly spins between frames:
    # ~2 cores at 3 fps, against ~0.2 of one core single-threaded.
    Evision.setNumThreads(1)

    {:ok,
     %{
       net: Yolox.load(),
       detect_opts: Keyword.merge(Yolox.default_opts(), Keyword.take(opts, [:threshold])),
       presence: Presence.new(presence_opts),
       presence_opts: presence_opts,
       gate: Gate.new(Keyword.get(opts, :gate, [])),
       prev_signature: nil,
       last_box: nil,
       status: :offline,
       since: DateTime.utc_now()
     }}
  end

  @impl true
  def handle_call(:status, _from, s), do: {:reply, %{state: s.status, since: s.since}, s}

  @impl true
  def handle_info({:frame, _, _, _} = frame, s), do: {:noreply, process(latest(frame), s)}
  def handle_info(:stream_up, s), do: {:noreply, set_status(s, :watching)}

  def handle_info(:stream_down, s) do
    {presence, event} = Presence.reset(s.presence)
    publish(event)
    s = publish_box(s, nil)
    {:noreply, set_status(%{s | presence: presence, prev_signature: nil}, :offline)}
  end

  defp latest(frame) do
    receive do
      {:frame, _, _, _} = newer -> latest(newer)
    after
      0 -> frame
    end
  end

  defp process({:frame, bin, {w, h}, ts}, s) do
    mat = Evision.Mat.from_binary(bin, {:u, 8}, h, w, 3)
    signature = Motion.signature(mat)

    changed =
      if s.prev_signature, do: Motion.changed_fraction(s.prev_signature, signature), else: 1.0

    {run?, gate} = Gate.decide(s.gate, ts, changed, s.presence.phase == :present)
    s = %{s | gate: gate, prev_signature: signature}

    if run?, do: detect(mat, {w, h}, ts, s), else: s
  end

  defp detect(mat, size, ts, s) do
    best = s.net |> Yolox.detect(mat, s.detect_opts) |> List.first()
    s = publish_box(s, best && normalize(best.box, size))
    {presence, event} = Presence.step(s.presence, ts, best)

    case event do
      {:dog_arrived, det} ->
        publish({:dog_arrived, %{score: det.score, thumbnail: thumbnail(mat, det)}})
        set_status(%{s | presence: presence}, :dog_present)

      {:dog_left, _} ->
        publish(event)
        set_status(%{s | presence: presence}, :watching)

      nil ->
        %{s | presence: presence}
    end
  end

  defp normalize({x, y, bw, bh}, {w, h}),
    do: Enum.map([x / w, y / h, bw / w, bh / h], &Float.round(&1 / 1, 4))

  defp publish_box(%{last_box: nil} = s, nil), do: s

  defp publish_box(s, box) do
    publish({:detection, box})
    %{s | last_box: box}
  end

  defp thumbnail(mat, %{box: {x, y, w, h}, score: score}) do
    mat
    |> Evision.rectangle({x, y}, {x + w, y + h}, {0, 200, 255}, thickness: 2)
    |> Evision.putText(
      "dog #{round(score * 100)}%",
      {x, max(y - 6, 12)},
      Evision.Constant.cv_FONT_HERSHEY_SIMPLEX(),
      0.5,
      {0, 200, 255},
      thickness: 1
    )
    |> then(&Evision.imencode(".jpg", &1))
  end

  defp set_status(%{status: status} = s, status), do: s

  defp set_status(s, status) do
    publish({:status, status})
    %{s | status: status, since: DateTime.utc_now()}
  end

  defp publish(nil), do: :ok
  defp publish(msg), do: Phoenix.PubSub.broadcast(PupWatch.PubSub, @topic, msg)
end
