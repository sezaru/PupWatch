#!/usr/bin/env bash
# Sync this tree to snorlax and run a command there. Usage: scripts/snorlax.sh mix test
# snorlax is the deploy target and sits on the camera's LAN.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="${PUPWATCH_REMOTE:-/mnt/main/projects/pupwatch}"

rsync -a --delete \
  --exclude /_build --exclude /deps --exclude /.devenv --exclude /.git \
  --exclude /priv/static/assets --exclude /tmp --exclude '/.env*' --exclude '/.nix-*' \
  "$ROOT/" "snorlax:$REMOTE/"

status=0
ssh snorlax "cd $REMOTE && bash scripts/in-shell.sh $(printf '%q ' "$@")" || status=$?
rsync -a "snorlax:$REMOTE/mix.lock" "$ROOT/mix.lock"
exit $status
