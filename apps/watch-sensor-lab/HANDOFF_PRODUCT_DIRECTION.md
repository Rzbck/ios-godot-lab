# HANDOFF — Watch Sensor Lab product direction / latest physical validation

Date: 2026-09-09

This supplements `apps/watch-sensor-lab/HANDOFF.md`. Re-check Git/HEAD before modifying application code.

## Physical milestone now validated

Using the exact Watch app bundle produced by the patched iLoader/isideload signing path, followed by a manual direct installation to the paired Apple Watch through `com.apple.streaming_zip_conduit`:

- watchOS completed installation through `InstallComplete = 100%` and `DataComplete`;
- the installed Watch bundle was no longer a placeholder (`IsPlaceholder` no longer true);
- the user physically put the Watch back on, opened **Watch Sensor Lab**, and confirmed the app launches and works on the real Apple Watch.

Classification:

- iPhone install/launch: physically validated previously;
- Watch signed bundle acceptance: physically validated;
- Watch direct install: physically validated;
- Watch launch: physically validated;
- automatic one-click iLoader iPhone + Watch install: NOT yet validated; tooling work continues in `Rzbck/isideload` / `Rzbck/iloader`.

Do not confuse this manual direct-install success with the automatic iLoader path being fixed.

## Product direction to keep for the next application phase

The intended product is a **session tracker / recorder** where the iPhone becomes the durable recorder and viewer for data collected from the iPhone and Apple Watch.

Target session flow:

```text
Start session
  -> sample iPhone + Watch sensors with timestamps/source
  -> synchronize Watch data to iPhone
  -> persist session locally on iPhone
  -> stop/finalize session
  -> review the recorded session on iPhone
```

Data to retain progressively:

- GPS route / trace;
- latitude/longitude + location accuracy;
- altitude and barometric/relative altitude when available;
- speed: instantaneous, average, maximum;
- acceleration / accelerometer;
- gyroscope;
- gravity / attitude / device motion;
- heading/course when useful;
- distance, duration and pace;
- elevation gain/loss;
- data quality / gaps / source (`iphone`, `watch`, `derived`);
- later, authorized HealthKit/workout metrics such as heart rate.

The iPhone should store complete session records so the user can later inspect tracks, speed, altitude, acceleration and other metrics without needing the Watch to remain connected.

Architecture should remain generic and timestamp-driven rather than hard-coded to the current prototype UI. Preserve the existing target architecture: native watchOS sensors -> WatchConnectivity -> iPhone native bridge -> Godot recorder/visualization/storage/export.

## Current priority before product work resumes

Finish and physically validate the automatic Windows/iLoader deployment path first. Do not start tracker/recorder feature implementation until the tooling path is stable enough that new exact-SHA builds can be installed reliably on both iPhone and Apple Watch.
