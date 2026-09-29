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

  def names, do: Map.keys(@toggles) ++ [:led, :night_vision, :alarm]

  @doc "Every setting in one round-trip; the ones this camera lacks come back `:unsupported`."
  def all(server \\ Client) do
    reads = Enum.map(names(), &{&1, read(&1)})

    with {:ok, responses} <- Client.request(server, Enum.map(reads, &elem(&1, 1))) do
      {:ok,
       reads
       |> Enum.zip(responses)
       |> Map.new(fn {{name, _}, resp} -> {name, parse(name, resp)} end)}
    end
  end

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
        :led -> get_in(result, ["led", "config", "enabled"])
        :night_vision -> get_in(result, ["image", "common", "inf_type"])
        :alarm -> get_in(result, ["msg_alarm", "chn1_msg_alarm_info", "enabled"])
        _ -> with({_, root, key} <- @toggles[name], do: get_in(result, [root, key, "enabled"]))
      end

    case value do
      "on" -> true
      "off" -> false
      mode when name == :night_vision and mode in @night_modes -> mode
      _ -> :unsupported
    end
  end

  defp parse(_name, _response), do: :unsupported
end
