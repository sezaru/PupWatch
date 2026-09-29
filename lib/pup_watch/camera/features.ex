defmodule PupWatch.Camera.Features do
  @moduledoc """
  Tapo-only camera settings (not in ONVIF), as request payloads for the TPAP
  channel. Payload shapes follow pytapo's getters/setters for non-child cameras.
  """

  alias PupWatch.Tapo.Client

  @toggles %{
    auto_track: {"TargetTrackConfig", "target_track", "target_track_info"},
    privacy: {"LensMaskConfig", "lens_mask", "lens_mask_info"},
    motion_detection: {"DetectionConfig", "motion_detection", "motion_det"},
    person_detection: {"PersonDetectionConfig", "people_detection", "detection"},
    pet_detection: {"PetDetectionConfig", "pet_detection", "detection"}
  }

  @night_modes ~w(auto on off)

  @components %{
    method: "getAppComponentList",
    params: %{app_component: %{name: "app_component_list"}}
  }

  @volumes %{
    speaker_volume: {"speaker", "setSpeakerVolume"},
    mic_volume: {"microphone", "setMicrophoneVolume"}
  }

  def names, do: Map.keys(@toggles) ++ [:led, :night_vision, :alarm] ++ Map.keys(@volumes)

  @doc """
  Every setting in one round-trip; the ones this camera lacks come back `:unsupported`.
  `:siren` is `:available` or `:unsupported`.
  """
  def all(server \\ Client) do
    reads = Enum.map(names(), &{&1, read(&1)})
    requests = [@components | Enum.map(reads, &elem(&1, 1))]

    with {:ok, [components | responses]} <- Client.request(server, requests) do
      alarm? = has_alarm?(components)

      settings =
        reads
        |> Enum.zip(responses)
        |> Map.new(fn {{name, _}, resp} -> {name, parse(name, resp)} end)

      # Firmware without the msgAlarm module still answers getLastAlarmInfo with
      # placeholder defaults, but rejects every alarm write and siren command.
      {:ok,
       settings
       |> Map.put(:alarm, if(alarm?, do: settings.alarm, else: :unsupported))
       |> Map.put(:siren, if(alarm?, do: :available, else: :unsupported))}
    end
  end

  defp has_alarm?(%{"result" => %{"app_component" => %{"app_component_list" => list}}}),
    do: Enum.any?(list, &(&1["name"] == "msgAlarm"))

  defp has_alarm?(_), do: false

  def set(server \\ Client, name, value) do
    with {:ok, request} <- write(name, value, server),
         {:ok, %{"error_code" => 0}} <- Client.request(server, request) do
      :ok
    else
      {:ok, %{"error_code" => code}} -> {:error, {:camera, code}}
      err -> err
    end
  end

  def siren(server \\ Client, action) when action in [:start, :stop] do
    case Client.request(server, %{method: "do", msg_alarm: %{manual_msg_alarm: %{action: action}}}) do
      {:ok, %{"error_code" => 0}} -> :ok
      {:ok, %{"error_code" => code}} -> {:error, {:camera, code}}
      err -> err
    end
  end

  # -- payloads -------------------------------------------------------------------

  defp read(name) when is_map_key(@toggles, name) do
    {method, root, key} = @toggles[name]
    %{method: "get" <> method, params: %{root => %{name: [key]}}}
  end

  defp read(:led), do: %{method: "getLedStatus", params: %{led: %{name: ["config"]}}}

  defp read(:night_vision),
    do: %{method: "getLightFrequencyInfo", params: %{image: %{name: "common"}}}

  defp read(name) when is_map_key(@volumes, name) do
    {key, _} = @volumes[name]
    %{method: "getAudioConfig", params: %{audio_config: %{name: [key]}}}
  end

  defp read(:alarm),
    do: %{method: "getLastAlarmInfo", params: %{msg_alarm: %{name: ["chn1_msg_alarm_info"]}}}

  defp write(name, on?, _server) when is_map_key(@toggles, name) and is_boolean(on?) do
    {method, root, key} = @toggles[name]
    {:ok, %{method: "set" <> method, params: %{root => %{key => %{enabled: on_off(on?)}}}}}
  end

  defp write(:led, on?, _server) when is_boolean(on?),
    do: {:ok, %{method: "setLedStatus", params: %{led: %{config: %{enabled: on_off(on?)}}}}}

  defp write(:night_vision, mode, _server) when mode in @night_modes,
    do: {:ok, %{method: "setDayNightModeConfig", params: %{image: %{common: %{inf_type: mode}}}}}

  defp write(name, volume, _server)
       when is_map_key(@volumes, name) and is_integer(volume) and volume in 0..100 do
    {key, method} = @volumes[name]
    {:ok, %{method: method, params: %{audio_config: %{key => %{volume: to_string(volume)}}}}}
  end

  # Keep the camera's own sound/light choice; only flip enabled.
  defp write(:alarm, on?, server) when is_boolean(on?) do
    with {:ok, resp} <- Client.request(server, read(:alarm)) do
      current = get_in(resp, ["result", "msg_alarm", "chn1_msg_alarm_info"]) || %{}

      {:ok,
       %{
         method: "set",
         msg_alarm: %{
           chn1_msg_alarm_info: %{
             alarm_type: current["alarm_type"] || "0",
             light_type: current["light_type"] || "0",
             alarm_mode: current["alarm_mode"] || ["sound"],
             enabled: on_off(on?)
           }
         }
       }}
    end
  end

  defp write(name, value, _server), do: {:error, {:invalid_setting, name, value}}

  defp on_off(true), do: "on"
  defp on_off(false), do: "off"

  # -- responses ------------------------------------------------------------------

  defp parse(name, %{"error_code" => 0, "result" => result}) do
    value =
      case name do
        :led ->
          get_in(result, ["led", "config", "enabled"])

        :night_vision ->
          get_in(result, ["image", "common", "inf_type"])

        :alarm ->
          get_in(result, ["msg_alarm", "chn1_msg_alarm_info", "enabled"])

        name when is_map_key(@volumes, name) ->
          get_in(result, ["audio_config", elem(@volumes[name], 0), "volume"])

        _ ->
          with({_, root, key} <- @toggles[name], do: get_in(result, [root, key, "enabled"]))
      end

    case value do
      "on" -> true
      "off" -> false
      mode when name == :night_vision and mode in @night_modes -> mode
      volume when is_map_key(@volumes, name) and is_binary(volume) -> parse_volume(volume)
      _ -> :unsupported
    end
  end

  defp parse(_name, _response), do: :unsupported

  defp parse_volume(volume) do
    case Integer.parse(volume) do
      {n, ""} -> n
      _ -> :unsupported
    end
  end
end
