defmodule PupWatch.Monitor.RecordingTest do
  use PupWatch.DataCase, async: false

  alias PupWatch.{Monitor, Storage}

  defp start!(at \\ DateTime.utc_now()),
    do: Monitor.start_recording!(%{started_at: at, peak_confidence: 0.7})

  test "start derives file paths from the id" do
    rec = start!()
    assert rec.status == :recording
    assert rec.clip_path == "clips/#{rec.id}.mp4"
    assert rec.thumbnail_path == "thumbs/#{rec.id}.jpg"
  end

  test "finish and fail close the recording" do
    done = start!() |> Monitor.finish_recording!(%{peak_confidence: 0.93})
    assert done.status == :complete
    assert done.peak_confidence == 0.93
    assert done.ended_at

    failed = start!() |> Monitor.fail_recording!()
    assert failed.status == :failed
    assert [] == Monitor.recordings_in_progress!()
  end

  test "history is newest first with durations, and paginates" do
    base = ~U[2026-09-29 10:00:00.000000Z]

    for i <- 0..4 do
      start!(DateTime.add(base, i * 60)) |> Monitor.finish_recording!(%{})
    end

    page = Monitor.recording_history!(page: [limit: 3])
    assert length(page.results) == 3
    assert page.more?

    starts = Enum.map(page.results, & &1.started_at)
    assert starts == Enum.sort(starts, {:desc, DateTime})
    assert Enum.all?(page.results, &is_integer(&1.duration_seconds))

    next =
      Monitor.recording_history!(
        page: [limit: 3, after: List.last(page.results).__metadata__.keyset]
      )

    assert length(next.results) == 2
  end

  test "destroy removes the clip and thumbnail" do
    Storage.ensure_dirs!()
    rec = start!()
    for rel <- [rec.clip_path, rec.thumbnail_path], do: File.write!(Storage.path(rel), "x")

    Monitor.delete_recording!(rec)

    refute File.exists?(Storage.path(rec.clip_path))
    refute File.exists?(Storage.path(rec.thumbnail_path))
    assert {:error, _} = Monitor.get_recording(rec.id)
  end
end
