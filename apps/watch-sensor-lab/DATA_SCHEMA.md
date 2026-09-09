# Watch Tracker — session data schema v2

The product uses one source-agnostic timeline for iPhone, Apple Watch and derived metrics. The previous Godot recorder schema v1 is retained as a prototype/reference; the native SwiftUI product writes schema v2.

## Native storage layout

```text
Documents/Sessions/<session_id>/
  samples.jsonl
  summary.json
```

`samples.jsonl` is append-only while a session is active so a long recording does not need to stay entirely in memory.

## Common sample envelope

```json
{
  "record": "sample",
  "schema": 2,
  "session_id": "1788990000123",
  "timestamp": 1788990000.123,
  "source": "iphone",
  "kind": "location",
  "payload": {},
  "quality": {}
}
```

Semantics:

- `timestamp`: Unix time in seconds at acquisition/ingestion time;
- `source`: `iphone`, `watch` or `derived`;
- `kind`: `location`, `heart_rate`, `motion`, `session_control` or another explicit sensor family;
- `payload`: sensor/metric values;
- `quality`: accuracy or freshness information when available.

## iPhone location payload

```json
{
  "latitude": 48.8566,
  "longitude": 2.3522,
  "altitude_m": 37.2,
  "speed_mps": 4.3,
  "distance_m": 1820.4,
  "elevation_gain_m": 83.0,
  "elevation_loss_m": 41.0
}
```

Quality carries `horizontal_accuracy_m` and `vertical_accuracy_m`. The live tracker rejects stale or very inaccurate points before using them for distance and route rendering.

## Apple Watch health payload

Heart-rate samples received from the Watch use:

```json
{
  "record": "sample",
  "schema": 2,
  "source": "watch",
  "kind": "heart_rate",
  "payload": {
    "bpm": 146.0
  }
}
```

Live Watch state also carries average heart rate and active energy so the iPhone UI can stay synchronized without polling HealthKit continuously.

## Apple Watch motion payload

```json
{
  "type": "sensor_sample",
  "schema": 2,
  "source": "watch",
  "kind": "motion",
  "timestamp": 1788990000.123,
  "payload": {
    "accel": [0.0, 0.0, 0.0],
    "gyro": [0.0, 0.0, 0.0]
  }
}
```

Motion remains auxiliary data and is not shown as primary workout UI.

## Shared live session state

WatchConnectivity uses a compact latest-state document so both devices converge even if a live `sendMessage` is missed:

```json
{
  "type": "tracker_state",
  "phase": "active",
  "session_id": "1788990000123",
  "origin": "watch",
  "elapsed_s": 532.0,
  "distance_m": 1820.4,
  "speed_mps": 4.3,
  "altitude_m": 37.2,
  "elevation_gain_m": 83.0,
  "elevation_loss_m": 41.0,
  "heart_rate_bpm": 146.0,
  "average_heart_rate_bpm": 139.0,
  "active_energy_kcal": 121.0
}
```

Control messages use `type=tracker_control` and `command=start|pause|resume|stop`. START/PAUSE/RESUME/STOP initiated on either device updates the same product session state.

## Derived live metrics

The native product currently derives or displays:

- route polyline;
- distance;
- current and average speed;
- pace;
- maximum speed for the final summary;
- altitude;
- elevation gain/loss;
- current and average heart rate;
- active energy;
- GPS accuracy/readiness;
- Watch connectivity state.

## Validation boundary

Schema v2 describes the native product implementation. CI compilation, signing with HealthKit capability, real heart-rate authorization and physical iPhone/Watch synchronization must still be validated for each exact product SHA before the implementation is called device-validated.
