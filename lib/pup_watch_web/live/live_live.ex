defmodule PupWatchWeb.LiveLive do
  use PupWatchWeb, :live_view

  import PupWatchWeb.RecordingComponents
  import PupWatchWeb.CameraComponents

  alias PupWatch.{Go2rtc, Monitor}
  alias PupWatch.Detection.Detector

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(PupWatch.PubSub, Detector.topic())
      PupWatchWeb.Endpoint.subscribe("recordings:all")
    end

    status = Monitor.camera_status!()

    {:ok,
     socket
     |> assign(page_title: "PupWatch", status: status.state, since: status.since)
     |> assign(presets: if(connected?(socket), do: presets(), else: []))
     |> assign(settings: nil, siren: false)
     |> then(&if(connected?(&1), do: load_settings(&1), else: &1))
     |> load_recent()}
  end

  defp presets do
    case Monitor.camera_presets() do
      {:ok, presets} -> presets
      _ -> []
    end
  end

  defp load_settings(socket),
    do: start_async(socket, :settings, fn -> Monitor.camera_settings!() end)

  defp load_recent(socket),
    do: assign(socket, recent: Monitor.recording_history!(page: [limit: 6]).results)

  @impl true
  def handle_event("webrtc_offer", %{"sdp" => sdp}, socket) do
    case Go2rtc.webrtc_answer(sdp) do
      {:ok, answer} -> {:reply, %{sdp: answer}, socket}
      {:error, reason} -> {:reply, %{error: inspect(reason)}, socket}
    end
  end

  def handle_event("move", %{"dir" => dir}, socket) when dir in ~w(up down left right),
    do: {:noreply, ptz(socket, Monitor.move_camera(String.to_existing_atom(dir)))}

  def handle_event("preset", %{"token" => token}, socket),
    do: {:noreply, ptz(socket, Monitor.goto_camera_preset(token))}

  def handle_event(
        "setting",
        %{"name" => name, "to" => value},
        %{assigns: %{settings: %{}}} = socket
      ) do
    name = String.to_existing_atom(name)

    shown =
      cond do
        value in ~w(true false) -> value == "true"
        match?({_, ""}, Integer.parse(value)) -> String.to_integer(value)
        true -> value
      end

    {:noreply,
     socket
     |> update(:settings, &Map.put(&1, name, shown))
     |> start_async({:set, name}, fn -> Monitor.set_camera_setting(name, value) end)}
  end

  def handle_event("setting", _, socket), do: {:noreply, socket}

  def handle_event("volume", %{"_target" => [key]} = params, socket)
      when key in ~w(speaker_volume mic_volume),
      do: handle_event("setting", %{"name" => key, "to" => params[key]}, socket)

  def handle_event("siren", _, socket) do
    action = if socket.assigns.siren, do: :stop, else: :start

    {:noreply,
     socket
     |> assign(siren: action == :start)
     |> start_async(:siren, fn -> Monitor.camera_siren(action) end)}
  end

  def handle_event("talk_unavailable", _, socket),
    do:
      {:noreply,
       put_flash(
         socket,
         :error,
         "Talking needs the HTTPS address — browsers only allow the mic on secure pages."
       )}

  def handle_event("talk_needs_webrtc", _, socket),
    do:
      {:noreply,
       put_flash(
         socket,
         :error,
         "Talking needs a WebRTC connection, which this browser couldn't make."
       )}

  def handle_event("rtc_stats", stats, socket) do
    Logger.info("rtc_stats " <> Jason.encode!(stats))
    {:noreply, socket}
  end

  def handle_event("mic_denied", _, socket),
    do: {:noreply, put_flash(socket, :error, "Microphone permission was denied.")}

  def handle_event("play", %{"id" => id}, socket),
    do: {:noreply, push_navigate(socket, to: ~p"/recordings?play=#{id}")}

  defp ptz(socket, {:ok, _}), do: socket

  defp ptz(socket, {:error, e}),
    do: put_flash(socket, :error, "Camera didn't move: #{Exception.message(e)}")

  @impl true
  def handle_async(:settings, {:ok, settings}, socket),
    do: {:noreply, assign(socket, settings: settings)}

  def handle_async(:settings, {:exit, reason}, socket) do
    Logger.warning("camera settings: #{inspect(reason)}")
    {:noreply, assign(socket, settings: :error)}
  end

  def handle_async({:set, _name}, {:ok, {:ok, _}}, socket), do: {:noreply, socket}

  # Roll the optimistic change back to what the camera actually has.
  def handle_async({:set, name}, result, socket) do
    Logger.warning("camera setting #{name}: #{inspect(result)}")

    {:noreply,
     socket
     |> put_flash(:error, "The camera didn't accept the #{label(name)} change.")
     |> load_settings()}
  end

  def handle_async(:siren, {:ok, {:ok, _}}, socket), do: {:noreply, socket}

  def handle_async(:siren, result, socket) do
    Logger.warning("camera siren: #{inspect(result)}")
    {:noreply, socket |> assign(siren: false) |> put_flash(:error, "The siren didn't respond.")}
  end

  @impl true
  def handle_info({:status, status}, socket),
    do: {:noreply, assign(socket, status: status, since: DateTime.utc_now())}

  def handle_info({:detection, box}, socket),
    do: {:noreply, push_event(socket, "detection", %{box: box})}

  def handle_info({:dog_arrived, _}, socket),
    do: {:noreply, push_event(socket, "dog_arrived", %{})}

  def handle_info({:dog_left, _}, socket),
    do: {:noreply, push_event(socket, "dog_left", %{})}

  def handle_info(%Phoenix.Socket.Broadcast{topic: "recordings:all"}, socket),
    do: {:noreply, load_recent(socket)}

  def handle_info(_, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="relative rounded-box overflow-hidden bg-black aspect-video">
        <div id="live-video" phx-hook="LiveVideo" phx-update="ignore" class="absolute inset-0">
          <video autoplay playsinline muted class="w-full h-full object-contain"></video>
          <div data-connecting class="absolute inset-0 grid place-items-center text-white/70 text-sm">
            Connecting…
          </div>
          <div class="absolute bottom-3 left-3 flex gap-2">
            <button type="button" data-speaker class="btn btn-circle btn-sm" title="Camera sound">
              <span class="hero-speaker-x-mark size-5"></span>
            </button>
          </div>
          <div class="absolute bottom-3 inset-x-0 flex justify-center pointer-events-none">
            <button
              type="button"
              data-talk
              class="btn btn-primary rounded-full select-none touch-none pointer-events-auto"
            >
              <span class="hero-microphone size-5"></span> <span data-talk-label>Hold to talk</span>
            </button>
          </div>
        </div>

        <div class="absolute top-3 right-3 pointer-events-none">
          <span :if={@status == :dog_present} class="badge badge-error gap-1 animate-pulse">
            <span class="hero-video-camera-mini size-4"></span>
            Dog detected · REC
            <span id="rec-elapsed" phx-hook="Elapsed" data-since={DateTime.to_iso8601(@since)}></span>
          </span>
          <span :if={@status == :watching} class="badge badge-neutral gap-1">
            <span class="hero-eye-mini size-4"></span> Watching
          </span>
          <span :if={@status == :offline} class="badge badge-warning gap-1">
            <span class="hero-signal-slash-mini size-4"></span> Detector offline
          </span>
        </div>

        <div class="absolute bottom-3 right-3 grid grid-cols-3 gap-1">
          <span></span>
          <.pad dir="up" icon="hero-chevron-up" />
          <span></span>
          <.pad dir="left" icon="hero-chevron-left" />
          <span></span>
          <.pad dir="right" icon="hero-chevron-right" />
          <span></span>
          <.pad dir="down" icon="hero-chevron-down" />
          <span></span>
        </div>
      </div>

      <div class="flex flex-wrap gap-2">
        <button
          :for={p <- @presets}
          type="button"
          phx-click="preset"
          phx-value-token={p.token}
          class="btn btn-sm btn-soft"
        >
          <.icon name="hero-map-pin" class="size-4" /> {p.name}
        </button>
        <div id="dog-alarm" phx-hook="DogAlarm" phx-update="ignore" class="ml-auto flex gap-2">
          <button type="button" data-stop class="btn btn-sm btn-error animate-pulse hidden">
            <span class="hero-speaker-x-mark size-4"></span> Stop alarm
          </button>
          <button type="button" data-toggle class="btn btn-sm btn-soft">
            <span class="hero-bell-slash size-4"></span> Dog alarm off
          </button>
        </div>
      </div>

      <.camera_settings settings={@settings} siren={@siren} />

      <section class="space-y-3">
        <div class="flex items-baseline justify-between">
          <h2 class="text-lg font-semibold">Latest visits</h2>
          <.link navigate={~p"/recordings"} class="link link-hover text-sm">All recordings →</.link>
        </div>
        <p :if={@recent == []} class="text-base-content/60 text-sm">No visits recorded yet.</p>
        <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
          <.recording_card :for={r <- @recent} recording={r} phx-click="play" phx-value-id={r.id} />
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :dir, :string, required: true
  attr :icon, :string, required: true

  defp pad(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="move"
      phx-value-dir={@dir}
      class="btn btn-circle btn-sm opacity-80"
    >
      <.icon name={@icon} class="size-4" />
    </button>
    """
  end
end
