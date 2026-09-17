#!/usr/bin/env python3
"""Convert the OpenCV Zoo SFace ONNX model to CoreML.

SFace is Apache-2.0 (OpenCV Zoo), a MobileFaceNet trained with the SFace loss.
Output: a 112x112 RGB image input that produces a 128-d L2-normalisable embedding.

Important: the ONNX graph already contains the normalisation ((x - 127.5) / 128)
as its first Sub/Mul nodes. Feeding an already-normalised image double-normalises
it, collapses the embedding and makes every face look alike, so the CoreML image
input must use scale 1 / bias 0 and hand over raw 0…255 pixels.

Usage:
    python convert_sface.py \
        --onnx models/face_recognition_sface_2021dec.onnx \
        --out  ../../Resources/FaceEmbedding.mlpackage
"""

from __future__ import annotations

import argparse
import pathlib
import shutil
import subprocess
import sys

import numpy as np

# No pre-processing: the graph does it. See the module docstring.
SCALE = 1.0
BIAS = [0.0, 0.0, 0.0]
INPUT_SIZE = 112


def build_torch_module(onnx_path: pathlib.Path):
    import onnx
    import torch
    from onnx2torch import convert

    model = onnx.load(str(onnx_path))
    graph = model.graph

    # The export lists initializers as graph inputs (IR-3 style). Keep only `data`.
    initializer_names = {initializer.name for initializer in graph.initializer}
    kept = [value for value in graph.input if value.name not in initializer_names]
    del graph.input[:]
    graph.input.extend(kept)

    torch_module = convert(model)
    torch_module.eval()
    return torch, torch_module


def onnx_reference(onnx_path: pathlib.Path, image: np.ndarray) -> np.ndarray:
    import onnxruntime as ort

    session = ort.InferenceSession(str(onnx_path), providers=["CPUExecutionProvider"])
    input_name = session.get_inputs()[0].name
    blob = image.astype(np.float32).transpose(2, 0, 1)[None, ...]
    return session.run(None, {input_name: blob})[0]


def convert(onnx_path: pathlib.Path, out_path: pathlib.Path, float16: bool) -> None:
    import coremltools as ct
    import torch

    torch, torch_module = build_torch_module(onnx_path)

    example = torch.rand(1, 3, INPUT_SIZE, INPUT_SIZE) * 2 - 1
    traced = torch.jit.trace(torch_module, example)

    precision = ct.precision.FLOAT16 if float16 else ct.precision.FLOAT32
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.ImageType(
                name="data",
                shape=(1, 3, INPUT_SIZE, INPUT_SIZE),
                scale=SCALE,
                bias=BIAS,
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="embedding")],
        convert_to="mlprogram",
        compute_precision=precision,
        minimum_deployment_target=ct.target.macOS14,
    )
    mlmodel.short_description = "SFace face embedding (OpenCV Zoo, Apache-2.0)"
    mlmodel.input_description["data"] = "112x112 RGB face crop"
    mlmodel.output_description["embedding"] = "128-d face embedding"

    if out_path.exists():
        shutil.rmtree(out_path)
    mlmodel.save(str(out_path))
    print(f"saved {out_path}")


def verify(onnx_path: pathlib.Path, mlpackage: pathlib.Path) -> None:
    import coremltools as ct
    from PIL import Image

    rng = np.random.default_rng(0)
    image = rng.integers(0, 256, size=(INPUT_SIZE, INPUT_SIZE, 3), dtype=np.uint8)

    reference = onnx_reference(onnx_path, image)[0]

    model = ct.models.MLModel(str(mlpackage))
    prediction = model.predict({"data": Image.fromarray(image, mode="RGB")})
    result = np.asarray(prediction["embedding"]).reshape(-1)

    cosine = float(
        np.dot(reference, result) / (np.linalg.norm(reference) * np.linalg.norm(result) + 1e-9)
    )
    print(f"parity cosine similarity: {cosine:.6f}")
    if cosine < 0.99:
        raise SystemExit("CoreML output diverges from the ONNX reference")


def compile_mlpackage(mlpackage: pathlib.Path) -> pathlib.Path:
    compiled = mlpackage.with_suffix(".mlmodelc")
    if compiled.exists():
        shutil.rmtree(compiled)
    subprocess.run(
        ["xcrun", "coremlc", "compile", str(mlpackage), str(compiled.parent)],
        check=True,
    )
    print(f"compiled {compiled}")
    return compiled


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--onnx", type=pathlib.Path, required=True)
    parser.add_argument("--out", type=pathlib.Path, required=True)
    parser.add_argument("--float16", action="store_true", default=True)
    parser.add_argument("--no-verify", action="store_true")
    parser.add_argument("--no-compile", action="store_true")
    args = parser.parse_args()

    if not args.onnx.exists():
        sys.exit(f"ONNX model not found: {args.onnx}")

    convert(args.onnx, args.out, args.float16)
    if not args.no_verify:
        verify(args.onnx, args.out)
    if not args.no_compile:
        compile_mlpackage(args.out)


if __name__ == "__main__":
    main()
