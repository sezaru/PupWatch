defmodule PupWatchWeb.RecordingComponents do
  use PupWatchWeb, :html

  attr :recording, :map, required: true
  attr :rest, :global

  def recording_card(assigns) do
    ~H"""
    <button type="button" class="card bg-base-200 hover:bg-base-300 overflow-hidden text-left" {@rest}>
      <figure class="relative aspect-video bg-base-300">
        <img src={~p"/thumbs/#{@recording.id}"} loading="lazy" class="w-full h-full object-cover" />
        <span
          :if={@recording.status == :recording}
          class="badge badge-error badge-sm absolute top-2 left-2 animate-pulse"
        >
          REC
        </span>
        <span
          :if={@recording.status == :failed}
          class="badge badge-warning badge-sm absolute top-2 left-2"
        >
          failed
        </span>
        <span
          :if={@recording.status != :recording}
          class="badge badge-neutral badge-sm absolute bottom-2 right-2"
        >
          {duration(@recording)}
        </span>
      </figure>
      <div class="px-3 py-2 text-sm">
        <div class="font-medium">{when_label(@recording.started_at)}</div>
        <div class="text-base-content/60">{round(@recording.peak_confidence * 100)}% dog</div>
      </div>
    </button>
    """
  end

  def duration(%{started_at: s, ended_at: e}) do
    secs = DateTime.diff(e || DateTime.utc_now(), s)
    "#{div(secs, 60)}:#{secs |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  def when_label(dt) do
    local = to_local(dt)
    today = to_local(DateTime.utc_now()) |> DateTime.to_date()

    prefix =
      case Date.diff(today, DateTime.to_date(local)) do
        0 -> "Today"
        1 -> "Yesterday"
        _ -> Calendar.strftime(local, "%b %-d")
      end

    "#{prefix} #{Calendar.strftime(local, "%H:%M:%S")}"
  end

  defp to_local(dt) do
    tz = Application.get_env(:pup_watch, :time_zone, "Etc/UTC")

    case DateTime.shift_zone(dt, tz) do
      {:ok, local} -> local
      _ -> dt
    end
  end
end
