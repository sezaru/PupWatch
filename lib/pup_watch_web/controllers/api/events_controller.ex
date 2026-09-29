defmodule PupWatchWeb.Api.EventsController do
  @moduledoc """
  Server-Sent Events: `event: dog_arrived` with `{id, started_at, live_url,
  thumbnail_url}` whenever a visit starts recording. A comment line goes out
  every 25 s so proxies (pfSense HAProxy) keep the connection open.
  """
  use PupWatchWeb, :controller

  @keepalive_ms 25_000

  def stream(conn, _params) do
    Phoenix.PubSub.subscribe(PupWatch.PubSub, "recordings:all")

    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      # nginx-style proxies otherwise buffer the stream
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    case chunk(conn, ": connected\n\n") do
      {:ok, conn} -> loop(conn)
      {:error, _} -> conn
    end
  end

  defp loop(conn) do
    receive do
      # Ash names the event after the action: :start creates a recording
      %Phoenix.Socket.Broadcast{event: "start", payload: %{data: rec}} ->
        send_event(conn, "dog_arrived", dog_arrived(rec))
    after
      @keepalive_ms -> send_event(conn, nil, nil)
    end
    |> case do
      {:ok, conn} -> loop(conn)
      {:error, _closed} -> conn
    end
  end

  defp send_event(conn, nil, nil), do: chunk(conn, ": keepalive\n\n")

  defp send_event(conn, name, data),
    do: chunk(conn, "event: #{name}\ndata: #{Jason.encode!(data)}\n\n")

  @doc false
  def dog_arrived(rec) do
    %{
      id: rec.id,
      started_at: rec.started_at,
      peak_confidence: rec.peak_confidence,
      live_url: url(~p"/"),
      thumbnail_url: url(~p"/thumbs/#{rec.id}")
    }
  end
end
