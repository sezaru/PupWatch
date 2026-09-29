defmodule PupWatch.Fixtures do
  @moduledoc "Videos built from the still fixtures with ffmpeg, cached under tmp/."

  @dir Path.expand("../../tmp/fixtures", __DIR__)

  @doc "2s empty, 4s dog, 6s empty — 640x360, with a silent A-law track like the C200."
  def visit_video, do: build("visit.mkv", visit_args())

  @doc "30s of the dog, for recorder tests that need a long-running source."
  def long_video do
    build("long.mkv", [
      "-loop",
      "1",
      "-t",
      "30",
      "-i",
      "test/fixtures/dog.jpg",
      "-f",
      "lavfi",
      "-t",
      "30",
      "-i",
      "anullsrc=r=8000:cl=mono",
      "-vf",
      "scale=640:360,setsar=1",
      "-r",
      "10",
      "-c:v",
      "libx264",
      "-pix_fmt",
      "yuv420p",
      "-c:a",
      "pcm_alaw"
    ])
  end

  defp visit_args do
    [
      "-f",
      "lavfi",
      "-i",
      "color=gray:s=640x360:d=2:r=10",
      "-loop",
      "1",
      "-t",
      "4",
      "-framerate",
      "10",
      "-i",
      "test/fixtures/dog.jpg",
      "-f",
      "lavfi",
      "-i",
      "color=gray:s=640x360:d=6:r=10",
      "-f",
      "lavfi",
      "-t",
      "12",
      "-i",
      "anullsrc=r=8000:cl=mono",
      "-filter_complex",
      "[1]scale=640:360,setsar=1[d];[0][d][2]concat=n=3:v=1[v]",
      "-map",
      "[v]",
      "-map",
      "3:a",
      "-c:v",
      "libx264",
      "-pix_fmt",
      "yuv420p",
      "-c:a",
      "pcm_alaw"
    ]
  end

  defp build(name, args) do
    out = Path.join(@dir, name)

    unless File.exists?(out) do
      File.mkdir_p!(@dir)
      {_, 0} = System.cmd("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y"] ++ args ++ [out])
    end

    out
  end

  def probe_duration(path) do
    {out, 0} =
      System.cmd("ffprobe", ~w(-v error -show_entries format=duration -of csv=p=0) ++ [path])

    out |> String.trim() |> String.to_float()
  end
end
