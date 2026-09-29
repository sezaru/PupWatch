defmodule PupWatch.Monitor.Camera do
  use Ash.Resource, otp_app: :pup_watch, domain: PupWatch.Monitor

  alias PupWatch.Camera.{Features, Onvif}

  actions do
    action :move, :atom do
      argument :direction, :atom,
        allow_nil?: false,
        constraints: [one_of: [:up, :down, :left, :right]]

      run fn input, _ ->
        with :ok <- Onvif.move(input.arguments.direction), do: {:ok, input.arguments.direction}
      end
    end

    action :presets, {:array, :map} do
      run fn _input, _ -> Onvif.presets() end
    end

    action :goto_preset, :string do
      argument :token, :string, allow_nil?: false

      run fn input, _ ->
        with :ok <- Onvif.goto_preset(input.arguments.token), do: {:ok, input.arguments.token}
      end
    end

    action :settings, :map do
      run fn _input, _ -> Features.all() end
    end

    action :set_setting, :atom do
      argument :name, :atom, allow_nil?: false, constraints: [one_of: Features.names()]
      # "true"/"false" for toggles, a mode for night vision, 0-100 for volumes
      argument :value, :string, allow_nil?: false

      run fn %{arguments: %{name: name, value: value}}, _ ->
        value =
          cond do
            value in ~w(true false) -> value == "true"
            match?({_, ""}, Integer.parse(value)) -> String.to_integer(value)
            true -> value
          end

        with :ok <- Features.set(name, value), do: {:ok, name}
      end
    end

    action :siren, :atom do
      argument :action, :atom, allow_nil?: false, constraints: [one_of: [:start, :stop]]

      run fn input, _ ->
        with :ok <- Features.siren(input.arguments.action), do: {:ok, input.arguments.action}
      end
    end

    action :status, :map do
      run fn _input, _ -> {:ok, PupWatch.Detection.Detector.status()} end
    end
  end
end
