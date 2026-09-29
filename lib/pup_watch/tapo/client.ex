defmodule PupWatch.Tapo.Client do
  @moduledoc """
  Session with the camera's TPAP control API (port 443): SPAKE2+ login as the
  built-in `admin` with the TP-Link account password, then encrypted requests.
  Mirrors pytapo's `Tpap` transport, including its care with failed logins —
  every one counts towards the camera's lockout.
  """
  use GenServer
  require Logger

  alias PupWatch.Tapo.{Channel, Spake2p}

  @session_errors [-40401, -40421]
  @refused_passcode -40401
  @relogin_retry_ms 2_000

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)

  @doc "Send a request map, or a list of them, through one multipleRequest."
  def request(server \\ __MODULE__, request),
    do: GenServer.call(server, {:request, request}, 60_000)

  @impl true
  def init(opts) do
    cfg = Keyword.merge(Application.get_env(:pup_watch, :tapo, []), opts)
    {:ok, %{host: cfg[:host], password: cfg[:password], info: nil, session: nil, passcode: nil}}
  end

  @impl true
  def handle_call({:request, _}, _from, %{password: nil} = s),
    do: {:reply, {:error, :tapo_not_configured}, s}

  def handle_call({:request, request}, _from, s) do
    payload = Jason.encode!(%{method: "multipleRequest", params: %{requests: List.wrap(request)}})
    {reply, s} = send_request(payload, s, 0)
    reply = with {:ok, [one]} when not is_list(request) <- reply, do: {:ok, one}
    {:reply, reply, s}
  end

  defp send_request(payload, s, attempt) do
    with {:ok, s} <- ensure_session(s),
         {:ok, response, s} <- round_trip(payload, s) do
      {unwrap(response), s}
    else
      {:error, reason, s} when attempt == 0 ->
        if retryable?(reason),
          do: send_request(payload, %{s | session: nil}, 1),
          else: {{:error, reason}, s}

      {:error, reason, s} ->
        {{:error, reason}, %{s | session: nil}}
    end
  end

  defp retryable?({:refused, code}), do: code in @session_errors
  defp retryable?({:http, _}), do: true
  defp retryable?(_), do: false

  defp unwrap(%{"result" => %{"responses" => responses}}) when is_list(responses),
    do: {:ok, responses}

  defp unwrap(%{"error_code" => code}) when code != 0, do: {:error, {:camera, code}}
  defp unwrap(other), do: {:error, {:unexpected, other}}

  # -- session ------------------------------------------------------------------

  defp ensure_session(%{session: %{expires_at: exp}} = s) do
    if System.monotonic_time(:second) < exp, do: {:ok, s}, else: login(%{s | session: nil})
  end

  defp ensure_session(s), do: login(s)

  defp login(s) do
    s = %{s | info: s.info || discover(s)}
    passcodes = [Spake2p.md5_hex(s.password), Spake2p.sha256_hex_upper(s.password)]

    # A re-login only retries the passcode that worked; a C200 refuses the first
    # pake_share after a session ends and accepts it a couple of seconds later.
    attempts = if s.passcode, do: [s.passcode, s.passcode], else: [0, 1]

    attempts
    |> Enum.with_index()
    |> Enum.reduce_while({:error, :no_attempt, s}, fn {index, n}, _acc ->
      if n > 0 and index == Enum.at(attempts, n - 1), do: Process.sleep(@relogin_retry_ms)

      case login_with(Enum.at(passcodes, index), s) do
        {:ok, session} -> {:halt, {:ok, %{s | session: session, passcode: index}}}
        {:error, {:refused, @refused_passcode} = reason} -> {:cont, {:error, reason, s}}
        {:error, reason} -> {:halt, {:error, reason, s}}
      end
    end)
    |> case do
      {:error, {:refused, @refused_passcode}, s} -> {:error, :invalid_password, s}
      other -> other
    end
  end

  defp discover(s) do
    case post_login(s, %{sub_method: "discover"}) do
      {:ok, %{"result" => %{"tpap" => info}}} -> info
      _ -> %{}
    end
  end

  defp login_with(passcode, s) do
    user_random = Base.encode64(:crypto.strong_rand_bytes(32))

    username =
      if s.info["user_hash_type"] == 1,
        do: Spake2p.sha256_hex_upper("admin"),
        else: Spake2p.md5_hex("admin")

    with {:ok, %{"result" => register}} <-
           post_login(s, %{
             sub_method: "pake_register",
             username: username,
             user_random: user_random,
             cipher_suites: [1],
             encryption: ["aes_128_ccm"],
             passcode_type: "userpw"
           })
           |> result(),
         credential when is_binary(credential) <-
           Spake2p.apply_extra_crypt(passcode, register["extra_crypt"]),
         scalar = :binary.decode_unsigned(:crypto.strong_rand_bytes(32)),
         client = Spake2p.client(register, user_random, credential, scalar),
         {:ok, %{"result" => share}} <-
           post_login(s, %{
             sub_method: "pake_share",
             user_share: Base.encode64(client.user_share),
             user_confirm: Base.encode64(client.user_confirm)
           })
           |> result(),
         true <-
           Spake2p.device_confirm_ok?(client, Base.decode64!(share["dev_confirm"])) ||
             {:error, :device_confirm_mismatch} do
      {key, nonce} = Spake2p.session_key_and_nonce(client.shared_key)

      {:ok,
       %{
         stok: share["stok"],
         key: key,
         nonce: nonce,
         seq: to_int(share["start_seq"]),
         expires_at: System.monotonic_time(:second) + to_int(share["expired"] || 3600)
       }}
    end
  end

  defp result({:ok, %{"result" => _} = body}), do: {:ok, body}

  defp result({:ok, body}) do
    case lockout_seconds(body) do
      0 -> {:error, {:refused, body["error_code"]}}
      secs -> {:error, {:locked_out, secs}}
    end
  end

  defp result(err), do: err

  defp lockout_seconds(body) do
    [body["error_info"], body["data"], get_in(body, ["result", "data"])]
    |> Enum.find_value(0, fn
      %{"sec_left" => secs} when is_integer(secs) and secs > 0 -> secs
      _ -> nil
    end)
  end

  defp round_trip(payload, %{session: session} = s) do
    frame = Channel.seal(session.key, session.nonce, session.seq, payload)
    s = put_in(s.session.seq, session.seq + 1)

    case post(s, "/stok=#{session.stok}/ds", frame, "application/octet-stream") do
      {:ok, raw} ->
        case Channel.open(session.key, session.nonce, raw) do
          {:ok, response} -> {:ok, response, s}
          {:error, reason} -> {:error, reason, s}
        end

      {:error, reason} ->
        {:error, reason, s}
    end
  end

  # -- HTTP -----------------------------------------------------------------------

  defp post_login(s, params) do
    with {:ok, raw} <-
           post(s, "/", Jason.encode!(%{method: "login", params: params}), "application/json") do
      Jason.decode(raw)
    end
  end

  defp post(s, path, body, type) do
    base = "https://#{s.host}"

    case Req.post(base <> path,
           body: body,
           headers: [
             {"requestByApp", "true"},
             {"referer", base},
             {"user-agent", "Tapo CameraClient Android"},
             {"content-type", type},
             {"accept", type}
           ],
           decode_body: false,
           retry: false,
           receive_timeout: 10_000,
           # the camera presents a self-signed certificate
           connect_options: [transport_opts: [verify: :verify_none]]
         ) do
      {:ok, %{body: raw}} -> {:ok, raw}
      {:error, e} -> {:error, {:http, e}}
    end
  end

  defp to_int(i) when is_integer(i), do: i
  defp to_int(s) when is_binary(s), do: String.to_integer(s)
end
