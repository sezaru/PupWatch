defmodule PupWatch.Detection.DetectorTest do
  use ExUnit.Case, async: false

  alias PupWatch.Detection.{Detector, FrameReader}
  alias PupWatch.Fixtures

  test "a dog walking through a replayed video arrives and leaves" do
    Phoenix.PubSub.subscribe(PupWatch.PubSub, Detector.topic())

    start_supervised!({Detector, name: :test_detector, presence: [leave_after_ms: 2_000]})

    start_supervised!(
      {FrameReader,
       name: :test_reader,
       source: Fixtures.visit_video(),
       size: {640, 360},
       fps: 3,
       sink: :test_detector}
    )

    assert_receive {:status, :watching}, 5_000
    assert_receive {:dog_arrived, %{score: score, thumbnail: <<0xFF, 0xD8, _::binary>>}}, 6_000
    assert score > 0.5
    assert %{state: :dog_present} = Detector.status(:test_detector)
    assert_receive {:dog_left, peak}, 8_000
    assert peak >= score
  end

  test "status is offline when the stream is unreachable" do
    start_supervised!({Detector, name: :test_detector2})

    start_supervised!(
      {FrameReader,
       name: :test_reader2, source: "/nonexistent.mp4", size: {640, 360}, sink: :test_detector2}
    )

    Process.sleep(300)
    assert %{state: :offline} = Detector.status(:test_detector2)
  end
end
