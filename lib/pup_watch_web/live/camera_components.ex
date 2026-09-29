defmodule PupWatchWeb.CameraComponents do
  use PupWatchWeb, :html

  @toggles [
    auto_track: "Follow motion",
    privacy: "Privacy mode (lens off)",
    led: "Status LED",
    alarm: "Camera alarm on detection",
    motion_detection: "Camera motion alerts",
    person_detection: "Camera person alerts",
    pet_detection: "Camera pet alerts"
  ]

  def label(:night_vision), do: "night vision"
  def label(name), do: @toggles |> Keyword.fetch!(name) |> String.downcase()

  attr :settings, :any, required: true
  attr :siren, :boolean, required: true

  def camera_settings(assigns) do
    assigns = assign(assigns, toggles: @toggles)

    ~H"""
    <section class="card bg-base-200">
      <div class="card-body gap-3 p-4">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-base">Camera</h2>
          <button
            :if={is_map(@settings) and @settings[:siren] == :available}
            type="button"
            phx-click="siren"
            class={[
              "btn btn-sm",
              if(@siren, do: "btn-error animate-pulse", else: "btn-outline btn-error")
            ]}
          >
            <.icon name="hero-megaphone" class="size-4" /> {if @siren, do: "Stop siren", else: "Siren"}
          </button>
        </div>

        <p :if={is_nil(@settings)} class="text-sm text-base-content/60">
          <span class="loading loading-spinner loading-xs"></span> Connecting to the camera…
        </p>
        <p :if={@settings == :error} class="text-sm text-warning">Camera settings unavailable.</p>

        <div :if={is_map(@settings)} class="grid sm:grid-cols-2 gap-x-6 gap-y-2">
          <label
            :for={{name, text} <- @toggles}
            :if={is_boolean(@settings[name])}
            class="flex items-center justify-between gap-3 cursor-pointer"
          >
            <span class="text-sm">{text}</span>
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@settings[name]}
              phx-click="setting"
              phx-value-name={name}
              phx-value-to={to_string(!@settings[name])}
            />
          </label>

          <div
            :if={is_binary(@settings[:night_vision])}
            class="flex items-center justify-between gap-3"
          >
            <span class="text-sm">Night vision</span>
            <div class="join">
              <button
                :for={mode <- ~w(auto on off)}
                type="button"
                phx-click="setting"
                phx-value-name="night_vision"
                phx-value-to={mode}
                class={["btn btn-xs join-item", @settings[:night_vision] == mode && "btn-primary"]}
              >
                {mode}
              </button>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end
end
