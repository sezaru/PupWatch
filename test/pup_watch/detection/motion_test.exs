defmodule PupWatch.Detection.MotionTest do
  use ExUnit.Case, async: true

  alias PupWatch.Detection.Motion

  defp frame(value),
    do: Evision.Mat.from_binary(:binary.copy(<<value>>, 640 * 360 * 3), {:u, 8}, 360, 640, 3)

  test "identical frames show no motion, a changed frame does" do
    dog = Evision.imread("test/fixtures/dog.jpg") |> Evision.resize({640, 360})
    gray = frame(128)

    assert Motion.changed_fraction(Motion.signature(gray), Motion.signature(gray)) == 0.0
    assert Motion.changed_fraction(Motion.signature(gray), Motion.signature(frame(131))) == 0.0
    assert Motion.changed_fraction(Motion.signature(gray), Motion.signature(dog)) > 0.3
  end
end
