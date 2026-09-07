# Native IOSLab bridge

`IOSLab` is a minimal Objective-C++ Godot iOS plugin compiled inside the macOS GitHub Actions job against the exact Godot 4.7.2 iOS headers.

It exposes only the Apple APIs that are missing from the GDScript-only bootstrap:

- CoreLocation request/start/stop + location updates;
- CoreBluetooth BLE discovery;
- ARKit support probe;
- LiDAR scene-reconstruction support probe;
- CoreNFC reader availability probe.

No GitHub credentials, telemetry credentials, Apple account information, UDID or pairing data are embedded or read by this plugin.
