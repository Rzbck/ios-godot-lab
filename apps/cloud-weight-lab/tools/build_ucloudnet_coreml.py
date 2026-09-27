#!/usr/bin/env python3
import argparse
import pickle
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import coremltools as ct


class BasicConv2d(nn.Module):
    def __init__(self, in_channels, out_channels, kernel_size, padding=0, stride=1, groups=1):
        super().__init__()
        self.conv2d = nn.Conv2d(
            in_channels, out_channels, kernel_size,
            stride=stride, padding=padding, groups=groups, bias=False
        )
        self.bn = nn.BatchNorm2d(out_channels)

    def forward(self, x):
        return self.bn(F.relu6(self.conv2d(x)))


class DoubleConv2d(nn.Module):
    def __init__(self, in_channels, out_channels):
        super().__init__()
        self.in_channels = in_channels
        self.out_channels = out_channels
        self.conv1 = BasicConv2d(in_channels, out_channels, 3, 1)
        self.conv2 = BasicConv2d(out_channels, out_channels, 3, 1)

    def forward(self, x):
        out = self.conv2(self.conv1(x))
        return out if self.in_channels != self.out_channels else out + x


class UNetDown(nn.Module):
    def __init__(self, in_channels, out_channels):
        super().__init__()
        self.pool = nn.MaxPool2d(3, 2, 1)
        self.conv = BasicConv2d(in_channels, out_channels, 3, 1)

    def forward(self, x):
        return self.conv(self.pool(x))


class UNetUp(nn.Module):
    def __init__(self, in_channels, out_channels):
        super().__init__()
        self.conv = BasicConv2d(in_channels, out_channels, 3, 1)

    def forward(self, x):
        x = F.interpolate(x, scale_factor=2, mode="bilinear", align_corners=True)
        return self.conv(x)


class UCloudNet(nn.Module):
    def __init__(self, in_channels=3, base_channels=2, aux=True):
        super().__init__()
        self.aux = aux
        self.in_conv = BasicConv2d(in_channels, base_channels, 3, 1)
        self.double_conv_1 = DoubleConv2d(base_channels, base_channels)
        self.down_1 = UNetDown(base_channels, base_channels * 2)
        self.double_conv_2 = DoubleConv2d(base_channels * 2, base_channels * 2)
        self.down_2 = UNetDown(base_channels * 2, base_channels * 4)
        self.double_conv_3 = DoubleConv2d(base_channels * 4, base_channels * 4)
        self.down_3 = UNetDown(base_channels * 4, base_channels * 8)
        self.double_conv_4 = DoubleConv2d(base_channels * 8, base_channels * 8)
        self.down_4 = UNetDown(base_channels * 8, base_channels * 16)
        self.double_conv_5 = DoubleConv2d(base_channels * 16, base_channels * 16)

        self.up_1 = UNetUp(base_channels * 16, base_channels * 8)
        self.double_conv_6 = DoubleConv2d(base_channels * 16, base_channels * 8)
        self.up_2 = UNetUp(base_channels * 8, base_channels * 4)
        self.double_conv_7 = DoubleConv2d(base_channels * 8, base_channels * 4)
        self.up_3 = UNetUp(base_channels * 4, base_channels * 2)
        self.double_conv_8 = DoubleConv2d(base_channels * 4, base_channels * 2)
        self.up_4 = UNetUp(base_channels * 2, base_channels)
        self.double_conv_9 = DoubleConv2d(base_channels * 2, base_channels)

        self.dp = nn.Dropout2d(p=0.2)
        self.classifier = nn.Conv2d(base_channels, 1, 3, 1, 1)

        if aux:
            self.aux_x2 = BasicConv2d(base_channels * 2, 1, 1)
            self.aux_x4 = BasicConv2d(base_channels * 4, 1, 1)

    def forward(self, x):
        out = self.in_conv(x)
        feat_1 = self.double_conv_1(out)
        out = self.down_1(feat_1)
        feat_2 = self.double_conv_2(out)
        out = self.down_2(feat_2)
        feat_3 = self.double_conv_3(out)
        out = self.down_3(feat_3)
        feat_4 = self.double_conv_4(out)
        out = self.down_4(feat_4)

        out = self.double_conv_5(out)
        out = self.up_1(out)
        out = torch.cat([out, feat_4], dim=1)
        out = self.double_conv_6(out)
        out = self.up_2(out)
        out = torch.cat([out, feat_3], dim=1)
        up_x4 = self.double_conv_7(out)
        out = self.up_3(up_x4)
        out = torch.cat([out, feat_2], dim=1)
        up_x2 = self.double_conv_8(out)
        out = self.up_4(up_x2)
        out = torch.cat([out, feat_1], dim=1)
        out = self.double_conv_9(out)
        primary = self.classifier(self.dp(out))

        if self.aux:
            return primary, self.aux_x2(up_x2), self.aux_x4(up_x4)
        return primary


