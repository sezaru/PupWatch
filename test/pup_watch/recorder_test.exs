defmodule PupWatch.RecorderTest do
  use PupWatch.DataCase, async: false

  alias PupWatch.{Fixtures, Monitor, Recorder, Storage}

  @topic "recorder_test"

  setup do
    Storage.ensure_dirs!()
    :ok
  end

  defp start_recorder(source, opts \\ []) do
    start_supervised!({Recorder, [name: :test_recorder, topic: @topic, source: source] ++ opts})
  end

  defp broadcast(msg), do: Phoenix.PubSub.broadcast(PupWatch.PubSub, @topic, msg)

  defp wait_for(fun, tries \\ 100) do
    case fun.() do
      nil when tries > 0 -> Process.sleep(100) && wait_for(fun, tries - 1)
      result -> result
    end
  end

  defp only_recording, do: Monitor.recording_history!() |> Enum.to_list()

  defp by_status(status) do
    fn ->
      case only_recording() do
        [%{status: ^status} = r | _] -> r
        _ -> nil
      end
    end
  end

  test "records a playable clip for a visit" do
    start_recorder(Fixtures.long_video())
    jpeg = File.read!("test/fixtures/dog.jpg")

    broadcast({:dog_arrived, %{score: 0.7, thumbnail: jpeg}})
    assert %{} = wait_for(by_status(:recording))
    Process.sleep(2_500)
    broadcast({:dog_left, 0.91})

    rec = wait_for(by_status(:complete))
    assert rec.peak_confidence == 0.91
    assert File.read!(Storage.path(rec.thumbnail_path)) == jpeg
    assert Fixtures.probe_duration(Storage.path(rec.clip_path)) > 1.5
  end

  test "rolls into a new clip at the cap" do
    start_recorder(Fixtures.long_video(), max_ms: 1_500)
    broadcast({:dog_arrived, %{score: 0.7, thumbnail: "jpg"}})
    Process.sleep(2_500)
    broadcast({:dog_left, 0.7})

    recs =
      wait_for(fn ->
        recs = only_recording()
        if length(recs) >= 2 and Enum.all?(recs, &(&1.status == :complete)), do: recs
      end)

    assert length(recs) >= 2
  end

  test "a clean end of stream keeps the clip" do
    start_recorder(Fixtures.visit_video())
    broadcast({:dog_arrived, %{score: 0.7, thumbnail: "jpg"}})
    rec = wait_for(by_status(:complete), 200)
    assert Fixtures.probe_duration(Storage.path(rec.clip_path)) > 10
  end

  test "a source that dies marks the recording failed" do
    start_recorder("/nonexistent.mp4")
    broadcast({:dog_arrived, %{score: 0.7, thumbnail: "jpg"}})
    assert %{status: :failed} = wait_for(by_status(:failed))
  end

  test "recordings left open by a crash are failed at boot" do
    open = Monitor.start_recording!(%{started_at: DateTime.utc_now()})
    start_recorder(Fixtures.long_video())
    assert Monitor.get_recording!(open.id).status == :failed
  end
end
