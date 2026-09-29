defmodule PupWatch.Storage do
  @moduledoc "Clips, thumbnails and the SQLite db live under one root."

  def root, do: Application.fetch_env!(:pup_watch, :storage_root)

  def path(relative), do: Path.join(root(), relative)

  def clip_path(id), do: "clips/#{id}.mp4"
  def thumbnail_path(id), do: "thumbs/#{id}.jpg"

  def ensure_dirs! do
    for dir <- ["clips", "thumbs"], do: File.mkdir_p!(path(dir))
    :ok
  end
end
