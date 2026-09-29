#!/usr/bin/env bash
# Runs ON snorlax: the tool shell for `scripts/snorlax.sh`.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export MIX_HOME="$PWD/.nix-mix" HEX_HOME="$PWD/.nix-hex"
# literal KEY=value lines: passwords may hold shell metacharacters
[ -f .env.snorlax ] && while IFS= read -r line || [ -n "$line" ]; do
  [[ $line =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] && export "$line"
done < .env.snorlax
exec nix shell nixpkgs#elixir nixpkgs#ffmpeg-headless nixpkgs#git nixpkgs#gcc \
  nixpkgs#gnumake nixpkgs#sqlite nixpkgs#tailwindcss_4 nixpkgs#esbuild nixpkgs#go2rtc \
  -c bash -c 'export MIX_TAILWIND_PATH=$(command -v tailwindcss) MIX_ESBUILD_PATH=$(command -v esbuild); "$@"' _ "$@"
