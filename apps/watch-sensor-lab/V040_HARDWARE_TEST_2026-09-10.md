# Watch Tracker v0.4 — first hardware checkpoint

Date: 2026-09-10

## Exact candidate

- repository: `Rzbck/ios-godot-lab`
- branch: `feat/watch-sensor-v040-20260910`
- exact installed app SHA before this documentation commit: `3efcc2cd313f1fefccb2ad5b011a2322aec2ca37`
- CI run: `34468523258` — SUCCESS
- artifact id: `10148601361`
- artifact name: `watch-sensor-lab-companion-3efcc2cd313f1fefccb2ad5b011a2322aec2ca37`
- artifact digest: `sha256:34b5170d3ef5ffb706f2be509c15707f843f3f69ac4d604c14d92db8a7567dc9`
- exact downloaded IPA: `E:\_Project\IOS APP\ios-godot-lab\artifacts\watch-sensor-lab\3efcc2cd313f\WatchSensorLab-companion-unsigned-3efcc2cd313f.ipa`
- local IPA SHA-256: `07b8aa7bec9e0716b569f6f5ec925c8299d4d3056405acd10a5451f8f1dc798f`

This document commit is NOT the tested application SHA. The hardware candidate remains `3efcc2cd...`.

## Physical observations reported by user

Validated on real hardware for this exact candidate:

- iPhone application installs/opens successfully;
- Apple Watch companion opens successfully;
- existing activity history remains visible on iPhone after the v0.4 upgrade/install;
- therefore normal upgrade did not silently erase the preserved v0.3.1 field activity.

Not yet physically tested/validated in this checkpoint:

- new v0.4 workout recording;
- live calories on iPhone/Watch;
- weather capture/network behavior;
- Watch recent-history synchronization/view;
- gyro non-zero behavior;
- barometric elevation/D+/D-;
- speed spike filtering;
- cadence/steps;
- auto-pause;
- post-STOP summary;
- Health/Fitness workout type, route and deletion;
- Auto Walk -> Run -> Walk or Cycle transitions;
- multisport/triathlon behavior.

## Legacy calories observation

The preserved v0.3.1 activity is visible in v0.4 history but has no calories associated in the historical summary.

This is expected from the legacy schema: the v0.3.1 `TrackerSummary` did not contain active-energy/calorie data. v0.4 adds optional `activeEnergyKcal` for new summaries while preserving backward decoding.

Future improvement requested by the user:

- when a legacy Watch Tracker session can be matched unambiguously to its app-managed HealthKit workout, enrich the historical presentation with HealthKit calories (and potentially other trustworthy contextual metrics) without rewriting or fabricating the original raw session evidence;
- if no unambiguous HealthKit match exists, display the metric as unavailable rather than estimating it silently.

## Weather requirement reaffirmed

The user explicitly reaffirmed that weather/environment data must be integrated and retained because temperature, humidity, wind/headwind and related conditions materially affect effort for walking, running and cycling.

The current v0.4 implementation already has provider-agnostic weather snapshots and environmental analysis in code/CI, but this behavior is NOT physically validated yet. It must be checked during the next real v0.4 outdoor session.

## Next physical test

Run a short controlled v0.4 outdoor session before adding more classifier complexity. Verify in priority order:

1. stable startup/acquisition UI;
2. live HR + active calories + cadence/steps;
3. weather snapshot appears and contains plausible temperature/wind data;
4. manual pause/resume remains authoritative and stable;
5. STOP opens the new summary;
6. new session appears in iPhone history with calories/weather;
7. recent activity reaches Watch history;
8. preserve/export the resulting session corpus for gyro/GPS/elevation/speed-filter analysis.

Do not purge the preserved baseline session `1789026745407`.