class InferenceModel(nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, image):
        primary = self.model(image)[0]
        return torch.sigmoid(primary)


def load_paddle_state(path: Path):
    with path.open("rb") as handle:
        state = pickle.load(handle)
    if not isinstance(state, dict):
        raise TypeError(f"Expected dict state, got {type(state)!r}")
    return state


def numpy_value(value):
    if isinstance(value, np.ndarray):
        return value
    if hasattr(value, "numpy"):
        return value.numpy()
    return np.asarray(value)


def map_state(model: nn.Module, paddle_state: dict):
    target = model.state_dict()
    converted = {}

    for source_key, raw_value in paddle_state.items():
        key = source_key.replace("._mean", ".running_mean").replace("._variance", ".running_var")
        if key not in target:
            if ".aux_" in key or key.startswith("aux_"):
                continue
            raise KeyError(f"Unexpected Paddle parameter: {source_key} -> {key}")

        array = numpy_value(raw_value)
        tensor = torch.from_numpy(np.array(array, copy=True)).to(dtype=target[key].dtype)
        if tuple(tensor.shape) != tuple(target[key].shape):
            raise ValueError(
                f"Shape mismatch for {source_key}: {tuple(tensor.shape)} != {tuple(target[key].shape)}"
            )
        converted[key] = tensor

    for key, value in target.items():
        if key.endswith("num_batches_tracked"):
            converted[key] = torch.zeros_like(value)

    missing = sorted(set(target) - set(converted))
    if missing:
        raise KeyError("Missing mapped parameters: " + ", ".join(missing))

    model.load_state_dict(converted, strict=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    torch.manual_seed(0)
    model = UCloudNet(in_channels=3, base_channels=2, aux=True)
    state = load_paddle_state(args.weights)
    map_state(model, state)
    model.eval()

    wrapped = InferenceModel(model).eval()
    example = torch.zeros(1, 3, 544, 304, dtype=torch.float32)

    with torch.no_grad():
        output = wrapped(example)
        if tuple(output.shape) != (1, 1, 544, 304):
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

    mlmodel.author = "UCloudNet authors; iOS conversion for Cloud Weight Lab"
    mlmodel.short_description = (
        "Ground-based sky/cloud semantic segmentation using UCloudNet k=2 daytime weights."
    )
    mlmodel.user_defined_metadata["source_repository"] = "https://github.com/Att100/UCloudNet"
    mlmodel.user_defined_metadata["source_commit"] = "799f25917361663a1ce2cf210c14a01c1ae45f15"
    mlmodel.user_defined_metadata["source_weights"] = (
        "ucloudnet_k_2_aux_lr_decay_d_epochs_100.pdparam"
    )
    mlmodel.user_defined_metadata["usage"] = "academic/research; personal prototype"

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists():
        import shutil
        shutil.rmtree(args.output)
    mlmodel.save(str(args.output))

    spec = mlmodel.get_spec()
    print("Core ML model generated:", args.output)
    print("Input:", spec.description.input[0].name)
    print("Output:", spec.description.output[0].name)


if __name__ == "__main__":
    main()
