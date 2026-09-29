# PupWatch

Watches the balcony Tapo C200, records a clip whenever the dog is in frame, and serves a
live page (WebRTC video, hold-to-talk, pan/tilt) plus a history of clips. Phoenix
LiveView + Ash (AshSqlite); detection is YOLOX-nano through Evision's OpenCV DNN.

Design: `docs/superpowers/specs/2026-09-29-pupwatch-v1-design.md`.

## Develop

Code here, run on snorlax (x86, camera LAN):

    scripts/snorlax.sh mix test
    scripts/snorlax.sh bash scripts/e2e/run.sh   # fake camera + headless browser

`scripts/fetch_model.sh` downloads `priv/models/yolox_nano.onnx` (gitignored).

## Deploy

`nix/package.nix` builds the release; the NixOS module lives in the nixos repo at
`flake/nixos/pupwatch/` (go2rtc + service on :30030, WebRTC media on :8555).
