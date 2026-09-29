# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :pup_watch,
  ecto_repos: [PupWatch.Repo],
  ash_domains: [PupWatch.Monitor],
  generators: [timestamp_type: :utc_datetime]

config :pup_watch, :camera,
  detect_source: "rtsp://127.0.0.1:8554/tapo_sub",
  record_source: "rtsp://127.0.0.1:8554/tapo",
  go2rtc_url: "http://127.0.0.1:1984",
  go2rtc_stream: "tapo",
  go2rtc_mp4_stream: "tapo_mp4",
  detect_size: {640, 360},
  detect_fps: 3

config :pup_watch, :pipeline, true
config :pup_watch, :time_zone, "America/Sao_Paulo"
config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :ash, default_string_length_count: :codepoints

config :spark,
  formatter: [remove_parens?: true, "Ash.Resource": [], "Ash.Domain": []]

# Configure the endpoint
config :pup_watch, PupWatchWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PupWatchWeb.ErrorHTML, json: PupWatchWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PupWatch.PubSub,
  live_view: [signing_salt: "rejCmdKv"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  path: System.get_env("MIX_ESBUILD_PATH"),
  version_check: false,
  pup_watch: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  path: System.get_env("MIX_TAILWIND_PATH"),
  version_check: false,
  pup_watch: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
