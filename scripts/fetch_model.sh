#!/usr/bin/env bash
#
# Fetch a nano YOLO object-detection model (ONNX, COCO 80 classes) for PupWatch.
#
# Default: YOLOX-nano, which is published as a ready-to-use .onnx directly on the
# official Megvii YOLOX GitHub release (pinned tag 0.1.1rc0). The `yolo`
# (yolo_elixir) library consumes it via its YoloX model module. COCO class 16 == "dog".
#
# Alternative (Ultralytics YOLOv8n / YOLO11n): Ultralytics ships only .pt weights,
# so an ONNX has to be exported locally. To use one of those instead, run:
#
#     pip install ultralytics
#     yolo export model=yolov8n.pt format=onnx     # or model=yolo11n.pt
#
# then drop the resulting yolov8n.onnx / yolo11n.onnx into priv/models/ and point
# the app's config at it (Ultralytics models use the YoloV8 module in yolo_elixir).

set -euo pipefail

MODEL_URL="https://github.com/Megvii-BaseDetection/YOLOX/releases/download/0.1.1rc0/yolox_nano.onnx"
MODEL_SHA256="c789161ed43c8269fcd4e67c67eeeb4e80c622da2eb296a20bc6007bd18a0b7d"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/../priv/models"
OUT="$MODELS_DIR/yolox_nano.onnx"

mkdir -p "$MODELS_DIR"

if [ -f "$OUT" ] && echo "$MODEL_SHA256  $OUT" | sha256sum -c - >/dev/null 2>&1; then
  echo "Model already present and verified: $OUT"
  exit 0
fi

echo "Downloading YOLOX-nano ONNX -> $OUT"
if ! curl -fL --retry 3 -o "$OUT" "$MODEL_URL"; then
  echo "ERROR: download failed from $MODEL_URL" >&2
  echo "Fetch it manually, or export an Ultralytics model (see header comment)." >&2
  exit 1
fi

echo "Verifying sha256..."
if ! echo "$MODEL_SHA256  $OUT" | sha256sum -c -; then
  echo "ERROR: sha256 mismatch for $OUT" >&2
  exit 1
fi

echo "Done: $OUT"
