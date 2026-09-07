# V2 runtime acceptance checklist

The current V2 branch is only accepted on the real iPhone after all relevant checks are observed on the exact built SHA:

- app launches without the Godot logo image;
- vertical scrolling starts from both card surfaces and margins;
- Overview reports the exact stamped SHA;
- touch and drag counters react;
- accelerometer / gravity / gyroscope / magnetometer update;
- haptic request is felt;
- CoreLocation permission, coordinates and map work;
- Apple Maps handoff works after a fix;
- BLE scanner reports state and nearby advertisements when available;
- ARKit / LiDAR / NFC availability probes return without crashing;
- camera permission and preview work;
- microphone permission and level meter work;
- HTTP(S) request can reach a chosen endpoint;
- WebSocket/WSS can connect and exchange text;
- UDP and OSC can send to a chosen reachable host such as TouchDesigner.

A CI PASS alone does not satisfy this checklist.
