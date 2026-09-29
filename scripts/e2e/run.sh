#!/usr/bin/env bash
# On snorlax, inside in-shell.sh: fake camera via go2rtc + dev server + headless browser.
set -euo pipefail
[ -f tmp/fixtures/e2e.mkv ] || { mkdir -p tmp/fixtures; ffmpeg -loglevel error -y -f lavfi -i color=gray:s=1280x720:d=3:r=15 -loop 1 -t 4 -framerate 15 -i test/fixtures/dog.jpg -f lavfi -i color=gray:s=1280x720:d=20:r=15 -f lavfi -t 27 -i anullsrc=r=8000:cl=mono -filter_complex "[1]scale=1280:720,setsar=1[d];[0][d][2]concat=n=3:v=1[v]" -map "[v]" -map 3:a -c:v libx264 -pix_fmt yuv420p -g 15 -c:a pcm_alaw tmp/fixtures/e2e.mkv; }
rm -f pupwatch_dev.db*; rm -rf tmp/storage
mix ash.setup --quiet >/dev/null
go2rtc -config scripts/e2e/go2rtc.yaml > tmp/go2rtc.log 2>&1 & G=$!
mix phx.server > tmp/server.log 2>&1 & S=$!
trap 'kill $G $S 2>/dev/null; pkill -f "tmp/fixtures/e2e.mkv" || true' EXIT
for _ in $(seq 60); do curl -sf -o /dev/null http://127.0.0.1:4000/ && break; sleep 1; done
nix shell --impure --expr "(builtins.getFlake \"nixpkgs\").legacyPackages.x86_64-linux.python3.withPackages (p: [p.playwright])" -c env PLAYWRIGHT_BROWSERS_PATH="$(nix build --no-link --print-out-paths nixpkgs#playwright-driver.browsers)" \
  PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true python3 scripts/e2e/browse.py
