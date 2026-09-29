defmodule PupWatch.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias PupWatch.Repo
      import PupWatch.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(PupWatch.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end
end
