defmodule PupWatch.Tapo.ChannelTest do
  use ExUnit.Case, async: true

  alias PupWatch.Tapo.Channel

  @key :crypto.strong_rand_bytes(16)
  @nonce :crypto.strong_rand_bytes(12)

  test "seal/open round-trips and carries the sequence number" do
    frame = Channel.seal(@key, @nonce, 42, ~s({"a":1}))
    assert <<42::32, _::binary>> = frame
    assert {:ok, %{"a" => 1}} = Channel.open(@key, @nonce, frame)
  end

  test "tampering, plain-JSON refusals and short replies are errors" do
    <<head::binary-10, byte, tail::binary>> = Channel.seal(@key, @nonce, 1, ~s({"a":1}))

    assert {:error, :auth_failed} =
             Channel.open(@key, @nonce, <<head::binary, Bitwise.bxor(byte, 1), tail::binary>>)

    assert {:error, {:refused, -40401}} = Channel.open(@key, @nonce, ~s({"error_code":-40401}))
    assert {:error, :short_reply} = Channel.open(@key, @nonce, <<1, 2, 3>>)
  end
end
