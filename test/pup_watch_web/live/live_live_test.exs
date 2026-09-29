defmodule PupWatchWeb.LiveLiveTest do
  use PupWatchWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PupWatchWeb.CameraComponents

  test "clicks before the camera settings load don't crash the page", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    render_click(view, "setting", %{"name" => "led", "to" => "false"})
    assert render_async(view) =~ "Camera settings unavailable"
  end

  # LiveView lets an input's own `value` override phx-value-value, which is what
  # broke the toggles; the target travels as `to` instead.
  test "toggles carry their target value as phx-value-to" do
    html =
      render_component(&CameraComponents.camera_settings/1,
        settings: %{
          led: true,
          auto_track: false,
          night_vision: "auto",
          pet_detection: :unsupported
        },
        siren: false
      )

    assert html =~ ~r/phx-value-name="led"[^>]*phx-value-to="false"/s
    assert html =~ ~r/phx-value-name="auto_track"[^>]*phx-value-to="true"/s
    assert html =~ ~s(phx-value-to="off")
    refute html =~ "pet alerts"
    refute html =~ "phx-value-value"
    refute html =~ "Siren"
  end

  test "detections are pushed to the video hook", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    send(view.pid, {:detection, [0.1, 0.2, 0.3, 0.4]})
    assert_push_event(view, "detection", %{box: [0.1, 0.2, 0.3, 0.4]})
    send(view.pid, {:detection, nil})
    assert_push_event(view, "detection", %{box: nil})
  end

  test "volume sliders render from the camera's values" do
    html =
      render_component(&CameraComponents.camera_settings/1,
        settings: %{mic_volume: 100, speaker_volume: 70},
        siren: false
      )

    assert html =~ ~r/name="speaker_volume"[^>]*value="70"/s
    assert html =~ ~r/name="mic_volume"[^>]*value="100"/s
  end
end
