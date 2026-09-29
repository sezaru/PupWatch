defmodule PupWatch.Monitor do
  use Ash.Domain, otp_app: :pup_watch

  resources do
    resource PupWatch.Monitor.Recording do
      define :start_recording, action: :start
      define :finish_recording, action: :finish
      define :fail_recording, action: :fail
      define :recording_history, action: :history
      define :recordings_in_progress, action: :in_progress
      define :get_recording, action: :read, get_by: [:id]
      define :delete_recording, action: :destroy
      define :oldest_finished_recordings, action: :oldest_finished
      define :unmeasured_recordings, action: :unmeasured
      define :measure_recording, action: :measure
    end

    resource PupWatch.Monitor.Settings do
      define :update_settings, action: :update
    end

    resource PupWatch.Monitor.Camera do
      define :move_camera, action: :move, args: [:direction]
      define :camera_presets, action: :presets
      define :goto_camera_preset, action: :goto_preset, args: [:token]
      define :camera_status, action: :status
      define :camera_settings, action: :settings
      define :set_camera_setting, action: :set_setting, args: [:name, :value]
      define :camera_siren, action: :siren, args: [:action]
    end
  end

  @doc "The settings row, created with defaults on first use."
  def settings! do
    case Ash.read_first!(PupWatch.Monitor.Settings) do
      nil -> Ash.create!(PupWatch.Monitor.Settings, %{}, action: :create)
      settings -> settings
    end
  end

  @doc "Bytes taken by finished recordings (in-progress ones aren't measured yet)."
  def storage_used_bytes, do: Ash.sum!(PupWatch.Monitor.Recording, :size_bytes) || 0
end
