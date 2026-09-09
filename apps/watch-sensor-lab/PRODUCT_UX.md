# Watch Tracker — product UI/UX direction

Date: 2026-09-09

## Product contract

The iPhone and Apple Watch are two views/controllers of one live tracking session. START/PAUSE/RESUME/STOP must converge to the same session state regardless of which device initiates the action.

The product is not a sensor-debug screen. Raw accelerometer/gyroscope values remain recordable but are not primary UI.

## iPhone live screen

The iPhone shell is native SwiftUI so layout follows iPhone safe areas and system sizing instead of a fixed 390x844 canvas.

Primary hierarchy:

1. full-screen Apple Map with current location and live route polyline;
2. compact top status for Watch connectivity and session state;
3. safe-area bottom sheet with elapsed time, distance, current speed, pace, heart rate, altitude and elevation gain;
4. large pause/resume and stop controls while active;
5. one large start control while idle.

The map remains the spatial context; metrics and controls are readable without covering most of the route.

## Apple Watch live experience

watchOS is intentionally glanceable and paged vertically with the Digital Crown:

1. primary page: elapsed time, distance, heart rate, current speed, ascent;
2. route page: live Apple Map and route polyline;
3. terrain page: altitude, ascent, descent, average heart rate;
4. controls page: large pause/resume and stop controls.

The idle screen exposes only readiness state and a large Start button.

## Sensor / metric pipeline

### iPhone

- Core Location: latitude/longitude, horizontal/vertical accuracy, speed, altitude;
- derived: route, distance, pace, max speed, elevation gain/loss;
- WatchConnectivity: Watch state, heart rate, energy and auxiliary motion samples;
- durable JSONL session log under Documents/Sessions/<session_id>/.

### Apple Watch

- HealthKit workout session and live workout builder;
- heart rate and average heart rate;
- active energy;
- Core Location route/speed/altitude/ascent/descent;
- Core Motion auxiliary samples;
- WatchConnectivity state/control synchronization with iPhone.

The iPhone can ask HealthKit to launch/wake the Watch workout app. Starting from Watch sends the live state back to the iPhone so its GPS recorder joins the same activity.

## Design references used

- Apple Human Interface Guidelines: Designing for watchOS, Workouts, Layout, Accessibility;
- Apple MapKit for SwiftUI documentation;
- Apple HealthKit multi-device workout/session documentation;
- Strava current iPhone/Apple Watch recording patterns for map-vs-metrics hierarchy, live elevation, route visibility and heart-rate presentation.

Do not copy another product's visual identity. The references are used for platform interaction patterns and information hierarchy only.

## Validation boundaries

Native product code, HealthKit declarations and the updated CI pipeline require CI and real-device validation before they can be called working.

The validated iLoader/isideload deployment chain must not be changed merely to style the product. If HealthKit authorization is absent after signing, investigate provisioning capability support separately and preserve the already validated Watch installation path.
