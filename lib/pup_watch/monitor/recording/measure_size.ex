defmodule PupWatch.Monitor.Recording.MeasureSize do
  use Ash.Resource.Change

  alias PupWatch.Storage

  @impl true
  def change(changeset, _opts, _context) do
    record = changeset.data

    size =
      [record.clip_path, record.thumbnail_path]
      |> Enum.map(fn rel ->
        case File.stat(Storage.path(rel)) do
          {:ok, %{size: size}} -> size
          _ -> 0
        end
      end)
      |> Enum.sum()

    Ash.Changeset.force_change_attribute(changeset, :size_bytes, size)
  end
end
