import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/pup_watch start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :pup_watch, PupWatchWeb.Endpoint, server: true
end

config :pup_watch, PupWatchWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :pup_watch, PupWatchWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/pup_watch_web/router\.ex$",
        ~r"lib/pup_watch_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if host = System.get_env("CAMERA_HOST") do
  if password = System.get_env("TAPO_CLOUD_PASSWORD") do
    # the camera checks this locally; it never needs to reach TP-Link
    config :pup_watch, :tapo, host: host, password: password
  end

  # the Tapo "camera account" -- the same one RTSP uses
  config :pup_watch, :onvif,
    url: "http://#{host}:#{System.get_env("ONVIF_PORT", "2020")}/onvif/service",
    username: System.fetch_env!("CAMERA_USER"),
    password: System.fetch_env!("CAMERA_PASSWORD")
end

if url = System.get_env("GO2RTC_URL") do
  config :pup_watch,
         :camera,
         Keyword.merge(Application.get_env(:pup_watch, :camera, []), go2rtc_url: url)
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise "environment variable SECRET_KEY_BASE is missing (mix phx.gen.secret)"

  storage = System.get_env("PUPWATCH_STORAGE") || raise "PUPWATCH_STORAGE is missing"

  config :pup_watch, :storage_root, storage

  config :pup_watch, PupWatch.Repo,
    database: Path.join(storage, "pupwatch.db"),
    pool_size: 5

  host = System.get_env("PHX_HOST") || "localhost"
  extra_hosts = String.split(System.get_env("PHX_EXTRA_HOSTS", ""), ",", trim: true)

  config :pup_watch, PupWatchWeb.Endpoint,
    url: [host: host, scheme: "https", port: 443],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    # TLS ends at the proxy, so the origin can't be compared with the (http) conn;
    # "//host" accepts any scheme and port, which also covers direct LAN access.
    check_origin: Enum.map([host | extra_hosts], &("//" <> &1)),
    secret_key_base: secret_key_base
end
