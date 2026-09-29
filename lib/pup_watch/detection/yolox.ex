defmodule PupWatch.Detection.Yolox do
  @moduledoc "YOLOX-nano (COCO) through OpenCV DNN, reduced to dog detections."

  @input 416
  @strides [8, 16, 32]
  @classes 80
  @row_floats 5 + @classes
  @dog 16

  def load(path \\ Application.app_dir(:pup_watch, "priv/models/yolox_nano.onnx")),
    do: Evision.DNN.readNetFromONNX(path)

  @doc "BGR u8 Mat in, `[%{score, box: {x, y, w, h}}]` in source pixels out, best first."
  def detect(net, mat, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.5)
    {h, w, _} = Evision.Mat.shape(mat)
    ratio = min(@input / h, @input / w)

    blob = mat |> letterbox(w, h, ratio) |> Evision.DNN.blobFromImage(swapRB: false)
    [out] = net |> Evision.DNN.Net.setInput(blob) |> Evision.DNN.Net.forward() |> List.wrap()

    out
    |> Evision.Mat.to_binary()
    |> decode(threshold)
    |> nms(0.45)
    |> Enum.map(fn %{box: {x, y, bw, bh}} = d ->
      %{d | box: {round(x / ratio), round(y / ratio), round(bw / ratio), round(bh / ratio)}}
    end)
  end

  # YOLOX exports pad bottom/right with 114 and take raw 0-255 BGR.
  defp letterbox(mat, w, h, ratio) do
    nw = round(w * ratio)
    nh = round(h * ratio)

    mat
    |> Evision.resize({nw, nh})
    |> Evision.copyMakeBorder(
      0,
      @input - nh,
      0,
      @input - nw,
      Evision.Constant.cv_BORDER_CONSTANT(),
      value: {114, 114, 114}
    )
  end

  defp decode(bin, threshold) do
    for {gx, gy, stride, i} <- grid(),
        <<_::binary-size(i * @row_floats * 4), cx::float-32-native, cy::float-32-native,
          bw::float-32-native, bh::float-32-native, obj::float-32-native,
          _::binary-size(@dog * 4), cls::float-32-native, _::binary>> = bin,
        score = obj * cls,
        score >= threshold do
      w = :math.exp(bw) * stride
      h = :math.exp(bh) * stride
      %{score: score, box: {(cx + gx) * stride - w / 2, (cy + gy) * stride - h / 2, w, h}}
    end
  end

  defp grid do
    :persistent_term.get({__MODULE__, :grid}, nil) ||
      then(
        for(
          s <- @strides,
          n = div(@input, s),
          gy <- 0..(n - 1),
          gx <- 0..(n - 1),
          do: {gx, gy, s}
        )
        |> Enum.with_index()
        |> Enum.map(fn {{gx, gy, s}, i} -> {gx, gy, s, i} end),
        fn g ->
          :persistent_term.put({__MODULE__, :grid}, g)
          g
        end
      )
  end

  defp nms(dets, iou_max) do
    dets
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.reduce([], fn d, kept ->
      if Enum.any?(kept, &(iou(&1.box, d.box) > iou_max)), do: kept, else: [d | kept]
    end)
    |> Enum.reverse()
  end

  defp iou({ax, ay, aw, ah}, {bx, by, bw, bh}) do
    iw = max(0, min(ax + aw, bx + bw) - max(ax, bx))
    ih = max(0, min(ay + ah, by + bh) - max(ay, by))
    inter = iw * ih
    inter / (aw * ah + bw * bh - inter)
  end
end
