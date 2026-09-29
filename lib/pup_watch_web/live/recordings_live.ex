defmodule PupWatchWeb.RecordingsLive do
  use PupWatchWeb, :live_view

  import PupWatchWeb.RecordingComponents

  alias PupWatch.Monitor

  @page 24

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: PupWatchWeb.Endpoint.subscribe("recordings:all")

    page = Monitor.recording_history!(page: [limit: @page])

    {:ok,
     socket
     |> assign(page_title: "Recordings", playing: nil, more?: page.more?, cursor: cursor(page))
     |> assign(empty?: page.results == [])
     |> stream(:recordings, page.results)}
  end

  @impl true
  def handle_params(%{"play" => id}, _uri, socket) do
    case Monitor.get_recording(id) do
      {:ok, rec} -> {:noreply, assign(socket, playing: rec)}
      _ -> {:noreply, assign(socket, playing: nil)}
    end
  end

  def handle_params(_, _, socket), do: {:noreply, assign(socket, playing: nil)}

  defp cursor(%{results: []}), do: nil
  defp cursor(page), do: List.last(page.results).__metadata__.keyset

  @impl true
  def handle_event("load-more", _, %{assigns: %{more?: false}} = socket), do: {:noreply, socket}

  def handle_event("load-more", _, socket) do
    page = Monitor.recording_history!(page: [limit: @page, after: socket.assigns.cursor])

    {:noreply,
     socket
     |> assign(more?: page.more?, cursor: cursor(page) || socket.assigns.cursor)
     |> stream(:recordings, page.results)}
  end

  def handle_event("play", %{"id" => id}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/recordings?play=#{id}")}

  def handle_event("close", _, socket), do: {:noreply, push_patch(socket, to: ~p"/recordings")}

  def handle_event("delete", %{"id" => id}, socket) do
    with {:ok, rec} <- Monitor.get_recording(id), :ok <- Monitor.delete_recording(rec) do
      {:noreply, push_patch(socket, to: ~p"/recordings")}
    else
      _ -> {:noreply, put_flash(socket, :error, "Couldn't delete that recording.")}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "destroy", payload: %{data: rec}}, socket),
    do: {:noreply, stream_delete(socket, :recordings, rec)}

  def handle_info(%Phoenix.Socket.Broadcast{event: "create", payload: %{data: rec}}, socket),
    do: {:noreply, socket |> assign(empty?: false) |> stream_insert(:recordings, rec, at: 0)}

  def handle_info(%Phoenix.Socket.Broadcast{payload: %{data: rec}}, socket),
    do: {:noreply, stream_insert(socket, :recordings, rec)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1 class="text-xl font-semibold">Recordings</h1>
      <p :if={@empty?} class="text-base-content/60 text-sm">No visits recorded yet.</p>

      <div
        id="recordings"
        phx-update="stream"
        phx-viewport-bottom={@more? && "load-more"}
        class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3"
      >
        <.recording_card
          :for={{dom_id, r} <- @streams.recordings}
          id={dom_id}
          recording={r}
          phx-click="play"
          phx-value-id={r.id}
        />
      </div>

      <dialog
        :if={@playing}
        id="player"
        class="modal modal-open"
        phx-window-keydown="close"
        phx-key="Escape"
      >
        <div class="modal-box max-w-4xl p-0 overflow-hidden">
          <video
            src={~p"/clips/#{@playing.id}"}
            controls
            autoplay
            playsinline
            class="w-full bg-black aspect-video"
          ></video>
          <div class="flex items-center justify-between px-4 py-3">
            <div class="text-sm">
              <div class="font-medium">{when_label(@playing.started_at)}</div>
              <div class="text-base-content/60">
                {duration(@playing)} · {round(@playing.peak_confidence * 100)}% dog
                <span :if={@playing.status == :failed} class="badge badge-warning badge-sm">failed</span>
              </div>
            </div>
            <div class="flex gap-2">
              <button
                type="button"
                class="btn btn-error btn-sm btn-outline"
                phx-click="delete"
                phx-value-id={@playing.id}
                data-confirm="Delete this recording?"
              >
                <.icon name="hero-trash" class="size-4" /> Delete
              </button>
              <button type="button" class="btn btn-sm" phx-click="close">Close</button>
            </div>
          </div>
        </div>
        <div class="modal-backdrop" phx-click="close"></div>
      </dialog>
    </Layouts.app>
    """
  end
end
