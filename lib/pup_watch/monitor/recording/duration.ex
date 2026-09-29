defmodule PupWatch.Monitor.Recording.Duration do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:started_at, :ended_at]

  @impl true
  def calculate(records, _opts, _context) do
    now = DateTime.utc_now()
    Enum.map(records, &DateTime.diff(&1.ended_at || now, &1.started_at))
  end
end
