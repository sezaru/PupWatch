defmodule PupWatchWeb.PwaTest do
  use PupWatchWeb.ConnCase, async: true

  test "the page links an installable manifest", %{conn: conn} do
    html = conn |> get(~p"/recordings") |> html_response(200)
    assert html =~ ~s(rel="manifest" href="/manifest.webmanifest")

    manifest = build_conn() |> get("/manifest.webmanifest")
    assert manifest.status == 200
    assert %{"display" => "standalone", "icons" => icons} = Jason.decode!(manifest.resp_body)

    for %{"src" => src} <- icons, do: assert(build_conn() |> get(src) |> Map.get(:status) == 200)
    assert build_conn() |> get("/sw.js") |> response_content_type(:javascript)
  end
end
