defmodule PupWatch.Camera.Onvif do
  @moduledoc "The two PTZ calls we need, as raw SOAP with WS-Security digest auth."

  @step 0.1

  def move(direction) do
    {x, y} =
      case direction do
        :left -> {@step, 0.0}
        :right -> {-@step, 0.0}
        :up -> {0.0, @step}
        :down -> {0.0, -@step}
      end

    with {:ok, token} <- profile_token() do
      call("""
      <RelativeMove xmlns="http://www.onvif.org/ver20/ptz/wsdl">
        <ProfileToken>#{token}</ProfileToken>
        <Translation>
          <PanTilt xmlns="http://www.onvif.org/ver10/schema" x="#{x}" y="#{y}"/>
        </Translation>
      </RelativeMove>
      """)
      |> ok()
    end
  end

  # No GotoHomePosition on the C200 (ActionNotSupported); presets saved in the Tapo app are.
  def presets do
    with {:ok, token} <- profile_token(),
         {:ok, body} <-
           call(
             ~s(<GetPresets xmlns="http://www.onvif.org/ver20/ptz/wsdl"><ProfileToken>#{token}</ProfileToken></GetPresets>)
           ) do
      {:ok, parse_presets(body)}
    end
  end

  def goto_preset(preset) do
    with {:ok, token} <- profile_token() do
      call("""
      <GotoPreset xmlns="http://www.onvif.org/ver20/ptz/wsdl">
        <ProfileToken>#{token}</ProfileToken>
        <PresetToken>#{preset}</PresetToken>
      </GotoPreset>
      """)
      |> ok()
    end
  end

  @doc false
  def parse_presets(body) do
    for [_, token, name] <-
          Regex.scan(~r/Preset token="([^"]+)"[^>]*>\s*<[^>]*Name>([^<]*)</, body),
        do: %{token: token, name: name}
  end

  defp profile_token do
    case :persistent_term.get({__MODULE__, :token}, nil) do
      nil ->
        with {:ok, body} <-
               call(~s(<GetProfiles xmlns="http://www.onvif.org/ver10/media/wsdl"/>)),
             [_, token] <- Regex.run(~r/Profiles[^>]*token="([^"]+)"/, body) do
          :persistent_term.put({__MODULE__, :token}, token)
          {:ok, token}
        else
          {:error, _} = err -> err
          _ -> {:error, :no_profile}
        end

      token ->
        {:ok, token}
    end
  end

  defp ok({:ok, _}), do: :ok
  defp ok(err), do: err

  defp call(body) do
    case Application.fetch_env(:pup_watch, :onvif) do
      {:ok, cfg} ->
        envelope = envelope(body, cfg[:username], cfg[:password])

        case Req.post(cfg[:url],
               body: envelope,
               headers: [{"content-type", "application/soap+xml; charset=utf-8"}],
               receive_timeout: 5_000,
               retry: false
             ) do
          {:ok, %{status: 200, body: resp}} -> {:ok, resp}
          {:ok, %{status: status, body: resp}} -> {:error, {:http, status, fault(resp)}}
          {:error, e} -> {:error, e}
        end

      :error ->
        {:error, :onvif_not_configured}
    end
  end

  defp fault(resp) do
    case Regex.run(~r/<[^>]*Text[^>]*>([^<]+)</, to_string(resp)) do
      [_, text] -> text
      _ -> nil
    end
  end

  @doc false
  def envelope(body, username, password, nonce \\ :crypto.strong_rand_bytes(16), created \\ now()) do
    digest = :crypto.hash(:sha, nonce <> created <> password) |> Base.encode64()

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
      <s:Header>
        <Security s:mustUnderstand="1" xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
          <UsernameToken>
            <Username>#{username}</Username>
            <Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordDigest">#{digest}</Password>
            <Nonce EncodingType="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-soap-message-security-1.0#Base64Binary">#{Base.encode64(nonce)}</Nonce>
            <Created xmlns="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">#{created}</Created>
          </UsernameToken>
        </Security>
      </s:Header>
      <s:Body xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
        #{body}
      </s:Body>
    </s:Envelope>
    """
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
