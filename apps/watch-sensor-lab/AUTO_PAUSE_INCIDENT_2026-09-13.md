# Auto-pause cycling incident — 2026-09-13

## Field observation

A real cycling session auto-paused and did not resume. After roughly 15 minutes of riding, the live distance was only about 0.04 km.

This is a hardware observation and is treated as authoritative. The affected session must be inspected read-only before any HealthKit reconstruction is attempted.

## Root cause found in current code

`SensorModel.pauseCore(reason: "auto")` stopped `CLLocationManager`, then set `currentSpeedMps = 0`.

`stageAutoResumeIfNeeded()` subsequently required movement evidence, including GPS speed, to resume. This creates a deadlock when Core Motion does not independently classify the resumed cycling motion.

A second unsafe condition exists at session start: auto-pause can arm while `currentSpeedMps` is still zero before trustworthy movement/GPS evidence has been observed.

A third robustness issue exists in the shared policy: a stale `stationary` Core Motion state can veto strong GPS movement evidence.

## Fix requirements

1. Auto-pause must never remove the sensor evidence needed to prove resume.
2. While auto-paused, GPS is a **read-only resume probe**. Probe locations must not mutate canonical route/distance before resume.
3. Strong fresh GPS evidence must override stale `stationary` motion classification.
4. Auto-pause must not arm until real movement and reliable GPS have been observed for the session.
5. Probe samples should be forwarded to the iPhone session store as forensic data so a future auto-pause failure does not erase the only available route evidence.
6. The iPhone should retain bounded/raw paused-location probe samples without changing displayed distance or route.
7. CI must cover the pause → movement probe → resume path deterministically.

## Recovery rule for the affected ride

Do not invent missing GPS points, timestamps, distance, or duration. First identify the exact session ID and inspect raw iPhone/Watch/HealthKit data through the existing read-only diagnostic API. Only reconstruct what genuine persisted evidence supports.
