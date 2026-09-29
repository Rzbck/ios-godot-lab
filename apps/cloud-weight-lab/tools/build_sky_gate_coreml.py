#!/usr/bin/env python3
import argparse
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
import segmentation_models_pytorch as smp
from safetensors.torch import load_file


class SkyProbabilityModel(nn.Module):
    def __init__(self, segmentation_model: nn.Module):
        super().__init__()
        self.model = segmentation_model
        self.register_buffer(
            "mean",
            torch.tensor([0.485, 0.456, 0.406], dtype=torch.float32).view(1, 3, 1, 1),
        )
        self.register_buffer(
            "std",
            torch.tensor([0.229, 0.224, 0.225], dtype=torch.float32).view(1, 3, 1, 1),
        )

    def forward(self, image):
        normalized = (image - self.mean) / self.std
        logits = self.model(normalized)
        probabilities = torch.softmax(logits, dim=1)
        return probabilities[:, 1:2, :, :]


def load_weights(model: nn.Module, path: Path) -> None:
    state = load_file(str(path))
    converted = {}
    for key, value in state.items():
        target_key = key[len("_model.") :] if key.startswith("_model.") else key
        converted[target_key] = value

    missing, unexpected = model.load_state_dict(converted, strict=False)
    if missing:
        raise KeyError("Missing SkyWater parameters: " + ", ".join(sorted(missing)))
    if unexpected:
        raise KeyError("Unexpected SkyWater parameters: " + ", ".join(sorted(unexpected)))


def rename_mlprogram_io(mlmodel: ct.models.MLModel) -> ct.models.MLModel:
    spec = mlmodel.get_spec()
    if len(spec.description.input) != 1 or len(spec.description.output) != 1:
        raise RuntimeError("Sky gate must expose exactly one input and one output")

    old_input = spec.description.input[0].name
    old_output = spec.description.output[0].name
    ct.utils.rename_feature(
        spec,
        old_input,
        "image_tensor",
        rename_inputs=True,
        rename_outputs=False,
    )
    ct.utils.rename_feature(
        spec,
        old_output,
        "sky_probability",
        rename_inputs=False,
        rename_outputs=True,
    )
    return ct.models.MLModel(spec, weights_dir=mlmodel.weights_dir)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    torch.manual_seed(0)
    model = smp.Segformer(
        encoder_name="mit_b2",
        encoder_weights=None,
        in_channels=3,
        classes=4,
    )
    load_weights(model, args.weights)
    model.eval()

    wrapped = SkyProbabilityModel(model).eval()
    example = torch.full((1, 3, 384, 384), 0.5, dtype=torch.float32)

    with torch.no_grad():
        reference = wrapped(example)
        if tuple(reference.shape) != (1, 1, 384, 384):
            raise RuntimeError(f"Unexpected sky model output shape: {tuple(reference.shape)}")
        if not torch.isfinite(reference).all():
            raise RuntimeError("Sky model produced non-finite probabilities")

    exported = torch.export.export(wrapped, (example,), strict=False).run_decompositions({})
    if exported.dialect not in ("ATEN", "EDGE"):
        raise RuntimeError(f"Unexpected torch.export dialect: {exported.dialect}")

    mlmodel = ct.convert(
        exported,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
    )
    mlmodel = rename_mlprogram_io(mlmodel)

    mlmodel.author = "Vincent Qin / SkyWater-Seg; iOS conversion for Cloud Weight Lab"
    mlmodel.short_description = (
        "Sky-vs-background semantic gate used before UCloudNet cloud segmentation."
    )
    mlmodel.user_defined_metadata["source_repository"] = (
        "https://huggingface.co/Realcat/skywater_seg"
    )
    mlmodel.user_defined_metadata["source_revision"] = (
        "a45ff48a4f924057e9fd947ec736b4098b06e337"
    )
    mlmodel.user_defined_metadata["source_weights_sha256"] = (
        "bba260c601533e4d34c7891cd055b051c2cd5fd2c22084a35d902bfb43e31341"
    )
    mlmodel.user_defined_metadata["license"] = "MIT"
    mlmodel.user_defined_metadata["capture"] = "torch.export"

    prediction = mlmodel.predict({"image_tensor": example.numpy()})
    converted = np.asarray(prediction["sky_probability"], dtype=np.float32)
    reference_np = reference.detach().cpu().numpy().astype(np.float32)
    if converted.shape != reference_np.shape:
        raise RuntimeError(
            f"Core ML sky output shape mismatch: {converted.shape} != {reference_np.shape}"
        )
    max_error = float(np.max(np.abs(converted - reference_np)))
    if not np.isfinite(converted).all() or max_error > 0.08:
        raise RuntimeError(f"Core ML sky conversion validation failed: max error {max_error:.5f}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        import shutil

        shutil.rmtree(args.output)
    mlmodel.save(str(args.output))

    spec = mlmodel.get_spec()
    print("Sky Core ML model generated:", args.output)
    print("Input:", spec.description.input[0].name, spec.description.input[0].type)
    print("Output:", spec.description.output[0].name, spec.description.output[0].type)
    print("Validation max abs error:", f"{max_error:.6f}")


if __name__ == "__main__":
    main()
