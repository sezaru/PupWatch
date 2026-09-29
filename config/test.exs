import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pup_watch, PupWatchWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "f7x2PCxPTe24t+1dsTQU1tVYMKxiT8nTl5djf24VnNEkoB4O1copZcJ6B7SpI18e",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :pup_watch, PupWatch.Repo,
  database: Path.expand("../pupwatch_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

config :pup_watch, :storage_root, Path.expand("../tmp/test_storage", __DIR__)
config :pup_watch, :pipeline, false
