{pkgs, ...}: {
  languages.elixir.enable = true;
  languages.erlang.enable = true;
  packages = with pkgs; [ffmpeg-headless sqlite go2rtc tailwindcss_4 esbuild inotify-tools];
  env.MIX_TAILWIND_PATH = "${pkgs.tailwindcss_4}/bin/tailwindcss";
  env.MIX_ESBUILD_PATH = "${pkgs.esbuild}/bin/esbuild";
}
