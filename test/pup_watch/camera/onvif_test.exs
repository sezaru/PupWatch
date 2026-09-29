defmodule PupWatch.Camera.OnvifTest do
  use ExUnit.Case, async: true

  alias PupWatch.Camera.Onvif

  # Worked example from the ONVIF core spec's WS-UsernameToken section.
  test "password digest is base64(sha1(nonce <> created <> password))" do
    nonce = Base.decode64!("LKqI6G/AikKCQrN0zqZFlg==")
    created = "2010-09-16T07:50:45Z"
    xml = Onvif.envelope("<X/>", "admin", "userpassword", nonce, created)

    assert xml =~ ">tuOSpGlFlIXsozq4HFNeeGeFLEI=</Password>"
    assert xml =~ ">LKqI6G/AikKCQrN0zqZFlg==</Nonce>"

    assert xml =~
             "<Created xmlns=\"http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd\">2010-09-16T07:50:45Z</Created>"

    assert xml =~ "<X/>"
  end

  test "parses presets as the C200 returns them" do
    body = """
    <tptz:GetPresetsResponse><tptz:Preset token="1"><tt:Name>sacada</tt:Name>
    <tt:PTZPosition><tt:PanTilt x="-0.41" y="-0.77"/></tt:PTZPosition></tptz:Preset>
    <tptz:Preset token="2"><tt:Name>sofa</tt:Name></tptz:Preset></tptz:GetPresetsResponse>
    """

    assert Onvif.parse_presets(body) == [
             %{token: "1", name: "sacada"},
             %{token: "2", name: "sofa"}
           ]
  end
end
