#!/usr/bin/env python3
import argparse
import shutil
from pathlib import Path

import coremltools as ct
import torch

from build_ucloudnet_coreml import InferenceModel, UCloudNet, load_paddle_state, map_state


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    torch.manual_seed(0)
    model = UCloudNet(in_channels=3, base_channels=2, aux=True)
    map_state(model, load_paddle_state(args.weights))
    model.eval()

    wrapped = InferenceModel(model).eval()
    example = torch.zeros(1, 3, 304, 544, dtype=torch.float32)

    with torch.no_grad():
        output = wrapped(example)
        if tuple(output.shape) != (1, 1, 304, 544):
            raise RuntimeError(f"Unexpected PyTorch output shape: {tuple(output.shape)}")

    traced = torch.jit.trace(wrapped, example, strict=True)
    traced.eval()

    mlmodel = ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
        inputs=[
            ct.ImageType(
                name="image",
                shape=example.shape,
                scale=1.0 / 255.0,
                color_layout=ct.colorlayout.RGB,
            )
        ],
        outputs=[ct.TensorType(name="cloud_probability")],
    )

    mlmodel.author = "UCloudNet authors; landscape iOS conversion for Cloud Weight Lab"
    mlmodel.short_description = "Ground-based sky/cloud segmentation, landscape 544x304."
    mlmodel.user_defined_metadata["source_repository"] = "https://github.com/Att100/UCloudNet"
    mlmodel.user_defined_metadata["source_commit"] = "799f25917361663a1ce2cf210c14a01c1ae45f15"
    mlmodel.user_defined_metadata["orientation"] = "landscape"
    mlmodel.user_defined_metadata["usage"] = "academic/research; personal prototype"

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        shutil.rmtree(args.output)
    mlmodel.save(str(args.output))

    print("Landscape Core ML model generated:", args.output)


if __name__ == "__main__":
    main()
