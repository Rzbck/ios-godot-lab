#!/usr/bin/env python3
import argparse
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from safetensors.torch import load_file
from transformers import SegformerConfig, SegformerForSemanticSegmentation


SKY_CLASS_INDEX = 2
INPUT_SIZE = 384
SOURCE_REPOSITORY = "https://huggingface.co/nvidia/segformer-b0-finetuned-ade-512-512"
SOURCE_REVISION = "489d5cd81a0b59fab9b7ea758d3548ebe99677da"
SOURCE_WEIGHTS_SHA256 = "6ae39addd01de6b1b8bde2cf677d43a5cd733424b8d186de3f95d1c51fee23f9"


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
        logits = self.model(pixel_values=normalized, return_dict=False)[0]
        probabilities = torch.softmax(logits, dim=1)
        sky = probabilities[:, SKY_CLASS_INDEX : SKY_CLASS_INDEX + 1, :, :]
        return F.interpolate(
            sky,
            size=(INPUT_SIZE, INPUT_SIZE),
            mode="bilinear",
            align_corners=False,
        )


def load_model(config_path: Path, weights_path: Path) -> nn.Module:
    config = SegformerConfig.from_json_file(str(config_path))
    if int(config.num_labels) != 150:
        raise RuntimeError(f"Expected 150 ADE20K classes, got {config.num_labels}")
    if str(config.id2label.get(SKY_CLASS_INDEX, "")).strip().lower() != "sky":
        raise RuntimeError(
            f"ADE20K class {SKY_CLASS_INDEX} is not sky: {config.id2label.get(SKY_CLASS_INDEX)!r}"
        )

    model = SegformerForSemanticSegmentation(config)
    state = load_file(str(weights_path))
    missing, unexpected = model.load_state_dict(state, strict=False)
    if missing:
        raise KeyError("Missing SegFormer parameters: " + ", ".join(sorted(missing)))
    if unexpected:
        raise KeyError("Unexpected SegFormer parameters: " + ", ".join(sorted(unexpected)))
    return model.eval()


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
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--weights", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    torch.manual_seed(0)
    model = load_model(args.config, args.weights)
    wrapped = SkyProbabilityModel(model).eval()
    example = torch.full((1, 3, INPUT_SIZE, INPUT_SIZE), 0.5, dtype=torch.float32)

    with torch.no_grad():
        reference = wrapped(example)
        if tuple(reference.shape) != (1, 1, INPUT_SIZE, INPUT_SIZE):
            raise RuntimeError(f"Unexpected sky model output shape: {tuple(reference.shape)}")
        if not torch.isfinite(reference).all():
            raise RuntimeError("Sky model produced non-finite probabilities")
        if float(reference.min()) < 0 or float(reference.max()) > 1:
            raise RuntimeError("Sky model produced probabilities outside [0, 1]")

    traced = torch.jit.trace(wrapped, example, strict=False)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="image_tensor", shape=example.shape, dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT16,
    )
    mlmodel = rename_mlprogram_io(mlmodel)

    mlmodel.author = "NVIDIA SegFormer / ADE20K; iOS conversion for Cloud Weight Lab"
    mlmodel.short_description = (
        "Generic ADE20K semantic sky gate used before UCloudNet cloud segmentation."
    )
    mlmodel.user_defined_metadata["source_repository"] = SOURCE_REPOSITORY
    mlmodel.user_defined_metadata["source_revision"] = SOURCE_REVISION
    mlmodel.user_defined_metadata["source_weights_sha256"] = SOURCE_WEIGHTS_SHA256
    mlmodel.user_defined_metadata["license"] = (
        "NVIDIA Source Code License for SegFormer; non-commercial research/evaluation only"
    )
    mlmodel.user_defined_metadata["dataset"] = "ADE20K / scene_parse_150"
    mlmodel.user_defined_metadata["sky_class_index"] = str(SKY_CLASS_INDEX)
    mlmodel.user_defined_metadata["capture"] = "torch.jit.trace"

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
    print("ADE20K sky Core ML model generated:", args.output)
    print("Input:", spec.description.input[0].name, spec.description.input[0].type)
    print("Output:", spec.description.output[0].name, spec.description.output[0].type)
    print("Validation max abs error:", f"{max_error:.6f}")


if __name__ == "__main__":
    main()
