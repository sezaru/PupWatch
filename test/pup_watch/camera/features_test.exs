defmodule PupWatch.Camera.FeaturesTest do
  use ExUnit.Case, async: true

  alias PupWatch.Camera.Features

  # Stands in for Tapo.Client: records requests, replies from a canned function.
  defmodule FakeCamera do
    use GenServer
    def start_link(reply), do: GenServer.start_link(__MODULE__, reply)
    def init(reply), do: {:ok, {reply, []}}

    def handle_call({:request, req}, _from, {reply, seen}),
      do: {:reply, reply.(req), {reply, [req | seen]}}

    def handle_call(:seen, _from, {_, seen} = s), do: {:reply, Enum.reverse(seen), s}
  end

  test "all/1 batches every read and maps replies, marking missing ones unsupported" do
    {:ok, cam} =
      FakeCamera.start_link(fn reqs ->
        {:ok,
         Enum.map(reqs, fn
           %{method: "getAppComponentList"} ->
             %{
               "error_code" => 0,
               "result" => %{"app_component" => %{"app_component_list" => [%{"name" => "led"}]}}
             }

           %{method: "getLastAlarmInfo"} ->
             %{
               "error_code" => 0,
               "result" => %{"msg_alarm" => %{"chn1_msg_alarm_info" => %{"enabled" => "off"}}}
             }

           %{method: "getTargetTrackConfig"} ->
             %{
               "error_code" => 0,
               "result" => %{"target_track" => %{"target_track_info" => %{"enabled" => "on"}}}
             }

           %{method: "getLedStatus"} ->
             %{"error_code" => 0, "result" => %{"led" => %{"config" => %{"enabled" => "off"}}}}

           %{method: "getAudioConfig", params: %{audio_config: %{name: ["speaker"]}}} ->
             %{
               "error_code" => 0,
               "result" => %{"audio_config" => %{"speaker" => %{"volume" => "70"}}}
             }

           %{method: "getAudioConfig"} ->
             %{
               "error_code" => 0,
               "result" => %{"audio_config" => %{"microphone" => %{"volume" => "100"}}}
             }

           %{method: "getLightFrequencyInfo"} ->
             %{
               "error_code" => 0,
               "result" => %{"image" => %{"common" => %{"inf_type" => "auto"}}}
             }

           _ ->
             %{"error_code" => -40106}
         end)}
      end)

    assert {:ok, settings} = Features.all(cam)
    assert settings.auto_track == true
    assert settings.led == false
    assert settings.night_vision == "auto"
    assert settings.speaker_volume == 70
    assert settings.mic_volume == 100
    assert settings.pet_detection == :unsupported
    # the read answers, but without the msgAlarm module the camera can't act on it
    assert settings.alarm == :unsupported
    assert settings.siren == :unsupported
    assert [batch] = GenServer.call(cam, :seen)
    assert length(batch) == length(Features.names()) + 1
  end

  test "alarm and siren are offered when the camera has the msgAlarm module" do
    {:ok, cam} =
      FakeCamera.start_link(fn reqs ->
        {:ok,
         Enum.map(reqs, fn
           %{method: "getAppComponentList"} ->
             %{
               "error_code" => 0,
               "result" => %{
                 "app_component" => %{"app_component_list" => [%{"name" => "msgAlarm"}]}
               }
             }

           %{method: "getLastAlarmInfo"} ->
             %{
               "error_code" => 0,
               "result" => %{"msg_alarm" => %{"chn1_msg_alarm_info" => %{"enabled" => "on"}}}
             }

           _ ->
             %{"error_code" => -40106}
         end)}
      end)

    assert {:ok, %{alarm: true, siren: :available}} = Features.all(cam)
  end

  test "set/3 builds pytapo's payloads" do
    {:ok, cam} = FakeCamera.start_link(fn _ -> {:ok, %{"error_code" => 0}} end)

    assert :ok = Features.set(cam, :auto_track, true)
    assert :ok = Features.set(cam, :night_vision, "off")
    assert :ok = Features.set(cam, :speaker_volume, 40)
    assert {:error, {:invalid_setting, :mic_volume, 140}} = Features.set(cam, :mic_volume, 140)

    assert {:error, {:invalid_setting, :night_vision, "dim"}} =
             Features.set(cam, :night_vision, "dim")

    assert [
             %{
               method: "setTargetTrackConfig",
               params: %{"target_track" => %{"target_track_info" => %{enabled: "on"}}}
             },
             %{method: "setDayNightModeConfig", params: %{image: %{common: %{inf_type: "off"}}}},
             %{
               method: "setSpeakerVolume",
               params: %{audio_config: %{"speaker" => %{volume: "40"}}}
             }
           ] = GenServer.call(cam, :seen)
  end

  test "camera error codes surface as errors" do
    {:ok, cam} = FakeCamera.start_link(fn _ -> {:ok, %{"error_code" => -40106}} end)
    assert {:error, {:camera, -40106}} = Features.set(cam, :led, true)
    assert {:error, {:camera, -40106}} = Features.siren(cam, :start)
  end
end
