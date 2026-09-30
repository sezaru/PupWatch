defmodule PupWatch.Detection.YoloxTest do
  use ExUnit.Case, async: true

  alias PupWatch.Detection.Yolox

  setup_all do
    %{net: Yolox.load()}
  end

  test "finds the dog, boxed in source-image pixels", %{net: net} do
    mat = Evision.imread("test/fixtures/dog.jpg")
    {h, w, _} = Evision.Mat.shape(mat)

    assert [%{score: score, box: {x, y, bw, bh}} | _] =
             Yolox.detect(net, mat, Yolox.default_opts())

    assert score > 0.6
    assert x >= 0 and y >= 0 and x + bw <= w + 5 and y + bh <= h + 5
    # the labrador fills most of the frame
    assert bw * bh > w * h * 0.3
  end

  # The real camera: a small fluffy Pomeranian that YOLOX-nano scored only 0.34.
  test "finds the Pomeranian on the balcony camera", %{net: net} do
    mat = Evision.imread("test/fixtures/pomeranian_balcony.jpg")
    assert [%{score: score, box: {x, y, _, _}}] = Yolox.detect(net, mat, Yolox.default_opts())
    assert score > 0.6
    # he sits on the mat, left of centre
    assert x in 120..190 and y in 100..160
  end

  test "a cat is not a dog", %{net: net} do
    assert [] ==
             Yolox.detect(net, Evision.imread("test/fixtures/no_dog.jpg"), Yolox.default_opts())
  end
end
