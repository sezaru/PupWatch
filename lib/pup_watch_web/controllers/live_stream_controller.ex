defmodule PupWatchWeb.LiveStreamController do
  @moduledoc """
  Fallback live view for browsers whose WebRTC can't connect (e.g. Firefox with
  `ice.no_host`): go2rtc's fragmented MP4, relayed so its API stays on localhost.
  """
  use PupWatchWeb, :controller

  def show(conn, _params) do
    cam = Application.fetch_env!(:pup_watch, :camera)

    resp =
      Req.get!("#{cam[:go2rtc_url]}/api/stream.mp4",
        params: [src: cam[:go2rtc_mp4_stream]],
        into: :self,
        receive_timeout: 30_000,
        retry: false
      )

    conn =
      conn
      |> put_resp_content_type("video/mp4", nil)
      |> put_resp_header("cache-control", "no-store")
      |> send_chunked(200)

    Enum.reduce_while(resp.body, conn, fn data, conn ->
      case chunk(conn, data) do
        {:ok, conn} -> {:cont, conn}
        {:error, _closed} -> {:halt, conn}
      end
    end)
  end
end
