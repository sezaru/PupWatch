defmodule PupWatchWeb.RecordingsLiveTest do
  use PupWatchWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PupWatch.{Monitor, Storage}

  defp start!,
    do: Monitor.start_recording!(%{started_at: DateTime.utc_now(), peak_confidence: 0.8})

  test "live page shows status and recent visits, updating as they arrive", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")
    assert html =~ "Detector offline"
    assert html =~ "No visits recorded yet"

    rec = start!()
    assert render(view) =~ ~p"/thumbs/#{rec.id}"

    send(view.pid, {:status, :dog_present})
    assert render(view) =~ "Dog detected"
  end

  test "new and finished recordings stream in", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/recordings")

    rec = start!()
    assert render(view) =~ "REC"

    Monitor.finish_recording!(rec, %{})
    refute render(view) =~ "REC"
    assert render(view) =~ "80% dog"
  end

  test "play opens the player and delete removes the recording + files", %{conn: conn} do
    Storage.ensure_dirs!()
    rec = start!() |> Monitor.finish_recording!(%{})
    File.write!(Storage.path(rec.clip_path), "mp4")

    {:ok, view, _} = live(conn, ~p"/recordings?play=#{rec.id}")
    assert has_element?(view, "#player video[src='/clips/#{rec.id}']")

    view |> element("#player button", "Delete") |> render_click()
    refute has_element?(view, "#player")
    refute has_element?(view, "#recordings-#{rec.id}")
    refute File.exists?(Storage.path(rec.clip_path))
  end

  test "clips honor Range requests", %{conn: conn} do
    Storage.ensure_dirs!()
    rec = start!()
    File.write!(Storage.path(rec.clip_path), "0123456789")

    conn = conn |> put_req_header("range", "bytes=2-5") |> get(~p"/clips/#{rec.id}")
    assert conn.status == 206
    assert conn.resp_body == "2345"
    assert get_resp_header(conn, "content-range") == ["bytes 2-5/10"]

    assert build_conn() |> get(~p"/clips/#{Ecto.UUID.generate()}") |> response(404)
  end
end
