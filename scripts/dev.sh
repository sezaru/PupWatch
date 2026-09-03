#!/usr/bin/env bash
# Run a command inside the pupwatch devenv with the extra bits evision's
# source build needs. Usage: scripts/dev.sh mix test
#
# Why this exists: the flakeless `devenv` wrapper here has no `shell` command
# and `use devenv` isn't wired into direnv, so we load the generated devenv
# env script directly. Two source-build gaps are also patched:
#   1. python3 (evision runs a Python binding generator at compile time)
#   2. evision 0.2.17's hex package omits the py_src/{config,ir,emit}
#      subpackages, so the source build fails; we vendor them here.
# no `set -u`: the generated devenv env script references interactive vars (PS1)
set -eo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
: "${PS1:=}"

# --- load devenv environment (strip the trailing `exec` from the generated script)
ENVFILE="$(ls -t .devenv/shell-*.sh 2>/dev/null | head -1 || true)"
if [ -z "$ENVFILE" ]; then
  echo "dev.sh: no .devenv/shell-*.sh found — enter the devenv once to generate it" >&2
  exit 1
fi
# shellcheck disable=SC1090
source <(head -n -1 "$ENVFILE")

# --- python3 for evision's compile-time binding generator
if ! command -v python3 >/dev/null 2>&1; then
  PY="$(nix build --no-link --print-out-paths nixpkgs#python3 2>/dev/null)"
  export PATH="$PY/bin:$PATH"
fi

# --- self-heal evision's missing py_src subpackages (see header)
EV_PY="deps/evision/py_src"
if [ -d "$EV_PY" ] && [ ! -d "$EV_PY/config" ]; then
  cp -r scripts/evision-0.2.17-py_src/* "$EV_PY/"
fi

exec "$@"
