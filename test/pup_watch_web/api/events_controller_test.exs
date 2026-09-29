defmodule PupWatchWeb.Api.EventsControllerTest do
  use PupWatch.DataCase, async: false

  alias PupWatch.Monitor

  # Real HTTP: a chunked stream that never ends doesn't fit Plug.Test.
  setup do
    port = 40_000 + :rand.uniform(9_000)
    start_supervised!({Bandit, plug: PupWatchWeb.Endpoint, port: port, ip: {127, 0, 0, 1}})
    %{url: "http://127.0.0.1:#{port}/api/events"}
  end

  test "streams dog_arrived when a recording starts", %{url: url} do
    resp = Req.get!(url, into: :self, receive_timeout: 5_000, retry: false)
    assert resp.status == 200
    assert ["text/event-stream" <> _] = resp.headers["content-type"]

    rec =
      Monitor.start_recording!(%{
        started_at: ~U[2026-09-29 12:00:00.000000Z],
        peak_confidence: 0.87
      })

    body = collect(resp, "")
    assert body =~ ": connected"
    [_, json] = Regex.run(~r/event: dog_arrived\ndata: (.+)\n\n/, body)
    event = Jason.decode!(json)
    assert event["id"] == rec.id
    assert event["peak_confidence"] == 0.87
    assert event["live_url"] =~ ~r{/$}
    assert event["thumbnail_url"] =~ "/thumbs/#{rec.id}"
  end

  defp collect(resp, acc) do
    if acc =~ "dog_arrived" do
      acc
    else
      receive do
        message ->
          case Req.parse_message(resp, message) do
            {:ok, chunks} -> collect(resp, acc <> Enum.map_join(chunks, &chunk_data/1))
            _ -> collect(resp, acc)
          end
      after
        5_000 -> flunk("no dog_arrived event; got: #{inspect(acc)}")
      end
    end
  end

  defp chunk_data({:data, data}), do: data
  defp chunk_data(_), do: ""
end
