defmodule PupWatchWeb.ClipController do
  use PupWatchWeb, :controller

  alias PupWatch.{Monitor, Storage}

  def clip(conn, %{"id" => id}), do: serve(conn, id, :clip_path, "video/mp4")
  def thumb(conn, %{"id" => id}), do: serve(conn, id, :thumbnail_path, "image/jpeg")

  defp serve(conn, id, field, type) do
    with {:ok, rec} <- Monitor.get_recording(id),
         path = Storage.path(Map.fetch!(rec, field)),
         {:ok, %{size: size}} <- File.stat(path) do
      conn
      |> put_resp_content_type(type, nil)
      |> put_resp_header("accept-ranges", "bytes")
      |> send_range(path, size, get_req_header(conn, "range"))
    else
      _ -> send_resp(conn, 404, "not found")
    end
  end

  # Browsers seek in <video> with Range requests; without 206 support they can't scrub.
  defp send_range(conn, path, size, ["bytes=" <> spec]) do
    case parse_range(spec, size) do
      {first, last} ->
        conn
        |> put_resp_header("content-range", "bytes #{first}-#{last}/#{size}")
        |> send_file(206, path, first, last - first + 1)

      :error ->
        conn |> put_resp_header("content-range", "bytes */#{size}") |> send_resp(416, "")
    end
  end

  defp send_range(conn, path, _size, _), do: send_file(conn, 200, path)

  defp parse_range(spec, size) do
    case String.split(spec, "-", parts: 2) do
      ["", suffix] -> clamp(size - String.to_integer(suffix), size - 1, size)
      [first, ""] -> clamp(String.to_integer(first), size - 1, size)
      [first, last] -> clamp(String.to_integer(first), String.to_integer(last), size)
      _ -> :error
    end
  rescue
    ArgumentError -> :error
  end

  defp clamp(first, last, size) do
    first = max(first, 0)
    last = min(last, size - 1)
    if first <= last, do: {first, last}, else: :error
  end
end
