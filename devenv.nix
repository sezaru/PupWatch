{ pkgs, ... }:
{
  languages.elixir.enable = true;
  languages.erlang.enable = true;
  packages = with pkgs; [ cmake opencv pkg-config curl python3 ];
  env.EVISION_PREFER_PRECOMPILED = "false";
}
