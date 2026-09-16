# Device candidate — neutral Auto startup auto-pause — 2026-09-16

This note intentionally carries no runtime code. Its commit is the exact-SHA
device-candidate trigger for the neutral Auto startup auto-pause repair.

## Field failure reproduced

- failed physical build: `6884591568c8f71cc9e4246c10ff0bf1045d2102`
- session: `1789535250518`
- selected activity: `automatic`
- effective activity remained: `automatic`
- auto-pause enabled: yes
- distance: `0 m`
- cadence: `0 spm`
- Watch fused stillness reached `true`
- Watch inertial stillness reached `true`
- stale GPS speed was explicitly `speed_fresh=false`
- pause evaluation repeatedly returned `decision_reason=unsupported_activity`

## Root cause

Neutral Auto startup deliberately leaves `effectiveActivity == .automatic` until
a concrete sport is detected. The conservative auto-pause stability policy did
not list `.automatic` as supported, so a workout started while already still
could never arm auto-pause even with corroborated stillness.

## Repair

Runtime code is carried by parent code SHA
`bcac4d0cea1b1bc4aeb1c03b7b535746af2ce962`:

- keep Auto neutral for sport identification;
- treat `.automatic` only as a conservative auto-pause control profile;
- use walking pause thresholds/dwells while sport is still unknown;
- preserve fused-stillness requirement and fresh-speed veto;
- preserve fail-closed behavior for unsupported real sports;
- add field regression coverage for session `1789535250518`;
- keep auto-pause evaluation telemetry consistent with the shared policy.

## Pre-device verification on parent code SHA

- generated-source chain executed twice successfully;
- static workflow invariants passed;
- shared iPhone/Watch workflow parity passed;
- tracker product invariants passed;
- unsigned iPhone build passed;
- unsigned watchOS build passed;
- HealthKit declarations passed;
- iPhone + embedded watchOS companion assembly passed;
- exact-SHA IPA packaging passed.

Physical validation is still required. Acceptance remains:

1. start Auto while physically stationary;
2. after stabilization/dwell, Watch enters auto-pause and stays paused;
3. begin real locomotion;
4. Watch resumes once and remains active without pause/resume oscillation.

Do not merge to `main` or call the behavior physically validated until those
steps have been observed on the device.
