defmodule PupWatch.Tapo.Channel do
  @moduledoc """
  Framing of the TPAP `/stok=<stok>/ds` channel: `<<seq::32>> <> AES-128-CCM(json) <> tag`,
  with the nonce's last 4 bytes replaced by the sequence number.
  """

  @tag_len 16

  def nonce_for(<<prefix::binary-8, _::binary-4>>, seq), do: <<prefix::binary, seq::32>>

  def seal(key, nonce, seq, plaintext) do
    {cipher, tag} =
      :crypto.crypto_one_time_aead(
        :aes_128_ccm,
        key,
        nonce_for(nonce, seq),
        plaintext,
        <<>>,
        @tag_len,
        true
      )

    <<seq::32, cipher::binary, tag::binary>>
  end

  # A refusal comes back as plain JSON, before any decryption.
  def open(_key, _nonce, "{" <> _ = json) do
    case Jason.decode(json) do
      {:ok, %{"error_code" => code}} -> {:error, {:refused, code}}
      _ -> {:error, :bad_reply}
    end
  end

  def open(key, nonce, <<seq::32, rest::binary>>) when byte_size(rest) >= @tag_len do
    cipher_len = byte_size(rest) - @tag_len
    <<cipher::binary-size(cipher_len), tag::binary>> = rest

    case :crypto.crypto_one_time_aead(
           :aes_128_ccm,
           key,
           nonce_for(nonce, seq),
           cipher,
           <<>>,
           tag,
           false
         ) do
      :error -> {:error, :auth_failed}
      plain -> Jason.decode(plain)
    end
  end

  def open(_key, _nonce, _short), do: {:error, :short_reply}
end
