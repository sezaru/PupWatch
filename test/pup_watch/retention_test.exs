defmodule PupWatch.RetentionTest do
  use PupWatch.DataCase, async: false

  alias PupWatch.{Monitor, Retention, Storage}

  setup do
    Storage.ensure_dirs!()
    :ok
  end

  # Sparse file: reports `bytes` in stat without using the disk.
  defp sized_recording(at, bytes) do
    rec = Monitor.start_recording!(%{started_at: at})
    {:ok, f} = :file.open(Storage.path(rec.clip_path), [:write, :raw])
    {:ok, _} = :file.position(f, bytes)
    :ok = :file.truncate(f)
    :ok = :file.close(f)
    Monitor.finish_recording!(rec, %{})
  end

  test "finishing measures the clip, and old recordings go once over the limit" do
    base = ~U[2026-09-29 10:00:00.000000Z]
    old = sized_recording(base, 600_000_000)
    mid = sized_recording(DateTime.add(base, 60), 600_000_000)
    new = sized_recording(DateTime.add(base, 120), 600_000_000)
    live = Monitor.start_recording!(%{started_at: DateTime.add(base, -600)})
    assert old.size_bytes == 600_000_000

    Monitor.update_settings!(Monitor.settings!(), %{max_storage_gb: 1})
    start_supervised!({Retention, name: :test_retention})
    Retention.enforce(:test_retention)

    remaining = Monitor.recording_history!() |> Enum.map(& &1.id) |> MapSet.new()
    assert MapSet.equal?(remaining, MapSet.new([new.id, live.id]))
    refute File.exists?(Storage.path(old.clip_path))
    refute File.exists?(Storage.path(mid.clip_path))
    assert Monitor.storage_used_bytes() <= 1_000_000_000
  end

  test "recordings from before sizes were tracked get measured at start" do
    rec = Monitor.start_recording!(%{started_at: DateTime.utc_now()})
    File.write!(Storage.path(rec.clip_path), "12345")
    File.write!(Storage.path(rec.thumbnail_path), "12")
    rec = rec |> Ash.Changeset.for_update(:finish) |> Ash.update!()
    Ecto.Adapters.SQL.query!(PupWatch.Repo, "UPDATE recordings SET size_bytes = NULL")

    start_supervised!({Retention, name: :test_retention})
    Retention.enforce(:test_retention)

    assert Monitor.get_recording!(rec.id).size_bytes == 7
  end
end
