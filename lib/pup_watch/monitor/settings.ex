defmodule PupWatch.Monitor.Settings do
  @moduledoc "App settings, a single row."
  use Ash.Resource,
    otp_app: :pup_watch,
    domain: PupWatch.Monitor,
    data_layer: AshSqlite.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  sqlite do
    table "settings"
    repo PupWatch.Repo
  end

  pub_sub do
    module PupWatchWeb.Endpoint
    prefix "settings"
    publish_all :update, "changed"
  end

  actions do
    defaults [:read]

    create :create do
      accept [:max_storage_gb]
    end

    update :update do
      accept [:max_storage_gb]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :max_storage_gb, :integer,
      allow_nil?: false,
      default: 20,
      constraints: [min: 1],
      public?: true
  end
end
