#!/usr/bin/env bash
# Runs ON snorlax: the tool shell for `scripts/snorlax.sh`.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export MIX_HOME="$PWD/.nix-mix" HEX_HOME="$PWD/.nix-hex"
[ -f .env.snorlax ] && { set -a; . ./.env.snorlax; set +a; }
exec nix shell nixpkgs#elixir nixpkgs#ffmpeg-headless nixpkgs#git nixpkgs#gcc \
  nixpkgs#gnumake nixpkgs#sqlite nixpkgs#tailwindcss_4 nixpkgs#esbuild nixpkgs#go2rtc \
  -c bash -c 'export MIX_TAILWIND_PATH=$(command -v tailwindcss) MIX_ESBUILD_PATH=$(command -v esbuild); "$@"' _ "$@"
