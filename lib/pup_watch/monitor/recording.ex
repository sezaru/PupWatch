defmodule PupWatch.Monitor.Recording do
  use Ash.Resource,
    otp_app: :pup_watch,
    domain: PupWatch.Monitor,
    data_layer: AshSqlite.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  alias PupWatch.Storage

  sqlite do
    table "recordings"
    repo PupWatch.Repo
  end

  pub_sub do
    module PupWatchWeb.Endpoint
    prefix "recordings"
    publish_all :create, "all"
    publish_all :update, "all"
    publish_all :destroy, "all"
  end

  actions do
    defaults [:read]

    create :start do
      accept [:started_at, :peak_confidence]

      change fn changeset, _ ->
        id = Ash.Changeset.get_attribute(changeset, :id) || Ash.UUID.generate()

        Ash.Changeset.force_change_attributes(changeset,
          id: id,
          clip_path: Storage.clip_path(id),
          thumbnail_path: Storage.thumbnail_path(id)
        )
      end
    end

    update :finish do
      accept [:peak_confidence]
      require_atomic? false
      change set_attribute(:status, :complete)
      change set_attribute(:ended_at, &DateTime.utc_now/0)
      change PupWatch.Monitor.Recording.MeasureSize
    end

    update :fail do
      require_atomic? false
      change set_attribute(:status, :failed)
      change set_attribute(:ended_at, &DateTime.utc_now/0)
      change PupWatch.Monitor.Recording.MeasureSize
    end

    # recordings made before sizes were tracked
    update :measure do
      require_atomic? false
      change PupWatch.Monitor.Recording.MeasureSize
    end

    read :history do
      prepare build(sort: [started_at: :desc], load: [:duration_seconds])
      pagination keyset?: true, default_limit: 24, required?: false
    end

    read :in_progress do
      filter expr(status == :recording)
    end

    read :oldest_finished do
      filter expr(status != :recording)
      prepare build(sort: [started_at: :asc])
    end

    read :unmeasured do
      filter expr(status != :recording and is_nil(size_bytes))
    end

    destroy :destroy do
      primary? true
      require_atomic? false

      change after_action(fn _changeset, record, _ctx ->
               for rel <- [record.clip_path, record.thumbnail_path],
                   do: File.rm(Storage.path(rel))

               {:ok, record}
             end)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :started_at, :utc_datetime_usec, allow_nil?: false, public?: true
    attribute :ended_at, :utc_datetime_usec, public?: true

    attribute :status, :atom,
      constraints: [one_of: [:recording, :complete, :failed]],
      default: :recording,
      allow_nil?: false,
      public?: true

    attribute :clip_path, :string, allow_nil?: false, public?: true
    attribute :thumbnail_path, :string, allow_nil?: false, public?: true
    attribute :peak_confidence, :float, default: 0.0, allow_nil?: false, public?: true
    # clip + thumbnail, set once the recording ends
    attribute :size_bytes, :integer, public?: true
  end

  calculations do
    calculate :duration_seconds, :integer, PupWatch.Monitor.Recording.Duration
  end
end
