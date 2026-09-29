defmodule PupWatchWeb.LiveLiveTest do
  use PupWatchWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias PupWatchWeb.CameraComponents

  test "clicks before the camera settings load don't crash the page", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    render_click(view, "setting", %{"name" => "led", "to" => "false"})
    assert render(view) =~ "Camera settings unavailable"
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
  end
end
