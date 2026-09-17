#!/usr/bin/env bash
# Build Resources/FaceEmbedding.mlmodelc from the Apache-2.0 SFace model.
#
# Usage: scripts/fetch-model.sh [--force]
#
# Needs Python 3.12+ (Homebrew python3.12 works). Everything else is installed
# into Tools/Conversion/.venv.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONVERSION="$ROOT/Tools/Conversion"
VENV="$CONVERSION/.venv"
MODELS="$CONVERSION/models"
ONNX="$MODELS/face_recognition_sface_2021dec.onnx"
OUT="$ROOT/Resources/FaceEmbedding.mlpackage"
COMPILED="$ROOT/Resources/FaceEmbedding.mlmodelc"
ONNX_URL="https://github.com/opencv/opencv_zoo/raw/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

if [[ -d "$COMPILED" && "$FORCE" -eq 0 ]]; then
  echo "FaceEmbedding.mlmodelc already exists (use --force to rebuild)"
  exit 0
fi

PYTHON="${PYTHON:-}"
if [[ -z "$PYTHON" ]]; then
  for candidate in python3.12 python3.13 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      PYTHON="$candidate"
      break
    fi
  done
fi
if [[ -z "$PYTHON" ]]; then
  echo "error: need Python 3.12+ (brew install python@3.12)" >&2
  exit 1
fi
echo "using $($PYTHON --version)"

if [[ ! -d "$VENV" ]]; then
  echo "creating venv..."
  "$PYTHON" -m venv "$VENV"
fi

echo "installing conversion dependencies (first run downloads PyTorch)..."
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet coremltools onnx onnxruntime onnx2torch torch numpy pillow

mkdir -p "$MODELS"
if [[ ! -f "$ONNX" ]]; then
  echo "downloading SFace ONNX (37 MB)..."
  curl -fL --progress-bar -o "$ONNX" "$ONNX_URL"
fi

echo "converting to CoreML..."
"$VENV/bin/python" "$CONVERSION/convert_sface.py" --onnx "$ONNX" --out "$OUT"

echo "done: $COMPILED"
echo "now run: xcodegen generate"
