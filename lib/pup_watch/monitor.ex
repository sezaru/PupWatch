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
end
