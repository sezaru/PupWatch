defmodule PupWatch.Release do
  @moduledoc "Run from the release: `bin/pup_watch eval PupWatch.Release.migrate`."

  def migrate do
    Application.load(:pup_watch)
    File.mkdir_p!(Application.fetch_env!(:pup_watch, :storage_root))

    for repo <- Application.fetch_env!(:pup_watch, :ecto_repos) do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end
