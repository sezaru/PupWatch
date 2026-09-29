defmodule PupWatch.Detection.Motion do
  @moduledoc "Cheap frame-difference motion measure, used to decide when YOLOX is worth running."

  @size {160, 90}

  @doc "A small blurred grayscale copy of the frame to compare against the next one."
  def signature(mat) do
    mat
    |> Evision.cvtColor(Evision.Constant.cv_COLOR_BGR2GRAY())
    |> Evision.resize(@size, interpolation: Evision.Constant.cv_INTER_AREA())
    |> Evision.gaussianBlur({5, 5}, 0)
  end

  @doc "Fraction (0..1) of pixels that changed noticeably between two signatures."
  def changed_fraction(prev, cur) do
    {_, mask} =
      Evision.threshold(Evision.absdiff(prev, cur), 25, 255, Evision.Constant.cv_THRESH_BINARY())

    {w, h} = @size
    Evision.countNonZero(mask) / (w * h)
  end
end
