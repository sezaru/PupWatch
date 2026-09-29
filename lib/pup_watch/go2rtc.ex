defmodule PupWatch.Go2rtc do
  @moduledoc "WebRTC signaling relay: go2rtc's API stays on localhost."

  def webrtc_answer(offer_sdp) do
    cam = Application.fetch_env!(:pup_watch, :camera)

    case Req.post("#{cam[:go2rtc_url]}/api/webrtc",
           params: [src: cam[:go2rtc_stream]],
           json: %{type: "offer", sdp: offer_sdp},
           receive_timeout: 10_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: %{"sdp" => sdp}}} -> {:ok, sdp}
      {:ok, %{status: status, body: body}} -> {:error, {status, body}}
      {:error, e} -> {:error, e}
    end
  end
end
