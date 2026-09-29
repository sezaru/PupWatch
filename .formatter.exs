[
  import_deps: [:ecto, :ecto_sql, :phoenix, :ash, :ash_sqlite, :ash_phoenix],
  plugins: [Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}"]
]
