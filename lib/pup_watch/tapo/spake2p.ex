defmodule PupWatch.Tapo.Spake2p do
  @moduledoc """
  Client side of the SPAKE2+ (P-256, RFC 9383 M/N points) login that TPAP Tapo
  firmware requires, plus its credential transforms. Ported from pytapo's
  `transport/tpap/spake2p.py` and checked against vectors generated from it.
  """
  import Bitwise

  @p 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
  @a @p - 3
  @b 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
  @n 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
  @g {0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296,
      0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5}
  @m_point "02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f"
  @n_point "03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49"

  # -- P-256 affine arithmetic (nil is the point at infinity) ------------------

  defp pow_mod(base, exp, mod), do: :crypto.mod_pow(base, exp, mod) |> :binary.decode_unsigned()
  defp inv(x), do: pow_mod(Integer.mod(x, @p), @p - 2, @p)

  def add(nil, q), do: q
  def add(p, nil), do: p

  def add({x1, y1}, {x2, y2}) when x1 == x2 and rem(y1 + y2, @p) == 0, do: nil

  def add({x1, y1} = p, {x2, y2} = q) do
    m =
      if p == q,
        do: Integer.mod((3 * x1 * x1 + @a) * inv(2 * y1), @p),
        else: Integer.mod((y2 - y1) * inv(x2 - x1), @p)

    x3 = Integer.mod(m * m - x1 - x2, @p)
    {x3, Integer.mod(m * (x1 - x3) - y1, @p)}
  end

  def mul(k, point), do: do_mul(Integer.mod(k, @n), point, nil)

  defp do_mul(0, _addend, acc), do: acc

  defp do_mul(k, addend, acc) do
    acc = if (k &&& 1) == 1, do: add(acc, addend), else: acc
    do_mul(k >>> 1, add(addend, addend), acc)
  end

  def neg(nil), do: nil
  def neg({x, y}), do: {x, Integer.mod(-y, @p)}

  def decode_point(<<4, x::256, y::256>>), do: {x, y}

  def decode_point(<<prefix, x::256>>) when prefix in [2, 3] do
    y = pow_mod(Integer.mod(pow_mod(x, 3, @p) + @a * x + @b, @p), div(@p + 1, 4), @p)
    {x, if((y &&& 1) == (prefix &&& 1), do: y, else: @p - y)}
  end

  def encode_point({x, y}), do: <<4, x::256, y::256>>

  def generator, do: @g

  defp m_point, do: @m_point |> Base.decode16!(case: :lower) |> decode_point()
  defp n_point, do: @n_point |> Base.decode16!(case: :lower) |> decode_point()

  # -- KDFs ---------------------------------------------------------------------

  defp hmac(key, data), do: :crypto.mac(:hmac, :sha256, key, data)
  defp sha256(data), do: :crypto.hash(:sha256, data)

  def hkdf(ikm, salt, info, length) do
    prk = hmac(salt || <<0::256>>, ikm)

    Stream.unfold({<<>>, 1}, fn {t, i} ->
      t = hmac(prk, [t, info, i])
      {t, {t, i + 1}}
    end)
    |> Enum.take(div(length + 31, 32))
    |> IO.iodata_to_binary()
    |> binary_part(0, length)
  end

  defp len_prefixed(chunks),
    do: for(c <- chunks, into: <<>>, do: <<byte_size(c)::little-64, c::binary>>)

  # -- credential transforms ----------------------------------------------------

  def md5_hex(text), do: :crypto.hash(:md5, text) |> Base.encode16(case: :lower)
  def sha256_hex_upper(text), do: text |> sha256() |> Base.encode16()

  @crypt64 ~c"./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz" |> List.to_tuple()
  @crypt_order [{0, 10, 20}, {21, 1, 11}, {12, 22, 2}, {3, 13, 23}, {24, 4, 14}] ++
                 [{15, 25, 5}, {6, 16, 26}, {27, 7, 17}, {18, 28, 8}, {9, 19, 29}]

  defp to64(value, n),
    do: for(i <- 0..(n - 1), into: "", do: <<elem(@crypt64, value >>> (6 * i) &&& 0x3F)>>)

  defp repeat(digest, length),
    do: digest |> :binary.copy(div(length, 32) + 1) |> binary_part(0, length)

  @doc "SHA-256-crypt the way the Tapo app does it (pytapo `sha256_crypt`)."
  def sha256_crypt(key, prefix) do
    rest = String.replace_prefix(prefix, "$5$", "")

    {rounds, rest, explicit?} =
      with "rounds=" <> _ <- rest,
           [head, tail] when tail != "" <- String.split(rest, "$", parts: 2) do
        rounds = head |> String.replace_prefix("rounds=", "") |> String.to_integer()
        {rounds |> max(1000) |> min(999_999_999), tail, true}
      else
        _ -> {5000, rest, false}
      end

    salt_end =
      case :binary.match(rest, "$") do
        {pos, _} when pos > 0 -> pos
        _ -> byte_size(rest)
      end

    salt = binary_part(rest, 0, min(salt_end, 16))
    k = key
    klen = byte_size(k)
    b = sha256([k, salt, k])

    a =
      sha256([
        k,
        salt,
        repeat(b, klen)
        | Stream.unfold(klen, fn
            0 -> nil
            n -> {if((n &&& 1) == 1, do: b, else: k), n >>> 1}
          end)
          |> Enum.to_list()
      ])

    p = repeat(sha256(:binary.copy(k, klen)), klen)
    <<a0, _::binary>> = a
    sb = repeat(sha256(:binary.copy(salt, 16 + a0)), byte_size(salt))

    c =
      Enum.reduce(0..(rounds - 1), a, fn i, c ->
        odd? = (i &&& 1) == 1

        sha256([
          if(odd?, do: p, else: c),
          if(rem(i, 3) != 0, do: sb, else: []),
          if(rem(i, 7) != 0, do: p, else: []),
          if(odd?, do: c, else: p)
        ])
      end)

    byte = &:binary.at(c, &1)

    enc =
      for(
        {x, y, z} <- @crypt_order,
        into: "",
        do: to64(byte.(x) <<< 16 ||| byte.(y) <<< 8 ||| byte.(z), 4)
      ) <>
        to64(byte.(31) <<< 8 ||| byte.(30), 3)

    "$5$#{if explicit?, do: "rounds=#{rounds}$"}#{salt}$#{enc}"
  end

  @doc "The credential the camera asked for in its pake_register reply."
  def apply_extra_crypt(passcode, extra) when extra in [nil, %{}], do: passcode

  def apply_extra_crypt(passcode, %{"type" => type} = extra) do
    params = extra["params"] || %{}

    case {String.downcase(type), to_string(params["passwd_id"] || 0)} do
      {"password_shadow", "5"} -> sha256_crypt(passcode, to_string(params["passwd_prefix"]))
      {"password_shadow", "2"} -> :crypto.hash(:sha, passcode) |> Base.encode16(case: :lower)
      other -> {:error, {:unsupported_extra_crypt, other}}
    end
  end

  # -- one exchange -------------------------------------------------------------

  @doc """
  From the pake_register result, the base64 `user_random` we sent, the credential
  and a random scalar: our share + confirm, and what we need to check the reply.
  """
  def client(register, user_random, credential, scalar) do
    dk =
      :crypto.pbkdf2_hmac(
        :sha256,
        credential,
        Base.decode64!(register["dev_salt"]),
        to_int(register["iterations"]),
        80
      )

    <<w0::320, w1::320>> = dk
    w0 = Integer.mod(w0, @n)
    w1 = Integer.mod(w1, @n)
    yb_point = register["dev_share"] |> Base.decode64!() |> decode_point()
    x = Integer.mod(scalar, @n - 1) + 1
    xp = add(mul(x, @g), mul(w0, m_point()))
    h = add(yb_point, neg(mul(w0, n_point())))
    xb = encode_point(xp)
    yb = encode_point(yb_point)

    context =
      sha256(["PAKE V1", Base.decode64!(user_random), Base.decode64!(register["dev_random"])])

    ke =
      [
        context,
        "",
        "",
        encode_point(m_point()),
        encode_point(n_point()),
        xb,
        yb,
        encode_point(mul(x, h)),
        encode_point(mul(w1, h)),
        <<w0::256>>
      ]
      |> len_prefixed()
      |> sha256()

    <<kca::binary-32, kcb::binary-32>> = hkdf(ke, nil, "ConfirmationKeys", 64)

    %{
      user_share: xb,
      user_confirm: hmac(kca, yb),
      expected_dev_confirm: hmac(kcb, xb),
      shared_key: hkdf(ke, nil, "SharedKey", 32)
    }
  end

  def device_confirm_ok?(client, dev_confirm),
    do: :crypto.hash_equals(client.expected_dev_confirm, dev_confirm)

  def session_key_and_nonce(shared_key) do
    <<key::binary-16, _::binary>> =
      hkdf(shared_key, "tp-kdf-salt-aes128-key", "tp-kdf-info-aes128-key", 32)

    <<nonce::binary-12, _::binary>> =
      hkdf(shared_key, "tp-kdf-salt-aes128-iv", "tp-kdf-info-aes128-iv", 32)

    {key, nonce}
  end

  defp to_int(i) when is_integer(i), do: i
  defp to_int(s) when is_binary(s), do: String.to_integer(s)
end
