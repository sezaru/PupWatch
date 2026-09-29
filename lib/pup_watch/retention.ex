defmodule PupWatch.Retention do
  @moduledoc """
  Keeps recordings under the storage limit: after each recording ends, when the
  limit changes, and every 10 minutes, deletes the oldest finished recordings until
  the total fits. A recording still in progress is never deleted.
  """
  use GenServer
  require Logger

  alias PupWatch.Monitor

  @every_ms 10 * 60_000
  @gb 1_000_000_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)

  @doc "Enforce now and wait for it (tests, and the settings form)."
  def enforce(server \\ __MODULE__), do: GenServer.call(server, :enforce, 60_000)

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(PupWatch.PubSub, "recordings:all")
    Phoenix.PubSub.subscribe(PupWatch.PubSub, "settings:changed")
    {:ok, %{}, {:continue, :start}}
  end

  @impl true
  def handle_continue(:start, s) do
    for rec <- Monitor.unmeasured_recordings!(), do: Monitor.measure_recording!(rec)
    run()
    Process.send_after(self(), :tick, @every_ms)
    {:noreply, s}
  end

  @impl true
  def handle_call(:enforce, _from, s), do: {:reply, run(), s}

  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "update", payload: %{data: %{status: status}}},
        s
      )
      when status != :recording,
      do: {:noreply, tap(s, fn _ -> run() end)}

  def handle_info(%Phoenix.Socket.Broadcast{topic: "settings:changed"}, s),
    do: {:noreply, tap(s, fn _ -> run() end)}

  def handle_info(:tick, s) do
    run()
    Process.send_after(self(), :tick, @every_ms)
    {:noreply, s}
  end

  def handle_info(_, s), do: {:noreply, s}

  defp run do
    limit = Monitor.settings!().max_storage_gb * @gb
    used = Monitor.storage_used_bytes()

    if used > limit do
      {deleted, used} =
        Monitor.oldest_finished_recordings!()
        |> Enum.reduce_while({0, used}, fn
          _rec, {n, used} when used <= limit ->
            {:halt, {n, used}}

          rec, {n, used} ->
            :ok = Monitor.delete_recording(rec)
            {:cont, {n + 1, used - (rec.size_bytes || 0)}}
        end)

      Logger.info(
        "retention: deleted #{deleted} oldest recording(s) to fit #{div(limit, @gb)} GB"
      )

      {:deleted, deleted, used}
    else
      {:ok, used}
    end
  end
end
