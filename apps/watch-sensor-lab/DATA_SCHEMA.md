# Watch Sensor Lab — session data schema v1

This schema is intentionally source-agnostic so iPhone, Apple Watch and derived metrics can be merged into one session timeline.

## Storage layout

```text
user://sessions/<session_id>/
  samples.jsonl
  summary.json
```

`samples.jsonl` is append-only during recording. Each line is one JSON object. This avoids keeping a high-frequency session entirely in memory and makes partial recordings recoverable.

## Common sample envelope

```json
{
  "record": "sample",
  "schema": 1,
  "session_id": "...",
  "timestamp": 1788980000.123,
  "elapsed_ms": 15340,
  "source": "iphone",
  "kind": "motion",
  "payload": {},
  "quality": {}
}
```

Required semantics:

- `timestamp`: Unix time in seconds at acquisition/ingestion time;
- `elapsed_ms`: monotonic offset from session start when recorded on the iPhone;
- `source`: `iphone`, `watch` or `derived`;
- `kind`: sensor family such as `motion`, `location`, `altitude`, `heart_rate`, `session_event`;
- `payload`: sensor-specific values;
- `quality`: optional accuracy, freshness, confidence or gap information.

## iPhone / Watch motion payload

```json
{
  "accel": [0.0, 0.0, 0.0],
  "gyro": [0.0, 0.0, 0.0],
  "gravity": [0.0, 0.0, 0.0],
  "magnetometer": [0.0, 0.0, 0.0]
}
```

The first recorder implementation samples the iPhone motion values at 20 Hz. Watch motion uses the same envelope once the iPhone WatchConnectivity receiver is wired.

## Planned native location payload

```json
{
  "latitude": 48.8566,
  "longitude": 2.3522,
  "altitude_m": 37.2,
  "speed_m_s": 4.3,
  "course_deg": 112.0,
  "horizontal_accuracy_m": 4.8,
  "vertical_accuracy_m": 7.0,
  "speed_accuracy_m_s": 0.5,
  "course_accuracy_deg": 8.0
}
```

This payload will be produced by the native iPhone location bridge. The recorder format already accepts it through `ingest_external_sample("iphone", "location", ...)`.

## Planned Watch payload

WatchConnectivity messages should carry the original Watch acquisition timestamp and sequence number. The iPhone recorder must preserve those values inside `payload` or `quality` while also assigning the iPhone-side `elapsed_ms` used to merge the complete session.

Example:

```json
{
  "source": "watch",
  "kind": "motion",
  "payload": {
    "watch_timestamp": 1788980000.123,
    "sequence": 42,
    "accel": [0.0, 0.0, 0.0],
    "gyro": [0.0, 0.0, 0.0]
  }
}
```

## Derived records

Derived metrics are written or generated from the raw timeline rather than replacing raw sensor data. Planned values include:

- distance;
- instantaneous / average / maximum speed;
- pace;
- elevation gain/loss;
- route gaps;
- Watch <-> iPhone latency/jitter statistics.

## Current implementation boundary

Ready now on the tracker branch:

- local iPhone session creation/finalization;
- append-only JSONL persistence;
- 20 Hz iPhone motion ingestion;
- summary persistence;
- generic external sample entry point.

Still pending native bridge work:

- CLLocation GPS/speed/altitude;
- WatchConnectivity receiver on iPhone;
- HealthKit/workout data;
- route/map and graph review UI.
